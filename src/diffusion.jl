module Diffusion

using 
  Reexport,
  StaticArrays

@reexport using OceanTurb

export
  Model,
  step!

struct Parameters{T} <: AbstractParameters
  κ::T
end

@specify_solution CellField c

mutable struct Model{TS,G,T} <: AbstractModel{TS,G,T}
  @add_standard_model_fields
  parameters::Parameters
end

function Model(;
       nz = 100, 
       Lz = 1.0,
        κ = 0.1,
  stepper = :ForwardEuler,
      bcs = BoundaryConditions(ZeroFlux())
)

  grid = UniformGrid(nz, Lz)
  parameters = Parameters(κ)
  solution = Solution(CellField(grid))
  equation = Equation(∂c∂t)
  timestepper = Timestepper(:ForwardEuler, solution)

  return Model(timestepper, grid, solution, equation, bcs, Clock(), parameters)
end

function set_kappa!(model, κ)
  model.parameters = Parameters(κ)
  return nothing
end

#
# Model specification
#

# Convenient operators
κ∂z(κ::Number, c, i) = κ*∂z(c, i)
κ∂z(κ::AbstractField, c, i) = κ.data[i]*∂z(c, i)

@inline ∇κ∇c(κ, c, i)           = ( κ∂z(κ, c, i+1) -    κ∂z(κ, c, i)      ) /    dzf(c, i)
@inline ∇κ∇c_top(κ, c, flux)    = (     -flux      - κ∂z(κ, c, length(c)) ) / dzf(c, length(c))
@inline ∇κ∇c_bottom(κ, c, flux) = (  κ∂z(κ, c, 2)  +        flux          ) /    dzf(c, 1)

# Top and bottom flux estimates for constant (Dirichlet) boundary conditions
@inline bottom_flux(κ, c, c_bndry, dzf) = -2*bottom(κ)*( c_bndry - bottom(c)) / bottom(dzf) # -κ*∂c/∂z at the bottom
@inline top_flux(κ, c, c_bndry, dzf)    = -2*  top(κ) *(  top(c) -  c_bndry ) /   top(dzf)  # -κ*∂c/∂z at the top

# Interior diffusion equation
@inline ∂c∂t(model, i) = ∇κ∇c(model.parameters.κ, model.solution.c, i)

# Flux Boundary conditions
∂c∂t(model, bc::FluxBC{Top})      = ∇κ∇c_top(   model.parameters.κ, model.solution.c, bc.flux(model))
∂c∂t(model, bc::FluxBC{Bottom})   = ∇κ∇c_bottom(model.parameters.κ, model.solution.c, bc.flux(model))

# Constant Boundary conditions
function ∂c∂t(model, bc::ValueBC{Bottom}) 
  flux = bottom_flux(model.parameters.κ, model.solution.c, bc.value(model), model.grid.dzf)
  return ∇κ∇c_bottom(model.parameters.κ, model.solution.c, flux)
end

function ∂c∂t(model, bc::ValueBC{Top}) 
  flux = top_flux(model.parameters.κ, model.solution.c, bc.value(model), model.grid.dzf)
  return ∇κ∇c_top(model.parameters.κ, model.solution.c, flux)
end

end # module