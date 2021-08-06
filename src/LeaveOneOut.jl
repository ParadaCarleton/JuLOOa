using AxisKeys
using Distributions
using InteractiveUtils
using LoopVectorization
using Statistics
using Tullio

export loo, psis_loo

const LOO_METHODS = subtypes(AbstractCVMethod)

"""
    function loo(args...; method=PsisLooMethod(), kwargs...) -> PsisLoo

Compute the approximate leave-one-out cross-validation score using the specified method.

Currently, this function only serves to call `psis_loo`, but this could change in the
future. The default methods or return type may change without warning; thus, we recommend
using `psis_loo` instead if reproducibility is required.

See also: [`psis_loo`](@ref), [`PsisLoo`](@ref).
"""
function loo(args...; method=PsisLooMethod(), kwargs...)
    if typeof(method) ∈ LOO_METHODS
        return psis_loo(args...; kwargs...)
    else
        throw(ArgumentError("Invalid method provided. Valid methods are $LOO_METHODS"))
    end
end


"""
    function psis_loo(
        log_likelihood::Array{Real} [, args...];
        [, chain_index::Vector{Integer}, kwargs...]
    ) -> PsisLoo

Use Pareto-Smoothed Importance Sampling to calculate the leave-one-out cross-validation
estimate.

# Arguments

  - `log_likelihood::Array`: An array or matrix of log-likelihood values indexed as
    `[data, step, chain]`. The chain argument can be left off if `chain_index` is provided
    or if all posterior samples were drawn from a single chain.
  - `args...`: Positional arguments to be passed to [`psis`](@ref).
  - `chain_index::Vector`: An (optional) vector of integers specifying which chain each
    step belongs to. For instance, `chain_index[3]` should return `2` if
    `log_likelihood[:, 3]` belongs to the second chain.
  - `kwargs...`: Keyword arguments to be passed to [`psis`](@ref).

See also: [`psis`](@ref), [`loo`](@ref), [`PsisLoo`](@ref).
"""
function psis_loo(
    log_likelihood::AbstractArray, args...; 
    kwargs...
) where {F<:Real, T<:AbstractArray{F, 3}}
    

    dims = size(log_likelihood)
    data_size = dims[1]
    mcmc_count = dims[2] * dims[3]  # total number of samples from posterior
    log_count = log(mcmc_count)


    # TODO: Add a way of using score functions other than ELPD
    # log_likelihood::ArrayType = similar(log_likelihood)
    # log_likelihood .= score(log_likelihood)

    psis_object = psis(-log_likelihood, args...; kwargs...)
    weights = psis_object.weights
    ξ = psis_object.pareto_k
    r_eff = psis_object.r_eff

    @tullio pointwise_loo[i] := weights[i, j, k] * exp(log_likelihood[i, j, k]) |> log
    @tullio pointwise_naive[i] := exp(log_likelihood[i, j, k] - log_count) |> log
    pointwise_overfit = pointwise_naive - pointwise_loo
    @tullio pointwise_mcse[i] := sqrt <|
        (weights[i, j, k] * (log_likelihood[i, j, k] - pointwise_loo[i]))^2
    @turbo pointwise_mcse .= pointwise_mcse ./ sqrt.(r_eff)  # autocorrelation adjustment


    pointwise = KeyedArray(
        hcat(
            pointwise_loo,
            pointwise_naive,
            pointwise_overfit,
            pointwise_mcse,
            ξ
        );
        data=1:length(pointwise_loo),
        statistic=[
            :loo_est,
            :naive_est,
            :overfit,
            :mcse,
            :pareto_k
        ],
    )

    table = _generate_loo_table(log_likelihood, pointwise, data_size)

    return PsisLoo(table, pointwise, psis_object)

end


function psis_loo(
    log_likelihood::T,
    args...;
    chain_index::AbstractVector=ones(size(log_likelihood, 1)),
    kwargs...,
) where {F <: Real, T <: AbstractMatrix{F}}
    new_log_ratios = _convert_to_array(log_likelihood, chain_index)
    return psis_loo(new_log_ratios, args...; kwargs...)
end
    

function _generate_loo_table(
    log_likelihood::AbstractArray, 
    pointwise::AbstractArray, 
    data_size::Integer
)

    # create table with the right labels
    table = KeyedArray(
        similar(log_likelihood, 3, 4);
        criterion=[:loo_est, :naive_est, :overfit],
        statistic=[:total, :se_total, :mean, :se_mean],
    )

    # calculate the sample expectation for the total score
    to_sum = pointwise([:loo_est, :naive_est, :overfit])
    @tullio averages[crit] := to_sum[data, crit] / data_size
    averages = reshape(averages, 3)
    table(:, :mean) .= averages

    # calculate the sample expectation for the average score
    table(:, :total) .= table(:, :mean) .* data_size

    # calculate the sample expectation for the standard error in the totals
    se_mean = std(to_sum; mean=averages', dims=1) / sqrt(data_size)
    se_mean = reshape(se_mean, 3)
    table(:, :se_mean) .= se_mean

    # calculate the sample expectation for the standard error in averages
    table(:, :se_total) .= se_mean * data_size

    return table
end