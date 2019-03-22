module OceanTurb

export # This file, core functionality:
    AbstractModel,
    AbstractSolution,
    AbstractParameters,
    Clock,
    time,
    iter,
    set!,
    reset!,

    # utils.jl
    second,
    minute,
    hour,
    day,
    year,
    stellaryear,
    Ω,
    pressenter,
    @zeros,
    @specify_solution,
    @add_standard_model_fields,

    # grids.jl
    Grid,
    UniformGrid,
    height,
    length,
    size,

    # fields.jl
    FieldLocation,
    Cell,
    Face,
    AbstractField,
    Field,
    CellField,
    FaceField,
    Δc,
    Δf,
    onface,
    oncell,
    ∂z,
    ∂²z,
    ∂z!,
    nodes,
    set!,
    interior,
    top,
    bottom,

    # equations.jl
    Equation,

    # timesteppers.jl
    Timestepper,
    iterate!,
    unpack,
    ForwardEulerTimestepper,

    # boundary_conditions.jl
    Flux,
    Value,
    BoundaryCondition,
    FieldBoundaryConditions,
    FluxBoundaryCondition,
    ZeroFluxBoundaryConditions,
    set_top_bc!,
    set_bottom_bc!,
    set_top_flux_bc!,
    set_bottom_flux_bc!,
    set_flux_bcs!,
    set_bcs!,
    getbc

using
  StaticArrays,
  LinearAlgebra

import Base: time, setproperty!

#
# Preliminary abstract types for OceanTurb.jl
#

abstract type AbstractParameters end
abstract type AbstractEquation end
abstract type Grid{T, A<:AbstractArray} end
abstract type Timestepper end
abstract type AbstractField{A<:AbstractArray, G<:Grid} end
abstract type AbstractSolution{N, T} <: FieldVector{N, T} end
abstract type AbstractModel{TS<:Timestepper, G<:Grid, E<:AbstractEquation, T<:AbstractFloat} end  # Explain: what is a `Model`?

#
# Core OceanTurb.jl functionality
#

include("utils.jl")
include("grids.jl")
include("fields.jl")
include("boundary_conditions.jl")
include("equations.jl")
include("timesteppers.jl")

mutable struct Clock{T}
  time :: T
  iter :: Int
end

Clock() = Clock(0.0, 0)
time(m::AbstractModel) = model.clock.time
iter(m::AbstractModel) = model.clock.iter

function reset!(clock)
  clock.time = 0
  clock.iter = 0
  return nothing
end

#
# Sugary things for solutions and models
#

"""
    set!(solution, kwargs...)

Set the fields of a solution. For example, use

T0 = rand(4)
S0(z) = exp(-z^2/10)
set!(solution, T=T0, S=S0)

To set solution.T and solution.S to T0 and S0.
"""
function set!(solution::AbstractSolution; kwargs...)
  for (k, v) in kwargs
    setproperty!(solution, k, v)
  end
  return nothing
end

function setproperty!(sol::AbstractSolution, c::Symbol, data::Union{Number, AbstractArray, Function})
  set!(getproperty(sol, c), data)
  return nothing
end

#
# Ocean Turbulence Models
#

include("diffusion.jl")
include("k_profile_parameterization.jl")

end # module