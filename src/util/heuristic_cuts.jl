export heuristic_cut_callback_generator

import JuMP
import MathProgBase

function heuristic_cut_callback_generator(wm::GenericWaterModel, params::Dict{String, Any},
                                          nlp_solver::MathProgBase.AbstractMathProgSolver,
                                          n_s::Int, n::Int = wm.cnw)
    function heuristic_cut_callback(cb::MathProgBase.MathProgCallbackData)
        num_nodes_explored = convert(Int, MathProgBase.cbgetexplorednodes(cb))
        resistances = wm.ref[:nw][n][:resistance]
        connection_ids = collect(ids(wm, n, :connection))
        resistance_indices = Dict{Int, Int}(a => 1 for a in connection_ids)

        if (num_nodes_explored > 0) && (num_nodes_explored % 500 == 0)
            for (a, connection) in wm.ref[:nw][n][:connection]
                xr_a = getvalue(wm.var[:nw][n][:xr][a])
                geq_indices = filter(r -> xr_a[r] >= 1.0 / length(xr_a), 1:length(xr_a))
                r_val, r_rel = findmin([xr_a[r] for r in geq_indices])
                resistance_indices[a] = geq_indices[r_rel]
            end
        else
            # Update resistances used throughout the network.
            for (a, connection) in wm.ref[:nw][n][:connection]
                xr_a = getvalue(wm.var[:nw][n][:xr][a])
                xr_ones = findall(r -> isapprox(xr_a[r], 1.0, atol = 0.01), 1:length(xr_a))
                xr_zeros = findall(r -> isapprox(xr_a[r], 0.0, atol = 0.01), 1:length(xr_a))
                xr_are_integers = (length(xr_ones) + length(xr_zeros)) == length(xr_a)

                dir = getvalue(wm.var[:nw][n][:dir][a])
                dir_is_integer = isapprox(dir, 1.0, atol = 0.01) ||
                                 isapprox(dir, 0.0, atol = 0.01)

                if !(xr_are_integers && dir_is_integer)
                    return
                else
                    resistance_indices[a] = xr_ones[1]
                end
            end
        end

        # TODO: Toggle this on and off and examine the effects.
        if compute_objective(wm, resistance_indices, n) >= params["obj_best"]
            return
        end

        repaired, resistance_indices = repair_solution(wm, resistance_indices,
                                                       params["max_repair_iters"],
                                                       params["obj_best"],
                                                       nlp_solver, n)

        if repaired
            # Update objective values.
            current_objective = compute_objective(wm, resistance_indices, n)
            params["obj_last"] = params["obj_curr"]
            params["obj_curr"] = current_objective
            params["obj_best"] = min(params["obj_curr"], params["obj_best"])

            q, h = get_cvx_solution(wm, resistance_indices, nlp_solver)

            # Set the integer values appropriately.
            for (a, connection) in wm.ref[:nw][n][:connection]
                segment_selected = false
                resistance_index = resistance_indices[a]
                setsolutionvalue(cb, wm.var[:nw][n][:dir][a], q[a] >= 0.0 ? 1 : 0)
                setsolutionvalue(cb, wm.var[:nw][n][:xr][a][resistance_index], 1)

                for r in setdiff(1:length(resistances[a]), [resistance_index])
                    setsolutionvalue(cb, wm.var[:nw][n][:xr][a][r], 0)

                    for k in 1:n_s
                        setsolutionvalue(cb, wm.var[:nw][n][:xsp][a][k, r], 0)
                        setsolutionvalue(cb, wm.var[:nw][n][:xsn][a][k, r], 0)
                    end
                end

                for k in 1:n_s
                    if q[a] >= 0.0
                        qp_ar = wm.var[:nw][n][:qp][a][:, resistance_index]
                        qp_ark_lb = k > 1 ? getupperbound(qp_ar[k-1]) : 0.0
                        qp_ark_ub = getupperbound(qp_ar[k])

                        if q[a] >= qp_ark_lb && q[a] <= qp_ark_ub && !segment_selected
                            segment_selected = true
                            setsolutionvalue(cb, wm.var[:nw][n][:xsp][a][k, resistance_index], 1)
                        else
                            setsolutionvalue(cb, wm.var[:nw][n][:xsp][a][k, resistance_index], 0)
                        end
                    else
                        qn_ar = wm.var[:nw][n][:qn][a][:, resistance_index]
                        qn_ark_lb = k > 1 ? getupperbound(qn_ar[k-1]) : 0.0
                        qn_ark_ub = getupperbound(qn_ar[k])

                        if -q[a] >= qn_ark_lb && -q[a] <= qn_ark_ub && !segment_selected
                            segment_selected = true
                            setsolutionvalue(cb, wm.var[:nw][n][:xsn][a][k, resistance_index], 1)
                        else
                            setsolutionvalue(cb, wm.var[:nw][n][:xsn][a][k, resistance_index], 0)
                        end
                    end
                end
            end

            # Register the solution via the callback.
            addsolution(cb)
        end
    end

    return heuristic_cut_callback
end