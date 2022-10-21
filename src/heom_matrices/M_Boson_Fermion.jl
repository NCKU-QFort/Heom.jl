"""
    mutable struct M_Boson_Fermion <: AbstractHEOMMatrix
Heom liouvillian superoperator matrix for mixtured (bosonic and fermionic) bath 

# Fields
- `data` : the sparse matrix of HEOM liouvillian superoperator
- `tier_b` : the tier (cutoff) for bosonic bath
- `tier_f` : the tier (cutoff) for fermionic bath
- `dim` : the dimension of system
- `N` : the number of total ADOs
- `Nb` : the number of bosonic ADOs
- `Nf` : the number of fermionic ADOs
- `sup_dim` : the dimension of system superoperator
- `parity` : the parity of the density matrix
- `bath_b::Vector{BosonBath}` : the vector which stores all `BosonBath` objects
- `bath_f::Vector{FermionBath}` : the vector which stores all `FermionBath` objects
- `hierarchy_b::HierarchyDict`: the object which contains all dictionaries for boson-bath-ADOs hierarchy.
- `hierarchy_f::HierarchyDict`: the object which contains all dictionaries for fermion-bath-ADOs hierarchy.
"""
mutable struct M_Boson_Fermion <: AbstractHEOMMatrix
    data::SparseMatrixCSC{ComplexF64, Int64}
    const tier_b::Int
    const tier_f::Int
    const dim::Int
    const N::Int
    const Nb::Int
    const Nf::Int
    const sup_dim::Int
    const parity::Symbol
    const bath_b::Vector{BosonBath}
    const bath_f::Vector{FermionBath}
    const hierarchy_b::HierarchyDict
    const hierarchy_f::HierarchyDict
end

function M_Boson_Fermion(Hsys, tier_b::Int, tier_f::Int, Bath_b::BosonBath, Bath_f::FermionBath, parity::Symbol=:even; verbose::Bool=true)
    return M_Boson_Fermion(Hsys, tier_b, tier_f, [Bath_b], [Bath_f], parity, verbose = verbose)
end

function M_Boson_Fermion(Hsys, tier_b::Int, tier_f::Int, Bath_b::Vector{BosonBath}, Bath_f::FermionBath, parity::Symbol=:even; verbose::Bool=true)
    return M_Boson_Fermion(Hsys, tier_b, tier_f, Bath_b, [Bath_f], parity, verbose = verbose)
end

function M_Boson_Fermion(Hsys, tier_b::Int, tier_f::Int, Bath_b::BosonBath, Bath_f::Vector{FermionBath}, parity::Symbol=:even; verbose::Bool=true)
    return M_Boson_Fermion(Hsys, tier_b, tier_f, [Bath_b], Bath_f, parity, verbose = verbose)
end

"""
    M_Boson_Fermion(Hsys, tier_b, tier_f, Bath_b, Bath_f, parity=:even; verbose=true)
Generate the boson-fermion-type Heom liouvillian superoperator matrix

# Parameters
- `Hsys` : The system Hamiltonian
- `tier_b::Int` : the tier (cutoff) for the bosonic bath
- `tier_f::Int` : the tier (cutoff) for the fermionic bath
- `Bath_b::Vector{BosonBath}` : objects for different bosonic baths
- `Bath_f::Vector{FermionBath}` : objects for different fermionic baths
- `parity::Symbol` : The parity symbol of the density matrix (either `:odd` or `:even`). Defaults to `:even`.
- `verbose::Bool` : To display verbose output and progress bar during the process or not. Defaults to `true`.
"""
function M_Boson_Fermion(        
        Hsys,
        tier_b::Int,
        tier_f::Int,
        Bath_b::Vector{BosonBath},
        Bath_f::Vector{FermionBath},
        parity::Symbol=:even;
        verbose::Bool=true
    )

    # check parity
    if (parity != :even) && (parity != :odd)
        error("The parity symbol of density matrix should be either \":odd\" or \":even\".")
    end

    # check for system dimension
    if !isValidMatrixType(Hsys)
        error("Invalid matrix \"Hsys\" (system Hamiltonian).")
    end
    Nsys,   = size(Hsys)
    sup_dim = Nsys ^ 2
    I_sup   = sparse(I, sup_dim, sup_dim)

    # the liouvillian operator for free Hamiltonian term
    Lsys = -1im * (spre(Hsys) - spost(Hsys))

    # check for bosonic bath
    Nado_b, baths_b, hierarchy_b = genBathHierarchy(Bath_b, tier_b, Nsys)
    idx2nvec_b = hierarchy_b.idx2nvec
    nvec2idx_b = hierarchy_b.nvec2idx

    # check for fermionic bath
    Nado_f, baths_f, hierarchy_f = genBathHierarchy(Bath_f, tier_f, Nsys)
    idx2nvec_f = hierarchy_f.idx2nvec
    nvec2idx_f = hierarchy_f.nvec2idx

    Nado_tot = Nado_b * Nado_f

    # start to construct the matrix
    L_row = Int[]
    L_col = Int[]
    L_val = ComplexF64[]
    lk = SpinLock()
    if verbose
        println("Preparing block matrices for HEOM liouvillian superoperator (using $(nthreads()) threads)...")
        flush(stdout)
        prog = Progress(Nado_b + Nado_f; desc="Processing: ", PROGBAR_OPTIONS...)
    end
    @threads for idx_b in 1:Nado_b
        # diagonal (boson)
        sum_ω   = 0.0
        nvec_b = idx2nvec_b[idx_b]
        n_exc_b = sum(nvec_b) 
        idx = (idx_b - 1) * Nado_f
        if n_exc_b >= 1
            sum_ω += bath_sum_ω(nvec_b, baths_b)
        end

        # diagonal (fermion)
        for idx_f in 1:Nado_f
            nvec_f = idx2nvec_f[idx_f]
            n_exc_f = sum(nvec_f)
            if n_exc_f >= 1
                sum_ω += bath_sum_ω(nvec_f, baths_f)
            end
            lock(lk)
            try
                add_operator!(Lsys - sum_ω * I_sup, L_row, L_col, L_val, Nado_tot, idx + idx_f, idx + idx_f)
            finally
                unlock(lk)
            end
        end
        
        # off-diagonal (boson)
        count = 0
        nvec_neigh = copy(nvec_b)
        for bB in baths_b
            for k in 1:bB.Nterm
                count += 1
                n_k = nvec_b[count]
                if n_k >= 1
                    nvec_neigh[count] = n_k - 1
                    idx_neigh = nvec2idx_b[nvec_neigh]
                    
                    op = prev_grad_boson(bB, k, n_k)
                    for idx_f in 1:Nado_f
                        lock(lk)
                        try
                            add_operator!(op, L_row, L_col, L_val, Nado_tot, (idx + idx_f), (idx_neigh - 1) * Nado_f + idx_f)
                        finally
                            unlock(lk)
                        end
                    end
                    nvec_neigh[count] = n_k
                end
                if n_exc_b <= tier_b - 1
                    nvec_neigh[count] = n_k + 1
                    idx_neigh = nvec2idx_b[nvec_neigh]
                    
                    op = next_grad_boson(bB)
                    for idx_f in 1:Nado_f
                        lock(lk)
                        try
                            add_operator!(op, L_row, L_col, L_val, Nado_tot, (idx + idx_f), (idx_neigh - 1) * Nado_f + idx_f)
                        finally
                            unlock(lk)
                        end
                    end

                    nvec_neigh[count] = n_k
                end
            end
        end
        if verbose
            next!(prog)
        end
    end

    # fermion (n+1 & n-1 tier) superoperator
    @threads for idx_f in 1:Nado_f
        nvec_f = idx2nvec_f[idx_f]
        n_exc_f = sum(nvec_f)

        count = 0
        nvec_neigh = copy(nvec_f)
        for fB in baths_f
            for k in 1:fB.Nterm
                count += 1
                n_k = nvec_f[count]
                if n_k >= 1
                    nvec_neigh[count] = n_k - 1
                    idx_neigh = nvec2idx_f[nvec_neigh]
                    op = prev_grad_fermion(fB, k, n_exc_f, sum(nvec_neigh[1:(count - 1)]), parity)

                elseif n_exc_f <= tier_f - 1
                    nvec_neigh[count] = n_k + 1
                    idx_neigh = nvec2idx_f[nvec_neigh]
                    op = next_grad_fermion(fB, n_exc_f, sum(nvec_neigh[1:(count - 1)]), parity)

                else
                    continue
                end

                for idx_b in 1:Nado_b
                    idx = (idx_b - 1) * Nado_f
                    lock(lk)
                    try
                        add_operator!(op, L_row, L_col, L_val, Nado_tot, idx + idx_f, idx + idx_neigh)
                    finally
                        unlock(lk)
                    end
                end

                nvec_neigh[count] = n_k
            end
        end
        if verbose
            next!(prog)
        end
    end
    if verbose
        print("Constructing matrix...")
        flush(stdout)
    end
    L_he = sparse(L_row, L_col, L_val, Nado_tot * sup_dim, Nado_tot * sup_dim)
    if verbose 
        println("[DONE]") 
        flush(stdout)
    end
    return M_Boson_Fermion(L_he, tier_b, tier_f, Nsys, Nado_tot, Nado_b, Nado_f, sup_dim, parity, Bath_b, Bath_f, hierarchy_b, hierarchy_f)
end