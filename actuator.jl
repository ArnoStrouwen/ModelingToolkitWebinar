using ModelingToolkit
#using ModelingToolkit: t_nounits as t, D_nounits as D
using DifferentialEquations
using DelimitedFiles
using Plots

@parameters t
D = Differential(t)

function System(u_fun=identity;name, p_s = 100e5, p_r = 10e5, C = 2.7*0.5)
    pars = @parameters begin
        rho_0 = 1000
        beta = 2e9
        A = 0.1
        m = 100
        L = 1
        p_s = p_s
        p_r = p_r
        C = C
        c = 1000
        A_p = 0.00094
    end   
    vars = @variables begin
        p_1(t) = p_s
        p_2(t) = p_r
        x(t)=0
        dx(t)=0
        ddx(t)=A*(p_1 - p_2)
        rho_1(t)=rho_0*(1 + p_1/beta)
        rho_2(t)=rho_0*(1 + p_2/beta)
        drho_1(t)=0
        drho_2(t)=0
        dm_1(t)=0
        dm_2(t)=0
    end
    
    # let -----
    u_1 = dm_1/(rho_0*A_p)
    u_2 = dm_2/(rho_0*A_p)

    eqs = [
        D(x) ~ dx
        D(dx) ~ ddx
        D(rho_1) ~ drho_1
        D(rho_2) ~ drho_2
        +dm_1 ~ drho_1*(L+x) + rho_1*dx
        -dm_2 ~ drho_2*(L-x) - rho_2*dx
        rho_1 ~ rho_0*(1 + p_1/beta)
        rho_2 ~ rho_0*(1 + p_2/beta)
        m*ddx ~ (p_1 - p_2)*A - c*dx
        (p_s - p_1) ~ C*rho_0*u_fun(u_1)
        (p_2 - p_r) ~ C*rho_0*u_fun(u_2)
    ]

    return ODESystem(eqs, t, vars, pars; name)
end


# ---------------------------------------------------------------
# Here I build a linear system (u_fun = identity), this solves fine
# ---------------------------------------------------------------
@mtkbuild sys1 = System(;C=270/2)
prob1 = ODEProblem(sys1, [], (0, 0.01))
sol1 = solve(prob1) # Success


# ---------------------------------------------------------------
# Now I build a non-linear system (u_fun(x) = x^2), this can only 
# be solved with a non-adaptive ImplicitEuler using special nlsolve
# ---------------------------------------------------------------
@mtkbuild sys2 = System(x->x^2)
prob2 = ODEProblem(sys2, [], (0, 0.01))
sol2 = solve(prob2) #Unstable
sol2 = solve(prob2, FBDF()) # MaxIters
sol2 = solve(prob2, Rodas4()) #Unstable
sol2 = solve(prob2, Rodas4(); dt=1e-5, adaptive=false) #Unstable
sol2 = solve(prob2, ImplicitEuler(nlsolve=NLNewton(check_div=false, always_new=true, relax=4/10,max_iter=100))) # Success


# ---------------------------------------------------------------
# The only way I can get this problem to solve with a higher order
# solver is to use a hack where I take a small step with ImplicitEuler
# and then I can use Rodas4 in this case
# ---------------------------------------------------------------
dt = 1e-7
prob2 = ODEProblem(sys2, [], (0, dt))
u0sol = solve(prob2, ImplicitEuler(nlsolve=NLNewton(check_div=false, always_new=true, relax=4/10,max_iter=100)); dt, adaptive=false, initializealg=NoInit())
prob2 = ODEProblem(sys2, u0sol[2], (0, 0.01))
sol2 = solve(prob2, Rodas5P()) # Unstable
sol2 = solve(prob2, Rodas4()) # Success


# ---------------------------------------------------------------
# To prove the case that hacks shouldn't be necesary, the problem
# can be converted to Modelica and run.  This code shows how to do 
# this, this has already been run previously.  
# ---------------------------------------------------------------
# include("convert_to_modelica.jl")
# convert_to_modelica(sys2)

# using OMJulia
# omc = OMJulia.OMCSession()
# simflags="-override=startTime=0,stopTime=0.01,tolerance=1e-6,solver=dassl,outputFormat=csv"
# ModelicaSystem(omc, "modelica.mo", "MTK")
# simulate(omc;  resultfile = "modelica.csv", simflags)
# resultfile = joinpath(getWorkDirectory(omc), "modelica.csv")

resultfile = "modelica.csv"
data, header = readdlm(resultfile, ','; header=true);
i(var) = findfirst(vec(header) .== var)

# ---------------------------------------------------------------
# Comparing the results shows a near line on line match.  
# Therefore if Modelica can do it, so should DifferentialEquations.jl
# ---------------------------------------------------------------
# dx ----
plot(data[:,1], data[:,i("dx")]; label="modelica")
plot!(sol2; idxs=sys2.dx)
# plot!(sol1; idxs=sys1.dx) # linear result is nearly the same

# drho_1 ----
plot(data[:,1], data[:,i("drho_1")]; label="modelica")
plot!(sol2; idxs=sys2.drho_1)


# ---------------------------------------------------------------
# QUESTIONS
# [1] How to get a more robust solve from DifferentialEquations.jl when x^2?
# [2] How do I use the new MTK initialization to initialize rho_1 and rho_2 without the need for writing `rho_0*(1 + p/beta)` twice (once when definining the variable, once in the equations)
# ---------------------------------------------------------------