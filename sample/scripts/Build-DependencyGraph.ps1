# ------------------------------------------------------------------------------
# Builds depenedency graph for CompanyXyz assemblies

# Import library functions
Remove-Module DotnetDependencyGraph
Import-Module ../DotnetDependencyGraph.psm1


# 0. Copy DLLs to working folder

$working = Join-Path $PSScriptRoot "../working"
$data = Join-Path $working "data"
Remove-Item $data -Recurse
$newDirectory = New-Item -ItemType Directory -Path $data

Get-ChildItem (Join-Path $PSScriptRoot "..\src\CompanyXyz.DependencySample.Worker\bin\Debug") -Filter CompanyXyz*.dll -Recur -File | `
    ForEach-Object { Copy-Item $_.FullName $data -Force }

# 1. List files, get references, expand data with attribute details, save to CSV (because expanding takes time)

# TODO Run this bit in a new PowerShell Session otherwise all the DLLs are loaded and locked in our current session so executing again will fail
Get-ChildItem (Join-Path $data "CompanyXyz*.*") | Get-ReferencedAssemblies | Resolve-AssemblyReferences | Export-CSV (Join-Path $working "Dependencies-CompanyXyz.csv")

#Get-Content 'Dependencies-Manual-CompanyXyz.csv' | Add-Content 'Working\Dependencies-CompanyXyz.csv'

# 2. Load saved CSV, filter (e.g. direct, included only), convert to DOT using the color table, save to file
# Array of name regex + color pairs. Checks are applied in order until first match.

$nameColor = @( `
    ( '^CompanyXyz\.DependencySample\.Worker', '#ccffcc' )
);

$dotProps = 'rankdir=LR;'

Import-CSV (Join-Path $working "Dependencies-CompanyXyz.csv") `
    | Where-Object { ($_.DependencyType -eq 'Direct') -and ($_.Scope -eq 'Included') } `
    | Where-Object { -not ($_.Assembly -match 'Test|Migrat') } `
    | ConvertTo-DotGraph $nameColor $dotProps | Out-File (Join-Path $working "CompanyXyz.dot") -encoding ASCII

# 3. Use GraphViz to generate graphs

#$graphViz = 'C:\Program Files (x86)\Graphviz2.38\bin\dot.exe'
#& $graphViz `-Tsvg `-oCompanyXyz.svg Working\CompanyXyz.dot
#& $graphViz `-Tpng `-oCompanyXyz.png Working\CompanyXyz.dot


# $storageAssemblyPath = 'C:\Code\dotnet-dependency-graph\sample/working/data/CompanyXyz.DependencySample.Worker.dll'
# $bytes = [System.IO.File]::ReadAllBytes($storageAssemblyPath)
# $assembly = [System.Reflection.Assembly]::Load($bytes)
# $referenced = $assembly.GetReferencedAssemblies();

