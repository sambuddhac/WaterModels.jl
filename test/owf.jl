@testset "Optimal Water Flow Problems (Single Network)" begin
    network = WaterModels.parse_file("../test/data/epanet/snapshot/pump-hw-lps.inp")

    wm = instantiate_model(deepcopy(network), NLPWaterModel, build_owf)
    result = WaterModels.optimize_model!(wm, optimizer=_make_juniper(wm, ipopt))
    @test result["termination_status"] == LOCALLY_SOLVED
    @test isapprox(result["solution"]["node"]["1"]["h"], 10.0, rtol=1.0e-3)
    @test isapprox(result["solution"]["node"]["2"]["h"], 98.98, rtol=1.0e-3)
    @test isapprox(result["solution"]["pump"]["1"]["status"], 1.0, atol=1.0e-3)
    @test result["objective"] <= 128.302

    wm = instantiate_model(deepcopy(network), MICPRWaterModel, build_owf, ext=Dict(:pump_breakpoints=>3))
    result = WaterModels.optimize_model!(wm, optimizer=_make_juniper(wm, ipopt))
    @test result["termination_status"] == LOCALLY_SOLVED
    @test isapprox(result["solution"]["node"]["1"]["h"], 10.0, rtol=1.0e-3)
    @test result["solution"]["node"]["2"]["h"] <= 98.99
    @test isapprox(result["solution"]["pump"]["1"]["status"], 1.0, atol=1.0e-3)
    @test result["objective"] <= 128.302

    result = run_owf(deepcopy(network), MILPWaterModel, cbc, ext=Dict(:pump_breakpoints=>4))
    @test result["termination_status"] == OPTIMAL
    @test isapprox(result["solution"]["node"]["1"]["h"], 10.0, rtol=1.0e-3)
    @test isapprox(result["solution"]["node"]["2"]["h"], 98.98, rtol=1.0e-1)
    @test isapprox(result["solution"]["pump"]["1"]["status"], 1.0, atol=1.0e-3)
    @test result["objective"] <= 128.302

    result = run_owf(deepcopy(network), MILPRWaterModel, cbc, ext=Dict(:pump_breakpoints=>3))
    @test result["termination_status"] == OPTIMAL
    @test isapprox(result["solution"]["node"]["1"]["h"], 10.0, rtol=1.0e-3)
    @test result["solution"]["node"]["2"]["h"] <= 98.99
    @test isapprox(result["solution"]["pump"]["1"]["status"], 1.0, atol=1.0e-3)
    @test result["objective"] <= 128.302
end

@testset "Optimal Water Flow Problems (Multinetwork)" begin
    network = WaterModels.parse_file("../test/data/epanet/multinetwork/owf-hw-lps.inp")
    network = WaterModels.make_multinetwork(network)

    wm = instantiate_model(deepcopy(network), NLPWaterModel, build_mn_owf)
    result = WaterModels.optimize_model!(wm, optimizer=_make_juniper(wm, ipopt))
    @test result["termination_status"] == LOCALLY_SOLVED

    wm = instantiate_model(deepcopy(network), MICPRWaterModel, build_mn_owf, ext=Dict(:pump_breakpoints=>3))
    result = WaterModels.optimize_model!(wm, optimizer=_make_juniper(wm, ipopt))
    @test result["termination_status"] == LOCALLY_SOLVED

    result = run_mn_owf(deepcopy(network), MILPWaterModel, cbc, ext=Dict(:pump_breakpoints=>4))
    @test result["termination_status"] == OPTIMAL

    result = run_mn_owf(deepcopy(network), MILPRWaterModel, cbc, ext=Dict(:pump_breakpoints=>3))
    @test result["termination_status"] == OPTIMAL
end
