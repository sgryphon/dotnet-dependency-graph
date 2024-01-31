#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Builds .NET assembly dependency graph diagram and output to diagram formats

.DESCRIPTION

    For details on C4 see: https://c4model.com/

.EXAMPLE

    scripts/Build-DependencyGraph.ps1 -Verbose

#>
[CmdletBinding()]    
param ()

# Import library functions
#Remove-Module DotnetDependencyGraph
Import-Module ../DotnetDependencyGraph.psm1 -Force

$working = Join-Path $PSScriptRoot "../working"
# $working = 'C:\Code\dotnet-dependency-graph\sample\working'
$data = Join-Path $working "data"
$csvFilePath = Join-Path $working "Dependencies-CompanyXyz.csv"


Write-Verbose "Copying DLLs to working folder $working"

if (Test-Path $data) {
    Remove-Item $data -Recurse
}
$newDirectory = New-Item -ItemType Directory -Path $data

Get-ChildItem (Join-Path $working "..\src\CompanyXyz.DependencySample.Worker\bin\Debug") -Filter CompanyXyz*.dll -Recur -File | `
    ForEach-Object { Copy-Item $_.FullName $data -Force }


 Write-Verbose "Get references from DLLs, expand data with attribute details, and save to $csvFilePath"

# $references = ls src\CompanyXyz.DependencySample.Worker\bin\Debug\net8.0\CompanyXyz.* | Get-ReferencedAssemblies

Get-ChildItem (Join-Path $data "CompanyXyz*.*") | Get-ReferencedAssemblies | Resolve-AssemblyReferences | Export-CSV (Join-Path $working "Dependencies-CompanyXyz.csv")

#Get-Content 'Dependencies-Manual-CompanyXyz.csv' | Add-Content 'Working\Dependencies-CompanyXyz.csv'


Write-Verbose "Load from saved CSV, filter, convert to diagram output"

# 2. Load saved CSV, filter (e.g. direct, included only), convert to DOT using the color table, save to file
# Array of name regex + color pairs. Checks are applied in order until first match.

$nameColor = @{ `
    '^CompanyXyz\.DependencySample\.Worker' = '#ccffcc'
};

#$dotProps = 'rankdir=LR;'
# Import-CSV (Join-Path $working "Dependencies-CompanyXyz.csv") `
#     | Where-Object { ($_.DependencyType -eq 'Direct') -and ($_.Scope -eq 'Included') } `
#     | Where-Object { -not ($_.Assembly -match 'Test|Migrat') } `
#     | ConvertTo-DotGraph $nameColor $dotProps | Out-File (Join-Path $PSScriptRoot "../docs/CompanyXyz.dot") -encoding ASCII

$plantUmlAdditionalContent = "left to right direction"
Import-CSV (Join-Path $working "Dependencies-CompanyXyz.csv") `
    | Where-Object { ($_.DependencyType -eq 'Direct') } `
    | Where-Object { -not ($_.Assembly -match 'Test|Migrat') } `
    | ConvertTo-PlantUml "Company XYZ - Dependency Sample component diagram" -NameColor $nameColor -AdditionalContent $plantUmlAdditionalContent `
    | Out-File (Join-Path $working "../docs/dotnet-dependencies-CompanyXyz.puml")


Write-Verbose "Load from saved CSV, filter, convert to C4 (in PlantUML), and save"

$nameTag = @{ `
    '^CompanyXyz\.DependencySample\.Worker' = 'Worker'
    '^System\.' = 'System'
};
$c4AdditionalContent = "LAYOUT_LEFT_RIGHT()`n" `
    + "AddComponentTag(""Worker"", `$bgColor=""#ccffcc"")`n" `
    + "AddComponentTag(""System"", `$bgColor=""#ccccff"")";
Import-CSV (Join-Path $working "Dependencies-CompanyXyz.csv") `
    | Where-Object { ($_.DependencyType -eq 'Direct') } `
    | ConvertTo-C4ComponentDiagram "Component Diagram - Company XYZ - Dependency Sample" -NameTag $nameTag -AdditionalContent $c4AdditionalContent `
    | Out-File (Join-Path $working "../docs/c4-component-CompanyXyz.puml")
    
