# DotnetDependencyGraph.psm1
# Functions for extracting DLL dependencies from .NET assemblies and generating dependency graphs
#
# Copyright (C) 2016, 2017, 2019, 2023 Sly Gryphon
# https://github.com/sgryphon/dotnet-dependency-graph
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

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

    # List files, get references, resolve data with attribute details, save to CSV (because resolving takes time)

    ls CompanyXyz.* | Get-ReferencedAssemblies | Resolve-AssemblyReferences | Export-CSV Dependencies-CompanyXyz.csv

    # You can then filter and convert the dependency list to graph formats, e.g. ConvertTo-DotGraph
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

    # List files, get references, resolve data with attribute details, save to CSV (because resolving takes time)

    ls CompanyXyz.*.dll | Get-ReferencedAssemblies | Resolve-AssemblyReferences | Export-CSV Dependencies-CompanyXyz.csv

    # You can then filter and convert the dependency list to graph formats, e.g. ConvertTo-DotGraph

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
    Convert list of dependencies into C4-PlantUML component diagram format

.DESCRIPTION

    See: https://github.com/plantuml-stdlib/C4-PlantUML

    Note: You may want to filter to only include direct dependencies before
    generating graphs.

.INPUTS

    Objects with Assembly, AssemblyType (EXE or DLL), Reference and Scope.

.OUTPUTS

    Lines of C4-PlantUML code.

.EXAMPLE

    # Load saved CSV, filter (e.g. direct, included only), convert using a color table, save to file

    # Array of name regex + color pairs. Checks are applied in order until first match.
    $tagColor = @{ `
        '^CompanyXyz\.SystemA' = 'Up'; `
        '^CompanyXyz\.SystemB' = 'Charm'; `
        '^CompanyXyz\.SystemC' = 'Strange'; `
    };

    $additionalContent = "AddElementTag(""Up"", `$backgroundColor=""#ffcccc"")`n" `
        + "AddElementTag(""Charm"", `$backgroundColor=""#ccffcc"")`n" `
        + "AddElementTag(""Strange"", `$backgroundColor=""#ccccff"")`n"

    Import-CSV Dependencies-CompanyXyz.csv | ? { ($_.DependencyType -eq "Direct") -and ($_.Scope -eq "Included") } `
        | ConvertTo-C4ComponentDiagram -TagColor $tagColor -AdditionalContent $additionalContent
        | Out-File c4-components-CompanyXyz.puml

    # Use PlantUML to generate graphs (https://plantuml.com/)

#>
function ConvertTo-C4ComponentDiagram {
    [CmdletBinding()]    
    param (
        # Document title
        [string] $Title,
        # Array of name Regex to match and tag pairs. Rules are applied in order until first match. Pass in formatting for the tags in AdditionalContent.
        $NameTag,
        # Additional content to add to the start of the document
        [string] $AdditionalContent,
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
        if ( -not $Title ) {
            $Title = "Component diagram - dotnet assembly dependencies";
        }

        Write-Output "@startuml"
        Write-Output ""
        Write-Output "!include <C4/C4_Component>"
        # Write-Output "!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Component.puml"
        Write-Output "AddComponentTag(""Application"", `$bgColor=""#0000ff"")"
        Write-Output ""
        Write-Output "title $Title"
        Write-Output ""

        if ($AdditionalContent) {
            Write-Output $AdditionalContent
            Write-Output ""    
        }
        
        $defined = @();

        # Included items
        foreach ($item in $allReferences) {
            if ( -not( $defined -contains $item.Assembly ) ) {
                $format = FormatC4Component $item.Assembly "Included" $item.AssemblyType $NameTag;
                Write-Output "$format";
                $defined += $item.Assembly;
            }
        }

        Write-Output ""

        # Referenced items
        foreach ($item in $allReferences) {
            if ( -not( $defined -contains $item.Reference ) ) {
                $format = FormatC4Component $item.Reference $item.Scope "DLL" $NameTag;
                Write-Output "$format";
                $defined += $item.Reference;
            }
        }

        Write-Output ""

        # Links
        foreach ($item in $allReferences) {
            Write-Output "Rel($($item.Assembly), $($item.Reference), ""Use"", "".NET reference"")"
        }

        Write-Output ""
        Write-Output "SHOW_LEGEND()"
        Write-Output ""
        Write-Output "@enduml"
    }
}

function FormatC4Component ( $name, $scope, $assemblyType, $nameTag ) {
    # Shape based on type
    if ( $assemblyType -eq "EXE" ) {
        $tag = "Application"; # Default green
    }
    else {
        if ( $scope -eq "Included" ) {
            $macro = "Component"
        }
        else {
            $macro = "Component_Ext"
        }
    }

    # Tag based on name
    $tag = ""
    foreach ($key in $nameTag.Keys) {
        if ( $name -match $key ) {
            $tag = $nameTag[$key];
            break;
        }
    }

    $tagPart = ""
    if ($tag) {
        $tagPart = ", `$tags=""$tag""";
    }

    $format = "$macro($name, ""$name"", ""$assemblyType""$tagPart)";
    return $format; 
}


<#
.SYNOPSIS
    Convert list of dependencies into PlantUML format

.DESCRIPTION

    Note: You may want to filter to only include direct dependencies before
    generating graphs.

.INPUTS

    Objects with Assembly, AssemblyType (EXE or DLL), Reference and Scope.

.OUTPUTS

    Lines of PlantUML code.

.EXAMPLE

    # Load saved CSV, filter (e.g. direct, included only), convert using a color table, save to file

    # Array of name regex + color pairs. Checks are applied in order until first match.
    $nameColor = @{ `
        '^CompanyXyz\.SystemA' = '#ffcccc'; `
        '^CompanyXyz\.SystemB' = '#ccffcc'; `
        '^CompanyXyz\.SystemC' = '#ccccff'; `
    };
            
    Import-CSV Dependencies-CompanyXyz.csv | ? { ($_.DependencyType -eq "Direct") -and ($_.Scope -eq "Included") } `
        | ConvertTo-PlantUml -NameColor $nameColor | Out-File dotnet-dependencies-CompanyXyz.puml

    # Use PlantUML to generate graphs (https://plantuml.com/)

#>
function ConvertTo-PlantUml {
    [CmdletBinding()]    
    param (
        # Document title
        [string] $Title,
        # Array of name Regex to match and hex colour pairs. Rules are applied in order until first match.
        $NameColor,
        # Additional content to add to the start of the document
        [string] $AdditionalContent,
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
        if ( -not $Title ) {
            $Title = "Component diagram - dotnet assembly dependencies";
        }

        Write-Output "@startuml"
        Write-Output ""
        Write-Output "title $Title"
        Write-Output ""

        if ($AdditionalContent) {
            Write-Output $AdditionalContent
            Write-Output ""    
        }
        
        $defined = @();

        # Included items
        foreach ($item in $allReferences) {
            if ( -not( $defined -contains $item.Assembly ) ) {
                $format = FormatPlantUmlComponent $item.Assembly "Included" $item.AssemblyType $NameColor;
                Write-Output "$format";
                $defined += $item.Assembly;
            }
        }

        Write-Output ""

        # Referenced items
        foreach ($item in $allReferences) {
            if ( -not( $defined -contains $item.Reference ) ) {
                $format = FormatPlantUmlComponent $item.Reference $item.Scope "DLL" $NameColor;
                Write-Output "$format";
                $defined += $item.Reference;
            }
        }

        Write-Output ""

        # Links
        foreach ($item in $allReferences) {
            Write-Output "[$($item.Assembly)] ..> [$($item.Reference)] : <<use>>"
        }

        Write-Output ""
        Write-Output "@enduml"
    }
}

function FormatPlantUmlComponent ( $name, $scope, $assemblyType, $nameColor ) {
    # Shape based on type
    if ( $assemblyType -eq "EXE" ) {
        $stereotype = "<<Application>>";
        $color = "#cccccc"; # Default grey
    }
    else {
        if ( $scope -eq "Included" ) {
            $stereotype = $null;
            $color = "#ffffff"; # Default white
        }
        else {
            $stereotype = "<<External>>";
            $color = "#eeeeee"; # Default off-white
        }
    }

    # Color based on name
    foreach ($key in $nameColor.Keys) {
        if ( $name -match $key ) {
            $color = $nameColor[$key];
            break;
        }
    }

    $format = "component [$name] $stereotype $color";
    return $format; 
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

    # Load saved CSV, filter (e.g. direct, included only), convert to DOT using the color table, save to file

    # Array of name regex + color pairs. Checks are applied in order until first match.
    $nameColor = @{ `
        '^CompanyXyz\.SystemA' = '#ffcccc'; `
        '^CompanyXyz\.SystemB' = '#ccffcc'; `
        '^CompanyXyz\.SystemC' = '#ccccff'; `
    };
            
    Import-CSV Dependencies-CompanyXyz.csv | ? { ($_.DependencyType -eq "Direct") -and ($_.Scope -eq "Included") } `
        | ConvertTo-DotGraph $nameColor | Out-File CompanyXyz.dot -encoding ASCII

    # Use GraphViz to generate graphs (install from https://www.graphviz.org/) 

    &'C:\Program Files\Graphviz2.38\bin\dot.exe' `-Tsvg `-oCompanyXyz.svg CompanyXyz.dot
    &'C:\Program Files\Graphviz2.38\bin\dot.exe' `-Tpng `-oCompanyXyz.png CompanyXyz.dot

#>
function ConvertTo-DotGraph {
    [CmdletBinding()]    
    param (
        # Array of name Regex to match and hex colour pairs. Rules are applied in order until first match.
        $NameColor,
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
    foreach ($key in $nameColor.Keys) {
        if ( $name -match $key ) {
            $color = $nameColor[$key];
            break;
        }
    }

    $format = """$name"" [shape=$shape,style=filled,fillcolor=""$color""]";
    return $format; 
}


Export-ModuleMember -Function ConvertTo-C4ComponentDiagram
Export-ModuleMember -Function ConvertTo-DotGraph
Export-ModuleMember -Function ConvertTo-PlantUml
Export-ModuleMember -Function Get-ReferencedAssemblies
Export-ModuleMember -Function Resolve-AssemblyReferences
