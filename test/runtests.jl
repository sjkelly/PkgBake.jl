using PkgBake
using Test

@testset "options probe" begin
    @test PkgBake.have_trace_compile() == true

end

