using
  OceanTurb,
  Test

import OceanTurb: Diffusion

# --
# Run tests
# --

@testset "Utils" begin
  include("utilstests.jl")
  @test test_zeros(Float64)
  @test test_zeros(Float32)
end

@testset "Grids" begin
  include("gridtests.jl")
  nz = 3
  Lz = 4.2
  for T in (Float64, Float32, Float16)
    @test test_uniform_grid_type(T, nz, Lz)
    @test test_uniform_grid_spacing(T, nz, Lz)
    @test test_uniform_grid_limits_zc_right(T, nz, Lz)
    @test test_uniform_grid_limits_zf_right(T, nz, Lz)
    @test test_uniform_grid_limits_zc_left(T, nz, Lz)
    @test test_uniform_grid_limits_zf_left(T, nz, Lz)
  end
end

@testset "Fields" begin
  include("fieldtests.jl")
  nz = 3
  Lz = 4.2
  for T in (Float64, Float32, Float16)
    @test test_cell_field_construction(T, nz, Lz)
    @test test_face_field_construction(T, nz, Lz)
    @test test_cell_∂z(T)
    @test test_face_∂z(T)
    @test test_cell_plus(T)
    @test test_cell_times(T)
  end
  @test test_field_indexing()
end


function test_model(; nz=3, Lz=1.5, timestepper=NullTimestepper())
  grid = UniformGrid(nz, Lz)
  model = Model(grid=grid, solution=CellField(grid), timestepper=timestepper)
  model.solution.data == [0, 0, 0]
end

#=
@testset "Model" begin
  @test test_model()
  solution = CellField(UniformGrid(3, 1.5))
  @test test_model(timestepper=ForwardEulerTimestepper(solution))
end
=#

@testset "Diffusion" begin
  include("diffusiontests.jl")
  @test test_diffusion_basic()
  @test test_diffusion_set_c()
end

#=
@testset "Forcing" begin

  function testforcinginterpolant(fld=:shortwave)
    kwargs = Dict(:tdata=>[0, year], fld=>[0, 1.0])
    forcing = Forcing(; kwargs...)
    finterp = ForcingInterpolant(forcing)
    isapprox(getfield(finterp, fld)(0.6year), 0.6)
  end

  for fld in fieldnames(ForcingInterpolant)
    @test testforcinginterpolant(fld)
  end
end
=#

#=
@testset "Mixing" begin
  include("testmixing.jl")
  @test testconvect1()
  @test testconvect2()
  @test testgradri()
  @test testbulkri()
  @test testbulkmix1()
  @test testbulkmix2()
  @test testgradmixing()
end

@testset "Time stepping" begin
  include("teststeps.jl")
  @test teststepuv1()
  @test teststepuv2()
  @test teststepforward()
end
=#