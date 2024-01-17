# ------------------------------------------------------------------------------
# Inline

. ../DotnetDependencyGraph.ps1

Remove-Item Data -Recurse
New-Item -ItemType Directory -Path Data

Get-ChildItem ..\.. -Filter CompanyXyz*.dll -Recur -File | `
    Where-Object { -not ($_.FullName -match 'docs') } | `
    ForEach-Object { cp $_.FullName Data -Force }

Get-ChildItem ..\.. -Filter CompanyXyz*.exe -Recur -File | `
    Where-Object { -not ($_.FullName -match 'docs') } | `
    ForEach-Object { cp $_.FullName Data -Force }

# 1. List files, get references, expand data with attribute details, save to CSV (because expanding takes time)

if (-not (Test-Path 'Working')) {
    New-Item -ItemType Directory -Path 'Working'
}

# Run this bit in a new PowerShell Session otherwise all the DLLs are loaded and locked in our current session so executing again will fail
Get-ChildItem Data\CompanyXyz*.* | Get-ReferencedAssemblies | Expand-AssemblyReferences | Export-CSV 'Working\Dependencies-CompanyXyz.csv'

#Get-Content 'Dependencies-Manual-CompanyXyz.csv' | Add-Content 'Working\Dependencies-CompanyXyz.csv'

# 2. Load saved CSV, filter (e.g. direct, included only), convert to DOT using the color table, save to file
# Array of name regex + color pairs. Checks are applied in order until first match.

$nameColor = @( `
    ( '^CompanyXyz\.Services\.Builder\.Api$', '#ffcccc' ), `
    ( '^CompanyXyz\.System1\.', '#ccffcc' ), `
    ( '^CompanyXyz\.System2\.', '#ccccff' )
);

$dotProps = 'rankdir=LR;'

Import-CSV 'Working\Dependencies-CompanyXyz.csv' `
    | Where-Object { ($_.DependencyType -eq 'Direct') -and ($_.Scope -eq 'Included') } `
    | Where-Object { -not ($_.Assembly -match 'Test|Migrat') } `
    | Generate-Dot $nameColor $dotProps | Out-File 'Working\CompanyXyz.dot' -encoding ASCII

# 3. Use GraphViz to generate graphs

$graphViz = 'C:\Program Files (x86)\Graphviz2.38\bin\dot.exe'

& $graphViz `-Tsvg `-oCompanyXyz.svg Working\CompanyXyz.dot
& $graphViz `-Tpng `-oCompanyXyz.png Working\CompanyXyz.dot
