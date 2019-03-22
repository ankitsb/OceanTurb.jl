module KPP

using
    OceanTurb,
    StaticArrays,
    LinearAlgebra

const nsol = 4
@specify_solution CellField U V T S

"""
    Parameters(; kwargs...)

Construct KPP parameters.

    Args
    ====
    Cε : Surface layer fraction
    etc.
"""
struct Parameters{T} <: AbstractParameters
    Cε    :: T  # Surface layer fraction
    Cκ    :: T  # Von Karman constant
    CNL   :: T  # Non-local flux proportionality constant

    Cstab :: T  # Reduction of wind-driven diffusivity due to stable buoyancy flux
    Cunst :: T  # Reduction of wind-driven diffusivity due to stable buoyancy flux

    Cb_U  :: T  # Buoyancy flux viscosity proportionality for convective turbulence
    Cτ_U  :: T  # Wind stress viscosity proportionality for convective turbulence
    Cb_T  :: T  # Buoyancy flux diffusivity proportionality for convective turbulence
    Cτ_T  :: T  # Wind stress diffusivity proportionality for convective turbulence

    Cd_U  :: T  # Buoyancy flux diffusivity proportionality for convective turbulence
    Cd_T  :: T  # Wind stress diffusivity proportionality for convective turbulence

    CRi   :: T  # Critical bulk_richardson_number number
    CKE   :: T  # Unresolved turbulence parameter

    KU₀   :: T  # Interior diffusivity
    KT₀   :: T  # Interior diffusivity
    KS₀   :: T  # Interior diffusivity
end

function Parameters(T=Float64;
       Cε = 0.1,
       Cκ = 0.4,
      CNL = 6.33,
    Cstab = 2.0,
    Cunst = 6.4,
     Cb_U = 0.599,
     Cτ_U = 0.135,
     Cb_T = 1.36,
     Cτ_T = -1.85,
     Cd_U = 0.5,
     Cd_T = 2.5,
      CRi = 4.32,
      CKE = 0.3,
       K₀ = 1e-5, KU₀=K₀, KT₀=K₀, KS₀=K₀
     )

     Parameters{T}(Cε, Cκ, CNL, Cstab, Cunst,
                   Cb_U, Cτ_U, Cb_T, Cτ_T, Cd_U, Cd_T,
                   CRi, CKE, KU₀, KT₀, KS₀)
end

# Shape functions (these shoul become parameters eventually).
# 'd' is a non-dimensional depth coordinate.
default_shape_N(d) = d*(1-d)^2
default_shape_K(d) = d*(1-d)^2

struct Constants{T}
    g  :: T # Gravitiational acceleration
    cP :: T # Heat capacity of water
    ρ₀ :: T # Reference density
    α  :: T # Thermal expansion coefficient
    β  :: T # Haline expansion coefficient
    f  :: T # Coriolis parameter
end

function Constants(T=Float64; α=2.5e-4, β=8e-5, ρ₀=1035, cP=3992, f=0, g=9.81)
    Constants{T}(g, cP, ρ₀, α, β, f)
end

mutable struct State{T} <: FieldVector{6, T}
    Fu :: T
    Fv :: T
    Fθ :: T
    Fs :: T
    Fb :: T
    h  :: T
end

State(T=Float64) = State{T}(0, 0, 0, 0, 0, 0)

"""
    update_state!(model)

Update the top flux conditions and mixing depth for `model`
and store in `model.state`.
"""
function update_state!(m)
    m.state.Fu = getbc(m, m.bcs.U.top)
    m.state.Fv = getbc(m, m.bcs.V.top)
    m.state.Fθ = getbc(m, m.bcs.T.top)
    m.state.Fs = getbc(m, m.bcs.S.top)
    m.state.Fb = m.constants.g * (m.constants.α * m.state.Fθ - m.constants.β * m.state.Fs)
    m.state.h  = mixing_depth(m)
    return nothing
end

struct Model{TS, G, E, T} <: AbstractModel{TS, G, E, T}
    @add_standard_model_fields
    parameters :: Parameters{T}
    constants  :: Constants{T}
    state      :: State{T}
end

function Model(; N=10, L=1.0,
            grid = UniformGrid(N, L),
       constants = Constants(),
      parameters = Parameters(),
         stepper = :ForwardEuler,
             bcs = BoundaryConditions((ZeroFluxBoundaryConditions() for i=1:nsol)...)
    )

    solution = Solution((CellField(grid) for i=1:nsol)...)
    equation = Equation(calc_rhs_explicit!)
    timestepper = Timestepper(:ForwardEuler, solution)

    return Model(timestepper, grid, equation, solution, bcs, Clock(),
                    parameters, constants, State())
end


# Note: to increase readability, we use 'm' to refer to 'model' in function
# definitions below.
#

## ** The K-Profile-Parameterization! **
K_KPP(h, w_scale, d, shape=default_shape_K) = max(0, h * w_scale * shape(d))

d(m, i) = -m.grid.zf[i] / m.state.h

# K_{U,V,T,S} is calculated at face points
K_U(m, i) = K_KPP(h, w_scale_U(m, i), d(m, i)) + m.parameters.K0_U
K_T(m, i) = K_KPP(h, w_scale_T(m, i), d(m, i)) + m.parameters.K0_T

const K_V = K_U
const K_S = K_T


"Return the buoyancy gradient at face point i."
∂B∂z(T, S, g, α, β, i) = g * (α*∂z(T, i) - β*∂z(S, i))
∂B∂z(m, i) = ∂B∂z(m.solution.T, m.solution.S, m.constants.g, m.constants.α, m.constants.β, i)

#
# Diagnosis of mixing depth "h"
#

"Returns the surface_layer_average for mixing depth h = -zf[i]."
function surface_layer_average(c, Cε, i)
    iε = length(c)+1 - Cε*(length(c)+1 - i) # (fractional) face "index" of the surface layer
    face = ceil(Int, iε)  # the next cell face above the fractional depth
    frac = face - iε # the fraction of the lowest cell in the surface layer.

    # Example 1:

    #   length(c) = 9 (face_length = 10)
    #          Cε = 0.1
    #           i = 9
    #   => iε = 10 - 0.1*(1) = 9.9, face = 10, frac = 0.1.

    # Example 2:

    # length(c) = 99 (face_length = 100)
    #        Cε = 0.1
    #         i = 18
    #       => iε = 100 - 0.1*82 = 91.8, face = 92, frac = 0.2.

    # Contribution of fractional cell to total integral
    surface_layer_integral = frac > 0 ? frac * Δf(c, face-1) * c.data[face-1] : 0

    # Add cells above face, if there are any.
    for j = face:length(c)
      @inbounds surface_layer_integral += Δf(c, j) * c.data[j]
    end

    h = -c.grid.zf[i] # depth
    return surface_layer_integral / (Cε*h)
end

"""
Return Δc(hᵢ), the difference between the surface-layer average of c and its value at depth hᵢ, where
i is a face index.
"""
Δ(c::CellField, Cε, i) = surface_layer_average(c, Cε, i) - onface(c, i)

"Returns the parameterization for unresolved KE at face point i."
function unresolved_kinetic_energy(T, S, Bz, Fb, CKE, g, α, β, i)
    h = -T.grid.zf[i]
    return CKE * h^(4/3) * sqrt(max(0, Bz)) * max(0, Fb)^(1/3)
end

"""
    bulk_richardson_number(model, i)

Returns the bulk Richardson number of `model` at face `i`.
"""
function bulk_richardson_number(U, V, T, S, Fb, CKE, Cε, g, α, β, i)
    hΔB = -U.grid.zf[i] * ( g * (α*Δ(T, Cε, i) - β*Δ(S, Cε, i)) )
    Bz = ∂B∂z(T, S, g, α, β, i)
    uKE = unresolved_kinetic_energy(T, S, Bz, Fb, CKE, g, α, β, i)
    KE = Δ(U, Cε, i)^2 + Δ(V, Cε, i)^2 + uKE

    if KE == 0 && hΔB == 0 # Alistar Adcroft's theorem
        return 0
    else
        return hΔB / KE
    end
end

bulk_richardson_number(m, i) = bulk_richardson_number(
    m.solution.U, m.solution.V, m.solution.T, m.solution.S,
    m.state.Fb, m.parameters.CKE, m.parameters.Cε, m.constants.g,
    m.constants.α, m.constants.β, i)

"""
    mixing_depth(model)

Calculate the mixing depth 'h' for `model`.
"""
function mixing_depth(m)
    # Descend through grid until Ri rises above critical value
    Ri₁ = 0
    ih₁ = m.grid.N + 1 # start at top
    while ih₁ > 2 && Ri₁ < m.parameters.CRi
        ih₁ -= 1 # descend
        Ri₁ = bulk_richardson_number(m, ih₁)
    end

    # Here, ih₁ >= 2.

    if !isfinite(Ri₁)         # Ri is infinite:
        z★ = m.grid.zf[ih₁+1] # "mixing depth" is just above where Ri = inf.

    elseif Ri₁ < m.parameters.CRi # We descended to ih₁=2 and Ri is still too low:
        z★ = m.grid.zf[1]         # mixing depth extends to bottom of grid.

    else                                             # We have descended below critical Ri:
        ΔRi = bulk_richardson_number(m, ih₁+1) - Ri₁ # linearly interpolate to find h.
        # x = x₀ + Δx * (y-y₀) / Δy
        z★ = m.grid.zf[ih₁] + Δf(m.grid, ih₁) * (m.parameters.CRi - Ri₁) / ΔRi
    end

    return -z★ # "depth" is negative height.
end

#
# Vertical velocity scale
#

"Return true if the boundary layer is unstable and convecting."
isunstable(model) = model.state.Fb > 0

"Return the turbuent velocity scale associated with wind stress."
ωτ(Fu, Fv) = (Fu^2 + Fv^2)^(1/4)
ωτ(m::Model) = ωτ(m.state.Fu, m.state.Fv)

"Return the turbuent velocity scale associated with convection."
ωb(Fb, h) = abs(h * Fb)^(1/3)
ωb(m::Model) = ωb(m.state.Fb, m.state.h)

"Return truncated, non-dimensional depth coordinate."
dϵ(m::Model, d) = min(m.parameters.Cε, d)

"Return the vertical velocity scale at depth d for a stable boundary layer."
w_scale_stable(Cκ, Cstab, ωτ, ωb, d) = Cκ * ωτ / (1 + Cstab * d * (ωb/ωτ)^3)

"Return the vertical velocity scale at scaled depth dϵ for an unstable boundary layer."
function w_scale_unstable(Cd, Cκ, Cunst, Cb, Cτ, ωτ, ωb, dϵ, nϕ)
    if dϵ < Cd * (ωτ/ωb)^3
        return Cκ * ωτ * (1 + Cunst * (ωb/ωτ)^3 * dϵ)^nϕ
    else
        return Cb * ωb * (dϵ + Cτ * (ωτ/ωb)^3)^(1/3)
    end
end

const nU = 1/4
const nT = 1/2

"Return the vertical velocity scale for momentum at face point i."
function w_scale_U(m, i)
    if isunstable(m)
        return w_scale_unstable(m.parameters.Cd_U, m.parameters.Cκ, m.parameters.Cunst,
                                m.parameters.Cb_U, m.parameters.Cτ_U,
                                ωτ(m), ωb(m), min(m.parameters.Cε, d(m, i)), nU)
    else
        return w_scale_stable(m.parameters.Cκ, m.parameters.Cstab, ωτ(m), ωb(m), d(m, i))
    end
end

"Return the vertical velocity scale for tracers at face point i."
function w_scale_T(m, i)
    if isunstable(m)
        return w_scale_unstable(m.parameters.Cd_T, m.parameters.Cκ, m.parameters.Cunst,
                                m.parameters.Cb_T, m.parameters.Cτ_T,
                                ωτ(m), ωb(m), min(m.parameters.Cε, d(m, i)), nT)
    else
        return w_scale_stable(m.parameters.Cκ, m.parameters.Cstab, ωτ(m), ωb(m), d(m, i))
    end
end

const w_scale_V = w_scale_U
const w_scale_S = w_scale_T

#
# Non-local flux
#

"""
    nonlocal_flux(flux, d, shape=default_shape)

Returns the nonlocal flux, N = flux*shape(d),
where `flux` is the flux of some quantity out of the surface,
`shape` is a shape function, and `d` is a non-dimensional depth coordinate
that increases from 0 at the surface to 1 at the bottom of the mixing layer.

Because flux is defined as pointing in the positive direction,
a positive surface flux implies negative surface flux divergence,
which implies a reduction to the quantity in question.
For example, positive heat flux out of the surface implies cooling.
"""
nonlocal_flux(flux, d, shape=default_shape_N) = flux*shape(d) # not minus sign due to flux convention

const N = nonlocal_flux

∂NT∂z(m, i) = ( N(m.state.Fθ, d(m, i+1)) - N(m.state.Fθ, d(m, i)) ) / Δf(m.grid, i)
∂NS∂z(m, i) = ( N(m.state.Fs, d(m, i+1)) - N(m.state.Fs, d(m, i)) ) / Δf(m.grid, i)

#
# Local diffusive flux
#

const BC = BoundaryCondition

# ∇K∇c for c::CellField
K∂z(K, c, i) = K*∂z(c, i)
∇K∇c(Kᵢ₊₁, Kᵢ, c, i)              = ( K∂z(Kᵢ₊₁, c, i+1) -    K∂z(Kᵢ, c, i)      ) /    Δf(c, i)
∇K∇c_top(Kᵢ, c, top_flux)         = (     -top_flux     - K∂z(Kᵢ, c, length(c)) ) / Δf(c, length(c))
∇K∇c_bottom(Kᵢ₊₁, c, bottom_flux) = (  K∂z(Kᵢ₊₁, c, 2)  +     bottom_flux       ) /    Δf(c, 1)

## Top and bottom flux estimates for constant (Dirichlet) boundary conditions
bottom_flux(K, c, c_bndry, Δf) = -2K*( bottom(c) - c_bndry ) / bottom(Δf) # -K*∂c/∂z at the bottom
top_flux(K, c, c_bndry, Δf)    = -2K*(  c_bndry  -  top(c) ) /   top(Δf)  # -K*∂c/∂z at the top

#∇K∇c_top(Kᵢ, c, bc::BC{<:Flux}, model)      = ∇K∇c_top(Kᵢ, c, get_bc(bc, model))
∇K∇c_bottom(Kᵢ₊₁, c, bc::BC{<:Flux}, model) = ∇K∇c_bottom(Kᵢ₊₁, c, getbc(model, bc))

#
# Equation entry
#

function calc_rhs_explicit!(rhs, model)

    # Preliminaries
    U, V, T, S = model.solution
    update_state!(model)

    for i in interior(U)
        @inbounds begin
            rhs.U[i] =  f*V[i] + ∇K∇c(K_U(m, i+1), K_U(m, i), U, i)
            rhs.V[i] = -f*U[i] + ∇K∇c(K_V(m, i+1), K_V(m, i), V, i)
            rhs.T[i] =           ∇K∇c(K_T(m, i+1), K_T(m, i), T, i) - ∂NT∂z(m, i)
            rhs.S[i] =           ∇K∇c(K_S(m, i+1), K_S(m, i), S, i) - ∂NS∂z(m, i)
        end
    end

    # Flux into the top (the only boundary condition allowed)
    rhs.U[m.grid.N] =  f*V[m.grid.N] * ∇K∇c_top(K_U(m, m.grid.N), U, model.state.Fu)
    rhs.V[m.grid.N] = -f*U[m.grid.N] * ∇K∇c_top(K_V(m, m.grid.N), V, model.state.Fv)
    rhs.T[m.grid.N] =                  ∇K∇c_top(K_T(m, m.grid.N), T, model.state.Fθ) - ∂NT∂z(m, m.grid.N)
    rhs.S[m.grid.N] =                  ∇K∇c_top(K_S(m, m.grid.N), S, model.state.Fs) - ∂NS∂z(m, m.grid.N)

    # Bottom
    rhs.U[1] =  f*V[1] * ∇K∇c_bottom(K_U(m, 2), U, model.bcs.U.bottom, model)
    rhs.V[1] = -f*U[1] * ∇K∇c_bottom(K_V(m, 2), V, model.bcs.V.bottom, model)
    rhs.T[1] =           ∇K∇c_bottom(K_T(m, 2), T, model.bcs.T.bottom, model) - ∂NT∂z(m, 1)
    rhs.S[1] =           ∇K∇c_bottom(K_S(m, 2), S, model.bcs.S.bottom, model) - ∂NS∂z(m, 1)


    return nothing
end

end # module