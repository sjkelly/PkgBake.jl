module PkgBake

using PackageCompiler
using ProgressMeter

#stdlibs
using Base64, CRC32c, Dates, DelimitedFiles, Distributed, FileWatching,
      InteractiveUtils, Libdl, LibGit2, LinearAlgebra, Logging,
      Markdown, Mmap, Printf, Profile, Random, REPL, Serialization, SHA,
      SharedArrays, Sockets, SparseArrays, SuiteSparse, Test, Unicode, UUIDs,
      Pkg, Statistics

const bakeable_libs = [Base,
    # included stdlibs
    Base64, CRC32c, Dates, DelimitedFiles, Distributed, FileWatching,
    InteractiveUtils, Libdl, LibGit2, LinearAlgebra, Logging,
    Markdown, Mmap, Printf, Profile, Random, REPL, Serialization, SHA,
    SharedArrays, Sockets, SparseArrays, SuiteSparse, Test, Unicode, UUIDs,
    # external
    Pkg, Statistics]
# TODO: Future not included

"""
    bake

Add additional precompiled methods to Base and StdLibs that are self contained.
"""
function bake(;dir="", replace_default=true)
    st = Pkg.installed()
    @info "PkgBake: Loading Packages and generating precompile statments"
    ctx = isempty(dir) ? create_pkg_context(Base.active_project()) : create_pkg_context(dir)
    @show Pkg.Operations.load_manifest_deps(ctx)
    #PackageCompiler.create_sysimage(; precompile_statements_file="ohmyrepl_precompile.jl", replace_default=replace_default)
end

"""
    sanitize_precompile()

Prepares and sanitizes a julia file for precompilation. This removes any non-concrete
methods and anything non-Base or StdLib.
"""
function sanitize_precompile(path::String)
    lines = String[]
    for line in readlines(path)
        # Generally any line with where is non-concrete, so we can skip.
        # Symbol is also runtime dependent so skip as well
        if isempty(line) || contains(line, "where") || contains(line, "Symbol(")
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

"""
    recurse through the call and make sure everything is in Base, Core, or a StdLib
"""
function is_bakeable(ex::Expr)
    @show ex, typeof(ex)
    for arg in ex.args
        @show arg, typeof(arg)
        if is_bakeable(arg)
            continue
        else
            return false
        end
    end
    return true
end

function is_bakeable(ex::Symbol)
    @show ex, typeof(ex)
    for lib in bakeable_libs
        if isdefined(lib, ex)
            return true
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


end
