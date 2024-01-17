Dotnet Dependency Graph
=======================

A collection of PowerShell functions for extracting and analysing .NET assembly dependenies,
and then generating a dependency graph from them.

Graphs are generated in a structured text format that can then be rended by tools.

Supported output formats:
* PlantUML component diagram
* GraphViz DOT language

Functions
---------

| Function | Description |
| -------- | ----------- |
| Get-ReferencedAssemblies | Pass in a list of file paths and the referencenced assemblies will be extracted
| Resolve-AssemblyReferences | Analyses the references to determine if they are direct, indirect, or redundant
| ConvertTo-PlantUml | Converts to Plant UML graph language, as a component diagram
| ConvertTo-DotGraph | Converts to GraphViz DOT graph language


To use
------

1. Build all your project DLLs/EXEs
2. Copy all the outputs into one folder
3. Use the functions to analyse the dependencies:

```pwsh
# Import the module
Import-Module ./DotnetDependencyGraph.psm1

# List all your company DLLs and extract the references
$references = ls CompanyXyz.*.dll | Get-ReferencedAssemblies

# Analyse references to determine relationships
$analysed = $references | Resolve-AssemblyReferences

# Filter and output to PlantUML
$plantUml = $analysed | Where-Object { ($_.DependencyType -eq 'Direct') } | ConvertTo-PlantUml

# Output to file
$plantUml | Out-File "dotnet-dependencies.puml"
```

Functions have full help, including examples, etc: 

```pwsh
Get-Help ConvertTo-PlantUml -Full
```


Note on dependencies
--------------------

The scripts classify dependencies as either Included or External.

* Included are dependencies between the files being analysed, i.e. the main project.
* External are dependencies to libraries, .NET Framework, and other files outside those being analysed.

Dependencies are also classified as either Indirect, Redundant, or Direct.

* Indirect are where a child has a reference, but the top assembly does not; it is still required, i.e. dependent.
* Redundant is where a child has a reference (i.e. it is already indirect), but the top level also has a reference; i.e. required both directly and by a child.
* Direct is where the assembly has a reference, but no children do (i.e. it is not redundant).

Generally you will want to show only Included, Direct references, for your project only, or all Direct references, for your project and third party references.

You can adjust the filter for the specific references you want to include (e.g. maybe exclude system references)

Generally you don't want to show redundant links  (if a higher level library has a direct reference), to keep the diagram clean.

Sample project
--------------

A sample project is included, that has a `Build-DependencyGraph.ps1` script, configure to call the relevant functions in sequence with the required parameters.

First build the project (`dotnet build`) to generate the DLLs, then run the script `scripts/Build-DependencyGraph.ps1`, and it will generate the files.

The script has an interim step of storing the expanded dependencies into a CSV file (in the `working` directory).

You can copy (or install) the module into your own project, and then adapt the script to run it.


Possible variations
-------------------

The graph generator takes in a dictionary of regular expression keys and colours to use. When processing the graph the function uses the first matching (if any) key. Otherwise the default colours are based on type -- light grey for EXEs (no longer commonly used), plain (white) for your code, and a darker grey for external components.

The colouring and filtering can be changed as desired. It is also possible to manually group assemblies together to make the diagram clearer.

Sometimes it is useful to also include some of the Direct references, to see where various external libraries are used. In this case you probably want to filter out the base .NET Framework (System.* and Microsoft.* ), and only show 'interesting' 3rd party library references.

In some cases Redundant links can also be valuable to show, to find all references, but they often just clutter the diagram.
