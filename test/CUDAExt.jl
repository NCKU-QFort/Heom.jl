using CUDA
using LinearSolve

CUDA.versioninfo()

CUDA.@time @testset "CUDA Extension" begin

    # re-define the bath (make the matrix smaller)
    λ = 0.01
    W = 0.5
    kT = 0.5
    μ = 0
    N = 3
    tier = 3

    # System Hamiltonian
    Hsys = Qobj([0 0; 0 0])

    # system-bath coupling operator
    Qb = sigmax()
    Qf = sigmam()

    # initial state
    ψ0 = basis(2, 1)

    Bbath = Boson_DrudeLorentz_Pade(Qb, λ, W, kT, N)
    Fbath = Fermion_Lorentz_Pade(Qf, λ, μ, W, kT, N)

    # Solving time Evolution
    ## Schrodinger HEOMLS
    L_cpu = M_S(Hsys; verbose = false)
    L_gpu = cu(L_cpu)
    ados_cpu = evolution(L_cpu, ψ0, [0, 10]; verbose = false)
    ados_gpu = evolution(L_gpu, ψ0, [0, 10]; verbose = false)
    @test isapprox(getRho(ados_cpu[end]), getRho(ados_gpu[end]), atol = 1e-4)

    ## Boson HEOMLS
    L_cpu = M_Boson(Hsys, tier, Bbath; verbose = false)
    L_gpu = cu(L_cpu)
    ados_cpu = evolution(L_cpu, ψ0, [0, 10]; verbose = false)
    ados_gpu = evolution(L_gpu, ψ0, [0, 10]; verbose = false)
    @test isapprox(getRho(ados_cpu[end]), getRho(ados_gpu[end]), atol = 1e-4)

    ## Boson Fermion HEOMLS
    L_cpu = M_Fermion(Hsys, tier, Fbath; verbose = false)
    L_gpu = cu(L_cpu)
    ados_cpu = evolution(L_cpu, ψ0, [0, 10]; verbose = false)
    ados_gpu = evolution(L_gpu, ψ0, [0, 10]; verbose = false)
    @test isapprox(getRho(ados_cpu[end]), getRho(ados_gpu[end]), atol = 1e-4)

    ## Boson Fermion HEOMLS
    L_cpu = M_Boson_Fermion(Hsys, tier, tier, Bbath, Fbath; verbose = false)
    L_gpu = cu(L_cpu)
    tlist = 0:1:10
    ados_cpu = evolution(L_cpu, ψ0, tlist; verbose = false)
    ados_gpu = evolution(L_gpu, ψ0, tlist; verbose = false)
    for i in 1:length(tlist)
        isapprox(getRho(ados_cpu[i]), getRho(ados_gpu[i]), atol = 1e-4)
    end

    # SIAM
    ϵ = -5
    U = 10
    σm = sigmam() ## σ-
    σz = sigmaz() ## σz
    II = qeye(2)  ## identity matrix
    d_up = tensor(σm, II)
    d_dn = tensor(-1 * σz, σm)
    ψ0 = tensor(basis(2, 0), basis(2, 0))
    Hsys = ϵ * (d_up' * d_up + d_dn' * d_dn) + U * (d_up' * d_up * d_dn' * d_dn)
    Γ = 2
    μ = 0
    W = 10
    kT = 0.5
    N = 5
    tier = 3
    bath_up = Fermion_Lorentz_Pade(d_up, Γ, μ, W, kT, N)
    bath_dn = Fermion_Lorentz_Pade(d_dn, Γ, μ, W, kT, N)
    bath_list = [bath_up, bath_dn]

    ## solve stationary state
    L_even_cpu = M_Fermion(Hsys, tier, bath_list; verbose = false)
    L_even_gpu = cu(L_even_cpu)
    ados_cpu = SteadyState(L_even_cpu; verbose = false)
    ados_gpu = SteadyState(L_even_gpu, ψ0, 10; verbose = false)
    @test all(isapprox.(ados_cpu.data, ados_gpu.data; atol = 1e-6))

    ## solve density of states
    ωlist = -5:0.5:5
    L_odd_cpu = M_Fermion(Hsys, tier, bath_list, ODD; verbose = false)
    L_odd_gpu = cu(L_odd_cpu)
    dos_cpu = DensityOfStates(L_odd_cpu, ados_cpu, d_up, ωlist; verbose = false)
    dos_gpu = DensityOfStates(
        L_odd_gpu,
        ados_cpu,
        d_up,
        ωlist;
        solver = KrylovJL_BICGSTAB(rtol = 1.0f-10, atol = 1.0f-12),
        verbose = false,
    )
    for (i, ω) in enumerate(ωlist)
        @test dos_cpu[i] ≈ dos_gpu[i] atol = 1e-6
    end
end