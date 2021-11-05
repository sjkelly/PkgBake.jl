
"""
    have_trace_compile

`true` if Julia is running with `--trace-compile`
"""
function have_trace_compile()
    jloptstc = Base.JLOptions().trace_compile
    jloptstc == C_NULL && return false
    return true
end

"""
    force_trace_compile(::String)

Force the trace compile to be enabled for the given file.
"""
function force_trace_compile(path::String)
    # find trace-compile field offset
    trace_compile_offset = 0
    for i = 1:fieldcount(Base.JLOptions)
        if fieldname(Base.JLOptions, i) === :trace_compile
            trace_compile_offset = fieldoffset(Base.JLOptions, i)
            break
        end
    end
    unsafe_store!(cglobal(:jl_options, Ptr{UInt8})+trace_compile_offset, pointer(path))
end