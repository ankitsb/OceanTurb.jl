
# Tests for the Diffusion module
#

function test_diffusion_basic()
    model = Diffusion.Model(N=4, H=2, K=0.1)
    model.parameters.K == 0.1
end

function test_diffusion_set_c()
    model = Diffusion.Model(N=4, H=2, K=0.1)
    c0 = 1:4
    model.solution.c = c0
    model.solution.c.data[1:model.grid.N] == c0
end

function test_diffusive_flux(stepper=:ForwardEuler; top_flux=0.3, bottom_flux=0.13, N=10)
    model = Diffusion.Model(N=N, H=1, K=1.0, stepper=stepper)
    model.bcs.c.top = FluxBoundaryCondition(top_flux)
    model.bcs.c.bottom = FluxBoundaryCondition(bottom_flux)

    C₀ = integral(model.solution.c)
    C(t) = C₀ - (top_flux - bottom_flux) * t

    dt = 1e-6
    time_step!(model, dt, 10)

    return C(time(model)) ≈ integral(model.solution.c)
end

function test_diffusion_cosine(stepper=:ForwardEuler)
    model = Diffusion.Model(N=100, H=π/2, K=1.0, stepper=stepper)
    z = model.grid.zc

    c_init(z) = cos(2z)
    c_ans(z, t) = exp(-4t) * c_init(z)

    model.solution.c = c_init

    dt = 1e-3
    time_step!(model, dt)

    # The error tolerance is a bit arbitrary.
    norm(c_ans.(z, time(model)) .- data(model.solution.c)) < model.grid.N*1e-6
end

function test_diffusion_cosine_run_until(stepper=:ForwardEuler)
    model = Diffusion.Model(N=100, H=π/2, K=1.0, stepper=stepper)
    z = model.grid.zc

    c_init(z) = cos(2z)
    c_ans(z, t) = exp(-4t) * c_init(z)

    model.solution.c = c_init

    dt = 1e-3
    tfinal = 3dt/2
    run_until!(model, dt, tfinal)

    # The error tolerance is a bit arbitrary.
    norm(c_ans.(z, tfinal) .- data(model.solution.c)) < model.grid.N*1e-6
end


function test_advection(stepper=:ForwardEuler)
    H = 1.0
    W = -1.0
    δ = H/10
    h = H/2

    model = Diffusion.Model(N=100, H=H, K=0.0, W=W, stepper=stepper,
                            bcs = Diffusion.BoundaryConditions(FieldBoundaryConditions(
                                    GradientBoundaryCondition(0.0),
                                    GradientBoundaryCondition(0.0))))

    c_gauss(z, t) = exp( -(z-W*t)^2 / (2*δ^2) )
    c₀(z) = c_gauss(z+h, 0)
    model.solution.c = c₀

    time_step!(model, 1e-3, 10)

    c_current(z) = c_gauss(z+h, time(model))
    c_answer = CellField(model.grid)
    set!(c_answer, c_current)

    norm(data(c_answer) .- data(model.solution.c)) < 0.05
end

function test_damping(stepper=:ForwardEuler)
    H = 1.0
    μ = 0.1

    model = Diffusion.Model(N=3, H=H, K=0.0, μ=μ, stepper=stepper,
                            bcs = Diffusion.BoundaryConditions(FieldBoundaryConditions(
                                    GradientBoundaryCondition(0.0),
                                    GradientBoundaryCondition(0.0))))

    c_damp(t) = exp(-μ*t)
    c₀(z) = c_damp(0)
    model.solution.c = c₀

    time_step!(model, 1e-3, 100)

    c_current(t) = c_damp(time(model))
    c_answer = CellField(model.grid)
    set!(c_answer, c_current)

    all(abs.(data(c_answer) .- data(model.solution.c)) .< 1e-6)
end

@testset "Diffusion" begin
    @test test_diffusion_basic()
    @test test_diffusion_set_c()

    for stepper in steppers
        @test test_diffusion_cosine(stepper)
        @test test_diffusion_cosine_run_until(stepper)
        @test test_diffusive_flux(stepper, top_flux=0, bottom_flux=0)
        @test test_diffusive_flux(stepper)
        @test test_advection(stepper)
        @test test_damping(stepper)
    end
end

