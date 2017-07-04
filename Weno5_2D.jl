#module Weno5_2D

using LaTeXStrings

const tmax = 0.1		# end of time integration

const NBnd = 3			# number of boundary cells

const Nx = 256 + 2*NBnd	# number of cells including boundaries
const Ny = 64  + 2*NBnd	# number of cells including boundaries

const iMin = 1 + NBnd	# grid loop x minimum without boundaries
const iMax = Nx - NBnd	# grid loop x maximum without boundaries
const jMin = 1 + NBnd	# grid loop y minimum without boundaries
const jMax = Ny - NBnd	# grid loop y maximum without boundaries

const xsize = 4
const ysize = 1

const dx = xsize/(Nx - 2*NBnd)
const dy = ysize/(Ny - 2*NBnd)

const gam = 5.0/3.0	# adiabatic index & friends
const gam0 = 1-gam
const gam1 = (gam-1)/2
const gam2 = (gam-2)/(gam-1)
const gamS = (gam-1)/gam

const courFac = 0.8		# Courant Factor

const eps = 1e-6 		# Jiang & Wu eq 2.3++ 

export WENO5_2D

function WENO5_2D()

    q = initial_conditions() #  q=[rho,vx,vy,vz,Bx,By,Bz,S,E]

    bxb, byb = face_centered_bfld(q)

    boundaries!(q)

    t = 0
    nstep = 0

    while t < tmax

        dt, vxmax, vymax = timestep(q)

	    @printf "%d : t = %g, dt = %g, vmax = %g, %g \n" nstep t dt vxmax vymax
    
        q, bxb, byb = classical_RK4_step(q, bxb, byb, dt)
        
		t += dt

		nstep += 1

    end # while

	return

end # WENO5_2D

function classical_RK4_step(q0::Array{Float64,3}, bxb0::Array{Float64,2}, 
                            byb0::Array{Float64,2}, dt::Float64)

    fsy = SharedArray{Float64}(Nx, Ny) * 0
    gsx = SharedArray{Float64}(Nx, Ny) * 0

#printq(q0,bxb0,byb0,fsy,gsx)
    # step 1
    q0_E = copy(q0[:,:,[1,2,3,4,5,6,7,9]])  # 8th component is E here
    dFx0_E, fsy_E, tmp = weno5_flux_difference_E(q0_E)
    
    q0_E = rotate_state(q0_E, "fwd")

    dFy0_E, tmp, gsx_E = weno5_flux_difference_E(q0_E)

    q0_E = rotate_state(q0_E, "bwd")                           
    dFy0_E = rotate_state(dFy0_E, "bwd")                           
    gsx_E = transpose(gsx_E)
    
    q1_E = q0_E - 1/2 * dt/dx * dFx0_E  - 1/2 * dt/dy * dFy0_E
 
    boundaries!(q1_E)
    q1_E, bxb1_E, byb1_E = fluxCT(q1_E, bxb0, byb0, fsy_E, gsx_E, dt, 1/2)
    boundaries!(q1_E)

printq(q1_E,bxb0,byb0,fsy_E,gsx_E)
@assert false

    q0_S = copy(q0[:,:,[1,2,3,4,5,6,7,8]])  # 8th component is S here
    dFx0_S, fsy_S, tmp = weno5_flux_difference_S(q0_S)

    q0_S = rotate_state(q0_S, "fwd") # x -> y

    dFy0_S, tmp, gsx_S = weno5_flux_difference_S(q0_S)
    
    q0_S = rotate_state(q0_S,"bwd")  # y -> x
    dFy0_S = rotate_state(dFy0_S,"bwd")
    gsx_S = transpose(gsx_S)

    q1_S = q0_S - 1/2 * dt/dx * dFx0_S - 1/2 * dt/dy * dFy0_S 

    boundaries!(q1_S)
    bxb1_S, byb1_S = fluxCT(q1_S, bxb0, byb0, fsy_S, gsx_S)
    boundaries!(q1_S)

printq(q1_S,bxb1_S,byb1_S,fsy_S,gsx_S)

    q1, fsy, gsx, idx = ES_Switch(q1_E, q1_S, fsy_S, gsx_S, fsy_E, gsx_E) 

    boundaries!(q1)
    bxb1, byb1 = fluxCT(q1, bxb0, byb0, fsy, gsx)
    boundaries!(q1)

printq(q1, bxb0,byb0, fsy,gsx)
@assert false

    # step 2
    # step 3
    # step 4

    #bxb4 = (-bxb0 + bxb1 + 2*bxb2 + bxb3)/3
    #byb4 = (-byb0 + byb1 + 2*byb2 + byb3)/3

    return q4, bxb4, byb4

end # classical_RK4_step

function fluxCT(q::Array{Float64,3}, bxb0::Array{Float64,2}, byb0::Array{Float64,2}, 
                fsy::Array{Float64,2}, gsx::Array{Float64,2}, dt::Float64, RK4prefac::Float64)

    for j = 2:Ny-1
        fsy[NBnd-1,j] = fsy[NBnd,j]
        fsy[Nx-NBnd+1,j] = fsy[Nx,j]
    end

    @inbounds @simd for i = 2:Nx-1
        gsx[i,2] = gsx[i,NBnd]
        gsx[i,Ny-NBnd+1] = gsx[i,Ny]
    end

    Ox = SharedArray{Float64}(Nx, Ny) .* 0

    for j = 2:Ny-1
        @inbounds @simd for i = 2:Nx-1
            Ox[i,j] = 0.5 * (gsx[i,j] + gsx[i+1,j] - fsy[i,j] - fsy[i,j+1])
        end
    end

    bxb1 = SharedArray{Float64}(Nx, Ny) .* 0
    byb1 = SharedArray{Float64}(Nx, Ny) .* 0
    q1 = copy(q)

    for j = 2:Ny-1
        @inbounds @simd for i = 2:Nx-1
            bxb1[i,j] = bxb0[i,j] - RK4prefac*dt/dy * (Ox[i,j] - Ox[i,j-1])
            byb1[i,j] = byb0[i,j] + RK4prefac*dt/dx * (Ox[i,j] - Ox[i-1,j])
        end
    end

    #  interpolate face centered bfld to centre, 4th order

    for j = NBnd+1:Ny-2
        @inbounds @simd for i = NBnd+1:Nx-2
            q1[i,j,5] = (-bxb1[i-2,j] + 9*bxb1[i-1,j] + 9*bxb1[i,j]- bxb1[i+1,j])/16
            q1[i,j,6] = (-byb1[i,j-2] + 9*byb1[i,j-1] + 9*byb1[i,j]- byb1[i,j+1])/16
        end
    end

    return q1, bxb1, byb1
end # fluxCT

# Entropy (S) code

function weno5_flux_difference_S(q_2D::Array{Float64,3})

    const Nqx = size(q_2D,1) # q might be rotated
    const Nqy = size(q_2D,2)

    dq = SharedArray{Float64}(Nqx, Nqy, 8) * 0
    bsy = SharedArray{Float64}(Nqx, Nqy) * 0
    bsz = SharedArray{Float64}(Nqx, Nqy) * 0

    #@sync @parallel 
    for j = 1:Nqy  # 1D along x for fixed y

        q = q_2D[:,j,:]

        u = compute_primitive_variables_S(q) # [rho,vx,vy,vz,Bx,By,Bz,P(S)]  

        a = compute_eigenvalues(u)

	    F = compute_fluxes_S(q,u)

	    L, R = compute_eigenvectors_S(q,u,F)
	
        if (j == 4) 
            @printf "S : j = %g \n" j
        end

	    dF = weno5_interpolation(q,a,F,L,R,j)

       for i = NBnd+1:Nqx-NBnd # only data domain
    		dq[i,j,1] = dF[i,1] - dF[i-1,1]
    		dq[i,j,2] = dF[i,2] - dF[i-1,2]
    		dq[i,j,3] = dF[i,3] - dF[i-1,3]
    		dq[i,j,4] = dF[i,4] - dF[i-1,4]
    		dq[i,j,5] = 0                   # fluxct scheme later
    		dq[i,j,6] = dF[i,5] - dF[i-1,5]
    		dq[i,j,7] = dF[i,6] - dF[i-1,6]
	    	dq[i,j,8] = dF[i,7] - dF[i-1,7]
	    end

        for i = NBnd:Nqx-NBnd
            bsy[i,j] = dF[i,5] + 0.5 *(u[i,5]*u[i,3] + u[i+1,5]*u[i+1,3])
            bsz[i,j] = dF[i,6] + 0.5 *(u[i,5]*u[i,4] + u[i+1,5]*u[i+1,4])
        end
    end

    return dq, bsy, bsz
end

function compute_eigenvectors_S(q::Array{Float64,2}, u::Array{Float64,2}, 
								F::Array{Float64,2}) # Roe solver
    N = size(q, 1)

	L = zeros(Float64, N,7,7) # left hand eigenvectors
	R = zeros(Float64, N,7,7) # right hand eigenvectors

	for i=2:N-1
		
		drho = abs(u[i,1] - u[i+1,1]) # to cell boundary

		if drho <= 1e-12
			rho = 0.5 * (u[i,1] + u[i+1,1])
		else 
			rho = abs(gam0*drho/(u[i+1,1]^gam0 - u[i,1]^gam0))^(1/gam)
		end

		vx = 0.5 * (u[i,2] + u[i+1,2])
		vy = 0.5 * (u[i,3] + u[i+1,3])
		vz = 0.5 * (u[i,4] + u[i+1,4])

		Bx = 0.5 * (u[i,5] + u[i+1,5])
		By = 0.5 * (u[i,6] + u[i+1,6])
		Bz = 0.5 * (u[i,7] + u[i+1,7])

		pg = 0.5 * (u[i,8] + u[i+1,8])
		S = pg/rho^(gam-1) 

		v2 = vx^2 + vy^2 + vz^2
		B2 = Bx^2 + By^2 + Bz^2

		cs2 = max(0, gam*abs(pg/rho))
		cs = sqrt(cs2)
		bbn2 = B2/rho
		bnx2 = Bx^2/rho

		root = max(0, (bbn2+cs2)^2 - 4*bnx2*cs2)
		root = sqrt(root)

		lf = sqrt(max(0, (bbn2+cs2+root)/2)) 	# fast mode
		la = sqrt(max(0, bnx2))					# alven mode
		ls = sqrt(max(0, (bbn2+cs2-root)/2))	# slow mode

		# resolve degeneracies

		Bt2 = By^2 + Bz^2
		sgnBx = sign(Bx) # -1, 0, 1

        if sgnBx == 0
            sgnBx = 1
        end

		bty = 1/sqrt(2)
		btz = 1/sqrt(2)

		if Bt2 > 1e-30
			bty = By/sqrt(Bt2)
			btz = Bz/sqrt(Bt2)
		end

		af = 1
		as = 1

		dl2 = lf^2 - ls^2

		if dl2 >= 1e-30
			af = sqrt(max(0,cs2 - ls^2))/sqrt(dl2)
			as = sqrt(max(0,lf^2 - cs2))/sqrt(dl2)
		end

		# eigenvectors

		sqrt_rho = sqrt(rho)

		L[i,1,1] =  af*(gamS*cs2+lf*vx) - as*ls*(bty*vy+btz*vz)*sgnBx
        L[i,1,2] = -af*lf
        L[i,1,3] =  as*ls*bty*sgnBx
        L[i,1,4] =  as*ls*btz*sgnBx
        L[i,1,5] =  cs*as*bty*sqrt_rho
        L[i,1,6] =  cs*as*btz*sqrt_rho
        L[i,1,7] =  af*cs2*rho/(gam*S)
            
        L[i,2,1] =  btz*vy-bty*vz
        L[i,2,2] =  0
        L[i,2,3] = -btz
        L[i,2,4] =  bty
        L[i,2,5] = -btz*sgnBx*sqrt_rho
        L[i,2,6] =  bty*sgnBx*sqrt_rho
        L[i,2,7] =  0
            
        L[i,3,1] =  as*(gamS*cs2+ls*vx) + af*lf*(bty*vy+btz*vz)*sgnBx
        L[i,3,2] = -as*ls
        L[i,3,3] = -af*lf*bty*sgnBx
        L[i,3,4] = -af*lf*btz*sgnBx
        L[i,3,5] = -cs*af*bty*sqrt_rho
        L[i,3,6] = -cs*af*btz*sqrt_rho
        L[i,3,7] =  as*cs2*rho/(gam*S)
            
        L[i,4,1] =  1/gam
        L[i,4,2] =  0
        L[i,4,3] =  0
        L[i,4,4] =  0
        L[i,4,5] =  0
        L[i,4,6] =  0
        L[i,4,7] = -rho/(gam*S)
            
        L[i,5,1] =  as*(gamS*cs2-ls*vx) - af*lf*(bty*vy+btz*vz)*sgnBx
        L[i,5,2] =  as*ls
        L[i,5,3] =  af*lf*bty*sgnBx
        L[i,5,4] =  af*lf*btz*sgnBx
        L[i,5,5] = -cs*af*bty*sqrt_rho
        L[i,5,6] = -cs*af*btz*sqrt_rho
        L[i,5,7] =  as*cs2*rho/(gam*S)
            
        L[i,6,1] =  btz*vy-bty*vz
        L[i,6,2] =  0
        L[i,6,3] = -btz
        L[i,6,4] =  bty
        L[i,6,5] =  btz*sgnBx*sqrt_rho
        L[i,6,6] = -bty*sgnBx*sqrt_rho
        L[i,6,7] =  0
            
        L[i,7,1] =  af*(gamS*cs2-lf*vx) + as*ls*(bty*vy+btz*vz)*sgnBx
        L[i,7,2] =  af*lf
        L[i,7,3] = -as*ls*bty*sgnBx
        L[i,7,4] = -as*ls*btz*sgnBx
        L[i,7,5] =  cs*as*bty*sqrt_rho
        L[i,7,6] =  cs*as*btz*sqrt_rho
        L[i,7,7] =  af*cs2*rho/(gam*S)

        for m=1:7
            L[i,1,m] *= 0.5/cs2
            L[i,2,m] *= 0.5
            L[i,3,m] *= 0.5/cs2 # 4 missing ?
            L[i,5,m] *= 0.5/cs2
            L[i,6,m] *= 0.5
        	L[i,7,m] *= 0.5/cs2
        end

		R[i,1,1] = af
        R[i,2,1] = af*(vx-lf)
        R[i,3,1] = af*vy + as*ls*bty*sgnBx
        R[i,4,1] = af*vz + as*ls*btz*sgnBx
        R[i,5,1] = cs*as*bty/sqrt_rho
        R[i,6,1] = cs*as*btz/sqrt_rho
        R[i,7,1] = af*S/rho
            
        R[i,1,2] =  0
        R[i,2,2] =  0
        R[i,3,2] = -btz
        R[i,4,2] =  bty
        R[i,5,2] = -btz*sgnBx/sqrt_rho
        R[i,6,2] =  bty*sgnBx/sqrt_rho
        R[i,7,2] =  0
            
        R[i,1,3] =  as
        R[i,2,3] =  as*(vx-ls)
        R[i,3,3] =  as*vy - af*lf*bty*sgnBx
        R[i,4,3] =  as*vz - af*lf*btz*sgnBx
        R[i,5,3] = -cs*af*bty/sqrt_rho
        R[i,6,3] = -cs*af*btz/sqrt_rho
        R[i,7,3] =  as*S/rho
            
        R[i,1,4] =  1
        R[i,2,4] =  vx
        R[i,3,4] =  vy
        R[i,4,4] =  vz
        R[i,5,4] =  0
        R[i,6,4] =  0
        R[i,7,4] =  gam0*S/rho
            
        R[i,1,5] =  as
        R[i,2,5] =  as*(vx+ls)
        R[i,3,5] =  as*vy + af*lf*bty*sgnBx
        R[i,4,5] =  as*vz + af*lf*btz*sgnBx
        R[i,5,5] = -cs*af*bty/sqrt_rho
        R[i,6,5] = -cs*af*btz/sqrt_rho
        R[i,7,5] =  as*S/rho
            
        R[i,1,6] =  0
        R[i,2,6] =  0
        R[i,3,6] = -btz
        R[i,4,6] =  bty
        R[i,5,6] =  btz*sgnBx/sqrt_rho
        R[i,6,6] = -bty*sgnBx/sqrt_rho
        R[i,7,6] =  0
            
        R[i,1,7] = af
        R[i,2,7] = af*(vx+lf)
        R[i,3,7] = af*vy - as*ls*bty*sgnBx
        R[i,4,7] = af*vz - as*ls*btz*sgnBx
        R[i,5,7] = cs*as*bty/sqrt_rho
        R[i,6,7] = cs*as*btz/sqrt_rho
        R[i,7,7] = af*S/rho

		sgnBt = sign(Bz) # enforce continuity

		if By != 0
			sgnBt = sign(Bx)
		end

        if sgnBt == 0
            sgnBt = 1
        end

		if cs >= la
			for m=1:7
				L[i,3,m] *= sgnBt 
				L[i,5,m] *= sgnBt 
				R[i,m,3] *= sgnBt 
				R[i,m,5] *= sgnBt 
			end
		else
			for m=1:7
				L[i,1,m] *= sgnBt 
				L[i,7,m] *= sgnBt 
				R[i,m,1] *= sgnBt 
				R[i,m,7] *= sgnBt 
			end
		end
	end  # for i

	return L, R
end # compute_eigenvectors_S


function compute_fluxes_S(q::Array{Float64,2}, u::Array{Float64,2})
	
    const N = size(u,1)

	F = zeros(Float64, N, 7)

    @inbounds @simd for i = 1:N

        pt = u[i,8] + 0.5*(u[i,5]^2+u[i,6]^2+u[i,7]^2) 

        F[i,1] = u[i,1]*u[i,2] 				    # rho * vx
        F[i,2] = q[i,2]*u[i,2] + pt - u[i,5]^2 	# mvx*vx + Ptot - Bx^2
        F[i,3] = q[i,3]*u[i,2] - u[i,5]*u[i,6]  # mvy*vx - Bx*By
        F[i,4] = q[i,4]*u[i,2] - u[i,5]*u[i,7] 	# mvy*vx - Bx*Bz
        F[i,5] = u[i,6]*u[i,2] - u[i,5]*u[i,3] 	# By*vx - Bx*vy
        F[i,6] = u[i,7]*u[i,2] - u[i,5]*u[i,4]  # Bz*vx - Bx*vz
        F[i,7] = q[i,8]*u[i,2]	               	# S*vx
    end

	return F # cell centered fluxes
end


function compute_primitive_variables_S(q::Array{Float64,2})

	u = copy(q)  # = [rho,Mx,My,Mz,Bx,By,Bz,S]

    @inbounds @simd for i = 1:size(u,1)

        u[i,2] /= u[i,1] # vx = Mx/rho
        u[i,3] /= u[i,1] # vy
        u[i,4] /= u[i,1] # vz
        u[i,8] *= u[i,1]^(gam-1)# Pressure from S
    end

	return u # = [rho,vx,vy,vz,Bx,By,Bz,P(S)]; J&W eq. 2.23
end

# Energy (E) - code

function weno5_flux_difference_E(q_2D::Array{Float64,3})

    const Nqx = size(q_2D,1) # q might be rotated
    const Nqy = size(q_2D,2)

    dq = SharedArray{Float64}(Nqx, Nqy, 8) * 0
    bsy = SharedArray{Float64}(Nqx, Nqy) * 0
    bsz = SharedArray{Float64}(Nqx, Nqy) * 0

    #@sync @parallel 
    for j = 1:Nqy  # 1D along x for fixed y

        q = q_2D[:,j,:]

        u = compute_primitive_variables_E(q) # [rho,vx,vy,vz,Bx,By,Bz,P(S)]  

        a = compute_eigenvalues(u)

	    F = compute_fluxes_E(q,u)

        if (j == 4) 
            @printf "E : j = %g \n" j
        end

	    L, R = compute_eigenvectors_E(q,u,F, j)
	
	    dF = weno5_interpolation(q,a,F,L,R,j)

       for i = NBnd+1:Nqx-NBnd
    		dq[i,j,1] = dF[i,1] - dF[i-1,1]
    		dq[i,j,2] = dF[i,2] - dF[i-1,2]
    		dq[i,j,3] = dF[i,3] - dF[i-1,3]
    		dq[i,j,4] = dF[i,4] - dF[i-1,4]
    		dq[i,j,5] = 0                   # fluxct scheme later
    		dq[i,j,6] = dF[i,5] - dF[i-1,5]
    		dq[i,j,7] = dF[i,6] - dF[i-1,6]
	    	dq[i,j,8] = dF[i,7] - dF[i-1,7]
	    end

        for i = NBnd:Nqx-NBnd
            bsy[i,j] = dF[i,5] + 0.5 *(u[i,5]*u[i,3] + u[i+1,5]*u[i+1,3])
            bsz[i,j] = dF[i,6] + 0.5 *(u[i,5]*u[i,4] + u[i+1,5]*u[i+1,4])
        end
    end
    @printf "%g %g  \n" bsy[2,1]  bsy[1,2]
    
    return dq, bsy, bsz
end


function compute_eigenvectors_E(q::Array{Float64,2}, u::Array{Float64,2}, 
								F::Array{Float64,2},j) # Roe solver
    const N = size(q,1)

	L = zeros(Float64, N,7,7) # left hand eigenvectors
	R = zeros(Float64, N,7,7) # right hand eigenvectors

	for i=2:N-1
		
		rho = 0.5 * (u[i,1] + u[i+1,1]) # to cell boundary

		vx = 0.5 * (u[i,2] + u[i+1,2])
		vy = 0.5 * (u[i,3] + u[i+1,3])
		vz = 0.5 * (u[i,4] + u[i+1,4])
		
        Bx = 0.5 * (u[i,5] + u[i+1,5])
		By = 0.5 * (u[i,6] + u[i+1,6])
		Bz = 0.5 * (u[i,7] + u[i+1,7])
		
        E = 0.5 * (q[i,8] + q[i+1,8]) # q NOT u

		v2 = vx^2 + vy^2 + vz^2
		B2 = Bx^2 + By^2 + Bz^2

		pg = (gam-1) * (E - 0.5 * (rho*v2 + B2) )

		cs2 = max(0, gam*abs(pg/rho))
		cs = sqrt(cs2)
		bbn2 = B2/rho
		bnx2 = Bx^2/rho

		root = max(0, (bbn2+cs2)^2 - 4*bnx2*cs2)
		root = sqrt(root)

		lf = sqrt(max(0, (bbn2+cs2+root)/2)) 	# fast mode
		la = sqrt(max(0, bnx2))					# alven mode
		ls = sqrt(max(0, (bbn2+cs2-root)/2))	# slow mode

		# resolve degeneracies

		Bt2 = By^2 + Bz^2
		sgnBx = sign(Bx) # -1, 0, 1

        if sgnBx == 0
            sgnBx = 1
        end

		bty = 1/sqrt(2)
		btz = 1/sqrt(2)

		if Bt2 >= 1e-30
			bty = By/sqrt(Bt2)
			btz = Bz/sqrt(Bt2)
		end

		af = 1
		as = 1

		dl2 = lf^2 - ls^2

		if dl2 >= 1e-30
			af = sqrt(max(0,cs2 - ls^2))/sqrt(dl2)
			as = sqrt(max(0,lf^2 - cs2))/sqrt(dl2)
		end

		# eigenvectors E version

		sqrt_rho = sqrt(rho)

		L[i,1,1] = af*(gam1*v2 + lf*vx) - as*ls*(bty*vy + btz*vz)*sgnBx
        L[i,1,2] = af*(gam0*vx - lf)
        L[i,1,3] = gam0*af*vy + as*ls*bty*sgnBx
        L[i,1,4] = gam0*af*vz + as*ls*btz*sgnBx
        L[i,1,5] = gam0*af*By + cs*as*bty*sqrt_rho
        L[i,1,6] = gam0*af*Bz + cs*as*btz*sqrt_rho
        L[i,1,7] = -gam0*af
                                                                   
        L[i,2,1] = btz*vy - bty*vz
        L[i,2,2] = 0
        L[i,2,3] = -btz
        L[i,2,4] = bty
        L[i,2,5] = -btz*sgnBx*sqrt_rho
        L[i,2,6] = bty*sgnBx*sqrt_rho
        L[i,2,7] = 0

        L[i,3,1] = as*(gam1*v2 + ls*vx) + af*lf*(bty*vy + btz*vz)*sgnBx
        L[i,3,2] = gam0*as*vx - as*ls
        L[i,3,3] = gam0*as*vy - af*lf*bty*sgnBx
        L[i,3,4] = gam0*as*vz - af*lf*btz*sgnBx
        L[i,3,5] = gam0*as*By - cs*af*bty*sqrt_rho 
        L[i,3,6] = gam0*as*Bz - cs*af*btz*sqrt_rho 
        L[i,3,7] = -gam0*as
                                                                   
        L[i,4,1] = -cs2/gam0 - 0.5*v2
        L[i,4,2] = vx
        L[i,4,3] = vy
        L[i,4,4] = vz
        L[i,4,5] = By
        L[i,4,6] = Bz
        L[i,4,7] = -1
                                                                   
        L[i,5,1] = as*(gam1*v2 - ls*vx) - af*lf*(bty*vy + btz*vz)*sgnBx
        L[i,5,2] = as*(gam0*vx+ls)
        L[i,5,3] = gam0*as*vy + af*lf*bty*sgnBx
        L[i,5,4] = gam0*as*vz + af*lf*btz*sgnBx
        L[i,5,5] = gam0*as*By - cs*af*bty*sqrt_rho 
        L[i,5,6] = gam0*as*Bz - cs*af*btz*sqrt_rho 
        L[i,5,7] = -gam0*as
                                                                   
        L[i,6,1] = btz*vy - bty*vz
        L[i,6,2] = 0
        L[i,6,3] = -btz
        L[i,6,4] = bty
        L[i,6,5] = btz*sgnBx*sqrt_rho
        L[i,6,6] = -bty*sgnBx*sqrt_rho
        L[i,6,7] = 0
                                                                   
        L[i,7,1] = af*(gam1*v2 - lf*vx) + as*ls*(bty*vy + btz*vz)*sgnBx
        L[i,7,2] = af*(gam0*vx + lf)
        L[i,7,3] = gam0*af*vy - as*ls*bty*sgnBx
        L[i,7,4] = gam0*af*vz - as*ls*btz*sgnBx
        L[i,7,5] = gam0*af*By + cs*as*bty*sqrt_rho
        L[i,7,6] = gam0*af*Bz + cs*as*btz*sqrt_rho
        L[i,7,7] = -gam0*af

        for m=1:7
            L[i,1,m] *= 0.5/cs2
            L[i,2,m] *= 0.5
            L[i,3,m] *= 0.5/cs2 
			L[i,4,m] *= -gam0/cs2
            L[i,5,m] *= 0.5/cs2
            L[i,6,m] *= 0.5
        	L[i,7,m] *= 0.5/cs2
        end

		R[i,1,1] = af
        R[i,2,1] = af*(vx - lf)
        R[i,3,1] = af*vy + as*ls*bty*sgnBx
        R[i,4,1] = af*vz + as*ls*btz*sgnBx
        R[i,5,1] = cs*as*bty/sqrt_rho
        R[i,6,1] = cs*as*btz/sqrt_rho
        R[i,7,1] = af*(lf^2 - lf*vx + 0.5*v2 - gam2*cs2) + as*ls*(bty*vy + btz*vz)*sgnBx 
           
        R[i,1,2] = 0
        R[i,2,2] = 0
        R[i,3,2] = -btz
        R[i,4,2] = bty
        R[i,5,2] = -btz*sgnBx/sqrt_rho
        R[i,6,2] = bty*sgnBx/sqrt_rho
        R[i,7,2] = bty*vz - btz*vy
                                                      
        R[i,1,3] = as
        R[i,2,3] = as*(vx-ls)
        R[i,3,3] = as*vy - af*lf*bty*sgnBx
        R[i,4,3] = as*vz - af*lf*btz*sgnBx
        R[i,5,3] = -cs*af*bty/sqrt_rho
        R[i,6,3] = -cs*af*btz/sqrt_rho
        R[i,7,3] = as*(ls^2 - ls*vx + 0.5*v2 - gam2*cs2) - af*lf*(bty*vy + btz*vz)*sgnBx
            
        R[i,1,4] = 1
        R[i,2,4] = vx
        R[i,3,4] = vy
        R[i,4,4] = vz
        R[i,5,4] = 0
        R[i,6,4] = 0
        R[i,7,4] = 0.5*v2
                                                       
        R[i,1,5] =  as
        R[i,2,5] =  as*(vx + ls)
        R[i,3,5] =  as*vy + af*lf*bty*sgnBx
        R[i,4,5] =  as*vz + af*lf*btz*sgnBx
        R[i,5,5] = -cs*af*bty/sqrt_rho
        R[i,6,5] = -cs*af*btz/sqrt_rho
        R[i,7,5] =  as*(ls^2 + ls*vx + 0.5*v2 - gam2*cs2) + af*lf*(bty*vy + btz*vz)*sgnBx
            
        R[i,1,6] =  0
        R[i,2,6] =  0
        R[i,3,6] = -btz
        R[i,4,6] =  bty
        R[i,5,6] =  btz*sgnBx/sqrt_rho
        R[i,6,6] = -bty*sgnBx/sqrt_rho
        R[i,7,6] =  bty*vz - btz*vy
                                                      
        R[i,1,7] = af
        R[i,2,7] = af*(vx + lf)
        R[i,3,7] = af*vy - as*ls*bty*sgnBx
        R[i,4,7] = af*vz - as*ls*btz*sgnBx
        R[i,5,7] = cs*as*bty/sqrt_rho
        R[i,6,7] = cs*as*btz/sqrt_rho
        R[i,7,7] = af*(lf^2 + lf*vx + 0.5*v2 - gam2*cs2) - as*ls*(bty*vy + btz*vz)*sgnBx

		sgnBt = sign(Bz) # enforce continuity

		if By != 0
			sgnBt = sign(Bx)
		end

        if sgnBt == 0
            sgnBt = 1
        end

		if cs >= la
			for m=1:7
				L[i,3,m] *= sgnBt 
				L[i,5,m] *= sgnBt 
				R[i,m,3] *= sgnBt 
				R[i,m,5] *= sgnBt 
			end
		else
			for m=1:7
				L[i,1,m] *= sgnBt 
				L[i,7,m] *= sgnBt 
				R[i,m,1] *= sgnBt 
				R[i,m,7] *= sgnBt 
			end
		end
	end  # for i

	return L, R
end # compute_eigenvectors_E

function compute_fluxes_E(q::Array{Float64,2}, u::Array{Float64,2})
	
    const N = size(u,1)

	F = zeros(Float64, N, 7)

    @inbounds @simd for i = 1:N
	    pt = u[i,8] + (u[i,5]^2+u[i,6]^2+u[i,7]^2)/2 # total pressure from E
    	vB = u[i,2]*u[i,5] + u[i,3]*u[i,6] + u[i,4]*u[i,7] # v*B

        F[i,1] = u[i,1]*u[i,2] 					    # rho * vx
	    F[i,2] = q[i,2]*u[i,2] + pt - u[i,5]^2	    # mvx*vx + Ptot - Bx^2
        F[i,3] = q[i,3]*u[i,2] - u[i,5]*u[i,6] 	    # mvy*vx - Bx*By
        F[i,4] = q[i,4]*u[i,2] - u[i,5]*u[i,7] 	    # mvy*vx - Bx*Bz
        F[i,5] = u[i,6]*u[i,2] - u[i,5]*u[i,3] 	    # By*vx - Bx*vy
        F[i,6] = u[i,7]*u[i,2] - u[i,5]*u[i,4]   	# Bz*vx - Bx*vz
        F[i,7] = (q[i,8]+pt)*u[i,2] - u[i,5]*vB	    # (E+Ptot)*vx - Bx * (v*B)
    end

	return F
end
function compute_primitive_variables_E(q::Array{Float64,2})

	u = copy(q) # = [rho,Mx,My,Mz,Bx,By,Bz,E]
	
    @inbounds @simd for i = 1:size(u,1)
	    u[i,2] /= u[i,1] # vx = Mx/rho
	    u[i,3] /= u[i,1] # vy
    	u[i,4] /= u[i,1] # vz

	    v2 = u[i,2]^2 + u[i,3]^2 + u[i,4]^2
	    B2 = u[i,5]^2 + u[i,6]^2 + u[i,7]^2

	    u[i,8] -= 0.5 * (u[i,1]*v2 + B2) # Pressure from E
	    u[i,8] *= (gam-1)
    end

	return u # = [rho,vx,vy,vz,Bx,By,Bz,P(E)] ; B&W eq. 2.23
end

function compute_eigenvalues(u::Array{Float64,2})

    N = size(u, 1)

	B2  = u[:,5].^2 + u[:,6].^2 + u[:,7].^2
	vdB = u[:,2].*u[:,5] + u[:,3].*u[:,6] + u[:,4].*u[:,7]

	cs2 = gam * abs.(u[:,8]./u[:,1])
	bad = find(cs2 .< 0)
	cs2[bad] = 0

	bbn2 = B2./u[:,1]
	bnx2 = u[:,5].^2./u[:,1]

	root = safe_sqrt((bbn2+cs2).^2 - 4*bnx2.*cs2)

	lf = safe_sqrt((bbn2+cs2+root)/2)
	la = safe_sqrt(bnx2)
	ls = safe_sqrt((bbn2+cs2-root)/2)

	a = zeros(Float64, N, 7) # eigenvalues cell center

    @inbounds @simd for i=1:N 
        a[i,1] = u[i,2] - lf[i] # u is rotated, integration is along 2 direction
    	a[i,2] = u[i,2] - la[i]
	    a[i,3] = u[i,2] - ls[i]
	    a[i,4] = u[i,2]
    	a[i,5] = u[i,2] + ls[i]
    	a[i,6] = u[i,2] + la[i]
    	a[i,7] = u[i,2] + lf[i]
    end

	return a #  J&W 2.27+1

end

function face_centered_bfld(q::Array{Float64,3})

    bxb = SharedArray{Float64}(Nx, Ny) * 0 # needed on 2:N-2 only
    byb = SharedArray{Float64}(Nx, Ny) * 0

    @sync @parallel for j = 2:Ny-2 # fourth order interpolation
        @inbounds @simd for i = 2:Nx-2
           bxb[i,j] = (-q[i-1,j,5] + 9*q[i,j,5] + 9*q[i+1,j,5] - q[i+2,j,5])/16
           byb[i,j] = (-q[i,j-1,6] + 9*q[i,j,6] + 9*q[i,j+1,6] - q[i,j+2,6])/16
        end
    end

    return bxb, byb
end

function boundaries!(q::Array{Float64,3})

    for j = 1:Ny
        q[1,j,:] = q[NBnd+1,j,:]
        q[2,j,:] = q[NBnd+1,j,:]
        q[3,j,:] = q[NBnd+1,j,:]
        q[Nx,j,:] = q[Nx-NBnd,j,:]
        q[Nx-1,j,:] = q[Nx-NBnd,j,:]
        q[Nx-2,j,:] = q[Nx-NBnd,j,:]
    end
    
    @inbounds @simd for i = 1:Nx
        q[i, 1,:] = q[i,NBnd+1,:]
        q[i, 2,:] = q[i,NBnd+1,:]
        q[i, 3,:] = q[i,NBnd+1,:]
        q[i, Ny,:] = q[i,Ny-NBnd,:]
        q[i, Ny-1,:] = q[i,Ny-NBnd,:]
        q[i, Ny-2,:] = q[i,Ny-NBnd,:]
    end

    return
end

function ES_Switch(q_E::Array{Float64,3}, q_S::Array{Float64,3}, fsy_S::Array{Float64,2}, 
                   gsx_S::Array{Float64,2}, fsy_E::Array{Float64,2}, gsx_E::Array{Float64,2})
	
	q_SE = copy(q_E)
    q_SE[:,:,8] = E2S(q_E) 		# convert q(E) to q(S(E))

printq(q_SE, fsy_S,gsx_S, fsy_S,gsx_S)
@assert false

	dS = abs.(q_SE[:,:,8] - q_S[:,:,8])
	
    bad = find(dS .>= 1e-5)
    
    println(size(dS), size(bad))

    q = SharedArray{Float64}(Nx,Ny, 9) .* 0
	q[:,:,1:8] = q_S			# use q(S) by default

    fsy = copy(fsy_S)
    gsx = copy(gsx_S)

    #@sync @parallel
    for j = 2:Ny
        for i = 2:Nx
            if dS[i,j] >= 1e-5
               # println("$i $j $(q_SE[i,j,8]) $(q_S[i,j,8]) ")
                q[i,j,1:8] = q_SE[i,j,1:8]

                fsy[i,j] = fsy_E[i,j]
                fsy[i-1,j] = fsy_E[i-1,j]
                    
                gsx[i,j] = gsx_E[i,j]       
                gsx[i,j-1] = gsx_E[i,j-1] # need neighbouring component
            end
        end
    end

    q[:,:,9] = S2E(q) # save E(S) in the 9th component

	return q, fsy, gsx, bad
end

function E2S(qE::Array{Float64,3})

	E = qE[:,:,8]

	rho = qE[:,:,1]
    mom2 = qE[:,:,2].^2 + qE[:,:,3].^2 + qE[:,:,4].^2
    B2 = qE[:,:,5].^2 + qE[:,:,6].^2 + qE[:,:,7].^2
	
	S = (E - 0.5*mom2./rho - B2/2)*(gam-1)./rho.^(gam-1)
	
	return S  # Ryu+ 1993, eq. 2.3 + 1
end

function S2E(qS::Array{Float64,3})
	
	S = qS[:,:,8]
	rho = qS[:,:,1]
	mom2 = qS[:,:,2].^2 + qS[:,:,3].^2 + qS[:,:,4].^2
	B2 = qS[:,:,5].^2 + qS[:,:,6].^2 + qS[:,:,7].^2

	E = rho.^(gam-1).*S/(gam-1) + B2/2 + 0.5.*mom2./rho

	return E # Ryu+ 1993, eq. 2.3+1
end

function weno5_interpolation(q::Array{Float64,2}, a::Array{Float64,2},
							 F::Array{Float64,2}, L::Array{Float64,3},
							 R::Array{Float64,3},j)
    N = size(q,1)

	dF = zeros(Float64, N, 7)

	for i = NBnd:N-NBnd
		
    	Fs = zeros(Float64, 7)
	    Fsk = zeros(Float64, 6)
    	qsk = zeros(Float64, 6)
	    dFsk = zeros(Float64, 5)
    	dqsk = zeros(Float64, 5)

		for m=1:7

			amax = max(abs(a[i,m]),abs(a[i+1,m])) # J&W eq 2.10

			for ks=1:6 # stencil i-2 -> i+3 : 5th order

				Fsk[ks] = L[i,m,1]*F[i-3+ks,1] + L[i,m,2]*F[i-3+ks,2] +
                     	  L[i,m,3]*F[i-3+ks,3] + L[i,m,4]*F[i-3+ks,4] +
                     	  L[i,m,5]*F[i-3+ks,5] + L[i,m,6]*F[i-3+ks,6] +
                     	  L[i,m,7]*F[i-3+ks,7]                     
                                                                   
            	qsk[ks] = L[i,m,1]*q[i-3+ks,1] + L[i,m,2]*q[i-3+ks,2] +
                     	  L[i,m,3]*q[i-3+ks,3] + L[i,m,4]*q[i-3+ks,4] +
                     	  L[i,m,5]*q[i-3+ks,6] + L[i,m,6]*q[i-3+ks,7] +
                     	  L[i,m,7]*q[i-3+ks,8]
			end # ks

			for ks=1:5
				dFsk[ks] = Fsk[ks+1] - Fsk[ks]
				dqsk[ks] = qsk[ks+1] - qsk[ks]
			end

			first = (-Fsk[2]+7*Fsk[3]+7*Fsk[4]-Fsk[5]) / 12 # J&W eq 2.11

			aterm = (dFsk[1] + amax*dqsk[1]) / 2 # Lax-Friedrichs J&W eq. 2.10 & 2.16+
            bterm = (dFsk[2] + amax*dqsk[2]) / 2
            cterm = (dFsk[3] + amax*dqsk[3]) / 2
            dterm = (dFsk[4] + amax*dqsk[4]) / 2

            IS0 = 13*(aterm-bterm)^2 + 3*(aterm-3*bterm)^2
            IS1 = 13*(bterm-cterm)^2 + 3*(bterm+cterm)^2
            IS2 = 13*(cterm-dterm)^2 + 3*(3*cterm-dterm)^2

            alpha0 = 1/(eps+IS0)^2
            alpha1 = 6/(eps+IS1)^2
            alpha2 = 3/(eps+IS2)^2

            omega0 = alpha0/(alpha0+alpha1+alpha2)
            omega2 = alpha2/(alpha0+alpha1+alpha2)

            second = omega0*(aterm - 2*bterm + cterm)/3 + # phi_N(f+), J&W eq 2.3 + 1
                  	(omega2-0.5)*(bterm - 2*cterm + dterm)/6

            aterm = (dFsk[5] - amax*dqsk[5]) / 2 # Lax-Friedrichs J&W eq. 2.10 & 2.16+
            bterm = (dFsk[4] - amax*dqsk[4]) / 2
            cterm = (dFsk[3] - amax*dqsk[3]) / 2  
            dterm = (dFsk[2] - amax*dqsk[2]) / 2

            IS0 = 13*(aterm-bterm)^2 + 3*(aterm - 3*bterm)^2
            IS1 = 13*(bterm-cterm)^2 + 3*(bterm + cterm)^2
            IS2 = 13*(cterm-dterm)^2 + 3*(3*cterm - dterm)^2

            alpha0 = 1/(eps + IS0)^2
            alpha1 = 6/(eps + IS1)^2
            alpha2 = 3/(eps + IS2)^2

            omega0 = alpha0/(alpha0 + alpha1 + alpha2)
            omega2 = alpha2/(alpha0 + alpha1 + alpha2)

            third  = omega0*(aterm - 2*bterm + cterm) / 3 +	# phi_N(f-)
                    (omega2 - 0.5)*(bterm - 2*cterm + dterm) / 6

            Fs[m] = first - second + third # J&W eq. 2.16 + 1
		end # m
	
		@inbounds @simd for m = 1:7
			
			dF[i,m] = Fs[1]*R[i,m,1] + Fs[2]*R[i,m,2] + # J&W eq. 2.17
                   	  Fs[3]*R[i,m,3] + Fs[4]*R[i,m,4] +
                      Fs[5]*R[i,m,5] + Fs[6]*R[i,m,6] +
                      Fs[7]*R[i,m,7] 
		end
	end # i

	return dF
end # weno5_interpolation()

function rotate_state(q::Array{Float64,3}, direction::String)

    p = SharedArray{Float64}(size(q,2),size(q,1),8) * 0

    if direction == "fwd"

        p[:,:,1] = transpose(q[:,:,1]) # rho
        p[:,:,2] = transpose(q[:,:,3]) # Mx -> Mz
        p[:,:,3] = transpose(q[:,:,4]) # My -> Mx
        p[:,:,4] = transpose(q[:,:,2]) # Mz -> My
        p[:,:,5] = transpose(q[:,:,6]) # Bx -> Bz
        p[:,:,6] = transpose(q[:,:,7]) # By -> Bx
        p[:,:,7] = transpose(q[:,:,5]) # Bz -> By
        p[:,:,8] = transpose(q[:,:,8]) # S or E

    elseif direction == "bwd"

        p[:,:,1] = transpose(q[:,:,1]) # rho
        p[:,:,3] = transpose(q[:,:,2]) # Mz -> Mx
        p[:,:,4] = transpose(q[:,:,3]) # Mx -> My
        p[:,:,2] = transpose(q[:,:,4]) # My -> Mx
        p[:,:,6] = transpose(q[:,:,5]) # Bz -> Bx
        p[:,:,7] = transpose(q[:,:,6]) # Bx -> By
        p[:,:,5] = transpose(q[:,:,7]) # By -> Bz
        p[:,:,8] = transpose(q[:,:,8]) # S or E
    else
        @assert false "Direction parameter : 'fwd' or 'bwd' "
    end

    return p
end # rotate


function timestep(q::Array{Float64,3})

    vxmax, vymax = compute_global_vmax(q)

    dtx = dx/vxmax
    dty = dy/vymax

    dt = courFac /(1/dtx + 1/dty)

    return dt, vxmax, vymax
end

function compute_global_vmax(q::Array{Float64,3})

    vxmax = SharedArray{Float64}(Nx, Ny)
    vymax = SharedArray{Float64}(Nx, Ny)

    @sync @parallel for j = jMin:jMax # Jiang & Wu after eq 2.24
		for i = iMin:iMax
			
			rho = (q[i,j,1] + q[i+1,j,1])/2
           
			vx = (q[i,j,2] + q[i+1,j,2])/2 / rho
			vy = (q[i,j,3] + q[i+1,j,3])/2 / rho
			vz = (q[i,j,4] + q[i+1,j,4])/2 / rho

			Bx = (q[i,j,5] + q[i+1,j,5])/2
			By = (q[i,j,6] + q[i+1,j,6])/2
			Bz = (q[i,j,7] + q[i+1,j,7])/2

			S = (q[i,j,8] + q[i+1,j,8])/2

			pres = S * rho^(gam-1)

			cs2 = gam * abs(pres/rho)
			B2 = Bx^2 + By^2 + Bz^2

			bbn2 = B2/rho

			bnx2 = Bx^2/rho
			bny2 = By^2/rho

			rootx = sqrt((bbn2+cs2)^2 - 4*bnx2*cs2)
			rooty = sqrt((bbn2+cs2)^2 - 4*bny2*cs2)

			lfx = sqrt(0.5 * (bbn2+cs2+rootx)) 
			lfy = sqrt(0.5 * (bbn2+cs2+rooty)) 

			vxmax[i,j] = abs(vx) + lfx
			vymax[i,j] = abs(vy) + lfy
		end
	end

	return maximum(vxmax), maximum(vymax)
end

function initial_conditions() # Shock Cloud interaction

	const R0 = 0.12
	const R1 = 0.19

    q = Array{Float64}(Nx, Ny, 9)*0

	# state variables left & right
	#        rho      vx    vy vz Bx        By      Bz    Press
	sl = [2.11820, 13.69836, 0, 0, 0, 19.33647, 19.33647, 65.8881]
	sr = [      1,        0, 0, 0, 0,  9.12871, 9.12871,      1.0]

	for j = 1:Ny
		for i = 1:Nx

			x = i * dx - NBnd*dx
			y = j * dy - NBnd*dy

			rr = sqrt((x - 1.5)^2 + (y - 0.5)^2)

			if x <= 1.2
                s = copy(sl)
			else 
                s = copy(sr)
			end

			if rr <= R0
				s[1] = 10
            end 
                
            if (rr > R0) && (rr <= R1) 
				s[1] = 1 + 9 * (R1-rr) / (R1-R0)
			end

			q[i,j,:] = state2conserved(s[1],s[2],s[3],s[4],s[5],s[6],s[7],s[8])
		end
	end

	return q
end

function state2conserved(rho::Float64, vx::Float64, vy::Float64, vz::Float64, 
                          Bx::Float64, By::Float64, Bz::Float64, P::Float64)
	
	v2 = vx^2 + vy^2 + vz^2
	B2 = Bx^2 + By^2 + Bz^2

	E = P / (gam-1) + 0.5 * (rho*v2+B2)
	S = P / rho^(gam-1)
	
    return [rho, rho*vx, rho*vy, rho*vz, Bx, By, Bz, S, E]
end

function safe_sqrt(x::Array{Float64,1})
	
	y = copy(x)
	bad = find(y .< 0)
	y[bad] = 0
		
	return sqrt.(y)
end

function printq(q::Array{Float64,3}, bxb::Array{Float64,2}, byb::Array{Float64,2},  
                fsy::Array{Float64,2}, gsx::Array{Float64,2}; ID="")

    xidx = [1,2,3,NBnd+1,78,79,80,Nx/2,Nx-NBnd,Nx/2-1,Nx/2,Nx/2+1,NBnd+1,Nx/2,Nx-NBnd, 10,10,10]
    yidx = [1,2,3,NBnd+1,35,35,35,NBnd+1,NBnd+1,Ny/2,Ny/2,Ny/2,Ny-NBnd,Ny-NBnd,Ny-NBnd, 67,68,69]

    @printf "%s \n" ID

    for i=1:length(xidx)
        
        x = Int64(xidx[i])
        y = Int64(yidx[i])

        @printf "%3i %3i " x-NBnd y-NBnd 
        @printf "%9.4g%9.4g%9.4g%9.4g" q[x,y,1] q[x,y,2] q[x,y,3] q[x,y,4] 
        @printf "%9.4g%9.4g%9.4g%9.4g" q[x,y,5] q[x,y,6] q[x,y,7] q[x,y,8] 
        @printf "%9.4g%9.4g%9.4g%9.4g\n" bxb[x,y] byb[x,y] fsy[x,y] gsx[x,y]
    end
    
    return
end

function printu(u::Array{Float64,2}; ID="")

    const n = size(u, 1)

    xidx = [NBnd+1,floor((n-2*NBnd)/4)+NBnd, n/2-1,n/2,n/2+1,
            floor(3*(n-2*NBnd)/4+NBnd),n-NBnd]

    @printf "%s \n" ID

    for i=1:length(xidx)
        
        x = Int64(xidx[i])

        @printf "%3i  " x-NBnd 
        @printf "%6.4g%6.4g%6.4g%6.4g" u[x,1] u[x,2] u[x,3] u[x,4] 
        @printf "%9.4g%9.4g%9.4g%9.4g\n" u[x,5] u[x,6] u[x,7] u[x,8] 
    end

    return
end

#end # module
