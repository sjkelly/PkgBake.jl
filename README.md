# PkgBake.jl

PkgBake is designed to enable safe and easy speedups of Julia code loading for Package Developers.

It consists of two elements:
 - A precompile caching system
 - A method sanitiser


## Using

Inside your `.julia/config/startup.jl` add the following:

```julia
import PkgBake

atexit(PkgBake.atexit_hook)
```

PkgBake will enable the `--trace-compile` equivalent automatically for you, and cache the files into `.julia/pkgbake/`.
If you call julia with `--trace-compile`, PkgBake will copy the files at exit.

To "bake" in the new precompiled statements that are exclusive to Base and Stdlibs, run:

```julia
julia> PkgBake.bake()
```

With this, you should notice anywhere from a 5-15% performance improvment, as Base and Stdlib method have been added to the sysimg.
Of course, this still allows you to change projects and such.

## Design and Use

When the Julia sysimage is created, it knows nothing of downstream
package use. PkgBake is a mechanism to provide specific `precompile` statements only for Base
and Stdlibs to save time and stay out of your way. Since the methods added are only in and for Base and
the Stdlibs, this should have little to no effect on development environments.

This is accomplished by "sanitizing" the precompile statements such that only additional
methods targeting Base and the Stdlib are added to the sysimg.

This is mostly a managment layer over Pkg, PackageCompiler, and MethodAnalysis.

There is some possibility to turning `PkgBake` into a general `precompile` database. Right now, this is
just fun hacks with some marginal profit :)

## Design Possibilities

### 1 - Local Cache
The precompile and loading is done locally.

### 2 - Ecosystem Cache
We pregenerate a Base-only precompile file for each julia version. The user will then just need to
pull this file and run. This will work for every published package.

### 3 - Upstream Target

This can be similar to a Linux distro popcon. PkgBake users upload their sanitized precompile files
and the most common precompiled methods get PRed to base.

### 4 - PkgEval Integration

This is similar to 3, except it is run as part of PkgEval on a new release. This might
require PkgEval to run twice.

### Future

Base only methods do not provide a significant speedup, only 2-5% from what has been observed
so far. A possible way forward is to actually manage the trace-compiles _and_ environments.
e.g. `__init__`s take a good deal of time and can be managed by the project tree.
When extracting the trace compiles we organize by project and manage sysimgs.

### Results (so far)
```
^[[Asteve@sjkdsk1:~$ juliarc
(c, typeof(c)) = (Dict{String,Any}(), Dict{String,Any})
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.5.0-beta1.0 (2020-05-28)
 _/ |\__'_|_|_|\__'_|  |
|__/                   |

julia> @time using Plots
  5.647230 seconds (7.96 M allocations: 496.850 MiB, 1.25% gc time)

julia> @time scatter!(rand(50))
  5.901242 seconds (10.30 M allocations: 534.544 MiB, 4.81% gc time)

julia> ^C

julia>
steve@sjkdsk1:~$ juliarc --trace-compile=`mktemp`
(c, typeof(c)) = (Dict{String,Any}(), Dict{String,Any})
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.5.0-beta1.0 (2020-05-28)
 _/ |\__'_|_|_|\__'_|  |
|__/                   |

julia> @time using Plots
  5.627413 seconds (7.96 M allocations: 496.846 MiB, 1.24% gc time)

julia> @time scatter!(rand(50))
  6.068422 seconds (10.29 M allocations: 534.059 MiB, 3.97% gc time)

julia> ^C

julia>
steve@sjkdsk1:~$ juliarc
(c, typeof(c)) = (Dict{String,Any}(), Dict{String,Any})
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.5.0-beta1.0 (2020-05-28)
 _/ |\__'_|_|_|\__'_|  |
|__/                   |

julia> PkgBake.bake()
[ Info: PkgBake: Writing unsanitized precompiles to /home/steve/.julia/pkgbake/pkgbake_unsanitized.jl
[ Info: PkgBake: Writing sanitized precompiles to /home/steve/.julia/pkgbake/pkgbake_sanitized.jl
[ Info: PkgBake: Found 156 new precompilable methods for Base out of 577 generated statements
[ Info: PkgBake: Generating sysimage
[ Info: PackageCompiler: creating system image object file, this might take a while...
[ Info: PackageCompiler: default sysimg replaced, restart Julia for the new sysimg to be in effect

julia> ^C

julia>
steve@sjkdsk1:~$ juliarc
(c, typeof(c)) = (Dict{String,Any}(), Dict{String,Any})
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.5.0-beta1.0 (2020-05-28)
 _/ |\__'_|_|_|\__'_|  |
|__/                   |

julia> @time using Plots
  5.466470 seconds (7.61 M allocations: 479.033 MiB, 1.98% gc time)

julia> @time scatter!(rand(50))
  5.376421 seconds (9.41 M allocations: 488.071 MiB, 2.19% gc time)
```
