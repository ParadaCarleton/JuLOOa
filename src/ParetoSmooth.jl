module ParetoSmooth
using Requires
using DocStringExtensions

function __init__()
    chains=false
    @require MCMCChains = "c7f686f2-ff18-58e9-bc7b-31028e88f75d" begin 
        include("MCMCChainsHelpers.jl")
        chains=true
    end
    @require Turing = "fce5fe82-541a-59a6-adf8-730c64b5f9a0" begin
        if !chains
            include("MCMCChainsHelpers.jl")
        end
        include("TuringHelpers.jl")
    end 

end

include("AbstractCV.jl")
include("ESS.jl")
include("GPD.jl")
include("InternalHelpers.jl")
include("ImportanceSampling.jl")
include("LeaveOneOut.jl")
include("ModelComparison.jl")
include("NaiveLPD.jl")
include("PublicHelpers.jl")

end
