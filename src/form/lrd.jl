# Define common LRD (linear relaxation- and direction-based) implementations of water
# distribution network constraints, which use directed flow variables.


########################################## PIPES ##########################################


function constraint_pipe_head_loss(wm::LRDWaterModel, n::Int, a::Int, node_fr::Int, node_to::Int, exponent::Float64, L::Float64, r::Float64, q_max_reverse::Float64, q_min_forward::Float64)
    # Get the number of breakpoints for the pipe.
    num_breakpoints = get(wm.ext, :pipe_breakpoints, 1)

    # Get the variable for flow directionality.
    y = var(wm, n, :y_pipe, a)

    # Get variables for positive flow and head difference.
    qp, dhp = var(wm, n, :qp_pipe, a), var(wm, n, :dhp_pipe, a)
    qp_min_forward, qp_ub = max(0.0, q_min_forward), JuMP.upper_bound(qp)

    # Loop over breakpoints strictly between the lower and upper variable bounds.
    for pt in range(qp_min_forward, stop = JuMP.upper_bound(qp), length = num_breakpoints+2)[2:end-1]
        # Add a linear outer approximation of the convex relaxation at `pt`.
        lhs = _get_head_loss_oa_binary(qp, y, pt, exponent)

        # Add the normalized constraint to the model.
        c = JuMP.@constraint(wm.model, r * lhs - inv(L) * dhp <= 0.0)

        # Append the :pipe_head_loss constraint array.
        append!(con(wm, n, :pipe_head_loss)[a], [c])
    end

    # Get the lower-bounding line for the qp curve.
    if qp_min_forward < qp_ub
        dhp_1, dhp_2 = r * qp_min_forward^exponent, r * qp_ub^exponent
        dhp_slope = (dhp_2 - dhp_1) * inv(qp_ub - qp_min_forward)
        dhp_lb_line = dhp_slope * (qp - qp_min_forward * y) + dhp_1 * y

        # Add the normalized constraint to the model.
        c = JuMP.@constraint(wm.model, inv(L) * dhp - dhp_lb_line <= 0.0)

        # Append the :pipe_head_loss constraint array.
        append!(con(wm, n, :pipe_head_loss)[a], [c])
    end

    # Get variables for negative flow and head difference.
    qn, dhn = var(wm, n, :qn_pipe, a), var(wm, n, :dhn_pipe, a)
    qn_min_forward, qn_ub = max(0.0, -q_max_reverse), JuMP.upper_bound(qn)

    # Loop over breakpoints strictly between the lower and upper variable bounds.
    for pt in range(qn_min_forward, stop = JuMP.upper_bound(qn), length = num_breakpoints+2)[2:end-1]
        # Add a linear outer approximation of the convex relaxation at `pt`.
        lhs = _get_head_loss_oa_binary(qn, 1.0 - y, pt, exponent)

        # Add the normalized constraint to the model.
        c = JuMP.@constraint(wm.model, r * lhs - inv(L) * dhn <= 0.0)

        # Append the :pipe_head_loss constraint array.
        append!(con(wm, n, :pipe_head_loss)[a], [c])
    end

    # Get the lower-bounding line for the qn curve.
    if qn_min_forward < qn_ub
        dhn_1, dhn_2 = r * qn_min_forward^exponent, r * qn_ub^exponent
        dhn_slope = (dhn_2 - dhn_1) * inv(qn_ub - qn_min_forward)
        dhn_lb_line = dhn_slope * (qn - qn_min_forward * (1.0 - y)) + dhn_1 * (1.0 - y)

        # Add the normalized constraint to the model.
        c = JuMP.@constraint(wm.model, inv(L) * dhn - dhn_lb_line <= 0.0)

        # Append the :pipe_head_loss constraint array.
        append!(con(wm, n, :pipe_head_loss)[a], [c])
    end
end


function constraint_on_off_pipe_head_loss_des(wm::LRDWaterModel, n::Int, a::Int, exponent::Float64, node_fr::Int, node_to::Int, L::Float64, resistances)
    # If the number of breakpoints is not positive, no constraints are added.
    num_breakpoints = get(wm.ext, :pipe_breakpoints, 1)

    # Get design pipe direction and status variable references.
    y, z = var(wm, n, :y_des_pipe, a), var(wm, n, :z_des_pipe, a)

    # Get head difference variables for the pipe.
    dhp, dhn = var(wm, n, :dhp_des_pipe, a), var(wm, n, :dhn_des_pipe, a)
    qp, qn = var(wm, n, :qp_des_pipe, a), var(wm, n, :qn_des_pipe, a)

    for (r_id, r) in enumerate(resistances)
        # Get directed flow variables and associated data.
        qp_ub, qn_ub = JuMP.upper_bound(qp[r_id]), JuMP.upper_bound(qn[r_id])

        # Loop over breakpoints strictly between the lower and upper variable bounds.
        for pt in range(0.0, stop = qp_ub, length = num_breakpoints+2)[2:end-1]
            lhs = r * _get_head_loss_oa_binary(qp[r_id], z[r_id], pt, exponent)
            c_1 = JuMP.@constraint(wm.model, lhs <= inv(L) * dhp)
            append!(con(wm, n, :on_off_pipe_head_loss_des)[a], [c_1])
        end

        # Loop over breakpoints strictly between the lower and upper variable bounds.
        for pt in range(0.0, stop = qn_ub, length = num_breakpoints+2)[2:end-1]
            lhs = r * _get_head_loss_oa_binary(qn[r_id], z[r_id], pt, exponent)
            c_2 = JuMP.@constraint(wm.model, lhs <= inv(L) * dhn)
            append!(con(wm, n, :on_off_pipe_head_loss_des)[a], [c_2])
        end
    end

    # Add linear upper bounds for the positive portion of head loss.
    qp_ub = JuMP.upper_bound.(qp)
    slopes_p = resistances .* qp_ub.^(exponent - 1.0)
    c_3 = JuMP.@constraint(wm.model, inv(L)*dhp <= sum(slopes_p .* qp))

    # Add linear upper bounds for the negative portion of head loss.
    qn_ub = JuMP.upper_bound.(qn)
    slopes_n = resistances .* qn_ub.^(exponent - 1.0)
    c_4 = JuMP.@constraint(wm.model, inv(L)*dhn <= sum(slopes_n .* qn))

    # Append the :on_off_pipe_head_loss_des constraint array.
    append!(con(wm, n, :on_off_pipe_head_loss_des)[a], [c_3, c_4])
end


########################################## PUMPS ##########################################


"Instantiate variables associated with modeling each pump's head gain."
function variable_pump_head_gain(wm::LRDWaterModel; nw::Int=wm.cnw, bounded::Bool=true, report::Bool=true)
    # Initialize variables for total hydraulic head gain from a pump.
    g = var(wm, nw)[:g_pump] = JuMP.@variable(wm.model, [a in ids(wm, nw, :pump)],
        base_name="$(nw)_g_pump", lower_bound=0.0, # Pump gain is nonnegative.
        start=comp_start_value(ref(wm, nw, :pump, a), "g_pump_start"))

    # Initialize an entry to the solution component dictionary for head gains.
    report && sol_component_value(wm, nw, :pump, :g, ids(wm, nw, :pump), g)

    # Get the number of breakpoints for the pump.
    pump_breakpoints = get(wm.ext, :pump_breakpoints, 2)

    # Create weights involved in convex combination constraints for pumps.
    lambda_pump = var(wm, nw)[:lambda_pump] = JuMP.@variable(wm.model,
        [a in ids(wm, nw, :pump), k in 1:pump_breakpoints],
        base_name="$(nw)_lambda", lower_bound=0.0, upper_bound=1.0,
        start=comp_start_value(ref(wm, nw, :pump, a), "lambda_start", k))

    # Create binary variables involved in convex combination constraints for pumps.
    x_pw_pump = var(wm, nw)[:x_pw_pump] = JuMP.@variable(wm.model,
        [a in ids(wm, nw, :pump), k in 1:pump_breakpoints-1], base_name="$(nw)_x_pw",
        binary=true, start=comp_start_value(ref(wm, nw, :pump, a), "x_pw_start"))
end


"Add constraints associated with modeling a pump's head gain."
function constraint_on_off_pump_head_gain(wm::LRDWaterModel, n::Int, a::Int, node_fr::Int, node_to::Int, pc::Array{Float64}, q_min_forward::Float64)
    # Get the number of breakpoints for the pump.
    pump_breakpoints = get(wm.ext, :pump_breakpoints, 2)

    # Gather pump flow, head gain, and status variables.
    qp, g, z = var(wm, n, :qp_pump, a), var(wm, n, :g_pump, a), var(wm, n, :z_pump, a)

    # Gather convex combination variables.
    lambda, x_pw = var(wm, n, :lambda_pump), var(wm, n, :x_pw_pump)

    # Add the required SOS constraints.
    c_1 = JuMP.@constraint(wm.model, sum(lambda[a, :]) == z)
    c_2 = JuMP.@constraint(wm.model, sum(x_pw[a, :]) == z)
    c_3 = JuMP.@constraint(wm.model, lambda[a, 1] <= x_pw[a, 1])
    c_4 = JuMP.@constraint(wm.model, lambda[a, end] <= x_pw[a, end])

    # Add a constraint for the flow piecewise approximation.
    breakpoints = range(q_min_forward, stop=JuMP.upper_bound(qp), length=pump_breakpoints)
    qp_lhs = sum(breakpoints[k] * lambda[a, k] for k in 1:pump_breakpoints)
    c_5 = JuMP.@constraint(wm.model, qp_lhs == qp)

    # Add a constraint that lower-bounds the head gain variable.
    f = (pc[1] .* breakpoints.^2) .+ (pc[2] .* breakpoints) .+ pc[3]
    gain_lb_expr = sum(f[k] .* lambda[a, k] for k in 1:pump_breakpoints)
    c_6 = JuMP.@constraint(wm.model, gain_lb_expr <= g)

    # Append the constraint array.
    append!(con(wm, n, :on_off_pump_head_gain, a), [c_1, c_2, c_3, c_4, c_5, c_6])

    for qp_hat in breakpoints
        # Add head gain outer (i.e., upper) approximations.
        rhs = _get_head_gain_oa(qp, z, qp_hat, pc)
        c_7_k = JuMP.@constraint(wm.model, g <= rhs)
        append!(con(wm, n, :on_off_pump_head_gain, a), [c_7_k])
    end

    for k in 2:pump_breakpoints-1
        # Add the adjacency constraints for piecewise variables.
        adjacency = x_pw[a, k-1] + x_pw[a, k]
        c_8_k = JuMP.@constraint(wm.model, lambda[a, k] <= adjacency)
        append!(con(wm, n, :on_off_pump_head_gain, a), [c_8_k])
    end
end


######################################## OBJECTIVES ########################################


"Instantiate the objective associated with the Optimal Water Flow problem."
function objective_owf_default(wm::LRDWaterModel)
    # Get the number of breakpoints for the pump.
    pump_breakpoints = get(wm.ext, :pump_breakpoints, 2)

    # Initialize the objective function.
    objective = JuMP.AffExpr(0.0)

    for (n, nw_ref) in nws(wm)
        # Get common variables.
        lambda = var(wm, n, :lambda_pump)

        for (a, pump) in nw_ref[:pump]
            if haskey(pump, "energy_price")
                # Get pump energy price data.
                price = pump["energy_price"]

                # Get pump flow and status variables.
                qp, z = var(wm, n, :qp_pump, a), var(wm, n, :z_pump, a)
                q_min_forward = max(get(pump, "flow_min_forward", _FLOW_MIN), _FLOW_MIN)

                # Generate a set of uniform flow and cubic function breakpoints.
                breakpoints = range(q_min_forward, stop = JuMP.upper_bound(qp), length = pump_breakpoints)
                energy = _calc_pump_energy_ua(wm, n, a, collect(breakpoints))

                # Add the cost corresponding to the current pump's operation.
                cost = sum(price * energy[k] * lambda[a, k] for k in 1:pump_breakpoints)
                JuMP.add_to_expression!(objective, cost)
            else
                Memento.error(_LOGGER, "No cost given for pump \"$(pump["name"])\"")
            end
        end
    end

    return JuMP.@objective(wm.model, _MOI.MIN_SENSE, objective)
end