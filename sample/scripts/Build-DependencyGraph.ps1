#!/usr/bin/env pwsh

# ------------------------------------------------------------------------------
# Builds depenedency graph for CompanyXyz assemblies

# Import library functions
#Remove-Module DotnetDependencyGraph
Import-Module ../DotnetDependencyGraph.psm1 -Force


# 0. Copy DLLs to working folder

$working = Join-Path $PSScriptRoot "../working"
$data = Join-Path $working "data"
Remove-Item $data -Recurse
$newDirectory = New-Item -ItemType Directory -Path $data

Get-ChildItem (Join-Path $PSScriptRoot "..\src\CompanyXyz.DependencySample.Worker\bin\Debug") -Filter CompanyXyz*.dll -Recur -File | `
    ForEach-Object { Copy-Item $_.FullName $data -Force }

# $references = ls src\CompanyXyz.DependencySample.Worker\bin\Debug\net8.0\CompanyXyz.* | Get-ReferencedAssemblies


# 1. List files, get references, expand data with attribute details, save to CSV (because expanding takes time)

# TODO Run this bit in a new PowerShell Session otherwise all the DLLs are loaded and locked in our current session so executing again will fail
Get-ChildItem (Join-Path $data "CompanyXyz*.*") | Get-ReferencedAssemblies | Resolve-AssemblyReferences | Export-CSV (Join-Path $working "Dependencies-CompanyXyz.csv")

#Get-Content 'Dependencies-Manual-CompanyXyz.csv' | Add-Content 'Working\Dependencies-CompanyXyz.csv'

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
    | Out-File (Join-Path $PSScriptRoot "../docs/dotnet-dependencies-CompanyXyz.puml")
