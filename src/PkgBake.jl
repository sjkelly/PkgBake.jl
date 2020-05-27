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
function bake(;dir=dirname(Base.active_project()), replace_default=true)
    @info "PkgBake: Loading Packages and generating precompile statements for $dir"
    ctx = create_pkg_context(dir)
    deps = values(Pkg.dependencies(create_pkg_context(dir)))

    pipe_out = "pipeout.txt"
    touch(pipe_out)

    precompile_lines = String[]

    progress = Progress(length(deps), 1)
    for dep in deps

        next!(progress, showvalues = [(:dep,dep.name), (:statements, length(precompile_lines))])

        # skip stdlibs
        if in(dep.name, string.(bakeable_libs)) || !dep.is_direct_dep
            continue
        end
        pc_temp = tempname()
        touch(pc_temp)
        cmd = `$(get_julia_cmd()) --project=$dir --trace-compile=$pc_temp -e $("using $(dep.name)")`
        try
            run(pipeline(cmd, stdout=pipe_out, stderr=pipe_out, append=true))
        catch err
            if isa(err, InterruptException)
                @warn "PkgBake: Interrupted by user"
                exit()
            else
                continue
            end
        end
        new_lines = readlines(pc_temp)
        rm(pc_temp)
        if !isempty(new_lines)
            append!(precompile_lines, new_lines)
        end
    end

    unique!(sort!(precompile_lines))

    timestamp = Dates.format(now(), "yyyy-mm-ddTHH_MM")
    pc_unsanitized = "pkgbake_unsanitized_$(timestamp).jl"
    @info "PkgBake: Writing unsanitized precompiles to $pc_unsanitized"
    open(pc_unsanitized, "w") do io
        for line in precompile_lines
            println(io, line)
        end
    end

    original_len = length(precompile_lines)
    @info "PkgBake: Santizing precompile statments"
    sanitized_lines = sanitize_precompile(precompile_lines)
    sanitized_len = length(sanitized_lines)

    pc_sanitized = "pkgbake_sanitized_$(timestamp).jl"
    @info "PkgBake: Writing unsanitized precompiles to $pc_sanitized"
    open(pc_sanitized, "w") do io
        for line in sanitized_lines
            println(io, line)
        end
    end

    @info "PkgBake: Found $sanitized_len precompilable methods for base out of $original_len generated statements"
    #@show precompile_lines, sanitized_lines
    #PackageCompiler.create_sysimage(; precompile_statements_file="ohmyrepl_precompile.jl", replace_default=replace_default)
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


end
