@time @testset "Auxiliary density operators" begin
    ados_b = ADOs(spzeros(Int64, 20), 5)
    ados_f = ADOs(spzeros(Int64, 8), 2)
    ados_bf = ADOs(spzeros(Int64, 40), 10)
    @test show(devnull, MIME("text/plain"), ados_b) == nothing
    @test show(devnull, MIME("text/plain"), ados_f) == nothing
    @test show(devnull, MIME("text/plain"), ados_bf) == nothing
    @test_throws ErrorException ADOs(zeros(8), 4)

    ρ_b = ados_b[:]
    # check iteration
    for (i, ado) in enumerate(ados_b)
        @test ρ_b[i] == ado
    end

    # expections for expect
    ados_wrong = ADOs(spzeros(Int64, 18), 2)
    @test_throws ErrorException Expect([0 0 0; 0 0 0; 0 0 0], ados_f)
    @test_throws ErrorException Expect([0 0; 0 0], [ados_b, ados_wrong])
    @test_throws ErrorException Expect([0 0 0; 0 0 0; 0 0 0], [ados_b, ados_f])
end
