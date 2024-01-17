# Functions for extracting and manipulating DLL dependencies 

# 1. List files, get references, expand data with attribute details, save to CSV (because expanding takes time)
# 
# ls CompanyXyz.* | Get-ReferencedAssemblies | Expand-AssemblyReferences | Export-CSV Dependencies-CompanyXyz.csv
#
# If some DLLs can't be loaded, it may be because PowerShell has an old version of .NET


# 2. Load saved CSV, filter (e.g. direct, included only), convert to DOT using the color table, save to file
# Array of name regex + color pairs. Checks are applied in order until first match.
#
# $nameColor = @( `
#	( "^CompanyXyz\.SystemA", "#ffcccc" ), `
#	( "^CompanyXyz\.SystemB", "#ccffcc" ), `
#	( "^CompanyXyz\.SystemC", "#ccccff" ), `
#	);
#	
# Import-CSV Dependencies-CompanyXyz.csv | ? { ($_.DependencyType -eq "Direct") -and ($_.Scope -eq "Included") } `
#   | Generate-Dot $nameColor | Out-File CompanyXyz.dot -encoding ASCII
#

# 3. Use GraphViz to generate graphs
# (install from https://www.graphviz.org/) 
#
# &'C:\Program Files\Graphviz2.38\bin\dot.exe' `-Tsvg `-oCompanyXyz.svg CompanyXyz.dot
# &'C:\Program Files\Graphviz2.38\bin\dot.exe' `-Tpng `-oCompanyXyz.png CompanyXyz.dot
#


# ------------------------------------------------------------------------------
# Get-ReferencedAssemblies
#  $_       List of filenames (strings); ignores values not ending in ".exe" or ".dll".
#  OUTPUT:  Objects with Assembly (name), AssemblyType (EXE or DLL),
#           and References (array of referenced names)
#
#  In general you only want to pass in a list of your own assemblies that you want
#  to analyse (these are later treated as Scope = Included). All first level external 
#  references will be extracted; if you include an external assembly (e.g. a third party DLL),
#  then _it's_ references will be expanded and included.
#

# Gets all dependencies from stream of filenames
function Get-ReferencedAssemblies () {
    begin {
    }
    process {
        $name = [string]$_;
        if ( $name.EndsWith(".exe") -or $name.EndsWith(".dll") ) {
            if ( $PSVersionTable.PSVersion.Major -ge 6 ) {
                $assembly = [System.Reflection.Assembly]::LoadFrom($name);
            } else {
                $assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($name);
            }

            $referenced = $assembly.GetReferencedAssemblies();

            $references = @();
            foreach ( $item in $referenced ) {
                $references += $item.Name;
            }

            $object = "" | Select-Object Assembly, AssemblyType, References;
            $object.Assembly = $assembly.GetName().Name;
            if ( $name.EndsWith(".exe") ) {
                $object.AssemblyType = "EXE";
            }
            else {
                $object.AssemblyType = "DLL";
            }
            $object.References = $references;
            Write-Output $object;
        }
    }
    end {
    }
}


# ------------------------------------------------------------------------------
# Expand-AssemblyReferences
#  $_       Objects with Assembly (name), AssemblyType (EXE or DLL),
#           and References (array of referenced names)
#  OUTPUT:  Objects with Assembly, AssemblyType (EXE or DLL), Reference
#           (each individual reference), ShortestChain, LongestChain, 
#           DependencyType (Direct, Redundant or Indirect),
#           Scope (Included or External).
#
#  The entire tree of references (both direct and indirect) is recursively expanded.
#
#  DependencyType: If LongestChain = 1, then the reference is a Direct dependent,
#  otherwise if ShortestChain = 1 (and LongestChain > 1), then the reference is Redundant
#  (it is including via a chain);
#  otherwise, the reference is indirect (only via a chain; no direct reference).
#
#  When graphing, it is common to only show the Direct dependencies, to avoid cluttering
#  up the diagram with Redundant and Indirect dependencies.
#
#  Scope: Files in the original input list are Included, otherwise External.
#
 
# Expands collection of references to individual lines for direct, redundant and indirect dependencies
function Expand-AssemblyReferences () {
    begin {
        # Build lookup dictionary
        $allAssemblyReferences = @{};
        $allAssemblyType = @{};
    }
    process {
        $allAssemblyReferences[$_.Assembly] = $_.References;
        $allAssemblyType[$_.Assembly] = $_.AssemblyType;
    }
    end {
        # Once lookup dictionary is complete, use it to create the dependency tree
        $expandedReferences = @{};
        foreach ($item in $allAssemblyReferences.Keys) {
            #Write-Host $item;
            $visited = @();
            $visited += $item;
            RecurseAddDescendents $allAssemblyReferences $visited $expandedReferences $allAssemblyType[$item];
        }

        # Update dependency attributes
        foreach ($entryKey in $expandedReferences.Keys) {
            $entry = $expandedReferences[$entryKey];
            if ($entry.LongestChain -eq 1) {
                $entry.DependencyType = "Direct";
            }
            else {
                if ($entry.ShortestChain -eq 1) {
                    $entry.DependencyType = "Redundant";
                }
                else {
                    $entry.DependencyType = "Indirect";
                }
            }

            $reference = $entry.Reference;
            if ( $allAssemblyReferences.ContainsKey($reference) ) {
                $entry.Scope = "Included";
            }
            else {
                $entry.Scope = "External";
            }
        }

        # Output
        foreach ($entryKey in $expandedReferences.Keys) {
            $entry = $expandedReferences[$entryKey];
            Write-Output $entry;
        }
    }	
}

function RecurseAddDescendents($lookup, $visited, $result, $assemblyType) {
    $current = $visited[-1]; # Last node
    if ( -not $lookup.ContainsKey($current) ) {
        # Not in lookup table
        return;
    }
    $start = $visited[0];
    $dependencies = $lookup[$current];
    foreach ($item in $dependencies) {
        if ( $visited -contains $item ) {
            # Circular link detected; finish processing branch
        }
        else {
            $chainLength = $visited.Length;
            $key = "$start|$item";
            $object = $result[$key];
            if ( -not $object ) {
                $object = "" | Select-Object Assembly, AssemblyType, Reference, ShortestChain, LongestChain, DependencyType, Scope;
                $object.Assembly = $current;
                $object.AssemblyType = $assemblyType;
                $object.Reference = $item;
                $object.ShortestChain = $chainLength;
                $object.LongestChain = $chainLength;
            }
            else {
                if ( $chainLength -lt $object.ShortestChain ) {
                    $object.ShortestChain = $chainLength;
                }
                if ( $chainLength -gt $object.LongestChain ) {
                    $object.LongestChain = $chainLength;
                }
            }
            $result[$key] = $object;

            # Recurse
            $visited += $item;
            RecurseAddDescendents $lookup $visited $result $assemblyType;
            $visited = $visited[0..($visited.Length - 2)];
        }
    }
}


# ------------------------------------------------------------------------------
# Generate-Dot
#  $nameColor  Dictionary of Regex to match name and hex color to use.
#  $_          Objects with Assembly, AssemblyType (EXE or DLL), Reference and Scope.
#  OUTPUT:     Lines of DOT code.
#
#  EXE's are output as hexagons, Scope = Included as rectangles, and all other
#  assemblies as ovals.
#
#  The $nameColor dictionary can be used to color the output based on the
#  first regular expression that matches the assembly name.
#  
#  Note: You may want to filter to only include direct dependencies before
#  generating graphs.
#

# Convert list of dependencies into DOT graph language format
function Generate-Dot ($nameColor, $dotProps) {
    begin {
        $allReferences = @();
    }
    process {
        $allReferences += $_;
    }
    end {
        Write-Output "digraph G { subgraph cluster_0 { label=""Legend""; ""Executable (.exe)"" [shape=hexagon,style=filled,fillcolor=""#cccccc""]; ""Library (.dll)"" [shape=rectangle,style=filled,fillcolor=""#ffffff""]; ""External Library / Other"" [shape=oval,style=filled,fillcolor=""#eeeeee""]; }";
        Write-Output $dotProps

        $defined = @();

        # Included items
        foreach ($item in $allReferences) {
            if ( -not( $defined -contains $item.Assembly ) ) {
                $format = FormatDot $item.Assembly "Included" $item.AssemblyType $nameColor;
                Write-Output "$format;";
                $defined += $item.Assembly;
            }
        }

        # Referenced items
        foreach ($item in $allReferences) {
            if ( -not( $defined -contains $item.Reference ) ) {
                $format = FormatDot $item.Reference $item.Scope "DLL" $nameColor;
                Write-Output "$format;";
                $defined += $item.Reference;
            }
        }

        # Links
        foreach ($item in $allReferences) {
            Write-Output "    ""$($item.Assembly)"" -> ""$($item.Reference)"";"
        }

        Write-Output "}";
    }
}

# EXE's are hexagons, Included DLLs are rectangles, and other items are ovals
function FormatDot ( $name, $scope, $assemblyType, $nameColor ) {
    # Shape based on type
    if ( $assemblyType -eq "EXE" ) {
        $shape = "hexagon";
        $color = "#cccccc"; # Default grey
    }
    else {
        if ( $scope -eq "Included" ) {
            $shape = "rectangle";
            $color = "#ffffff"; # Default white
        }
        else {
            $shape = "oval";
            $color = "#eeeeee"; # Default off-white
        }
    }

    # Color based on name
    foreach ($keyValue in $nameColor) {
        $key = $keyValue[0];
        if ( $name -match $key ) {
            $color = $keyValue[1];
            break;
        }
    }

    $format = """$name"" [shape=$shape,style=filled,fillcolor=""$color""]";
    return $format; 
}


# ------------------------------------------------------------------------------
# Inline

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
