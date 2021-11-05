
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