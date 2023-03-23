"""
    struct M_Boson <: AbstractHEOMMatrix
Heom liouvillian superoperator matrix for bosonic bath

# Fields
- `data` : the sparse matrix of HEOM liouvillian superoperator
- `tier` : the tier (cutoff level) for the bosonic hierarchy
- `dim` : the dimension of system
- `N` : the number of total ADOs
- `sup_dim` : the dimension of system superoperator
- `parity` : the parity label of the fermionic system (usually `:even`, only set as `:odd` for calculating spectrum of fermionic system).
- `bath::Vector{BosonBath}` : the vector which stores all `BosonBath` objects
- `hierarchy::HierarchyDict`: the object which contains all dictionaries for boson-bath-ADOs hierarchy.
"""
struct M_Boson <: AbstractHEOMMatrix
    data::SparseMatrixCSC{ComplexF64, Int64}
    tier::Int
    dim::Int
    N::Int
    sup_dim::Int
    parity::Symbol
    bath::Vector{BosonBath}
    hierarchy::HierarchyDict
end

function M_Boson(Hsys, tier::Int, Bath::BosonBath, parity::Symbol=:even; threshold::Real = 0.0, verbose::Bool=true)
    return M_Boson(Hsys, tier, [Bath], parity, threshold = threshold, verbose = verbose)
end

"""
    M_Boson(Hsys, tier, Bath, parity=:even; threshold=0.0, verbose=true)
Generate the boson-type Heom liouvillian superoperator matrix

# Parameters
- `Hsys` : The time-independent system Hamiltonian
- `tier::Int` : the tier (cutoff level) for the bosonic bath
- `Bath::Vector{BosonBath}` : objects for different bosonic baths
- `parity::Symbol` : the parity label of the fermionic system (only set as `:odd` for calculating spectrum of fermionic system). Defaults to `:even`.
- `threshold::Real` : The threshold of the importance value (see Ref. [1]). Defaults to `0.0`.
- `verbose::Bool` : To display verbose output and progress bar during the process or not. Defaults to `true`.

Note that the parity only need to be set as `:odd` when the system contains fermionic systems and you need to calculate the spectrum (density of states) of it.

[1] [Phys. Rev. B 88, 235426 (2013)](https://doi.org/10.1103/PhysRevB.88.235426)
"""
@noinline function M_Boson(        
        Hsys,
        tier::Int,
        Bath::Vector{BosonBath},
        parity::Symbol=:even;
        threshold::Real=0.0,
        verbose::Bool=true
    )

    # check parity
    if (parity != :even) && (parity != :odd)
        error("The parity symbol of density matrix should be either \":even\" or \":odd\".")
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

    # bosonic bath
    if verbose && (threshold > 0.0)
        print("Checking the importance value for each ADOs...")
        flush(stdout)
    end
    Nado, baths, hierarchy = genBathHierarchy(Bath, tier, Nsys, threshold=threshold)
    idx2nvec = hierarchy.idx2nvec
    nvec2idx = hierarchy.nvec2idx
    if verbose && (threshold > 0.0)
        println("[DONE]")
        flush(stdout)
    end

    # start to construct the matrix
    Nthread = nthreads()
    L_row = [Int[] for _ in 1:Nthread]
    L_col = [Int[] for _ in 1:Nthread]
    L_val = [ComplexF64[] for _ in 1:Nthread]

    if verbose
        println("Preparing block matrices for HEOM liouvillian superoperator (using $(Nthread) threads)...")
        flush(stdout)
        prog = Progress(Nado; desc="Processing: ", PROGBAR_OPTIONS...)
    end
    @threads for idx in 1:Nado
        tID = threadid()

        # boson (current level) superoperator
        nvec = idx2nvec[idx]
        if nvec.level >= 1
            sum_γ = bath_sum_γ(nvec, baths)
            op = Lsys - sum_γ * I_sup
        else
            op = Lsys
        end
        add_operator!(op, L_row[tID], L_col[tID], L_val[tID], Nado, idx, idx)

        # connect to bosonic (n+1)th- & (n-1)th- level superoperator
        count = 0
        nvec_neigh = copy(nvec)
        for bB in baths
            for k in 1:bB.Nterm
                count += 1
                n_k = nvec[count]
                
                # connect to bosonic (n-1)th-level superoperator
                if n_k > 0
                    Nvec_minus!(nvec_neigh, count)
                    if (threshold == 0.0) || haskey(nvec2idx, nvec_neigh)
                        idx_neigh = nvec2idx[nvec_neigh]
                        op = _D_op(bB, k, n_k)
                        add_operator!(op, L_row[tID], L_col[tID], L_val[tID], Nado, idx, idx_neigh)
                    end
                    Nvec_plus!(nvec_neigh, count)
                end

                # connect to bosonic (n+1)th-level superoperator
                if nvec.level < tier
                    Nvec_plus!(nvec_neigh, count)
                    if (threshold == 0.0) || haskey(nvec2idx, nvec_neigh)
                        idx_neigh = nvec2idx[nvec_neigh]
                        op = _B_op(bB)
                        add_operator!(op, L_row[tID], L_col[tID], L_val[tID], Nado, idx, idx_neigh)
                    end
                    Nvec_minus!(nvec_neigh, count)
                end
            end
        end
        if verbose
            next!(prog) # trigger a progress bar update
        end
    end
    if verbose
        print("Constructing matrix...")
        flush(stdout)
    end
    L_he = sparse(reduce(vcat, L_row), reduce(vcat, L_col), reduce(vcat, L_val), Nado * sup_dim, Nado * sup_dim)
    if verbose
        println("[DONE]")
        flush(stdout)
    end
    return M_Boson(L_he, tier, Nsys, Nado, sup_dim, parity, Bath, hierarchy)
end