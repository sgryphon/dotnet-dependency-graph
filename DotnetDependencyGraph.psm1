# Functions for extracting and manipulating DLL dependencies from .NET assemblies

<#
.SYNOPSIS
    Gets all dependencies from a stream of filenames

.DESCRIPTION

    In general you only want to pass in a list of your own assemblies that you want
    to analyse (these are later treated as Scope = Included). All first level external 
    references will be extracted; if you include an external assembly (e.g. a third party DLL),
    then _it's_ references will be expanded and included.

.INPUTS

    List of filenames (strings); ignores values not ending in ".exe" or ".dll".

.OUTPUTS

    Objects with Assembly (name), AssemblyType (EXE or DLL), and References (array of referenced names)

.EXAMPLE

    1. List files, get references, resolve data with attribute details, save to CSV (because resolving takes time)

        ls CompanyXyz.* | Get-ReferencedAssemblies | Resolve-AssemblyReferences | Export-CSV Dependencies-CompanyXyz.csv

    If some DLLs can't be loaded, it may be because PowerShell has an old version of .NET


    2. Load saved CSV, filter (e.g. direct, included only), convert to DOT using the color table, save to file
    Array of name regex + color pairs. Checks are applied in order until first match.

        $nameColor = @( `
            ( "^CompanyXyz\.SystemA", "#ffcccc" ), `
            ( "^CompanyXyz\.SystemB", "#ccffcc" ), `
            ( "^CompanyXyz\.SystemC", "#ccccff" ), `
            );
            
        Import-CSV Dependencies-CompanyXyz.csv | ? { ($_.DependencyType -eq "Direct") -and ($_.Scope -eq "Included") } `
            | ConvertTo-DotGraph $nameColor | Out-File CompanyXyz.dot -encoding ASCII

    3. Use GraphViz to generate graphs (install from https://www.graphviz.org/) 

        &'C:\Program Files\Graphviz2.38\bin\dot.exe' `-Tsvg `-oCompanyXyz.svg CompanyXyz.dot
        &'C:\Program Files\Graphviz2.38\bin\dot.exe' `-Tpng `-oCompanyXyz.png CompanyXyz.dot

#>
function Get-ReferencedAssemblies {
    [CmdletBinding()]    
    param (
        # List of filenames (strings); ignores values not ending in ".exe" or ".dll".
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string[]]
        $InputObject
    )
    begin {
    }
    process {
        $name = [string]$_;
        if ( $name.EndsWith(".exe") -or $name.EndsWith(".dll") ) {
            # Load without locking (by taking an in-memory copy)
            $bytes = [System.IO.File]::ReadAllBytes($name)
            $assembly = [System.Reflection.Assembly]::Load($bytes)

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


<#
.SYNOPSIS
    Expands collection of references to individual lines for direct, redundant and indirect dependencies

.DESCRIPTION

    The entire tree of references (both direct and indirect) is recursively expanded.

    DependencyType: If LongestChain = 1, then the reference is a Direct dependent,
    otherwise if ShortestChain = 1 (and LongestChain > 1), then the reference is Redundant
    (it is including via a chain);
    otherwise, the reference is indirect (only via a chain; no direct reference).

    When graphing, it is common to only show the Direct dependencies, to avoid cluttering
    up the diagram with Redundant and Indirect dependencies.

    Scope: Files in the original input list are Included, otherwise External.

.INPUTS

    Objects with Assembly (name), AssemblyType (EXE or DLL),
    and References (array of referenced names)

.OUTPUTS

    Objects with Assembly, AssemblyType (EXE or DLL), Reference
    (each individual reference), ShortestChain, LongestChain, 
    DependencyType (Direct, Redundant or Indirect),
    Scope (Included or External).

.EXAMPLE

    1. List files, get references, resolve data with attribute details, save to CSV (because resolving takes time)

        ls CompanyXyz.* | Get-ReferencedAssemblies | Resolve-AssemblyReferences | Export-CSV Dependencies-CompanyXyz.csv

    If some DLLs can't be loaded, it may be because PowerShell has an old version of .NET


    2. Load saved CSV, filter (e.g. direct, included only), convert to DOT using the color table, save to file
    Array of name regex + color pairs. Checks are applied in order until first match.

        $nameColor = @( `
            ( "^CompanyXyz\.SystemA", "#ffcccc" ), `
            ( "^CompanyXyz\.SystemB", "#ccffcc" ), `
            ( "^CompanyXyz\.SystemC", "#ccccff" ), `
            );
            
        Import-CSV Dependencies-CompanyXyz.csv | ? { ($_.DependencyType -eq "Direct") -and ($_.Scope -eq "Included") } `
            | ConvertTo-DotGraph $nameColor | Out-File CompanyXyz.dot -encoding ASCII

    3. Use GraphViz to generate graphs (install from https://www.graphviz.org/) 

        &'C:\Program Files\Graphviz2.38\bin\dot.exe' `-Tsvg `-oCompanyXyz.svg CompanyXyz.dot
        &'C:\Program Files\Graphviz2.38\bin\dot.exe' `-Tpng `-oCompanyXyz.png CompanyXyz.dot

#>
function Resolve-AssemblyReferences {
    [CmdletBinding()]    
    param (
        # Objects with Assembly (name), AssemblyType (EXE or DLL), and References (array of referenced names)
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string[]]
        $InputObject
    )
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


<#
.SYNOPSIS
    Convert list of dependencies into DOT graph language format

.DESCRIPTION

    EXE's are output as hexagons, Scope = Included as rectangles, and all other
    assemblies as ovals.

    The $NameColor dictionary can be used to color the output based on the
    first regular expression that matches the assembly name.

    Note: You may want to filter to only include direct dependencies before
    generating graphs.

.INPUTS

    Objects with Assembly, AssemblyType (EXE or DLL), Reference and Scope.

.OUTPUTS

    Lines of DOT code.

.EXAMPLE

    1. List files, get references, resolve data with attribute details, save to CSV (because resolving takes time)

        ls CompanyXyz.* | Get-ReferencedAssemblies | Resolve-AssemblyReferences | Export-CSV Dependencies-CompanyXyz.csv

    If some DLLs can't be loaded, it may be because PowerShell has an old version of .NET


    2. Load saved CSV, filter (e.g. direct, included only), convert to DOT using the color table, save to file
    Array of name regex + color pairs. Checks are applied in order until first match.

        $nameColor = @( `
            ( "^CompanyXyz\.SystemA", "#ffcccc" ), `
            ( "^CompanyXyz\.SystemB", "#ccffcc" ), `
            ( "^CompanyXyz\.SystemC", "#ccccff" ), `
            );
            
        Import-CSV Dependencies-CompanyXyz.csv | ? { ($_.DependencyType -eq "Direct") -and ($_.Scope -eq "Included") } `
            | ConvertTo-DotGraph $nameColor | Out-File CompanyXyz.dot -encoding ASCII

    3. Use GraphViz to generate graphs (install from https://www.graphviz.org/) 

        &'C:\Program Files\Graphviz2.38\bin\dot.exe' `-Tsvg `-oCompanyXyz.svg CompanyXyz.dot
        &'C:\Program Files\Graphviz2.38\bin\dot.exe' `-Tpng `-oCompanyXyz.png CompanyXyz.dot

#>
function ConvertTo-DotGraph {
    [CmdletBinding()]    
    param (
        # Dictionary of name Regex to match name and hex colour to use. Rules are applied in order until first match.
        [string] $NameColor,
        # Additional properties to output to the Dot file
        [string] $DotProps,
        # Objects with Assembly (name), AssemblyType (EXE or DLL), and References (array of referenced names)
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string[]]
        $InputObject
    )
    begin {
        $allReferences = @();
    }
    process {
        $allReferences += $_;
    }
    end {
        Write-Output "digraph G { subgraph cluster_0 { label=""Legend""; ""Executable (.exe)"" [shape=hexagon,style=filled,fillcolor=""#cccccc""]; ""Library (.dll)"" [shape=rectangle,style=filled,fillcolor=""#ffffff""]; ""External Library / Other"" [shape=oval,style=filled,fillcolor=""#eeeeee""]; }";
        Write-Output $DotProps

        $defined = @();

        # Included items
        foreach ($item in $allReferences) {
            if ( -not( $defined -contains $item.Assembly ) ) {
                $format = FormatDot $item.Assembly "Included" $item.AssemblyType $NameColor;
                Write-Output "$format;";
                $defined += $item.Assembly;
            }
        }

        # Referenced items
        foreach ($item in $allReferences) {
            if ( -not( $defined -contains $item.Reference ) ) {
                $format = FormatDot $item.Reference $item.Scope "DLL" $NameColor;
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

Export-ModuleMember -Function Get-ReferencedAssemblies
Export-ModuleMember -Function Resolve-AssemblyReferences
Export-ModuleMember -Function ConvertTo-DotGraph
