# PkgBake.jl

PkgBake is designed to enable safe and easy speedups of Julia code loading for Package Developers.

The basic idea is to precompile more specific methods for the Julia Base and Stdlibs
without interfering with packages. This is a safer and most conservative form of
package precompilation, as it will not interfere with Projects or Manifests. Of course
you do not get the full speed advantage of a full precompilation, but you get additional
flexibility in development and should generally not need to worry about sysimage states.

# Design and Use

When the Julia sysimage is created, it knows nothing of downstream
package use. PkgBake is a mechanism to provide specific `precompile` statements only for Base
to save time and stay out of your way.


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
