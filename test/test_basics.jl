using Distributions
using Random


# typed equality comparison with `\cong`
≅(x::T, y::T) where {T} = x == y
≅(x, y) = false


@testset "sanity checks" begin
    let call = track(Core.Intrinsics.add_int, 1, 2)
        @test call isa PrimitiveCallNode
        @test getvalue(call) ≅ 3
    end
    
    f(x) = x + 1
    let call = track(f, 42)
        # @test node.valu isa Tuple{Int, GraphTape}
        @test call isa NestedCallNode
        @test getvalue(call) ≅ 43
        
        # println("Trace of `f(42)` for visual inspection:")
        # printlevels(call, 3)
        # println("\n")
        # println(@code_ir f(42))
        # println("\n")
    end
    
    geom(n, β) = rand() < β ? n : geom(n + 1, β)
    let call = track(geom, 3, 0.5)
        @test call isa NestedCallNode
        @test getvalue(call) isa Int
        
        # println("Trace of `geom(3, 0.6)` for visual inspection:")
        # printlevels(call, 3)
        # println("\n")
        # println(@code_ir geom(3, 0.6))
        # println("\n")
    end

    weird(n) = rand() < 1/(n + 1) ? n : weird(n + 1)
    let call = track(weird, 3)
        @test call isa NestedCallNode
        @test getvalue(call) isa Int
    end

    function test1(x)
        t = (x, x)
        t[1] + 1
    end
    let call = track(test1, 42)
        @test call isa NestedCallNode
        @test getvalue(call) ≅ 43
    end

    function test2(x)
        if x < 0
            return x + 1
        else
            return x - 1 #sum([x, x])
        end
    end
    let call = track(test2, 42)
        @test call isa NestedCallNode
        @test getvalue(call) ≅ 41
    end

    function test3(x)
        y = zero(x)
        while x > 0
            y += 1
            x -= 1
        end

        return y
    end
    let call = track(test3, 42)
        @test call isa NestedCallNode
        @test getvalue(call) ≅ 42
    end
    
    test4(x) = [x, x]
    let call = track(test4, 42)
        @test call isa NestedCallNode
        @test getvalue(call) ≅ [42, 42]
    end

    test5() = ccall(:rand, Cint, ())
    let call = track(test5)
        @test call isa NestedCallNode
        @test getvalue(call) isa Cint
    end

    # this can fail due to https://github.com/MikeInnes/IRTools.jl/issues/30
    # when it hits the ccall in expm1 in rand(::GammGDSampler)
    sampler = Distributions.GammaGDSampler(Gamma(2, 3))
    test6() = rand(Random.GLOBAL_RNG, sampler)
    let call = track(test6)
        @test call isa NestedCallNode
        @test getvalue(call) isa Float64
    end
    
    function test7()
        p = rand(Beta(1, 1))
        conj = rand(Bernoulli(p)) == 1
        if conj
            m = rand(Normal(0, 1))
        else
            m = rand(Gamma(3, 2))
        end

        m += 2
        return rand(Normal(m, 1))
    end
    let call = track(test7)
        @test call isa NestedCallNode
        @test getvalue(call) isa Float64
    end


    test8_va(x, y...) = 1
    test8(x) = test8_va(x, x, x)
    let call = track(test8, 1)
        # this will be distorted due to being a closure:
        # ⟨var"#test8#8"{var"#test8_va#7"}(var"#test8_va#7"())⟩(⟨1⟩) = 1
        #   @1: [Arg:§1:%1] var"#test8#8"{var"#test8_va#7"}(var"#test8_va#7"())
        #   @2: [Arg:§1:%2] 1
        #   @3: [§1:%3] ⟨getfield⟩(@1, ⟨:test8_va⟩) = var"#test8_va#7"()
        #   @4: [§1:%4] @3(@2, (@2, @2)...) = 1
        #     @1: [Arg:§1:%1] var"#test8_va#7"()
        #     @2: [Arg:§1:%2] 1
        #     @3: [Arg:§1:%3] (1, 1)
        #     @4: [§1:&1] return ⟨1⟩
        #   @5: [§1:&1] return @4 = 1
        
        @test call isa NestedCallNode
        @test call[4] isa NestedCallNode
        @test call[4].call.arguments == (TapeReference(1, call[2], 2),)
        @test call[4].call.varargs == (TapeReference(1, call[2], 2), TapeReference(1, call[2], 2))
    end


    # test for proper tracking into Core._apply, see https://github.com/TuringLang/IRTracker.jl/issues/37
    test9_f(args...) = tuple(args..., nothing)
    test9_g(args) = test9_f(nothing, args..., args...)
    let call = track(test9_g, (1, 2))
        # this will be distorted due to being a closure:
        # ⟨var"#test9_g#8"{var"#test9_f#7"}(var"#test9_f#7"())⟩(⟨(1, 2)⟩, ()...) → (nothing, 1, 2, 1, 2, nothing)
        #   @1: [Arg:§1:%1] var"#test9_g#8"{var"#test9_f#7"}(var"#test9_f#7"())
        #   @2: [Arg:§1:%2] (1, 2)
        #   @3: [§1:%3] ⟨getfield⟩(@1, ⟨:test9_f⟩) → var"#test9_f#7"()
        #   @4: [§1:%4] ⟨tuple⟩(⟨nothing⟩) → (nothing,)
        #   @5: [§1:%5] ⟨Core._apply⟩(@3, (@4, @2, @2)...) → (nothing, 1, 2, 1, 2, nothing)
        #     @1: [Arg:§1:%1] @5#1 → var"#test9_f#7"()
        #     @2: [Arg:§1:%2] @5#2 → (nothing, 1, 2, 1, 2)
        #     @3: [§1:%3] ⟨tuple⟩(⟨nothing⟩) → (nothing,)
        #     @4: [§1:%4] ⟨Core._apply⟩(⟨tuple⟩, (@2, @3)...) → (nothing, 1, 2, 1, 2, nothing)
        #     @5: [§1:&1] return @4 → (nothing, 1, 2, 1, 2, nothing)
        #   @6: [§1:&1] return @5 → (nothing, 1, 2, 1, 2, nothing)

        
        @test getvalue(call) ≅ (nothing, 1, 2, 1, 2, nothing)
        @test call[5] isa NestedCallNode{<:Tuple, typeof(Core._apply)}
        @test call[5][4] isa PrimitiveCallNode{<:Tuple, typeof(Core._apply)}
    end
    
    # direct test of  https://github.com/MikeInnes/IRTools.jl/issues/30
    # aka https://github.com/phipsgabler/DynamicComputationGraphs.jl/issues/19
    @test track(expm1, 1.0) isa NestedCallNode
end


@testset "shapshotting" begin
    function test9(x)
        r = [1,2]
        push!(r, x)
        r[1] = x
        return r
    end

    let call = track(test9, 42)
        # ⟨f⟩(⟨42⟩, ()...) = [42, 2, 42]
        #   @1: [Arg:§1:%1] f
        #   @2: [Arg:§1:%2] 42
        #   @3: [§1:%3] ⟨Base.vect⟩(⟨1⟩, ⟨2⟩) = [1, 2]
        #   @4: [§1:%4] ⟨push!⟩(@3, @2) = [1, 2, 42]
        #   @5: [§1:%5] ⟨setindex!⟩(@3, @2, ⟨1⟩) = [42, 2, 42]
        #   @6: [§1:&1] return @3 = [42, 2, 42]

        @test getvalue(call[3]) ≅ [1, 2]
        @test getvalue(call[4]) ≅ [1, 2, 42]
        @test getvalue(call[5]) ≅ [42, 2, 42]
    end

    # Issue #44
    test10(x) = x isa AbstractVector{<:Some}
    let call = track(test10, 1)
        @test call isa NestedCallNode
        @test getvalue(call) ≅ false
    end
end


@testset "errors" begin
    @test_throws MethodError track(isodd)            # no method -- too few args
    @test_throws MethodError track(isodd, 2, 3)      # no method -- too many args
end
