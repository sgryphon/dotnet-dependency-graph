Analyse Dependencies
====================

1. Install GraphViz, if you don't already have it (see below)
2. Build all your project DLLs/EXEs and copy them into one folder
3. Run the Analyse-Dependencies.ps1 script

The script has inline code which will:

* copy across the DLLs/EXEs (to the Data directory)
* calculate the dependencies
  * note that there are some manual dependencies that are appended to the end
* generate a DOT file with details of the dependencies
* run GraphViz to generate the graph

The output graph files are written to the main folder, and can be stored in source control.

The working folders (Data and Working) are excluded from source control.

Install GraphViz
----------------

You can use the package management tools in PowerShell, with the ChocolateyGet provider, to install GraphViz:

```
Install-PackageProvider ChocolateyGet
Import-PackageProvider ChocolateyGet
Install-Package Graphviz -Force
```

GraphViz can also be installed directly from  (https://www.graphviz.org/).

Manual Dependencies
-------------------

Some of the EXE dependencies did not calculate correctly, so there is a manual file containing them (Dependencies-Manual-InTruck.csv) that is appended to the output.

The file may need to be updated if dependencies change.


Graph colouring and parameters
------------------------------

The script has an array of regular expressions that control colouring.

Blue = EXE (usually self-hosted Windows Services)
Red = Web Site DLLs (hosted in IIS)
Green = InTruck EXE / other EXE (e.g. simulator and mock services)

There are also other parameters, e.g. if Left-to-Right is a better layout for your architecture.


Note on dependencies
--------------------

The scripts classify dependencies as either Included or External.

* Included are dependencies between the files being analysed, i.e. the main project.
* External are dependencies to libraries, .NET Framework, and other files outside those being analysed.

Dependencies are also classified as either Indirect, Redundant, or Direct.

* Indirect are where a child has a reference, but the top assembly does not; it is still required, i.e. dependent.
* Redundant is where a child has a reference (i.e. it is already indirect), but the top level also has a reference; i.e. required both directly and by a child.
* Direct is where the assembly has a reference, but no children do (i.e. it is not redundant).

The script is configured to only show Included, Direct references.

References to libraries, system DLLs, etc, are not shown.

Only the lowest level (direct) link to a child library is shown. Redundant links are not shown (if a higher level library has a direct reference), to keep the diagram clean.


Possible variations
-------------------

The colouring and filtering can be changed as desired. It is also possible to manually group assemblies together to make the diagram clearer.

Sometimes it is useful to also include some of the Direct references, to see where various external libraries are used. In this case you probably want to filter out the base .NET Framework (System.* and Microsoft.* ), and only show 'interesting' 3rd party library references.

In some cases Redundant links can also be valuable to show, to find all references, but they often just clutter the diagram.
