module PkgBake

using PackageCompiler
using ProgressMeter
using MethodAnalysis

#stdlibs
using Artifacts, Base64, CRC32c, Dates, DelimitedFiles, 
      Distributed, FileWatching, 
      InteractiveUtils, LazyArtifacts, 
      Libdl, LibGit2, LinearAlgebra, Logging,
      Markdown, Mmap, Printf, Profile, Random, REPL, Serialization, SHA,
      SharedArrays, Sockets, SparseArrays, TOML, Test, Unicode, UUIDs,
      ArgTools, Downloads, NetworkOptions, Pkg, Statistics, Tar

const base_stdlibs = [Base, Artifacts, Base64, CRC32c, Dates, DelimitedFiles, 
Distributed, FileWatching, 
InteractiveUtils, LazyArtifacts, 
Libdl, LibGit2, LinearAlgebra, Logging,
Markdown, Mmap, Printf, Profile, Random, REPL, Serialization, SHA,
SharedArrays, Sockets, SparseArrays, TOML, Test, Unicode, UUIDs,
ArgTools, Downloads, NetworkOptions, Pkg, Statistics, Tar]

include("cmd_utils.jl")
include("sanitizer.jl")

function get_all_modules()
    mods = Module[]
    for lib in base_stdlibs
        visit(lib) do obj
            if isa(obj, Module)
                push!(mods, obj)
                return true     # descend into submodules
            end
            false   # but don't descend into anything else (MethodTables, etc.)
        end
    end
    return vcat(mods, base_stdlibs)
end

const bakeable_libs = get_all_modules()

const __BAKEFILE = "bakefile.jl"

global __TRACE_PATH = "" # Avoid getting GC'ed when we force `trace_compile`

function __init__()
    init_dir()
    if !have_trace_compile()
        path, io = mktemp(;cleanup=false)
        close(io) # we don't need it open
        global __TRACE_PATH = path
        force_trace_compile(__TRACE_PATH)
    end
end


function init_dir()
    isempty(DEPOT_PATH) && @error "DEPOT_PATH is empty!"
    dir = joinpath(DEPOT_PATH[1],"pkgbake")
    !isdir(dir) && mkdir(dir)
    return abspath(dir)
end


"""
    bake

Add additional precompiled methods to Base and StdLibs that are self contained.
"""
function bake(;project=dirname(Base.active_project()), yes=false, useproject=false, replace_default=true)
    pkgbakedir = init_dir()

    precompile_lines = readlines(abspath(joinpath(init_dir(), "bakefile.jl")))

    unique!(sort!(precompile_lines))

    pc_unsanitized = joinpath(pkgbakedir, "pkgbake_unsanitized.jl")
    @info "PkgBake: Writing unsanitized precompiles to $pc_unsanitized"
    open(pc_unsanitized, "w") do io
        for line in precompile_lines
            println(io, line)
        end
    end

    original_len = length(precompile_lines)
    sanitized_lines = sanitize_precompile(precompile_lines)
    sanitized_len = length(sanitized_lines)

    pc_sanitized = joinpath(pkgbakedir, "pkgbake_sanitized.jl")
    @info "PkgBake: Writing sanitized precompiles to $pc_sanitized"
    open(pc_sanitized, "w") do io
        for line in sanitized_lines
            println(io, line)
        end
    end

    @info "PkgBake: Found $sanitized_len new precompilable methods for Base out of $original_len generated statements"
    !yes && println("Make new sysimg? [y/N]:")
    if yes || readline() == "y"
        @info "PkgBake: Generating sysimage"
        PackageCompiler.create_sysimage(; precompile_statements_file=pc_sanitized, replace_default=replace_default)

        push_bakefile_back()
    end

    nothing
end


function bakefile_io(f)
    bake = abspath(joinpath(init_dir(), "bakefile.jl"))
    !isfile(bake) && touch(bake)
    open(f, bake, "a")
end

trace_compile_path() = unsafe_string(Base.JLOptions().trace_compile)
current_process_sysimage_path() = unsafe_string(Base.JLOptions().image_file)

"""
atexit hook for caching precompile files

add to .julia/config/startup.jl

```
using PkgBake

atexit(PkgBake.atexit_hook)
```
"""
function atexit_hook()

    !have_trace_compile() && return

    trace_path = trace_compile_path()
    isempty(trace_path) && return

    trace_file = open(trace_path, "r")

    bakefile_io() do io
        for l in eachline(trace_file, keep=true)
            write(io, l)
        end
    end
    close(trace_file)
end


end
