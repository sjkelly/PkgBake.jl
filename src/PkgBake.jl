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

global __PRECOMPILE_CURSOR = 0

function __init__()
    init_dir()
end


function init_dir()
    isempty(DEPOT_PATH) && @error "DEPOT_PATH is empty!"
    dir = joinpath(DEPOT_PATH[1],"pkgbake")
    !isdir(dir) && mkdir(dir)
    return abspath(dir)
end

function init_project_dir(project::String)
    project_dict = Pkg.Types.parse_toml(project)
    if haskey(project_dict, "uuid")
        uuid = project_dict["uuid"]
    else
        uuid = "UNAMED"
        # TODO, need to resolve for v1.x somehow as they don't have UUIDs
    end
    project_dir = joinpath(init_dir(), uuid)
    !isdir(project_dir) && mkdir(project_dir)
end


"""
    bake

Add additional precompiled methods to Base and StdLibs that are self contained.
"""
function bake(;project=dirname(Base.active_project()), useproject=false, replace_default=true)
    pkgbakedir = init_dir()

    if useproject
        add_project_runtime_precompiles(project)
    end

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
    println("Make new sysimg? [y/N]:")
    ans = readline()
    if ans == "y"
        @info "PkgBake: Generating sysimage"
        PackageCompiler.create_sysimage(; precompile_statements_file=pc_sanitized, replace_default=replace_default)

        push_bakefile_back()
    end

    nothing
end


function add_project_runtime_precompiles(project)
    @info "PkgBake: Observing load-time precompile statements for project: $project"
    ctx = create_pkg_context(project)
    deps = values(Pkg.dependencies(create_pkg_context(project)))

    precompile_lines = String[]

    progress = Progress(length(deps), 1)

    bakefile_io() do io
        println(io, pkgbake_stamp())

        for dep in deps

            next!(progress, showvalues = [(:dep,dep.name), (:statements, length(precompile_lines))])

            # skip stdlibs and non-direct deps
            # TODO: Not sure if direct_dep means what i think it does
            if in(dep.name, string.(bakeable_libs)) || !dep.is_direct_dep
                continue
            end
            pc_temp = tempname()
            touch(pc_temp)
            cmd = `$(get_julia_cmd()) --project=$dir --startup-file=no --trace-compile=$pc_temp -e $("using $(dep.name)")`
            try
                run(pipeline(cmd, devnull))
            catch err
                if isa(err, InterruptException)
                    @warn "PkgBake: Interrupted by user"
                    exit()
                else
                    continue
                end
            end
            for l in eachline(pc_temp,keep=true)
                write(io, l)
            end
            rm(pc_temp)
        end
    end
end

const N_HISTORY = 10
bakefile_n(n) = abspath(joinpath(init_dir(), "bakefile_$(n).jl"))
function push_bakefile_back()
    dir = init_dir()
    bake = abspath(joinpath(dir, "bakefile.jl"))
    isfile(bakefile_n(N_HISTORY)) && rm(bakefile_n(N_HISTORY))
    # push back the history stack
    for n in (N_HISTORY-1):1
        isfile(bakefile_n(n)) && mv(bakefile_n(n), bakefile_n(n+1),force=true)
    end
    mv(bake, bakefile_n(1),force=true)
    touch(bake)

    return nothing
end


"""
    sanitize_precompile()

Prepares and sanitizes a julia file for precompilation. This removes any non-concrete
methods and anything non-Base or StdLib.
"""
function sanitize_precompile(precompile_lines::Vector{String})
    lines = String[]
    for line in precompile_lines
        # Generally any line with where is non-concrete, so we can skip.
        # Symbol is also runtime dependent so skip as well
        if isempty(line) || contains(line, '#') || contains(line, "where") || contains(line, "Symbol(")
            continue
        else
            try
                if can_precompile(Meta.parse(line))
                    push!(lines, line)
                end
            catch err
                show(err)
            end
        end
    end
    lines
end

"""
    can_precompile

Determine if this expr is something we can precompile.
"""
function can_precompile(ex::Expr)
    if ex.head !== :call && ex.args[1] !== :precompile
        return false
    else
        return is_bakeable(ex)
    end
end

# TODO: Some Base are marked nospecialize, so we should filter these out also
"""
    recurse through the call and make sure everything is in Base, Core, or a StdLib
"""
function is_bakeable(ex::Expr)

    # handle submodule (this might not be robust)
    if ex.head === :. && is_bakeable(ex.args[1])
        return true
    end

    for arg in ex.args
        #@show arg, typeof(arg)
        if is_bakeable(arg)
            continue
        else
            return false
        end
    end
    return true
end

function is_bakeable(ex::Symbol)
    for lib in bakeable_libs
        if isdefined(lib, ex)
            return true
        else
            continue
        end
    end
    return false
end

function is_bakeable(ex::QuoteNode)
    return is_bakeable(ex.value)
end

function is_bakeable(n::T) where T <: Number
    return true
end

function get_julia_cmd()
    julia_path = joinpath(Sys.BINDIR, Base.julia_exename())
    cmd = `$julia_path --color=yes --startup-file=no`
end

function create_pkg_context(project)
    project_toml_path = Pkg.Types.projectfile_path(project)
    if project_toml_path === nothing
        error("could not find project at $(repr(project))")
    end
    return Pkg.Types.Context(env=Pkg.Types.EnvCache(project_toml_path))
end

function pkgbake_stamp()
    "\n\t#version = $(VERSION); date = $(Dates.now())"
end

function bakefile_io(f)
    bake = abspath(joinpath(init_dir(), "bakefile.jl"))
    !isfile(bake) && touch(bake)
    open(f, bake, "a")
end

function have_trace_compile()
    jloptstc = Base.JLOptions().trace_compile
    jloptstc == C_NULL && return false
    return true
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
        println(io, pkgbake_stamp())
        for l in eachline(trace_file, keep=true)
            write(io, l)
        end
    end
    close(trace_file)
end


end
