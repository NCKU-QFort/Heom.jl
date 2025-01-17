## run the following command under HierarchicalEOM.jl root directory
# julia --project=docs/ -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd()));Pkg.instantiate()'
# julia --project=docs/ docs/make.jl

using Documenter, HierarchicalEOM

DocMeta.setdocmeta!(HierarchicalEOM, :DocTestSetup, :(using HierarchicalEOM); recursive = true)

const DRAFT = false # set `true` to disable cell evaluation

const MathEngine = MathJax3(
    Dict(
        :loader => Dict("load" => ["[tex]/physics"]),
        :tex => Dict(
            "inlineMath" => [["\$", "\$"], ["\\(", "\\)"]],
            "tags" => "ams",
            "packages" => ["base", "ams", "autoload", "physics"],
        ),
    ),
)

const PAGES = Any[
    "Home"=>Any[
        "Introduction"=>"index.md",
        "Installation"=>"install.md",
        "Quick Start"=>"quick_start.md",
        "Cite HierarchicalEOM.jl"=>"cite.md",
    ],
    "Manual"=>Any[
        "Bosonic Bath"=>Any[
            "Introduction"=>"bath_boson/bosonic_bath_intro.md",
            "Drude-Lorentz Spectral Density"=>"bath_boson/Boson_Drude_Lorentz.md",
            "Underdamped Spectral Density"=>"bath_boson/Boson_Underdamped.md",
        ],
        "Bosonic Bath (RWA)"=>Any["Introduction"=>"bath_boson_RWA/bosonic_bath_RWA_intro.md"],
        "Fermionic Bath"=>Any[
            "Introduction"=>"bath_fermion/fermionic_bath_intro.md",
            "Lorentz Spectral Density"=>"bath_fermion/Fermion_Lorentz.md",
        ],
        "Auxiliary Density Operators"=>"ADOs.md",
        "HEOMLS Matrices"=>Any[
            "Introduction"=>"heom_matrix/HEOMLS_intro.md",
            "HEOMLS for Schrödinger Equation"=>"heom_matrix/schrodinger_eq.md",
            "HEOMLS for Bosonic Bath"=>"heom_matrix/M_Boson.md",
            "HEOMLS for Fermionic Bath"=>"heom_matrix/M_Fermion.md",
            "HEOMLS for Bosonic and Fermionic Bath"=>"heom_matrix/M_Boson_Fermion.md",
            "HEOMLS for Master Equation"=>"heom_matrix/master_eq.md",
        ],
        "Parity Support"=>"Parity.md",
        "Hierarchy Dictionary"=>"hierarchy_dictionary.md",
        "Time Evolution"=>"time_evolution.md",
        "Stationary State"=>"stationary_state.md",
        "Spectrum"=>"spectrum.md",
        "Examples"=>"examples.md",
        "Solvers Lists"=>Any["ODE_solvers.md", "LS_solvers.md"],
        "Extensions"=>Any["CUDA.jl"=>"extensions/CUDA.md"],
    ],
    "Library API"=>"libraryAPI.md",
]

makedocs(;
    modules = [HierarchicalEOM],
    authors = "Yi-Te Huang",
    repo = Remotes.GitHub("qutip", "HierarchicalEOM.jl"),
    sitename = "Documentation | HierarchicalEOM.jl",
    pages = PAGES,
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://qutip.github.io/HierarchicalEOM.jl",
        edit_link = "main",
        mathengine = MathEngine,
        ansicolor = true,
        size_threshold_ignore = ["libraryAPI.md"],
    ),
    draft = DRAFT,
)

deploydocs(; repo = "github.com/qutip/HierarchicalEOM.jl", devbranch = "main")
