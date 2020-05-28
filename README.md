# PkgBake.jl

PkgBake is designed to enable safe and easy speedups of Julia code loading for Package Developers.

It works by tracing and precompiling more specific methods for the Julia Base and Stdlibs
without interfering with packages or development. This is a safer and most conservative form of
package precompilation, as it will not interfere with Projects or Manifests. Of course
you do not get the full speed advantage of a full precompilation, but you get additional
flexibility in development and should generally not need to worry about sysimage states as much.

# Using

Inside your `.julia/config/startup.jl` add the following:

```julia
using PkgBake

atexit(PkgBake.atexit_hook)
```

Now if you start julia with the `--trace-compile=<DIR>` flag, PkgBake will track and
collect these precompile files for you automatically.
On linux you can run ```julia --trace-compile=`mktemp` ```

To "bake" in the new precompiled statements:

```julia
julia> PkgBake.bake()
```

# Design and Use

When the Julia sysimage is created, it knows nothing of downstream
package use. PkgBake is a mechanism to provide specific `precompile` statements only for Base
to save time and stay out of your way. Since the methods added are only in and for Base and
the Stdlibs, this should have little to no effect on development environments.

This is accomplished by "sanitizing" the precompile statements such that only additional
methods targeting Base and the Stdlib are added to the sysimg.

# Design Possibilities

## 1 - Local Cache
The precompile and loading is done locally.

## 2 - Ecosystem Cache
We pregenerate a Base-only precompile file for each julia version. The user will then just need to
pull this file and run. This will work for every published package.

## 3 - Upstream Target

This can be similar to a Linux distro popcon. PkgBake users upload their sanitized precompile files
and the most common precompiled methods get PRed to base.

## 4 - PkgEval Integration

This is similar to 3, except it is run as part of PkgEval on a new release. This might
require PkgEval to run twice.

## Future

Base only methods do not provide a significant speedup, only 2-5% from what has been observed
so far. A possible way forward is to actually manage the trace-compiles _and_ environments.
e.g. `__init__`s take a good deal of time and can be managed by the project tree.
When extracting the trace compiles we organize by project and manage sysimgs.
