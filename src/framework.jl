"""
A model contains all the information required to run a rule in a cellular
simulation, given an initialised array. Models can be chained together in any order.

The output of the rule for an AbstractModel is written to the current cell in the grid.
"""
abstract type AbstractModel end

"""
An abstract type for models that do not write to every cell of the grid, for efficiency.

There are two main differences with `AbstractModel`. AbstractPartialModel requires
initialisation of the destination array before each timestep, and the output of
the rule is not written to the grid but done manually.
"""
abstract type AbstractPartialModel end


"""
    sim!(output, model, init, args...; time=1:1000, pause=0.0)
Runs the whole simulation, passing the destination aray to
the passed in output for each time-step.

### Arguments
- `output`: An [AbstractOutput](@ref) to store frames or display them on the screen.
- `model`: A single [`AbstractModel`](@ref) or a tuple of models that will each be run in sequence.
- `init`: The initialisation array.
- `args`: Any additional user defined args are passed through to [`rule`](@ref) and
  [`neighbors`](@ref) methods.

### Keyword Arguments
- `time`: Any Iterable of Number. Default: 1:1000
- `pause`: A Number that specifies the pause beteen frames in seconds. Default: 0.0
"""
sim!(output, model, init, args...; time=1:1000, pause=0.0) = begin
    # Initialise arrays to the same type and values as the passed in initial array
    source = deepcopy(init)
    dest = deepcopy(init)
    initialize(output)

    # Define the index coordinates. There might be a better way than this?
    width, height = size(init)
    index = collect((col,row) for col in 1:width, row in 1:height)

    # Loop over the selected timespan
    for t in time
        # Save the the current frame
        store_frame(output, source)
        # Display the current frame
        show_frame(output, t; pause=pause) || break
        # Run the automation on the source array, writing to the dest array and
        # setting the source and dest arrays for the next iteration.
        source, dest = broadcast_rules!(model, source, dest, index, t, args...)
    end
    output
end

"""
    broadcast_rules!(models, source, dest, index, t, args...)
Runs the rule(s) for each cell in the grid, dependin on the model(s) passed in.
For [`AbstractModel`] the returned values are written to the `dest` grid,
while for [`AbstractPartialModel`](@ref) the grid is
pre-initialised to zero and rules manually populate the dest grid.

Returns a tuple containing the source and dest arrays for the next iteration.
"""
broadcast_rules!(models::Tuple{T,Vararg}, source, dest, index, t, args...) where {T<:AbstractModel} = begin
    # Write rule outputs to every cell of the dest array
    broadcast!(rule, dest, models[1], source, index, t, (source,), (dest,), args...)
    # Swap source and dest for the next rule/iteration
    broadcast_rules!(Base.tail(models), dest, source, index, t, args...)
end
broadcast_rules!(models::Tuple{T,Vararg}, source, dest, index, t, args...) where {T<:AbstractPartialModel} = begin
    # Initialise the dest array
    dest .= source
    # The rule writes to the dest array manually where required
    broadcast(rule, models[1], source, index, t, (source,), (dest,), args...)
    # Swap source and dest for the next rule/iteration
    broadcast_rules!(Base.tail(models), dest, source, index, t, args...)
end
broadcast_rules!(models::Tuple{}, source, dest, index, t, args...) = source, dest
broadcast_rules!(model, args...) = broadcast_rules!((model,), args...)


"""
    function rule(model, state, index, t, source, dest, args...)
Rules alter cell values based on their current state and other cells, often
[`neighbors`](@ref). Most rules return a value to be written to the current cell,
except rules for models inheriting from [`AbstractPartialModel`](@ref).
These must write to the `dest` array directly.

### Arguments:
- `model` : [`AbstractModel`](@ref)
- `state`: the value of the current cell
- `index`: a (row, column) tuple of Int for the current cell coordinates
- `t`: the current time step
- `source`: the whole source array. Not to be written to
- `dest`: the whole destination array. To be written to for AbstractPartialModel.
- `args`: additional arguments passed through from user input to [`sim!`](@ref)

"""
function rule(model::Void, state, index, t, source, args...) end


"""
Singleton types for choosing the grid overflow rule used in
[`inbounds`](@ref). These determine what is done when a neighborhood
or jump extends outside of the grid.
"""
abstract type AbstractOverflow end
"Wrap cords that overflow to the opposite side"
struct Wrap <: AbstractOverflow end
"Skip coords that overflow boundaries"
struct Skip <: AbstractOverflow end

"""
    inbounds(x, max, overflow)
Check grid boundaries for a single coordinate and max value or a tuple
of coorinates and max values.

Returns a tuple containing the coordinate(s) followed by a boolean `true`
if the cell is in bounds, `false` if not.

Overflow of type [`Skip`](@ref) returns the coordinate and `false` to skip
coordinates that overflow outside of the grid.
[`Wrap`](@ref) returns a tuple with the current position or it's
wrapped equivalent, and `true` as it is allways in-bounds.
"""
inbounds(xs::Tuple, maxs::Tuple, overflow) = begin
    a, inbounds_a = inbounds(xs[1], maxs[1], overflow)
    b, inbounds_b = inbounds(xs[2], maxs[2], overflow)
    a, b, inbounds_a && inbounds_b
end
inbounds(x::Number, max::Number, overflow::Skip) = x, x > 0 && x <= max
inbounds(x::Number, max::Number, overflow::Wrap) = begin
    if x < 1
        x = max + rem(x, max)
    elseif x > max
        x = rem(x, max)
    end
    x, true
end