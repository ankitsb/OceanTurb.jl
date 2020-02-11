# Turbulent boundary layers

```math
\newcommand{\c}{\, ,}
\newcommand{\p}{\, .}
\newcommand{\d}{\partial}

\newcommand{\r}[1]{\mathrm{#1}}
\newcommand{\b}[1]{\boldsymbol{#1}}

\newcommand{\ee}{\mathrm{e}}

\newcommand{\beq}{\begin{equation}}
\newcommand{\eeq}{\end{equation}}

\newcommand{\beqs}{\begin{gather}}
\newcommand{\eeqs}{\end{gather}}
```

Models for the turbulent ocean surface boundary layer are partial
differential equations that approximate the effects of
atmospheric forcing on the turbulent vertical flux
and evolution of large-scale temperature, salinity, and momentum
fields.

Internal and surface fluxes of heat are due to

* absorption of incoming shortwave solar radiation;
* cooling by outgoing longwave radiation;
* latent and sensible heat exchange with the atmosphere.

Surface fluxes of salinity occur due to evaporation and precipitation,
while momentum fluxes are associated with atmospheric winds.

Vertical turbulent fluxes are typically associated with

* gravitational instability and convection, and
* mechanical turbulent mixing associated with currents and wind forcing.

`OceanTurb.jl` uses
an implementation of atmospheric and radiative forcings that is shared
across all models.
The models therefore differ in the way they
parameterize convective and mechanical mixing.

## Coordinate system

We use a Cartesian coordinate system in which gravity points downwards,
toward the ground or bottom of the ocean. The vertical coordinate ``z``
thus *increases upwards*. We locate the surface at ``z=0``. This means that if
the boundary layer has depth ``h``, the bottom of the boundary layer is
located at ``z=-h``.

## Governing equations

The one-dimensional, horizontally-averaged boundary-layer equations for
horizontal momentum ``U`` and ``V``, salinity ``S``, and
temperature ``T`` are

```math
\beqs
U_t =   f V - \d_z \overline{w u}      + F_u      \c \label{xmomentum} \\
V_t = - f U - \d_z \overline{w v}      + F_v      \c \\
T_t =       - \d_z \overline{w \theta} + F_\theta \c \label{temperature} \\
S_t =       - \d_z \overline{w s}      + F_s      \c \label{salinity} \\
\eeqs
```

where subscripts ``t`` and ``z`` denote derivatives with respect to time
and the vertical coordinate ``z`` and ``f`` is the Coriolis parameter.
The lowercase variables ``u``, ``v``, ``s``, and ``\theta`` refer to the
three-dimensional perturbations from horizontal velocity, salinity, and
temperature, respectively.
In \eqref{xmomentum}--\eqref{temperature}, internal forcing of
a variable ``\Phi`` is denoted ``F_\phi``.

## Buoyancy

`OceanTurb.jl` uses a linear equation of state, so that
buoyancy is deteremined from temperature ``T`` and salinity ``S`` via

```math
\begin{align}
B & \equiv - \frac{g \rho'}{\rho_0} \\
  &     = g \left [ \alpha \left ( T - T_0 \right ) - \beta \left ( S - S_0 \right ) \right ] \c
\end{align}
```

where ``g = 9.81 \, \mathrm{m \, s^{-2}}, \alpha = 2 \times 10^{-4} \, \mathrm{K^{-1}}``, and ``\beta = 8 \times 10^{-5}``,
are the default gravitational acceleration, the thermal expansion coefficient, and the
haline contraction coefficient, respectively.

## Surface fluxes

Turbulence in the ocean surface boundary layer is driven by fluxes from
the atmosphere above.
A surface flux of some variable ``\phi`` is denoted ``Q_\phi``.
Surface fluxes include

1. Momentum fluxes due to wind, denoted ``Q_u \b{x} + Q_v \b{y} = -\rho_0 \b{\tau}`` for wind stress ``\b{\tau}``;
2. Temperature flux ``Q_\theta = - Q_h / \rho_0 c_P`` associated with 'heating' ``Q_h``;
3. Salinity flux ``Q_s = (E-P)S`` associated evaporation ``E`` and precipitation ``P``.

We use the traditional convention ordinary to physics, but not always
ordinary to oceanography, in which a  positive flux corresponds to the
movement of a quantity in the positive ``z``-direction.
This means, for example, that a positive vertical velocity ``w`` gives rise
to a positive advective flux ``w \phi``.
This convention also implies that a positive temperature flux at the ocean surface ---
corresponding to heat fluxing upwards, out of the ocean, into the atmosphere ---
implies a cooling of the ocean surface boundary layer.

### Turbulent velocity scales

The surface buoyancy flux is determined from temperature and
salinity fluxes:

```math
\beq
Q_b = g \left ( \alpha Q_\theta - \beta Q_s \right ) \p
\eeq
```

The velocity scale of turbulent motions associated with
buoyancy flux ``Q_b`` and velocity fluxes ``Q_u`` and
``Q_v`` are

```math
\beq
w_\star \equiv | h Q_b |^{1/3} \qquad \text{and} \qquad u_\star \equiv | \b{\tau} / \rho_0 |^{1/2} \p
\eeq
```

where ``h`` is the depth of the 'mixing layer', or the depth to which
turbulent mixing and turbulent fluxes penetrate, ``\b{\tau}`` is wind stress,
and ``\rho_0 = 1028 \, \mathrm{kg \, m^{-3}}`` is a reference density.

Note that we also define a turbulent velocity scale for
stabilizing buoyancy fluxes ``Q_b < 0``, even though
a stabilizing buoyancy flux suppresses, rather than generates,
turbulence.
