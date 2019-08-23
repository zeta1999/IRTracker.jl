using IRTools
import Base: getproperty, getindex

struct _DCGCall end

const DCGCall = _DCGCall()
getproperty(::_DCGCall, name::Symbol) =
    (args...) -> IRTools.xcall(DynamicComputationGraphs, name, args...)


# Unique indexing into IR

abstract type IRIndex end

struct StmtIndex <: IRIndex
    varid::Int
end

struct BranchIndex <: IRIndex
    block::Int
    position::Int
end

getindex(ir::IRTools.IR, ix::StmtIndex) = ir[IRTools.var(ix.varid)]
getindex(ir::IRTools.IR, ix::BranchIndex) = IRTools.branches(ir, ix.block)[ix.position]



function print_intrinsic_error(f::Core.IntrinsicFunction, args...)
    # from https://github.com/JuliaLang/julia/blob/c6da87ff4bc7a855e217856757ad3413cf6d1f79/base/show.jl#L398
    name = unsafe_string(ccall(:jl_intrinsic_name, Cstring, (Core.IntrinsicFunction,), f))
    error("Can't track the intrinsic function ", name, " with arguments ",
          join(args, ", "))
end



struct TapeIndex
    id::Int
end

const VarToRecordDict = Dict{IRTools.Variable, TapeIndex}

record_variable!(d::VarToRecordDict, v::IRTools.Variable) = push!(d, v => TapeIndex(length(d) + 1))


reify_quote(expr) = Expr(:copyast, QuoteNode(expr))

prepare_expression(d::VarToRecordDict, var::IRTools.Variable) = d[var]
prepare_expression(::VarToRecordDict, expr) = expr

function prepare_expression(d::VarToRecordDict, expr::Expr)
    Expr(expr.head, map(expr -> prepare_expression(d, expr), expr.args)...)
end