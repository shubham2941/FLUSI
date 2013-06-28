! Wrapper for writing integral quantities to file
subroutine write_integrals(time,uk,u,vort,nlk,work)
  use mpi_header
  use vars
  implicit none

  complex (kind=pr),intent(inout)::uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real (kind=pr),intent(inout) :: u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real (kind=pr),intent(inout) :: vort(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  complex(kind=pr),intent(inout) ::nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real(kind=pr),intent(inout):: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr), intent(in) :: time

  select case(method(1:3))
  case("fsi")
     call write_integrals_fsi(time,uk,u,vort,nlk,work)
  case("mhd")
     call write_integrals_mhd(time,uk,u,vort,nlk,work)
  case default
     if (mpirank == 0) write(*,*) "Error! Unkonwn method in write_integrals"
     call abort
  end select
end subroutine write_integrals


! fsi version of writing integral quantities to disk
subroutine write_integrals_fsi(time,uk,u,vort,nlk,work)
  use mpi_header
  use fsi_vars
  implicit none

  complex(kind=pr),intent(inout)::uk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  complex(kind=pr),intent(inout) ::nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real(kind=pr),intent(inout) :: u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real(kind=pr),intent(inout) :: vort(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real(kind=pr),intent(inout):: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr), intent(in) :: time
  
  ! FIXME: compute integral quantities
  ! NB: consider using subroutines (eg: compute_max_div, compute_energies, etc)


  if(mpirank == 0) then
     open(14,file='drag_data',status='unknown',position='append')
     write(14,'(7(es12.4,1x))')  time,GlobalIntegrals%Ekin,&
          GlobalIntegrals%Dissip, GlobalIntegrals%Force(1),&
          GlobalIntegrals%Force(2),GlobalIntegrals%Force(3),&
       GlobalIntegrals%Volume
     close(14)
  endif
end subroutine write_integrals_fsi


! mhd version of writing integral quantities to disk
subroutine write_integrals_mhd(time,ubk,ub,wj,nlk,work)
  use mpi_header
  use mhd_vars
  implicit none

  complex (kind=pr),intent(inout)::ubk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real (kind=pr),intent(inout) :: ub(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real (kind=pr),intent(inout) :: wj(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  complex(kind=pr),intent(inout) ::nlk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3),1:nd)
  real(kind=pr),intent(inout):: work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr), intent(in) :: time
  integer :: i
  ! Local loop variables
  real(kind=pr) :: Ekin,Ekinx,Ekiny,Ekinz
  real(kind=pr) :: Emag,Emagx,Emagy,Emagz
  real(kind=pr) :: meanjx,meanjy,meanjz
  real(kind=pr) :: jmax,jxmax,jymax,jzmax
  real(kind=pr) :: divu,divb

  ! Compute u and B to physical space
  do i=1,nd
     call ifft(ub(:,:,:,i),ubk(:,:,:,i))
  enddo
  
  ! Compute the vorticity and store the result in the first three 3D
  ! arrays of nlk.
  call curl(nlk(:,:,:,1),nlk(:,:,:,2),nlk(:,:,:,3),&
       ubk(:,:,:,1),ubk(:,:,:,2),ubk(:,:,:,3))

  ! Compute the current density and store the result in the last three
  ! 3D arrays of nlk.
  call curl(nlk(:,:,:,4),nlk(:,:,:,5),nlk(:,:,:,6),&
       ubk(:,:,:,4),ubk(:,:,:,5),ubk(:,:,:,6))

  ! Transform vorcitity and current density to physical space, store
  ! in wj
  do i=1,nd
     call ifft(wj(:,:,:,i),nlk(:,:,:,i))
  enddo

  ! FIXME: TODO: compute more integral quantities

  ! Compute magnetic and kinetic energies
  call compute_energies(Ekin,Ekinx,Ekiny,Ekinz,&
       ub(:,:,:,1),ub(:,:,:,2),ub(:,:,:,3))
  call compute_energies(Emag,Emagx,Emagy,Emagz,&
       ub(:,:,:,4),ub(:,:,:,5),ub(:,:,:,6))
  if(mpirank == 0) then
     open(14,file='evt',status='unknown',position='append')
     write(14,97) time,Ekin,Ekinx,Ekiny,Ekinz,Emag,Emagx,Emagy,Emagz
     close(14)
  endif

  ! Compute current density values
  call compute_components(meanjx,meanjy,meanjz,&
       wj(:,:,:,4),wj(:,:,:,5),wj(:,:,:,6))
  call compute_max(jmax,jxmax,jymax,jzmax,wj(:,:,:,4),wj(:,:,:,5),wj(:,:,:,6))
  if(mpirank == 0) then
     open(14,file='jvt',status='unknown',position='append')
     write(14,97) time,meanjx,meanjy,meanjz,jmax,jxmax,jymax,jzmax
     close(14)
  endif
  
  ! Compute max normalized divergence
  call compute_max_div(divu,&
       ubk(:,:,:,1),ubk(:,:,:,2),ubk(:,:,:,3),&
       ub(:,:,:,1),ub(:,:,:,2),ub(:,:,:,3),&
       work,nlk(:,:,:,1))
  call compute_max_div(divb,&
       ubk(:,:,:,4),ubk(:,:,:,5),ubk(:,:,:,6),&
       ub(:,:,:,4),ub(:,:,:,5),ub(:,:,:,6),&
       work,nlk(:,:,:,1))
  if(mpirank == 0) then
     open(14,file='dvt',status='unknown',position='append')
     write(14,97) time,divu,divb
     close(14)
97   format(1X,9(E14.7,' ')) ! Why must Fortran require this nonsense?
  endif
end subroutine write_integrals_mhd


! Compute the average total energy and energy in each direction for a
! physical-space vector fields with components f1, f2, f3, leaving the
! input vector field untouched.
subroutine compute_energies(E,Ex,Ey,Ez,f1,f2,f3)
  use mpi_header
  use vars
  implicit none
  
  real(kind=pr),intent(out) :: E,Ex,Ey,Ez
  real(kind=pr),intent(inout):: f1(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(inout):: f2(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(inout):: f3(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr) :: LE,LEx,LEy,LEz ! local quantities
  real(kind=pr) :: v1,v2,v3
  integer :: ix,iy,iz,mpicode

  ! initialize local variables
  LE=0.d0
  LEx=0.d0
  LEy=0.d0
  LEz=0.d0

  ! Add contributions in physical space
  do ix=ra(1),rb(1)
     do iy=ra(2),rb(2)
        do iz=ra(3),rb(3)
           v1=f1(ix,iy,iz)
           v2=f2(ix,iy,iz)
           v3=f3(ix,iy,iz)
           
           LE=Le + v1*v1 + v2*v2 + v3*v3
           LEx=LEx + v1*v1
           LEy=LEy + v2*v2
           LEz=LEz + v3*v3
        enddo
     enddo
  enddo

  ! Sum over all MPI processes
  call MPI_REDUCE(LE,E,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(LEx,Ex,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(LEy,Ey,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(LEz,Ez,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
end subroutine compute_energies


! Compute the average average component in each direction for a
! physical-space vector fields with components f1, f2, f3, leaving the
! input vector field untouched.
subroutine compute_components(Cx,Cy,Cz,f1,f2,f3)
  use mpi_header
  use vars
  implicit none
  
  real(kind=pr),intent(out) :: Cx,Cy,Cz
  real(kind=pr),intent(inout):: f1(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(inout):: f2(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(inout):: f3(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr) :: LCx,LCy,LCz ! local quantities
  real(kind=pr) :: v1,v2,v3
  integer :: ix,iy,iz,mpicode

  ! initialize local variables
  LCx=0.d0
  LCy=0.d0
  LCz=0.d0

  ! Add contributions in physical space
  do ix=ra(1),rb(1)
     do iy=ra(2),rb(2)
        do iz=ra(3),rb(3)
           v1=f1(ix,iy,iz)
           v2=f2(ix,iy,iz)
           v3=f3(ix,iy,iz)
           
           LCx=LCx + v1
           LCy=LCy + v2
           LCz=LCz + v3
        enddo
     enddo
  enddo

  ! Sum over all MPI processes
  call MPI_REDUCE(LCx,Cx,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(LCy,Cy,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(LCz,Cz,&
       1,MPI_DOUBLE_PRECISION,MPI_SUM,0,&
       MPI_COMM_WORLD,mpicode)
end subroutine compute_components


! Compute the maximum divergence of the given 3D field
subroutine compute_max_div(maxdiv,fk1,fk2,fk3,f1,f2,f3,div,divk)
  use mpi_header
  use vars
  implicit none

  real(kind=pr),intent(out) :: maxdiv  
  real(kind=pr),intent(in):: f1(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(in):: f2(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(in):: f3(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  complex(kind=pr),intent(in) ::fk1(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  complex(kind=pr),intent(in) ::fk2(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  complex(kind=pr),intent(in) ::fk3(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  complex(kind=pr),intent(inout) ::divk(ca(1):cb(1),ca(2):cb(2),ca(3):cb(3))
  real(kind=pr),intent(inout):: div(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  integer :: ix,iy,iz,mpicode
  real(kind=pr) :: kx, ky, kz, locmax, fnorm, v1,v2,v3,d
  complex(kind=pr) :: imag ! imaginary unit

  imag = dcmplx(0.d0,1.d0)

  ! Compute the divergence in Fourier space, store in divk
  do iz=ca(1),cb(1)
     kz=scalez*(modulo(iz+nz/2,nz) -nz/2)
     do ix=ca(2),cb(2)
        kx=scalex*ix
        do iy=ca(3),cb(3)
           ky=scaley*(modulo(iy+ny/2,ny) -ny/2)
           divk(iz,ix,iy)=imag*&
                (kx*fk1(iz,ix,iy)&
                +ky*fk2(iz,ix,iy)&
                +kz*fk3(iz,ix,iy))
        enddo
     enddo
  enddo

  call ifft(div,divk)
  
  ! Find the local max
  locmax=0.d0
  do ix=ra(1),rb(1)
     do iy=ra(2),rb(2)
        do iz=ra(3),rb(3)
           v1=f1(ix,iy,iz)
           v2=f2(ix,iy,iz)
           v3=f3(ix,iy,iz)

           fnorm=v1*v2 + v2*v2 + v3*v3 + 1d-16 ! avoid division by zero
           d=abs(div(ix,iy,iz))/fnorm
           if(d > locmax) then
              locmax=d
           endif
        enddo
     enddo
  enddo

  ! Find the global max
  call MPI_REDUCE(locmax,maxdiv,&
       1,MPI_DOUBLE_PRECISION,MPI_MAX,0,&
       MPI_COMM_WORLD,mpicode)
end subroutine compute_max_div


! Compute the maximum components of the given 3D field
subroutine compute_max(vmax,xmax,ymax,zmax,f1,f2,f3)
  use mpi_header
  use vars
  implicit none

  real(kind=pr),intent(out) :: vmax,xmax,ymax,zmax
  real(kind=pr),intent(in):: f1(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(in):: f2(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  real(kind=pr),intent(in):: f3(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3))
  integer :: ix,iy,iz,mpicode
  real(kind=pr) :: v1,v2,v3
  real(kind=pr) :: Lmax,Lxmax,Lymax,Lzmax

  Lmax=0.d0
  Lxmax=0.d0
  Lymax=0.d0
  Lzmax=0.d0

  ! Find the (per-prod) max norm and max components in physical space
  do ix=ra(1),rb(1)
     do iy=ra(2),rb(2)
        do iz=ra(3),rb(3)
           v1=f1(ix,iy,iz)
           v2=f2(ix,iy,iz)
           v3=f3(ix,iy,iz)
           Lmax=max(Lmax,dsqrt(v1*v1 + v2*v2 + v3*v3))
           Lxmax=max(Lxmax,v1)
           Lymax=max(Lymax,v2)
           Lzmax=max(Lzmax,v3)
        enddo
     enddo
  enddo

  ! Determine the global max
  call MPI_REDUCE(Lmax,vmax,&
       1,MPI_DOUBLE_PRECISION,MPI_MAX,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(Lxmax,xmax,&
       1,MPI_DOUBLE_PRECISION,MPI_MAX,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(Lymax,ymax,&
       1,MPI_DOUBLE_PRECISION,MPI_MAX,0,&
       MPI_COMM_WORLD,mpicode)
  call MPI_REDUCE(Lzmax,zmax,&
       1,MPI_DOUBLE_PRECISION,MPI_MAX,0,&
       MPI_COMM_WORLD,mpicode)
end subroutine compute_max
