!     path:      $Source$
!     author:    $Author: miacono $
!     revision:  $Revision: 30822 $
!     created:   $Date: 2016-12-29 15:53:24 -0500 (Thu, 29 Dec 2016) $
!

       module rrtmg_sw_rad

!----------------------------------------------------------------------------
! Copyright (c) 2002-2016, Atmospheric & Environmental Research, Inc. (AER)
! All rights reserved.
!
! Redistribution and use in source and binary forms, with or without
! modification, are permitted provided that the following conditions are met:
!  * Redistributions of source code must retain the above copyright
!    notice, this list of conditions and the following disclaimer.
!  * Redistributions in binary form must reproduce the above copyright
!    notice, this list of conditions and the following disclaimer in the
!    documentation and/or other materials provided with the distribution.
!  * Neither the name of Atmospheric & Environmental Research, Inc., nor
!    the names of its contributors may be used to endorse or promote products
!    derived from this software without specific prior written permission.
!
! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
! AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
! IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
! ARE DISCLAIMED. IN NO EVENT SHALL ATMOSPHERIC & ENVIRONMENTAL RESEARCH, INC., 
! BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
! CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
! SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
! INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
! CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
! ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF 
! THE POSSIBILITY OF SUCH DAMAGE.
!                        (http://www.rtweb.aer.com/)                        
!----------------------------------------------------------------------------
!
! ****************************************************************************
! *                                                                          *
! *                             RRTMG_SW                                     *
! *                                                                          *
! *                                                                          *
! *                                                                          *
! *                 a rapid radiative transfer model                         *
! *                  for the solar spectral region                           *
! *           for application to general circulation models                  *
! *                                                                          *
! *                                                                          *
! *           Atmospheric and Environmental Research, Inc.                   *
! *                       131 Hartwell Avenue                                *
! *                       Lexington, MA 02421                                *
! *                                                                          *
! *                                                                          *
! *                          Eli J. Mlawer                                   *
! *                       Jennifer S. Delamere                               *
! *                        Michael J. Iacono                                 *
! *                        Shepard A. Clough                                 *
! *                                                                          *
! *                                                                          *
! *                                                                          *
! *                                                                          *
! *                                                                          *
! *                                                                          *
! *                      email:  miacono@aer.com                             *
! *                      email:  emlawer@aer.com                             *
! *                      email:  jdelamer@aer.com                            *
! *                                                                          *
! *       The authors wish to acknowledge the contributions of the           *
! *       following people:  Steven J. Taubman, Patrick D. Brown,            *
! *       Ronald E. Farren, Luke Chen, Robert Bergstrom.                     *
! *                                                                          *
! ****************************************************************************

! --------- Modules ---------

      use parkind, only : im => kind_im, rb => kind_rb
      use rrsw_vsn
      use mcica_subcol_gen_sw, only: mcica_subcol_sw
      use rrtmg_sw_cldprmc, only: cldprmc_sw
! *** Move the required call to rrtmg_sw_ini below and the following 
! use association to GCM initialization area ***
!      use rrtmg_sw_init, only: rrtmg_sw_ini
      use rrtmg_sw_setcoef, only: setcoef_sw
      use rrtmg_sw_spcvmc, only: spcvmc_sw

      implicit none

! public interfaces/functions/subroutines
      public :: rrtmg_sw, inatm_sw, earth_sun

!------------------------------------------------------------------
      contains
!------------------------------------------------------------------

!------------------------------------------------------------------
! Public subroutines
!------------------------------------------------------------------

      subroutine rrtmg_sw &
            (ncol    ,nlay    ,icld    ,iaer    , &
             play    ,plev    ,tlay    ,tlev    ,tsfc   , &
             h2ovmr , o3vmr   ,co2vmr  ,ch4vmr  ,n2ovmr ,o2vmr , &
             asdir   ,asdif   ,aldir   ,aldif   , &
             coszen  ,adjes   ,dyofyr  ,scon    ,isolvar, &
             inflgsw ,iceflgsw,liqflgsw,cldfmcl , &
             taucmcl ,ssacmcl ,asmcmcl ,fsfcmcl , &
             ciwpmcl ,clwpmcl ,reicmcl ,relqmcl , &
             tauaer  ,ssaaer  ,asmaer  ,ecaer   , &
             swuflx  ,swdflx  ,swhr    ,swuflxc ,swdflxc ,swhrc, &
! optional I/O
             bndsolvar,indsolvar,solcycfrac)

! ------- Description -------

! This program is the driver for RRTMG_SW, the AER SW radiation model for 
!  application to GCMs, that has been adapted from RRTM_SW for improved
!  efficiency and to provide fractional cloudiness and cloud overlap
!  capability using McICA.
!
! Note: The call to RRTMG_SW_INI should be moved to the GCM initialization 
!  area, since this has to be called only once. 
!
! This routine
!    b) calls INATM_SW to read in the atmospheric profile;
!       all layering in RRTMG is ordered from surface to toa. 
!    c) calls CLDPRMC_SW to set cloud optical depth for McICA based
!       on input cloud properties
!    d) calls SETCOEF_SW to calculate various quantities needed for 
!       the radiative transfer algorithm
!    e) calls SPCVMC to call the two-stream model that in turn 
!       calls TAUMOL to calculate gaseous optical depths for each 
!       of the 16 spectral bands and to perform the radiative transfer
!       using McICA, the Monte-Carlo Independent Column Approximation,
!       to represent sub-grid scale cloud variability
!    f) passes the calculated fluxes and cooling rates back to GCM
!
! Two modes of operation are possible:
!     The mode is chosen by using either rrtmg_sw.nomcica.f90 (to not use
!     McICA) or rrtmg_sw.f90 (to use McICA) to interface with a GCM.
!
!    1) Standard, single forward model calculation (imca = 0); this is 
!       valid only for clear sky or fully overcast clouds
!    2) Monte Carlo Independent Column Approximation (McICA, Pincus et al., 
!       JC, 2003) method is applied to the forward model calculation (imca = 1)
!       This method is valid for clear sky or partial cloud conditions.
!
! This call to RRTMG_SW must be preceeded by a call to the module
!     mcica_subcol_gen_sw.f90 to run the McICA sub-column cloud generator,
!     which will provide the cloud physical or cloud optical properties
!     on the RRTMG quadrature point (ngptsw) dimension.
!
! Two methods of cloud property input are possible:
!     Cloud properties can be input in one of two ways (controlled by input 
!     flags inflag, iceflag and liqflag; see text file rrtmg_sw_instructions
!     and subroutine rrtmg_sw_cldprmc.f90 for further details):
!
!    1) Input cloud fraction, cloud optical depth, single scattering albedo 
!       and asymmetry parameter directly (inflgsw = 0)
!    2) Input cloud fraction and cloud physical properties: ice fracion,
!       ice and liquid particle sizes (inflgsw = 1 or 2);  
!       cloud optical properties are calculated by cldprmc based
!       on input settings of iceflgsw and liqflgsw
!
! Two methods of aerosol property input are possible:
!     Aerosol properties can be input in one of two ways (controlled by input 
!     flag iaer, see text file rrtmg_sw_instructions for further details):
!
!    1) Input aerosol optical depth, single scattering albedo and asymmetry
!       parameter directly by layer and spectral band (iaer=10)
!    2) Input aerosol optical depth and 0.55 micron directly by layer and use
!       one or more of six ECMWF aerosol types (iaer=6)
!
!
! ------- Modifications -------
!
! This version of RRTMG_SW has been modified from RRTM_SW to use a reduced
! set of g-point intervals and a two-stream model for application to GCMs. 
!
!-- Original version (derived from RRTM_SW)
!     2002: AER. Inc.
!-- Conversion to F90 formatting; addition of 2-stream radiative transfer
!     Feb 2003: J.-J. Morcrette, ECMWF
!-- Additional modifications for GCM application
!     Aug 2003: M. J. Iacono, AER Inc.
!-- Total number of g-points reduced from 224 to 112.  Original
!   set of 224 can be restored by exchanging code in module parrrsw.f90 
!   and in file rrtmg_sw_init.f90.
!     Apr 2004: M. J. Iacono, AER, Inc.
!-- Modifications to include output for direct and diffuse 
!   downward fluxes.  There are output as "true" fluxes without
!   any delta scaling applied.  Code can be commented to exclude
!   this calculation in source file rrtmg_sw_spcvrt.f90.
!     Jan 2005: E. J. Mlawer, M. J. Iacono, AER, Inc.
!-- Revised to add McICA capability.
!     Nov 2005: M. J. Iacono, AER, Inc.
!-- Reformatted for consistency with rrtmg_lw.
!     Feb 2007: M. J. Iacono, AER, Inc.
!-- Modifications to formatting to use assumed-shape arrays. 
!     Aug 2007: M. J. Iacono, AER, Inc.
!-- Modified to output direct and diffuse fluxes either with or without
!   delta scaling based on setting of idelm flag. 
!     Dec 2008: M. J. Iacono, AER, Inc.
!-- Revised to add new solar variability options based on the
!   NRLSSI2 solar model
!     Dec 2016: M. J. Iacono, AER

! --------- Modules ---------

      use parrrsw, only : nbndsw, ngptsw, naerec, nstr, nmol, mxmol, &
                          jpband, jpb1, jpb2
      use rrsw_aer, only : rsrtaua, rsrpiza, rsrasya
      use rrsw_con, only : heatfac, oneminus, pi
      use rrsw_wvn, only : wavenum1, wavenum2

! ------- Declarations

! ----- Input -----
! Note: All volume mixing ratios are in dimensionless units of mole fraction obtained
! by scaling mass mixing ratio (g/g) with the appropriate molecular weights (g/mol) 
      integer(kind=im), intent(in) :: ncol            ! Number of horizontal columns     
      integer(kind=im), intent(in) :: nlay            ! Number of model layers
      integer(kind=im), intent(inout) :: icld         ! Cloud overlap method
                                                      !    0: Clear only
                                                      !    1: Random
                                                      !    2: Maximum/random
                                                      !    3: Maximum
      integer(kind=im), intent(inout) :: iaer         ! Aerosol option flag
                                                      !    0: No aerosol
                                                      !    6: ECMWF method
                                                      !    10:Input aerosol optical 
                                                      !       properties

      real(kind=rb), intent(in) :: play(:,:)          ! Layer pressures (hPa, mb)
                                                      !    Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: plev(:,:)          ! Interface pressures (hPa, mb)
                                                      !    Dimensions: (ncol,nlay+1)
      real(kind=rb), intent(in) :: tlay(:,:)          ! Layer temperatures (K)
                                                      !    Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: tlev(:,:)          ! Interface temperatures (K)
                                                      !    Dimensions: (ncol,nlay+1)
      real(kind=rb), intent(in) :: tsfc(:)            ! Surface temperature (K)
                                                      !    Dimensions: (ncol)
      real(kind=rb), intent(in) :: h2ovmr(:,:)        ! H2O volume mixing ratio
                                                      !    Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: o3vmr(:,:)         ! O3 volume mixing ratio
                                                      !    Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: co2vmr(:,:)        ! CO2 volume mixing ratio
                                                      !    Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: ch4vmr(:,:)        ! Methane volume mixing ratio
                                                      !    Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: n2ovmr(:,:)        ! Nitrous oxide volume mixing ratio
                                                      !    Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: o2vmr(:,:)         ! Oxygen volume mixing ratio
                                                      !    Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: asdir(:)           ! UV/vis surface albedo direct rad
                                                      !    Dimensions: (ncol)
      real(kind=rb), intent(in) :: aldir(:)           ! Near-IR surface albedo direct rad
                                                      !    Dimensions: (ncol)
      real(kind=rb), intent(in) :: asdif(:)           ! UV/vis surface albedo: diffuse rad
                                                      !    Dimensions: (ncol)
      real(kind=rb), intent(in) :: aldif(:)           ! Near-IR surface albedo: diffuse rad
                                                      !    Dimensions: (ncol)

      integer(kind=im), intent(in) :: dyofyr          ! Day of the year (used to get Earth/Sun
                                                      !  distance if adjflx not provided)
      real(kind=rb), intent(in) :: adjes              ! Flux adjustment for Earth/Sun distance
      real(kind=rb), intent(in) :: coszen(:)          ! Cosine of solar zenith angle
                                                      !    Dimensions: (ncol)
      real(kind=rb), intent(in) :: scon               ! Solar constant (W/m2)
                                                      !    Total solar irradiance averaged 
                                                      !    over the solar cycle.
                                                      !    If scon = 0.0, the internal solar 
                                                      !    constant, which depends on the  
                                                      !    value of isolvar, will be used. 
                                                      !    For isolvar=-1, scon=1368.22 Wm-2,
                                                      !    For isolvar=0,1,3, scon=1360.85 Wm-2,
                                                      !    If scon > 0.0, the internal solar
                                                      !    constant will be scaled to the 
                                                      !    provided value of scon.
      integer(kind=im), intent(in) :: isolvar         ! Flag for solar variability method
                                                      !   -1 = (when scon .eq. 0.0): No solar variability
                                                      !        and no solar cycle (Kurucz solar irradiance
                                                      !        of 1368.22 Wm-2 only);
                                                      !        (when scon .ne. 0.0): Kurucz solar irradiance
                                                      !        scaled to scon and solar variability defined
                                                      !        (optional) by setting non-zero scale factors
                                                      !        for each band in bndsolvar
                                                      !    0 = (when SCON .eq. 0.0): No solar variability 
                                                      !        and no solar cycle (NRLSSI2 solar constant of 
                                                      !        1360.85 Wm-2 for the 100-50000 cm-1 spectral 
                                                      !        range only), with facular and sunspot effects 
                                                      !        fixed to the mean of Solar Cycles 13-24;
                                                      !        (when SCON .ne. 0.0): No solar variability 
                                                      !        and no solar cycle (NRLSSI2 solar constant of 
                                                      !        1360.85 Wm-2 for the 100-50000 cm-1 spectral 
                                                      !        range only), is scaled to SCON
                                                      !    1 = Solar variability (using NRLSSI2  solar
                                                      !        model) with solar cycle contribution
                                                      !        determined by fraction of solar cycle
                                                      !        with facular and sunspot variations
                                                      !        fixed to their mean variations over the
                                                      !        average of Solar Cycles 13-24;
                                                      !        two amplitude scale factors allow
                                                      !        facular and sunspot adjustments from
                                                      !        mean solar cycle as defined by indsolvar 
                                                      !    2 = Solar variability (using NRLSSI2 solar
                                                      !        model) over solar cycle determined by 
                                                      !        direct specification of Mg (facular)
                                                      !        and SB (sunspot) indices provided
                                                      !        in indsolvar (scon = 0.0 only)
                                                      !    3 = (when scon .eq. 0.0): No solar variability
                                                      !        and no solar cycle (NRLSSI2 solar irradiance
                                                      !        of 1360.85 Wm-2 only);
                                                      !        (when scon .ne. 0.0): NRLSSI2 solar irradiance
                                                      !        scaled to scon and solar variability defined
                                                      !        (optional) by setting non-zero scale factors
                                                      !        for each band in bndsolvar
      real(kind=rb), intent(inout), optional :: indsolvar(:) ! Facular and sunspot amplitude 
                                                          ! scale factors (isolvar=1), or
                                                          ! Mg and SB indices (isolvar=2)
                                                          !    Dimensions: (2)
      real(kind=rb), intent(in), optional :: bndsolvar(:) ! Solar variability scale factors 
                                                          ! for each shortwave band
                                                          !    Dimensions: (nbndsw=14)
      real(kind=rb), intent(in), optional :: solcycfrac   ! Fraction of averaged solar cycle (0-1)
                                                          !    at current time (isolvar=1)

      integer(kind=im), intent(in) :: inflgsw         ! Flag for cloud optical properties
      integer(kind=im), intent(in) :: iceflgsw        ! Flag for ice particle specification
      integer(kind=im), intent(in) :: liqflgsw        ! Flag for liquid droplet specification

      real(kind=rb), intent(in) :: cldfmcl(:,:,:)     ! Cloud fraction
                                                      !    Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: taucmcl(:,:,:)     ! In-cloud optical depth
                                                      !    Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: ssacmcl(:,:,:)     ! In-cloud single scattering albedo
                                                      !    Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: asmcmcl(:,:,:)     ! In-cloud asymmetry parameter
                                                      !    Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: fsfcmcl(:,:,:)     ! In-cloud forward scattering fraction
                                                      !    Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: ciwpmcl(:,:,:)     ! In-cloud ice water path (g/m2)
                                                      !    Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: clwpmcl(:,:,:)     ! In-cloud liquid water path (g/m2)
                                                      !    Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: reicmcl(:,:)       ! Cloud ice effective radius (microns)
                                                      !    Dimensions: (ncol,nlay)
                                                      ! specific definition of reicmcl depends on setting of iceflgsw:
                                                      ! iceflgsw = 0: (inactive)
                                                      ! 
                                                      ! iceflgsw = 1: ice effective radius, r_ec, (Ebert and Curry, 1992),
                                                      !               r_ec range is limited to 13.0 to 130.0 microns
                                                      ! iceflgsw = 2: ice effective radius, r_k, (Key, Streamer Ref. Manual, 1996)
                                                      !               r_k range is limited to 5.0 to 131.0 microns
                                                      ! iceflgsw = 3: generalized effective size, dge, (Fu, 1996),
                                                      !               dge range is limited to 5.0 to 140.0 microns
                                                      !               [dge = 1.0315 * r_ec]
      real(kind=rb), intent(in) :: relqmcl(:,:)       ! Cloud water drop effective radius (microns)
                                                      !    Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: tauaer(:,:,:)      ! Aerosol optical depth (iaer=10 only)
                                                      !    Dimensions: (ncol,nlay,nbndsw)
                                                      ! (non-delta scaled)      
      real(kind=rb), intent(in) :: ssaaer(:,:,:)      ! Aerosol single scattering albedo (iaer=10 only)
                                                      !    Dimensions: (ncol,nlay,nbndsw)
                                                      ! (non-delta scaled)      
      real(kind=rb), intent(in) :: asmaer(:,:,:)      ! Aerosol asymmetry parameter (iaer=10 only)
                                                      !    Dimensions: (ncol,nlay,nbndsw)
                                                      ! (non-delta scaled)      
      real(kind=rb), intent(in) :: ecaer(:,:,:)       ! Aerosol optical depth at 0.55 micron (iaer=6 only)
                                                      !    Dimensions: (ncol,nlay,naerec)
                                                      ! (non-delta scaled)      

! ----- Output -----

      real(kind=rb), intent(out) :: swuflx(:,:)       ! Total sky shortwave upward flux (W/m2)
                                                      !    Dimensions: (ncol,nlay+1)
      real(kind=rb), intent(out) :: swdflx(:,:)       ! Total sky shortwave downward flux (W/m2)
                                                      !    Dimensions: (ncol,nlay+1)
      real(kind=rb), intent(out) :: swhr(:,:)         ! Total sky shortwave radiative heating rate (K/d)
                                                      !    Dimensions: (ncol,nlay)
      real(kind=rb), intent(out) :: swuflxc(:,:)      ! Clear sky shortwave upward flux (W/m2)
                                                      !    Dimensions: (ncol,nlay+1)
      real(kind=rb), intent(out) :: swdflxc(:,:)      ! Clear sky shortwave downward flux (W/m2)
                                                      !    Dimensions: (ncol,nlay+1)
      real(kind=rb), intent(out) :: swhrc(:,:)        ! Clear sky shortwave radiative heating rate (K/d)
                                                      !    Dimensions: (ncol,nlay)

! ----- Local -----

! Control
      integer(kind=im) :: nlayers             ! total number of layers
      integer(kind=im) :: istart              ! beginning band of calculation
      integer(kind=im) :: iend                ! ending band of calculation
      integer(kind=im) :: icpr                ! cldprop/cldprmc use flag
      integer(kind=im) :: iout                ! output option flag
      integer(kind=im) :: idelm               ! delta-m scaling flag
                                              ! [0 = direct and diffuse fluxes are unscaled]
                                              ! [1 = direct and diffuse fluxes are scaled]
                                              ! (total downward fluxes are always delta scaled)
      integer(kind=im) :: isccos              ! instrumental cosine response flag (inactive)
      integer(kind=im) :: iplon               ! column loop index
      integer(kind=im) :: i                   ! layer loop index                       ! jk
      integer(kind=im) :: ib                  ! band loop index                        ! jsw
      integer(kind=im) :: ia, ig              ! indices
      integer(kind=im) :: k                   ! layer loop index
      integer(kind=im) :: ims                 ! value for changing mcica permute seed
      integer(kind=im) :: imca                ! flag for mcica [0=off, 1=on]

      real(kind=rb) :: zepsec, zepzen         ! epsilon
      real(kind=rb) :: zdpgcp                 ! flux to heating conversion ratio

! Atmosphere
      real(kind=rb) :: pavel(nlay+1)          ! layer pressures (mb) 
      real(kind=rb) :: tavel(nlay+1)          ! layer temperatures (K)
      real(kind=rb) :: pz(0:nlay+1)           ! level (interface) pressures (hPa, mb)
      real(kind=rb) :: tz(0:nlay+1)           ! level (interface) temperatures (K)
      real(kind=rb) :: tbound                 ! surface temperature (K)
      real(kind=rb) :: pdp(nlay+1)            ! layer pressure thickness (hPa, mb)
      real(kind=rb) :: coldry(nlay+1)         ! dry air column amount
      real(kind=rb) :: wkl(mxmol,nlay+1)      ! molecular amounts (mol/cm-2)

!      real(kind=rb) :: earth_sun             ! function for Earth/Sun distance factor
      real(kind=rb) :: cossza                 ! Cosine of solar zenith angle
      real(kind=rb) :: adjflux(jpband)        ! adjustment for current Earth/Sun distance
      real(kind=rb) :: albdir(nbndsw)         ! surface albedo, direct          ! zalbp
      real(kind=rb) :: albdif(nbndsw)         ! surface albedo, diffuse         ! zalbd

      real(kind=rb) :: taua(nlay+1,nbndsw)    ! Aerosol optical depth
      real(kind=rb) :: ssaa(nlay+1,nbndsw)    ! Aerosol single scattering albedo
      real(kind=rb) :: asma(nlay+1,nbndsw)    ! Aerosol asymmetry parameter

! Atmosphere - setcoef
      integer(kind=im) :: laytrop             ! tropopause layer index
      integer(kind=im) :: layswtch            ! tropopause layer index
      integer(kind=im) :: laylow              ! tropopause layer index
      integer(kind=im) :: jp(nlay+1)          ! 
      integer(kind=im) :: jt(nlay+1)          !
      integer(kind=im) :: jt1(nlay+1)         !

      real(kind=rb) :: colh2o(nlay+1)         ! column amount (h2o)
      real(kind=rb) :: colco2(nlay+1)         ! column amount (co2)
      real(kind=rb) :: colo3(nlay+1)          ! column amount (o3)
      real(kind=rb) :: coln2o(nlay+1)         ! column amount (n2o)
      real(kind=rb) :: colch4(nlay+1)         ! column amount (ch4)
      real(kind=rb) :: colo2(nlay+1)          ! column amount (o2)
      real(kind=rb) :: colmol(nlay+1)         ! column amount
      real(kind=rb) :: co2mult(nlay+1)        ! column amount 

      integer(kind=im) :: indself(nlay+1)
      integer(kind=im) :: indfor(nlay+1)
      real(kind=rb) :: selffac(nlay+1)
      real(kind=rb) :: selffrac(nlay+1)
      real(kind=rb) :: forfac(nlay+1)
      real(kind=rb) :: forfrac(nlay+1)

      real(kind=rb) :: &                      !
                         fac00(nlay+1), fac01(nlay+1), &
                         fac10(nlay+1), fac11(nlay+1) 

! Atmosphere/clouds - cldprop
      integer(kind=im) :: ncbands             ! number of cloud spectral bands
      integer(kind=im) :: inflag              ! flag for cloud property method
      integer(kind=im) :: iceflag             ! flag for ice cloud properties
      integer(kind=im) :: liqflag             ! flag for liquid cloud properties

!      real(kind=rb) :: cldfrac(nlay+1)        ! layer cloud fraction
!      real(kind=rb) :: tauc(nlay+1)           ! in-cloud optical depth (non-delta scaled)
!      real(kind=rb) :: ssac(nlay+1)           ! in-cloud single scattering albedo (non-delta scaled)
!      real(kind=rb) :: asmc(nlay+1)           ! in-cloud asymmetry parameter (non-delta scaled)
!      real(kind=rb) :: fsfc(nlay+1)           ! in-cloud forward scattering fraction (non-delta scaled)
!      real(kind=rb) :: ciwp(nlay+1)           ! in-cloud ice water path
!      real(kind=rb) :: clwp(nlay+1)           ! in-cloud liquid water path
!      real(kind=rb) :: rei(nlay+1)            ! cloud ice particle size
!      real(kind=rb) :: rel(nlay+1)            ! cloud liquid particle size

!      real(kind=rb) :: taucloud(nlay+1,jpband)  ! in-cloud optical depth
!      real(kind=rb) :: taucldorig(nlay+1,jpband)! in-cloud optical depth (non-delta scaled)
!      real(kind=rb) :: ssacloud(nlay+1,jpband)  ! in-cloud single scattering albedo
!      real(kind=rb) :: asmcloud(nlay+1,jpband)  ! in-cloud asymmetry parameter

! Atmosphere/clouds - cldprmc [mcica]
      real(kind=rb) :: cldfmc(ngptsw,nlay+1)    ! cloud fraction [mcica]
      real(kind=rb) :: ciwpmc(ngptsw,nlay+1)    ! in-cloud ice water path [mcica]
      real(kind=rb) :: clwpmc(ngptsw,nlay+1)    ! in-cloud liquid water path [mcica]
      real(kind=rb) :: relqmc(nlay+1)           ! liquid particle effective radius (microns)
      real(kind=rb) :: reicmc(nlay+1)           ! ice particle effective size (microns)
      real(kind=rb) :: taucmc(ngptsw,nlay+1)    ! in-cloud optical depth [mcica]
      real(kind=rb) :: taormc(ngptsw,nlay+1)    ! unscaled in-cloud optical depth [mcica]
      real(kind=rb) :: ssacmc(ngptsw,nlay+1)    ! in-cloud single scattering albedo [mcica]
      real(kind=rb) :: asmcmc(ngptsw,nlay+1)    ! in-cloud asymmetry parameter [mcica]
      real(kind=rb) :: fsfcmc(ngptsw,nlay+1)    ! in-cloud forward scattering fraction [mcica]

! Atmosphere/clouds/aerosol - spcvrt,spcvmc
      real(kind=rb) :: ztauc(nlay+1,nbndsw)     ! cloud optical depth
      real(kind=rb) :: ztaucorig(nlay+1,nbndsw) ! unscaled cloud optical depth
      real(kind=rb) :: zasyc(nlay+1,nbndsw)     ! cloud asymmetry parameter 
                                                !  (first moment of phase function)
      real(kind=rb) :: zomgc(nlay+1,nbndsw)     ! cloud single scattering albedo
      real(kind=rb) :: ztaua(nlay+1,nbndsw)     ! total aerosol optical depth
      real(kind=rb) :: zasya(nlay+1,nbndsw)     ! total aerosol asymmetry parameter 
      real(kind=rb) :: zomga(nlay+1,nbndsw)     ! total aerosol single scattering albedo

      real(kind=rb) :: zcldfmc(nlay+1,ngptsw)   ! cloud fraction [mcica]
      real(kind=rb) :: ztaucmc(nlay+1,ngptsw)   ! cloud optical depth [mcica]
      real(kind=rb) :: ztaormc(nlay+1,ngptsw)   ! unscaled cloud optical depth [mcica]
      real(kind=rb) :: zasycmc(nlay+1,ngptsw)   ! cloud asymmetry parameter [mcica] 
      real(kind=rb) :: zomgcmc(nlay+1,ngptsw)   ! cloud single scattering albedo [mcica]

      real(kind=rb) :: zbbfu(nlay+2)          ! temporary upward shortwave flux (w/m2)
      real(kind=rb) :: zbbfd(nlay+2)          ! temporary downward shortwave flux (w/m2)
      real(kind=rb) :: zbbcu(nlay+2)          ! temporary clear sky upward shortwave flux (w/m2)
      real(kind=rb) :: zbbcd(nlay+2)          ! temporary clear sky downward shortwave flux (w/m2)
      real(kind=rb) :: zbbfddir(nlay+2)       ! temporary downward direct shortwave flux (w/m2)
      real(kind=rb) :: zbbcddir(nlay+2)       ! temporary clear sky downward direct shortwave flux (w/m2)
      real(kind=rb) :: zuvfd(nlay+2)          ! temporary UV downward shortwave flux (w/m2)
      real(kind=rb) :: zuvcd(nlay+2)          ! temporary clear sky UV downward shortwave flux (w/m2)
      real(kind=rb) :: zuvfddir(nlay+2)       ! temporary UV downward direct shortwave flux (w/m2)
      real(kind=rb) :: zuvcddir(nlay+2)       ! temporary clear sky UV downward direct shortwave flux (w/m2)
      real(kind=rb) :: znifd(nlay+2)          ! temporary near-IR downward shortwave flux (w/m2)
      real(kind=rb) :: znicd(nlay+2)          ! temporary clear sky near-IR downward shortwave flux (w/m2)
      real(kind=rb) :: znifddir(nlay+2)       ! temporary near-IR downward direct shortwave flux (w/m2)
      real(kind=rb) :: znicddir(nlay+2)       ! temporary clear sky near-IR downward direct shortwave flux (w/m2)

! Optional output fields 
      real(kind=rb) :: swnflx(nlay+2)         ! Total sky shortwave net flux (W/m2)
      real(kind=rb) :: swnflxc(nlay+2)        ! Clear sky shortwave net flux (W/m2)
      real(kind=rb) :: dirdflux(nlay+2)       ! Direct downward shortwave surface flux
      real(kind=rb) :: difdflux(nlay+2)       ! Diffuse downward shortwave surface flux
      real(kind=rb) :: uvdflx(nlay+2)         ! Total sky downward shortwave flux, UV/vis  
      real(kind=rb) :: nidflx(nlay+2)         ! Total sky downward shortwave flux, near-IR 
      real(kind=rb) :: dirdnuv(nlay+2)        ! Direct downward shortwave flux, UV/vis
      real(kind=rb) :: difdnuv(nlay+2)        ! Diffuse downward shortwave flux, UV/vis
      real(kind=rb) :: dirdnir(nlay+2)        ! Direct downward shortwave flux, near-IR
      real(kind=rb) :: difdnir(nlay+2)        ! Diffuse downward shortwave flux, near-IR

! Output - inactive
!      real(kind=rb) :: zuvfu(nlay+2)         ! temporary upward UV shortwave flux (w/m2)
!      real(kind=rb) :: zuvfd(nlay+2)         ! temporary downward UV shortwave flux (w/m2)
!      real(kind=rb) :: zuvcu(nlay+2)         ! temporary clear sky upward UV shortwave flux (w/m2)
!      real(kind=rb) :: zuvcd(nlay+2)         ! temporary clear sky downward UV shortwave flux (w/m2)
!      real(kind=rb) :: zvsfu(nlay+2)         ! temporary upward visible shortwave flux (w/m2)
!      real(kind=rb) :: zvsfd(nlay+2)         ! temporary downward visible shortwave flux (w/m2)
!      real(kind=rb) :: zvscu(nlay+2)         ! temporary clear sky upward visible shortwave flux (w/m2)
!      real(kind=rb) :: zvscd(nlay+2)         ! temporary clear sky downward visible shortwave flux (w/m2)
!      real(kind=rb) :: znifu(nlay+2)         ! temporary upward near-IR shortwave flux (w/m2)
!      real(kind=rb) :: znifd(nlay+2)         ! temporary downward near-IR shortwave flux (w/m2)
!      real(kind=rb) :: znicu(nlay+2)         ! temporary clear sky upward near-IR shortwave flux (w/m2)
!      real(kind=rb) :: znicd(nlay+2)         ! temporary clear sky downward near-IR shortwave flux (w/m2)

! Solar variability
      real(kind=rb) :: svar_f                 ! Solar variability facular multiplier
      real(kind=rb) :: svar_s                 ! Solar variability sunspot multiplier
      real(kind=rb) :: svar_i                 ! Solar variability baseline irradiance multiplier
      real(kind=rb) :: svar_f_bnd(jpband)     ! Solar variability facular multiplier (by band)
      real(kind=rb) :: svar_s_bnd(jpband)     ! Solar variability sunspot multiplier (by band)
      real(kind=rb) :: svar_i_bnd(jpband)     ! Solar variability baseline irradiance multiplier (by band)


! Initializations

      zepsec = 1.e-06_rb
      zepzen = 1.e-10_rb
      oneminus = 1.0_rb - zepsec
      pi = 2._rb * asin(1._rb)

      istart = jpb1
      iend = jpb2
      iout = 0
      icpr = 0
      ims = 2

! In a GCM with or without McICA, set nlon to the longitude dimension
!
! Set imca to select calculation type:
!  imca = 0, use standard forward model calculation (clear and overcast only)
!  imca = 1, use McICA for Monte Carlo treatment of sub-grid cloud variability
!            (clear, overcast or partial cloud conditions)

! *** This version uses McICA (imca = 1) ***

! Set icld to default selection of clear or cloud calculation and cloud overlap method
! if not passed in with valid value
! icld = 0, clear only
! icld = 1, with clouds using random cloud overlap (McICA only)
! icld = 2, with clouds using maximum/random cloud overlap (McICA only)
! icld = 3, with clouds using maximum cloud overlap (McICA only)
      if (icld.lt.0.or.icld.gt.3) icld = 2

! Set iaer to select aerosol option
! iaer = 0, no aerosols
! iaer = 6, use six ECMWF aerosol types
!           input aerosol optical depth at 0.55 microns for each aerosol type (ecaer)
! iaer = 10, input total aerosol optical depth, single scattering albedo 
!            and asymmetry parameter (tauaer, ssaaer, asmaer) directly
      if (iaer.ne.0.and.iaer.ne.6.and.iaer.ne.10) iaer = 0

! Set idelm to select between delta-M scaled or unscaled output direct and diffuse fluxes
! NOTE: total downward fluxes are always delta scaled
! idelm = 0, output direct and diffuse flux components are not delta scaled
!            (direct flux does not include forward scattering peak)
! idelm = 1, output direct and diffuse flux components are delta scaled (default)
!            (direct flux includes part or most of forward scattering peak)
      idelm = 1

! Call model and data initialization, compute lookup tables, perform
! reduction of g-points from 224 to 112 for input absorption
! coefficient data and other arrays.
!
! In a GCM this call should be placed in the model initialization
! area, since this has to be called only once.  
!      call rrtmg_sw_ini(cpdair)

! This is the main longitude/column loop in RRTMG.
! Modify to loop over all columns (nlon) or over daylight columns

      do iplon = 1, ncol

! Prepare atmosphere profile from GCM for use in RRTMG, and define
! other input parameters

         call inatm_sw (iplon, nlay, icld, iaer, &
              play, plev, tlay, tlev, tsfc, h2ovmr, &
              o3vmr, co2vmr, ch4vmr, n2ovmr, o2vmr, &
              adjes, dyofyr, scon, isolvar, &
              inflgsw, iceflgsw, liqflgsw, &
              cldfmcl, taucmcl, ssacmcl, asmcmcl, fsfcmcl, ciwpmcl, clwpmcl, &
              reicmcl, relqmcl, tauaer, ssaaer, asmaer, &
              nlayers, pavel, pz, pdp, tavel, tz, tbound, coldry, wkl, &
              adjflux, inflag, iceflag, liqflag, cldfmc, taucmc, &
              ssacmc, asmcmc, fsfcmc, ciwpmc, clwpmc, reicmc, relqmc, &
              taua, ssaa, asma, &
! solar variability
              svar_f, svar_s, svar_i, svar_f_bnd, svar_s_bnd, svar_i_bnd, &
! optional
              bndsolvar,indsolvar,solcycfrac)

!  For cloudy atmosphere, use cldprmc to set cloud optical properties based on
!  input cloud physical properties.  Select method based on choices described
!  in cldprmc.  Cloud fraction, water path, liquid droplet and ice particle
!  effective radius must be passed in cldprmc.  Cloud fraction and cloud
!  optical properties are transferred to rrtmg_sw arrays in cldprmc.  

         call cldprmc_sw(nlayers, inflag, iceflag, liqflag, cldfmc, &
                         ciwpmc, clwpmc, reicmc, relqmc, &
                         taormc, taucmc, ssacmc, asmcmc, fsfcmc)
         icpr = 1

! Calculate coefficients for the temperature and pressure dependence of the 
! molecular absorption coefficients by interpolating data from stored
! reference atmospheres.

         call setcoef_sw(nlayers, pavel, tavel, pz, tz, tbound, coldry, wkl, &
                         laytrop, layswtch, laylow, jp, jt, jt1, &
                         co2mult, colch4, colco2, colh2o, colmol, coln2o, &
                         colo2, colo3, fac00, fac01, fac10, fac11, &
                         selffac, selffrac, indself, forfac, forfrac, indfor)


! Cosine of the solar zenith angle 
!  Prevent using value of zero; ideally, SW model is not called from host model when sun 
!  is below horizon

         cossza = coszen(iplon)
         if (cossza .lt. zepzen) cossza = zepzen


! Transfer albedo, cloud and aerosol properties into arrays for 2-stream radiative transfer 

! Surface albedo
!  Near-IR bands 16-24 and 29 (1-9 and 14), 820-16000 cm-1, 0.625-12.195 microns
         do ib=1,9
            albdir(ib) = aldir(iplon)
            albdif(ib) = aldif(iplon)
         enddo
         albdir(nbndsw) = aldir(iplon)
         albdif(nbndsw) = aldif(iplon)
!  UV/visible bands 25-28 (10-13), 16000-50000 cm-1, 0.200-0.625 micron
         do ib=10,13
            albdir(ib) = asdir(iplon)
            albdif(ib) = asdif(iplon)
         enddo


! Clouds
         if (icld.eq.0) then

            zcldfmc(:,:) = 0._rb
            ztaucmc(:,:) = 0._rb
            ztaormc(:,:) = 0._rb
            zasycmc(:,:) = 0._rb
            zomgcmc(:,:) = 1._rb

         elseif (icld.ge.1) then
            do i=1,nlayers
               do ig=1,ngptsw
                  zcldfmc(i,ig) = cldfmc(ig,i)
                  ztaucmc(i,ig) = taucmc(ig,i)
                  ztaormc(i,ig) = taormc(ig,i)
                  zasycmc(i,ig) = asmcmc(ig,i)
                  zomgcmc(i,ig) = ssacmc(ig,i)
               enddo
            enddo

         endif   

! Aerosol
! IAER = 0: no aerosols
         if (iaer.eq.0) then

            ztaua(:,:) = 0._rb
            zasya(:,:) = 0._rb
            zomga(:,:) = 1._rb

! IAER = 6: Use ECMWF six aerosol types. See rrsw_aer.f90 for details.
! Input aerosol optical thickness at 0.55 micron for each aerosol type (ecaer), 
! or set manually here for each aerosol and layer.
         elseif (iaer.eq.6) then

!            do i = 1, nlayers
!               do ia = 1, naerec
!                  ecaer(iplon,i,ia) = 1.0e-15_rb
!               enddo
!            enddo

            do i = 1, nlayers
               do ib = 1, nbndsw
                  ztaua(i,ib) = 0._rb
                  zasya(i,ib) = 0._rb
                  zomga(i,ib) = 0._rb
                  do ia = 1, naerec
                     ztaua(i,ib) = ztaua(i,ib) + rsrtaua(ib,ia) * ecaer(iplon,i,ia)
                     zomga(i,ib) = zomga(i,ib) + rsrtaua(ib,ia) * ecaer(iplon,i,ia) * &
                                   rsrpiza(ib,ia)
                     zasya(i,ib) = zasya(i,ib) + rsrtaua(ib,ia) * ecaer(iplon,i,ia) * &
                                   rsrpiza(ib,ia) * rsrasya(ib,ia)
                  enddo
                  if (ztaua(i,ib) == 0._rb) then
                     ztaua(i,ib) = 0._rb
                     zasya(i,ib) = 0._rb
                     zomga(i,ib) = 1._rb
                  else
                     if (zomga(i,ib) /= 0._rb) then
                        zasya(i,ib) = zasya(i,ib) / zomga(i,ib)
                     endif
                     if (ztaua(i,ib) /= 0._rb) then
                        zomga(i,ib) = zomga(i,ib) / ztaua(i,ib)
                     endif
                  endif
               enddo
            enddo

! IAER=10: Direct specification of aerosol optical properties from GCM
         elseif (iaer.eq.10) then

            do i = 1 ,nlayers
               do ib = 1 ,nbndsw
                  ztaua(i,ib) = taua(i,ib)
                  zasya(i,ib) = asma(i,ib)
                  zomga(i,ib) = ssaa(i,ib)
               enddo
            enddo

         endif


! Call the 2-stream radiation transfer model

         do i=1,nlayers+1
            zbbcu(i) = 0._rb
            zbbcd(i) = 0._rb
            zbbfu(i) = 0._rb
            zbbfd(i) = 0._rb
            zbbcddir(i) = 0._rb
            zbbfddir(i) = 0._rb
            zuvcd(i) = 0._rb
            zuvfd(i) = 0._rb
            zuvcddir(i) = 0._rb
            zuvfddir(i) = 0._rb
            znicd(i) = 0._rb
            znifd(i) = 0._rb
            znicddir(i) = 0._rb
            znifddir(i) = 0._rb
         enddo


         call spcvmc_sw &
             (nlayers, istart, iend, icpr, idelm, iout, &
              pavel, tavel, pz, tz, tbound, albdif, albdir, &
              zcldfmc, ztaucmc, zasycmc, zomgcmc, ztaormc, &
              ztaua, zasya, zomga, cossza, coldry, wkl, adjflux, &	 
              isolvar, svar_f, svar_s, svar_i, &
              svar_f_bnd, svar_s_bnd, svar_i_bnd, &
              laytrop, layswtch, laylow, jp, jt, jt1, &
              co2mult, colch4, colco2, colh2o, colmol, coln2o, colo2, colo3, &
              fac00, fac01, fac10, fac11, &
              selffac, selffrac, indself, forfac, forfrac, indfor, &
              zbbfd, zbbfu, zbbcd, zbbcu, zuvfd, zuvcd, znifd, znicd, &
              zbbfddir, zbbcddir, zuvfddir, zuvcddir, znifddir, znicddir)

! Transfer up and down, clear and total sky fluxes to output arrays.
! Vertical indexing goes from bottom to top; reverse here for GCM if necessary.

         do i = 1, nlayers+1
            swuflxc(iplon,i) = zbbcu(i)
            swdflxc(iplon,i) = zbbcd(i)
            swuflx(iplon,i) = zbbfu(i)
            swdflx(iplon,i) = zbbfd(i)
            uvdflx(i) = zuvfd(i)
            nidflx(i) = znifd(i)
!  Direct/diffuse fluxes
            dirdflux(i) = zbbfddir(i)
            difdflux(i) = swdflx(iplon,i) - dirdflux(i)
!  UV/visible direct/diffuse fluxes
            dirdnuv(i) = zuvfddir(i)
            difdnuv(i) = zuvfd(i) - dirdnuv(i)
!  Near-IR direct/diffuse fluxes
            dirdnir(i) = znifddir(i)
            difdnir(i) = znifd(i) - dirdnir(i)
         enddo

!  Total and clear sky net fluxes
         do i = 1, nlayers+1
            swnflxc(i) = swdflxc(iplon,i) - swuflxc(iplon,i)
            swnflx(i) = swdflx(iplon,i) - swuflx(iplon,i)
         enddo

!  Total and clear sky heating rates
         do i = 1, nlayers
            zdpgcp = heatfac / pdp(i)
            swhrc(iplon,i) = (swnflxc(i+1) - swnflxc(i)) * zdpgcp
            swhr(iplon,i) = (swnflx(i+1) - swnflx(i)) * zdpgcp
         enddo
! Commented out from original version to
! Conserve energy
!         swhrc(iplon,nlayers) = 0._rb
!         swhr(iplon,nlayers) = 0._rb

! End longitude loop
      enddo

      end subroutine rrtmg_sw

!*************************************************************************
      real(kind=rb) function earth_sun(idn)
!*************************************************************************
!
!  Purpose: Function to calculate the correction factor of Earth's orbit
!  for current day of the year

!  idn        : Day of the year
!  earth_sun  : square of the ratio of mean to actual Earth-Sun distance

! ------- Modules -------

      use rrsw_con, only : pi

      integer(kind=im), intent(in) :: idn

      real(kind=rb) :: gamma

      gamma = 2._rb*pi*(idn-1)/365._rb

! Use Iqbal's equation 1.2.1

      earth_sun = 1.000110_rb + .034221_rb * cos(gamma) + .001289_rb * sin(gamma) + &
                   .000719_rb * cos(2._rb*gamma) + .000077_rb * sin(2._rb*gamma)

      end function earth_sun

!***************************************************************************
      subroutine inatm_sw (iplon, nlay, icld, iaer, &
            play, plev, tlay, tlev, tsfc, h2ovmr, &
            o3vmr, co2vmr, ch4vmr, n2ovmr, o2vmr, &
            adjes, dyofyr, scon, isolvar, &
            inflgsw, iceflgsw, liqflgsw, &
            cldfmcl, taucmcl, ssacmcl, asmcmcl, fsfcmcl, ciwpmcl, clwpmcl, &
            reicmcl, relqmcl, tauaer, ssaaer, asmaer, &
            nlayers, pavel, pz, pdp, tavel, tz, tbound, coldry, wkl, &
            adjflux, inflag, iceflag, liqflag, cldfmc, taucmc, &
            ssacmc, asmcmc, fsfcmc, ciwpmc, clwpmc, reicmc, relqmc, &
            taua, ssaa, asma, &
! solar variability
            svar_f, svar_s, svar_i, svar_f_bnd, svar_s_bnd, svar_i_bnd, &
! optional
            bndsolvar,indsolvar,solcycfrac)
!***************************************************************************
!
!  Input atmospheric profile from GCM, and prepare it for use in RRTMG_SW.
!  Set other RRTMG_SW input parameters.  
!
!***************************************************************************

! --------- Modules ----------

      use parrrsw, only : nbndsw, ngptsw, nstr, nmol, mxmol, &
                          jpband, jpb1, jpb2, rrsw_scon
      use rrsw_con, only : heatfac, oneminus, pi, grav, avogad
      use rrsw_wvn, only : ng, nspa, nspb, wavenum1, wavenum2, delwave

! ------- Declarations -------

! ----- Input -----
! Note: All volume mixing ratios are in dimensionless units of mole fraction obtained
! by scaling mass mixing ratio (g/g) with the appropriate molecular weights (g/mol) 
      integer(kind=im), intent(in) :: iplon           ! column loop index
      integer(kind=im), intent(in) :: nlay            ! number of model layers
      integer(kind=im), intent(in) :: icld            ! clear/cloud and cloud overlap flag
      integer(kind=im), intent(in) :: iaer            ! aerosol option flag

      real(kind=rb), intent(in) :: play(:,:)          ! Layer pressures (hPa, mb)
                                                      ! Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: plev(:,:)          ! Interface pressures (hPa, mb)
                                                      ! Dimensions: (ncol,nlay+1)
      real(kind=rb), intent(in) :: tlay(:,:)          ! Layer temperatures (K)
                                                      ! Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: tlev(:,:)          ! Interface temperatures (K)
                                                      ! Dimensions: (ncol,nlay+1)
      real(kind=rb), intent(in) :: tsfc(:)            ! Surface temperature (K)
                                                      ! Dimensions: (ncol)
      real(kind=rb), intent(in) :: h2ovmr(:,:)        ! H2O volume mixing ratio
                                                      ! Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: o3vmr(:,:)         ! O3 volume mixing ratio
                                                      ! Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: co2vmr(:,:)        ! CO2 volume mixing ratio
                                                      ! Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: ch4vmr(:,:)        ! Methane volume mixing ratio
                                                      ! Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: n2ovmr(:,:)        ! Nitrous oxide volume mixing ratio
                                                      ! Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: o2vmr(:,:)         ! Oxygen volume mixing ratio
                                                      ! Dimensions: (ncol,nlay)

      integer(kind=im), intent(in) :: dyofyr          ! Day of the year (used to get Earth/Sun
                                                      !  distance if adjflx not provided)
      real(kind=rb), intent(in) :: adjes              ! Flux adjustment for Earth/Sun distance
      real(kind=rb), intent(in) :: scon               ! Solar constant (W/m2)
                                                      !    Total solar irradiance averaged 
                                                      !    over the solar cycle.
                                                      !    If scon = 0.0, the internal solar 
                                                      !    constant, which depends on the  
                                                      !    value of isolvar, will be used. 
                                                      !    For isolvar=-1, scon=1368.22 Wm-2,
                                                      !    For isolvar=0,1,3, scon=1360.85 Wm-2,
                                                      !    If scon > 0.0, the internal solar
                                                      !    constant will be scaled to the 
                                                      !    provided value of scon.
      integer(kind=im), intent(in) :: isolvar         ! Flag for solar variability method
                                                      !   -1 = (when scon .eq. 0.0): No solar variability
                                                      !        and no solar cycle (Kurucz solar irradiance
                                                      !        of 1368.22 Wm-2 only);
                                                      !        (when scon .ne. 0.0): Kurucz solar irradiance
                                                      !        scaled to scon and solar variability defined
                                                      !        (optional) by setting non-zero scale factors
                                                      !        for each band in SOLVAR
                                                      !    0 = (when SCON .eq. 0.0): No solar variability 
                                                      !        and no solar cycle (NRLSSI2 solar constant of 
                                                      !        1360.85 Wm-2 for the 100-50000 cm-1 spectral 
                                                      !        range only), with facular and sunspot effects 
                                                      !        fixed to the mean of Solar Cycles 13-24;
                                                      !        (when SCON .ne. 0.0): No solar variability 
                                                      !        and no solar cycle (NRLSSI2 solar constant of 
                                                      !        1360.85 Wm-2 for the 100-50000 cm-1 spectral 
                                                      !        range only), is scaled to SCON
                                                      !    1 = Solar variability (using NRLSSI2  solar
                                                      !        model) with solar cycle contribution
                                                      !        determined by fraction of solar cycle
                                                      !        with facular and sunspot variations
                                                      !        fixed to their mean variations over the
                                                      !        average of Solar Cycles 13-24;
                                                      !        two amplitude scale factors allow
                                                      !        facular and sunspot adjustments from
                                                      !        mean solar cycle as defined by indsolvar 
                                                      !    2 = Solar variability (using NRLSSI2 solar
                                                      !        model) over solar cycle determined by 
                                                      !        direct specification of Mg (facular)
                                                      !        and SB (sunspot) indices provided
                                                      !        in indsolvar (scon = 0.0 only)
                                                      !    3 = (when scon .eq. 0.0): No solar variability
                                                      !        and no solar cycle (NRLSSI2 solar irradiance
                                                      !        of 1360.85 Wm-2 only);
                                                      !        (when scon .ne. 0.0): NRLSSI2 solar irradiance
                                                      !        scaled to scon and solar variability defined
                                                      !        (optional) by setting non-zero scale factors
                                                      !        for each band in bndsolvar
      real(kind=rb), intent(in), optional :: bndsolvar(:) ! Band scale factors for modeling spectral
                                                          ! variation of solar cycle for each shortwave band
                                                          ! for Kurucz solar constant (isolvar=-1), or
                                                          ! averaged NRLSSI2 model solar cycle (isolvar=3)
                                                          !    Dimensions: (nbndsw=14)
      real(kind=rb), intent(inout), optional :: indsolvar(:) ! Facular and sunspot amplitude 
                                                          ! scale factors (isolvar=1), or
                                                          ! Mg and SB indices (isolvar=2)
                                                          !    Dimensions: (2)
      real(kind=rb), intent(in), optional :: solcycfrac   ! Fraction of averaged solar cycle (0-1)
                                                          !    at current time (isolvar=1)

      integer(kind=im), intent(in) :: inflgsw         ! Flag for cloud optical properties
      integer(kind=im), intent(in) :: iceflgsw        ! Flag for ice particle specification
      integer(kind=im), intent(in) :: liqflgsw        ! Flag for liquid droplet specification

      real(kind=rb), intent(in) :: cldfmcl(:,:,:)     ! Cloud fraction
                                                      ! Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: taucmcl(:,:,:)     ! In-cloud optical depth (optional)
                                                      ! Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: ssacmcl(:,:,:)     ! In-cloud single scattering albedo
                                                      ! Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: asmcmcl(:,:,:)     ! In-cloud asymmetry parameter
                                                      ! Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: fsfcmcl(:,:,:)     ! In-cloud forward scattering fraction
                                                      ! Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: ciwpmcl(:,:,:)     ! In-cloud ice water path (g/m2)
                                                      ! Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: clwpmcl(:,:,:)     ! In-cloud liquid water path (g/m2)
                                                      ! Dimensions: (ngptsw,ncol,nlay)
      real(kind=rb), intent(in) :: reicmcl(:,:)       ! Cloud ice effective size (microns)
                                                      ! Dimensions: (ncol,nlay)
      real(kind=rb), intent(in) :: relqmcl(:,:)       ! Cloud water drop effective radius (microns)
                                                      ! Dimensions: (ncol,nlay)

      real(kind=rb), intent(in) :: tauaer(:,:,:)      ! Aerosol optical depth
                                                      ! Dimensions: (ncol,nlay,nbndsw)
      real(kind=rb), intent(in) :: ssaaer(:,:,:)      ! Aerosol single scattering albedo
                                                      ! Dimensions: (ncol,nlay,nbndsw)
      real(kind=rb), intent(in) :: asmaer(:,:,:)      ! Aerosol asymmetry parameter
                                                      ! Dimensions: (ncol,nlay,nbndsw)

! Atmosphere
      integer(kind=im), intent(out) :: nlayers        ! number of layers

      real(kind=rb), intent(out) :: pavel(:)          ! layer pressures (mb) 
                                                      ! Dimensions: (nlay)
      real(kind=rb), intent(out) :: tavel(:)          ! layer temperatures (K)
                                                      ! Dimensions: (nlay)
      real(kind=rb), intent(out) :: pz(0:)            ! level (interface) pressures (hPa, mb)
                                                      ! Dimensions: (0:nlay)
      real(kind=rb), intent(out) :: tz(0:)            ! level (interface) temperatures (K)
                                                      ! Dimensions: (0:nlay)
      real(kind=rb), intent(out) :: tbound            ! surface temperature (K)
      real(kind=rb), intent(out) :: pdp(:)            ! layer pressure thickness (hPa, mb)
                                                      ! Dimensions: (nlay)
      real(kind=rb), intent(out) :: coldry(:)         ! dry air column density (mol/cm2)
                                                      ! Dimensions: (nlay)
      real(kind=rb), intent(out) :: wkl(:,:)          ! molecular amounts (mol/cm-2)
                                                      ! Dimensions: (mxmol,nlay)

      real(kind=rb), intent(out) :: adjflux(:)        ! adjustment for current Earth/Sun distance
                                                      ! Dimensions: (jpband)
      real(kind=rb), intent(out) :: taua(:,:)         ! Aerosol optical depth
                                                      ! Dimensions: (nlay,nbndsw)
      real(kind=rb), intent(out) :: ssaa(:,:)         ! Aerosol single scattering albedo
                                                      ! Dimensions: (nlay,nbndsw)
      real(kind=rb), intent(out) :: asma(:,:)         ! Aerosol asymmetry parameter
                                                      ! Dimensions: (nlay,nbndsw)

! Atmosphere/clouds - cldprmc
      integer(kind=im), intent(out) :: inflag         ! flag for cloud property method
      integer(kind=im), intent(out) :: iceflag        ! flag for ice cloud properties
      integer(kind=im), intent(out) :: liqflag        ! flag for liquid cloud properties

      real(kind=rb), intent(out) :: cldfmc(:,:)       ! layer cloud fraction
                                                      ! Dimensions: (ngptsw,nlay)
      real(kind=rb), intent(out) :: taucmc(:,:)       ! in-cloud optical depth (non-delta scaled)
                                                      ! Dimensions: (ngptsw,nlay)
      real(kind=rb), intent(out) :: ssacmc(:,:)       ! in-cloud single scattering albedo (non-delta-scaled)
                                                      ! Dimensions: (ngptsw,nlay)
      real(kind=rb), intent(out) :: asmcmc(:,:)       ! in-cloud asymmetry parameter (non-delta scaled)
                                                      ! Dimensions: (ngptsw,nlay)
      real(kind=rb), intent(out) :: fsfcmc(:,:)       ! in-cloud forward scattering fraction (non-delta scaled)
                                                      ! Dimensions: (ngptsw,nlay)
      real(kind=rb), intent(out) :: ciwpmc(:,:)       ! in-cloud ice water path
                                                      ! Dimensions: (ngptsw,nlay)
      real(kind=rb), intent(out) :: clwpmc(:,:)       ! in-cloud liquid water path
                                                      ! Dimensions: (ngptsw,nlay)
      real(kind=rb), intent(out) :: relqmc(:)         ! liquid particle effective radius (microns)
                                                      ! Dimensions: (nlay)
      real(kind=rb), intent(out) :: reicmc(:)         ! ice particle effective size (microns)
                                                      ! Dimensions: (nlay)
! Solar variability
      real(kind=rb), intent(out) :: svar_f            ! Solar variability facular multiplier
      real(kind=rb), intent(out) :: svar_s            ! Solar variability sunspot multiplier
      real(kind=rb), intent(out) :: svar_i            ! Solar variability baseline irradiance multiplier
      real(kind=rb), intent(out) :: svar_f_bnd(jpband)! Solar variability facular multiplier (by band)
      real(kind=rb), intent(out) :: svar_s_bnd(jpband)! Solar variability sunspot multiplier (by band)
      real(kind=rb), intent(out) :: svar_i_bnd(jpband)! Solar variability baseline irradiance multiplier (by band)

! ----- Local -----
      real(kind=rb), parameter :: amd = 28.9660_rb    ! Effective molecular weight of dry air (g/mol)
      real(kind=rb), parameter :: amw = 18.0160_rb    ! Molecular weight of water vapor (g/mol)
!      real(kind=rb), parameter :: amc = 44.0098_rb   ! Molecular weight of carbon dioxide (g/mol)
!      real(kind=rb), parameter :: amo = 47.9998_rb   ! Molecular weight of ozone (g/mol)
!      real(kind=rb), parameter :: amo2 = 31.9999_rb  ! Molecular weight of oxygen (g/mol)
!      real(kind=rb), parameter :: amch4 = 16.0430_rb ! Molecular weight of methane (g/mol)
!      real(kind=rb), parameter :: amn2o = 44.0128_rb ! Molecular weight of nitrous oxide (g/mol)

! Set molecular weight ratios (for converting mmr to vmr)
!  e.g. h2ovmr = h2ommr * amdw)
      real(kind=rb), parameter :: amdw = 1.607793_rb  ! Molecular weight of dry air / water vapor
      real(kind=rb), parameter :: amdc = 0.658114_rb  ! Molecular weight of dry air / carbon dioxide
      real(kind=rb), parameter :: amdo = 0.603428_rb  ! Molecular weight of dry air / ozone
      real(kind=rb), parameter :: amdm = 1.805423_rb  ! Molecular weight of dry air / methane
      real(kind=rb), parameter :: amdn = 0.658090_rb  ! Molecular weight of dry air / nitrous oxide
      real(kind=rb), parameter :: amdo2 = 0.905140_rb ! Molecular weight of dry air / oxygen

      real(kind=rb), parameter :: sbc = 5.67e-08_rb   ! Stefan-Boltzmann constant (W/m2K4)

      integer(kind=im) :: isp, l, ix, n, imol, ib, ig   ! Loop indices
      real(kind=rb) :: amm, summol                      ! 
      real(kind=rb) :: adjflx                           ! flux adjustment for Earth/Sun distance
!      real(kind=rb) :: earth_sun                        ! function for Earth/Sun distance adjustment
      real(kind=rb) :: solvar(jpband)                   ! solar constant scaling factor by band
                                                        !  Dimension(jpband=29)

      real(kind=rb) :: wgt                              ! Weighting factor for amplitude scale factor adjustment
      real(kind=rb) :: svar_f_0, svar_s_0               ! Solar variability indices for current fractional
                                                        !  position in typical solar cycle, interpolated
                                                        !  from lookup table of values over solar cycle
      real(kind=rb) :: svar_cprim                       ! Solar variability intermediate value
      real(kind=rb) :: svar_r                           ! Solar variability intermediate value
      integer(kind=im) :: sfid                          ! Solar variability solar cycle fraction index
      real(kind=rb) :: tmp_a_0, tmp_b_0                 ! Solar variability temporary quantities
      real(kind=rb) :: fraclo, frachi, intfrac          ! Solar variability interpolation factors

! Mean quiet sun, facular brightening, and sunspot dimming coefficient terms (NRLSSI2, 100-50000 cm-1), 
! spectrally integrated (from hi-res values after mapping to g-point space)
      real(kind=rb), parameter :: Iint = 1360.37_rb     ! Solar quiet sun irradiance term, integrated
      real(kind=rb), parameter :: Fint = 0.996047_rb    ! Solar facular brightening term (index-offset), integrated
      real(kind=rb), parameter :: Sint = -0.511590_rb   ! Solar sunspot dimming term (index-offset), integrated
      real(kind=rb), parameter :: Foffset = 0.14959542_rb    ! Solar variability facular offset
      real(kind=rb), parameter :: Soffset = 0.00066696_rb    ! Solar variability sunspot offset

! Mg and SB indices for average solar cycle integrated over solar cycle
      real(kind=rb), parameter :: svar_f_avg = 0.1568113_rb  ! Solar variability NRLSSI2 Mg "Bremen" index 
                                                             !  time-averaged over Solar Cycles 13-24
                                                             !  and averaged over solar cycle
      real(kind=rb), parameter :: svar_s_avg = 909.21910_rb  ! Solar variability NRLSSI2 SB "SPOT67" index 
                                                             !  time-averaged over Solar Cycles 13-24
                                                             !  and averaged over solar cycle
      integer(kind=im), parameter :: nsolfrac = 132     ! Number of elements in solar arrays (12 months
                                                             !  per year over 11-year solar cycle)
      real(kind=rb) :: nsfm1_inv                        ! Inverse of (nsolfrac-1)

! Mg and SB index look-up tables for average solar cycle as a function of solar cycle
      real(kind=rb) :: mgavgcyc(nsolfrac)               ! Facular index from NRLSSI2 Mg "Bremen" index 
                                                        !  time-averaged over Solar Cycles 13-24
      real(kind=rb) :: sbavgcyc(nsolfrac)               ! Sunspot index from NRLSSI2 SB "SPOT67" index 
                                                        !  time-averaged over Solar Cycles 13-24
      mgavgcyc(:) = (/ &
        &   0.150737_rb,  0.150733_rb,  0.150718_rb,  0.150725_rb,  0.150762_rb,  0.150828_rb, &
        &   0.150918_rb,  0.151017_rb,  0.151113_rb,  0.151201_rb,  0.151292_rb,  0.151403_rb, &
        &   0.151557_rb,  0.151766_rb,  0.152023_rb,  0.152322_rb,  0.152646_rb,  0.152969_rb, &
        &   0.153277_rb,  0.153579_rb,  0.153899_rb,  0.154252_rb,  0.154651_rb,  0.155104_rb, &
        &   0.155608_rb,  0.156144_rb,  0.156681_rb,  0.157178_rb,  0.157605_rb,  0.157971_rb, &
        &   0.158320_rb,  0.158702_rb,  0.159133_rb,  0.159583_rb,  0.160018_rb,  0.160408_rb, &
        &   0.160725_rb,  0.160960_rb,  0.161131_rb,  0.161280_rb,  0.161454_rb,  0.161701_rb, &
        &   0.162034_rb,  0.162411_rb,  0.162801_rb,  0.163186_rb,  0.163545_rb,  0.163844_rb, &
        &   0.164029_rb,  0.164054_rb,  0.163910_rb,  0.163621_rb,  0.163239_rb,  0.162842_rb, &
        &   0.162525_rb,  0.162344_rb,  0.162275_rb,  0.162288_rb,  0.162369_rb,  0.162500_rb, &
        &   0.162671_rb,  0.162878_rb,  0.163091_rb,  0.163251_rb,  0.163320_rb,  0.163287_rb, &
        &   0.163153_rb,  0.162927_rb,  0.162630_rb,  0.162328_rb,  0.162083_rb,  0.161906_rb, &
        &   0.161766_rb,  0.161622_rb,  0.161458_rb,  0.161266_rb,  0.161014_rb,  0.160666_rb, &
        &   0.160213_rb,  0.159690_rb,  0.159190_rb,  0.158831_rb,  0.158664_rb,  0.158634_rb, &
        &   0.158605_rb,  0.158460_rb,  0.158152_rb,  0.157691_rb,  0.157152_rb,  0.156631_rb, &
        &   0.156180_rb,  0.155827_rb,  0.155575_rb,  0.155406_rb,  0.155280_rb,  0.155145_rb, &
        &   0.154972_rb,  0.154762_rb,  0.154554_rb,  0.154388_rb,  0.154267_rb,  0.154152_rb, &
        &   0.154002_rb,  0.153800_rb,  0.153567_rb,  0.153348_rb,  0.153175_rb,  0.153044_rb, &
        &   0.152923_rb,  0.152793_rb,  0.152652_rb,  0.152510_rb,  0.152384_rb,  0.152282_rb, &
        &   0.152194_rb,  0.152099_rb,  0.151980_rb,  0.151844_rb,  0.151706_rb,  0.151585_rb, &
        &   0.151496_rb,  0.151437_rb,  0.151390_rb,  0.151347_rb,  0.151295_rb,  0.151220_rb, &
        &   0.151115_rb,  0.150993_rb,  0.150883_rb,  0.150802_rb,  0.150752_rb,  0.150737_rb/)
      sbavgcyc(:) = (/ &
        &    50.3550_rb,   52.0179_rb,   59.2231_rb,   66.3702_rb,   71.7545_rb,   76.8671_rb, &
        &    83.4723_rb,   91.1574_rb,   98.4915_rb,  105.3173_rb,  115.1791_rb,  130.9432_rb, &
        &   155.0483_rb,  186.5379_rb,  221.5456_rb,  256.9212_rb,  291.5276_rb,  325.2953_rb, &
        &   356.4789_rb,  387.2470_rb,  422.8557_rb,  466.1698_rb,  521.5139_rb,  593.2833_rb, &
        &   676.6234_rb,  763.6930_rb,  849.1200_rb,  928.4259_rb,  994.9705_rb, 1044.2605_rb, &
        &  1087.5703_rb, 1145.0623_rb, 1224.3491_rb, 1320.6497_rb, 1413.0979_rb, 1472.1591_rb, &
        &  1485.7531_rb, 1464.1610_rb, 1439.1617_rb, 1446.2449_rb, 1496.4323_rb, 1577.8394_rb, &
        &  1669.5933_rb, 1753.0408_rb, 1821.9296_rb, 1873.2789_rb, 1906.5240_rb, 1920.4482_rb, &
        &  1904.6881_rb, 1861.8397_rb, 1802.7661_rb, 1734.0215_rb, 1665.0562_rb, 1608.8999_rb, &
        &  1584.8208_rb, 1594.0162_rb, 1616.1486_rb, 1646.6031_rb, 1687.1962_rb, 1736.4778_rb, &
        &  1787.2419_rb, 1824.9084_rb, 1835.5236_rb, 1810.2161_rb, 1768.6124_rb, 1745.1085_rb, &
        &  1748.7762_rb, 1756.1239_rb, 1738.9929_rb, 1700.0656_rb, 1658.2209_rb, 1629.2925_rb, &
        &  1620.9709_rb, 1622.5157_rb, 1623.4703_rb, 1612.3083_rb, 1577.3031_rb, 1516.7953_rb, &
        &  1430.0403_rb, 1331.5112_rb, 1255.5171_rb, 1226.7653_rb, 1241.4419_rb, 1264.6549_rb, &
        &  1255.5559_rb, 1203.0286_rb, 1120.2747_rb, 1025.5101_rb,  935.4602_rb,  855.0434_rb, &
        &   781.0189_rb,  718.0328_rb,  678.5850_rb,  670.4219_rb,  684.1906_rb,  697.0376_rb, &
        &   694.8083_rb,  674.1456_rb,  638.8199_rb,  602.3454_rb,  577.6292_rb,  565.6213_rb, &
        &   553.7846_rb,  531.7452_rb,  503.9732_rb,  476.9708_rb,  452.4296_rb,  426.2826_rb, &
        &   394.6636_rb,  360.1086_rb,  324.9731_rb,  297.2957_rb,  286.1536_rb,  287.4195_rb, &
        &   288.9029_rb,  282.7594_rb,  267.7211_rb,  246.6594_rb,  224.7318_rb,  209.2318_rb, &
        &   204.5217_rb,  204.1653_rb,  200.0440_rb,  191.0689_rb,  175.7699_rb,  153.9869_rb, &
        &   128.4389_rb,  103.8445_rb,   85.6083_rb,   73.6264_rb,   64.4393_rb,   50.3550_rb/)


! Add one to nlayers here to include extra model layer at top of atmosphere
      nlayers = nlay

!  Initialize all molecular amounts to zero here, then pass input amounts
!  into RRTM array WKL below.

      wkl(:,:) = 0.0_rb
      cldfmc(:,:) = 0.0_rb
      taucmc(:,:) = 0.0_rb
      ssacmc(:,:) = 1.0_rb
      asmcmc(:,:) = 0.0_rb
      fsfcmc(:,:) = 0.0_rb
      ciwpmc(:,:) = 0.0_rb
      clwpmc(:,:) = 0.0_rb
      reicmc(:) = 0.0_rb
      relqmc(:) = 0.0_rb
      taua(:,:) = 0.0_rb
      ssaa(:,:) = 1.0_rb
      asma(:,:) = 0.0_rb
      solvar(:) = 1.0_rb
      adjflux(:) = 1.0_rb
      svar_f = 1.0_rb 
      svar_s = 1.0_rb 
      svar_i = 1.0_rb 
      svar_f_bnd(:) = 1.0_rb 
      svar_s_bnd(:) = 1.0_rb 
      svar_i_bnd(:) = 1.0_rb 

! Adjust amplitude scaling to be 1.0 at solar min (solcycfrac=0.0229),
! to be the requested indsolvar at solar max (solcycfrac=0.3817), and
! to vary between those values at other solcycfrac. 
         if (indsolvar(1).ne.1.0_rb.or.indsolvar(2).ne.1.0_rb) then 
            if (solcycfrac.ge.0.0_rb.and.solcycfrac.lt.0.0229_rb) then
               wgt = (solcycfrac+1.0_rb-0.3817_rb)/(1.0229_rb-0.3817_rb)
               indsolvar(1) = indsolvar(1) + wgt * (1.0_rb-indsolvar(1))
               indsolvar(2) = indsolvar(2) + wgt * (1.0_rb-indsolvar(2))
            endif
            if (solcycfrac.ge.0.0229_rb.and.solcycfrac.le.0.3817_rb) then
               wgt = (solcycfrac-0.0229_rb)/(0.3817_rb-0.0229_rb)
               indsolvar(1) = 1.0_rb + wgt * (indsolvar(1)-1.0_rb)
               indsolvar(2) = 1.0_rb + wgt * (indsolvar(2)-1.0_rb)
            endif
            if (solcycfrac.gt.0.3817_rb.and.solcycfrac.le.1.0_rb) then
               wgt = (solcycfrac-0.3817_rb)/(1.0229_rb-0.3817_rb)
               indsolvar(1) = indsolvar(1) + wgt * (1.0_rb-indsolvar(1))
               indsolvar(2) = indsolvar(2) + wgt * (1.0_rb-indsolvar(2))
            endif
         endif

! Set flux adjustment for current Earth/Sun distance (two options).
! 1) Use Earth/Sun distance flux adjustment provided by GCM (input as adjes);
      adjflx = adjes
!
! 2) Calculate Earth/Sun distance from DYOFYR, the cumulative day of the year.
!    (Set adjflx to 1. to use constant Earth/Sun distance of 1 AU). 
      if (dyofyr .gt. 0) then
         adjflx = earth_sun(dyofyr)
      endif

! Apply selected solar variability option based on ISOLVAR and input 
! solar constant.
! For scon = 0, use internally defined solar constant, which is
! 1368.22 Wm-2 (for ISOLVAR=-1) and 1360.85 Wm-2 (for ISOLVAR=0,3;
! options ISOLVAR=1,2 model solar cycle variations from 1360.85 Wm-2)
!
! SCON = 0 
! Use internal TSI value
      if (scon .eq. 0.0_rb) then 

!   No solar cycle and no solar variability (Kurucz solar source function)
!   Apply constant scaling by band if first element of bndsolvar specified
         if (isolvar .eq. -1) then
            solvar(jpb1:jpb2) = 1.0_rb
            if (present(bndsolvar)) solvar(jpb1:jpb2) = bndsolvar(:)
         endif 

!   Mean solar cycle with no solar variability (NRLSSI2 model solar irradiance)
!   Quiet sun, facular, and sunspot terms averaged over the mean solar cycle 
!   (defined as average of Solar Cycles 13-24).
         if (isolvar .eq. 0) then
            svar_f = 1.0_rb
            svar_s = 1.0_rb
            svar_i = 1.0_rb
         endif 

!   Mean solar cycle with solar variability (NRLSSI2 model)
!   Facular and sunspot terms interpolated from LUTs to input solar cycle 
!   fraction for mean solar cycle. Scalings defined below to convert from 
!   averaged Mg and SB terms to Mg and SB terms interpolated here.
!   (Includes optional facular and sunspot amplitude scale factors)
         if (isolvar .eq. 1) then
!   Interpolate svar_f_0 and svar_s_0 from lookup tables using provided solar cycle fraction
            if (solcycfrac .le. 0.0_rb) then
               tmp_a_0 = mgavgcyc(1)
               tmp_b_0 = sbavgcyc(1)
            elseif (solcycfrac .ge. 1.0_rb) then
               tmp_a_0 = mgavgcyc(nsolfrac)
               tmp_b_0 = sbavgcyc(nsolfrac)
            else
               sfid = floor(solcycfrac * (nsolfrac-1)) + 1
               nsfm1_inv = 1.0_rb / (nsolfrac-1)
               fraclo = (sfid-1) * nsfm1_inv
               frachi = sfid * nsfm1_inv
               intfrac = (solcycfrac - fraclo) / (frachi - fraclo)
               tmp_a_0 = mgavgcyc(sfid) + intfrac * (mgavgcyc(sfid+1) - mgavgcyc(sfid))
               tmp_b_0 = sbavgcyc(sfid) + intfrac * (sbavgcyc(sfid+1) - sbavgcyc(sfid))
            endif
            svar_f_0 = tmp_a_0
            svar_s_0 = tmp_b_0
            svar_f = indsolvar(1) * (svar_f_0 - Foffset) / (svar_f_avg - Foffset)
            svar_s = indsolvar(2) * (svar_s_0 - Soffset) / (svar_s_avg - Soffset)
            svar_i = 1.0_rb
         endif 

!   Specific solar cycle with solar variability (NRLSSI2 model)
!   Facular and sunspot index terms input directly to model specific 
!   solar cycle.  Scalings defined below to convert from averaged
!   Mg and SB terms to specified Mg and SB terms. 
         if (isolvar .eq. 2) then
            svar_f = (indsolvar(1) - Foffset) / (svar_f_avg - Foffset)
            svar_s = (indsolvar(2) - Soffset) / (svar_s_avg - Soffset)
            svar_i = 1.0_rb
         endif 

!   Mean solar cycle with no solar variability (NRLSSI2 model)
!   Averaged facular, sunspot and quiet sun terms from mean solar cycle 
!   (derived as average of Solar Cycles 13-24). This information is built
!   into coefficient terms specified by g-point elsewhere. Separate
!   scaling by spectral band is applied as defined by bndsolvar. 
         if (isolvar .eq. 3) then
            solvar(jpb1:jpb2) = bndsolvar(:)
            do ib = jpb1,jpb2
               svar_f_bnd(ib) = solvar(ib)
               svar_s_bnd(ib) = solvar(ib)
               svar_i_bnd(ib) = solvar(ib)
            enddo
         endif 

      endif

! SCON > 0 
! Scale from internal TSI to externally specified TSI value (scon)
      if (scon .gt. 0.0_rb) then 

!   No solar cycle and no solar variability (Kurucz solar source function)
!   Scale from internal solar constant to requested solar constant.
!   Apply optional constant scaling by band if first element of bndsolvar > 0.0
         if (isolvar .eq. -1) then
            if (.not. present(bndsolvar)) solvar(jpb1:jpb2) = scon / rrsw_scon 
            if (present(bndsolvar)) solvar(jpb1:jpb2) = bndsolvar(:) * scon / rrsw_scon 
         endif 

!   Mean solar cycle with no solar variability (NRLSSI2 model solar irradiance)
!   Quiet sun, facular, and sunspot terms averaged over the mean solar cycle 
!   (defined as average of Solar Cycles 13-24).
!   Scale internal solar constant to requested solar constant. 
!!   Fint is provided as the product of (svar_f_avg-Foffset) and Fint, 
!!   Sint is provided as the product of (svar_s_avg-Soffset) and Sint
         if (isolvar .eq. 0) then
            svar_cprim = Fint + Sint + Iint
            svar_r = scon / svar_cprim
            svar_f = svar_r
            svar_s = svar_r
            svar_i = svar_r
         endif 

!   Mean solar cycle with solar variability (NRLSSI2 model)
!   Facular and sunspot terms interpolated from LUTs to input solar cycle 
!   fraction for mean solar cycle. Scalings defined below to convert from 
!   averaged Mg and SB terms to Mg and SB terms interpolated here.
!   Scale internal solar constant to requested solar constant. 
!   (Includes optional facular and sunspot amplitude scale factors)
         if (isolvar .eq. 1) then
!   Interpolate svar_f_0 and svar_s_0 from lookup tables using provided solar cycle fraction
            if (solcycfrac .le. 0.0_rb) then
               tmp_a_0 = mgavgcyc(1)
               tmp_b_0 = sbavgcyc(1)
            elseif (solcycfrac .ge. 1.0_rb) then
               tmp_a_0 = mgavgcyc(nsolfrac)
               tmp_b_0 = sbavgcyc(nsolfrac)
            else
               sfid = floor(solcycfrac * (nsolfrac-1)) + 1
               nsfm1_inv = 1.0_rb / (nsolfrac-1)
               fraclo = (sfid-1) * nsfm1_inv
               frachi = sfid * nsfm1_inv
               intfrac = (solcycfrac - fraclo) / (frachi - fraclo)
               tmp_a_0 = mgavgcyc(sfid) + intfrac * (mgavgcyc(sfid+1) - mgavgcyc(sfid))
               tmp_b_0 = sbavgcyc(sfid) + intfrac * (sbavgcyc(sfid+1) - sbavgcyc(sfid))
            endif
            svar_f_0 = tmp_a_0
            svar_s_0 = tmp_b_0
!   Define Cprime 
!            svar_cprim = indsolvar(1) * svar_f_avg * Fint + indsolvar(2) * svar_s_avg * Sint + Iint
!   Fint is provided as the product of (svar_f_avg-Foffset) and Fint, 
!   Sint is provided as the product of (svar_s_avg-Soffset) and Sint
            svar_i = (scon - (indsolvar(1) * Fint + indsolvar(2) * Sint)) / Iint
            svar_f = indsolvar(1) * (svar_f_0 - Foffset) / (svar_f_avg - Foffset)
            svar_s = indsolvar(2) * (svar_s_0 - Soffset) / (svar_s_avg - Soffset)
         endif 

!   Specific solar cycle with solar variability (NRLSSI2 model)
!   (Not available for SCON > 0)
!         if (isolvar .eq. 2) then
!            scon = 0.0_rb
!            svar_f = (indsolvar(1) - Foffset) / (svar_f_avg - Foffset)
!            svar_s = (indsolvar(2) - Soffset) / (svar_s_avg - Soffset)
!            svar_i = 1.0_rb
!         endif 

!   Mean solar cycle with no solar variability (NRLSSI2 model)
!   Averaged facular, sunspot and quiet sun terms from mean solar cycle 
!   (derived as average of Solar Cycles 13-24). This information is built
!   into coefficient terms specified by g-point elsewhere. Separate
!   scaling by spectral band is applied as defined by bndsolvar. 
!   Scale internal solar constant (svar_cprim) to requested solar constant (scon)
!   Fint is provided as the product of (svar_f_avg-Foffset) and Fint, 
!   Sint is provided as the product of (svar_s_avg-Soffset) and Sint
         if (isolvar .eq. 3) then
            svar_cprim = Fint + Sint + Iint
            if (.not. present(bndsolvar)) solvar(jpb1:jpb2) = scon / svar_cprim
            if (present(bndsolvar)) solvar(jpb1:jpb2) = bndsolvar(:) * scon / svar_cprim
            do ib = jpb1,jpb2
               svar_f_bnd(ib) = solvar(ib)
               svar_s_bnd(ib) = solvar(ib)
               svar_i_bnd(ib) = solvar(ib)
            enddo
         endif 

      endif

! Combine Earth-Sun adjustment and solar constant scaling
! when no solar variability and no solar cycle requested
      if (isolvar .lt. 0) then
         do ib = jpb1,jpb2
            adjflux(ib) = adjflx * solvar(ib)
         enddo
      endif
! Define Earth-Sun adjustment when solar variability requested
      if (isolvar .ge. 0) then
         do ib = jpb1,jpb2
            adjflux(ib) = adjflx
         enddo
      endif

!  Set surface temperature.
      tbound = tsfc(iplon)

!  Install input GCM arrays into RRTMG_SW arrays for pressure, temperature,
!  and molecular amounts.  
!  Pressures are input in mb, or are converted to mb here.
!  Molecular amounts are input in volume mixing ratio, or are converted from 
!  mass mixing ratio (or specific humidity for h2o) to volume mixing ratio
!  here. These are then converted to molecular amount (molec/cm2) below.  
!  The dry air column COLDRY (in molec/cm2) is calculated from the level 
!  pressures, pz (in mb), based on the hydrostatic equation and includes a 
!  correction to account for h2o in the layer.  The molecular weight of moist 
!  air (amm) is calculated for each layer.  
!  Note: In RRTMG, layer indexing goes from bottom to top, and coding below
!  assumes GCM input fields are also bottom to top. Input layer indexing
!  from GCM fields should be reversed here if necessary.

      pz(0) = plev(iplon,1)
      tz(0) = tlev(iplon,1)
      do l = 1, nlayers
         pavel(l) = play(iplon,l)
         tavel(l) = tlay(iplon,l)
         pz(l) = plev(iplon,l+1)
         tz(l) = tlev(iplon,l+1)
         pdp(l) = pz(l-1) - pz(l)
! For h2o input in vmr:
         wkl(1,l) = h2ovmr(iplon,l)
! For h2o input in mmr:
!         wkl(1,l) = h2o(iplon,l)*amdw
! For h2o input in specific humidity;
!         wkl(1,l) = (h2o(iplon,l)/(1._rb - h2o(iplon,l)))*amdw
         wkl(2,l) = co2vmr(iplon,l)
         wkl(3,l) = o3vmr(iplon,l)
         wkl(4,l) = n2ovmr(iplon,l)
         wkl(6,l) = ch4vmr(iplon,l)
         wkl(7,l) = o2vmr(iplon,l)
         amm = (1._rb - wkl(1,l)) * amd + wkl(1,l) * amw            
         coldry(l) = (pz(l-1)-pz(l)) * 1.e3_rb * avogad / &
                     (1.e2_rb * grav * amm * (1._rb + wkl(1,l)))
      enddo

! The following section can be used to set values for an additional layer (from
! the GCM top level to 1.e-4 mb) for improved calculation of TOA fluxes. 
! Temperature and molecular amounts in the extra model layer are set to 
! their values in the top GCM model layer, though these can be modified
! here if necessary. 
! If this feature is utilized, increase nlayers by one above, limit the two
! loops above to (nlayers-1), and set the top most (nlayers) layer values here. 

!      pavel(nlayers) = 0.5_rb * pz(nlayers-1)
!      tavel(nlayers) = tavel(nlayers-1)
!      pz(nlayers) = 1.e-4_rb
!      tz(nlayers-1) = 0.5_rb * (tavel(nlayers)+tavel(nlayers-1))
!      tz(nlayers) = tz(nlayers-1)
!      pdp(nlayers) = pz(nlayers-1) - pz(nlayers)
!      wkl(1,nlayers) = wkl(1,nlayers-1)
!      wkl(2,nlayers) = wkl(2,nlayers-1)
!      wkl(3,nlayers) = wkl(3,nlayers-1)
!      wkl(4,nlayers) = wkl(4,nlayers-1)
!      wkl(6,nlayers) = wkl(6,nlayers-1)
!      wkl(7,nlayers) = wkl(7,nlayers-1)
!      amm = (1._rb - wkl(1,nlayers-1)) * amd + wkl(1,nlayers-1) * amw
!      coldry(nlayers) = (pz(nlayers-1)) * 1.e3_rb * avogad / &
!                        (1.e2_rb * grav * amm * (1._rb + wkl(1,nlayers-1)))

! At this point all molecular amounts in wkl are in volume mixing ratio; 
! convert to molec/cm2 based on coldry for use in rrtm.  

      do l = 1, nlayers
         do imol = 1, nmol
            wkl(imol,l) = coldry(l) * wkl(imol,l)
         enddo
      enddo

! Transfer aerosol optical properties to RRTM variables;
! modify to reverse layer indexing here if necessary.

      if (iaer .ge. 1) then 
         do l = 1, nlayers
            do ib = 1, nbndsw
               taua(l,ib) = tauaer(iplon,l,ib)
               ssaa(l,ib) = ssaaer(iplon,l,ib)
               asma(l,ib) = asmaer(iplon,l,ib)
            enddo
         enddo
      endif

! Transfer cloud fraction and cloud optical properties to RRTM variables;
! modify to reverse layer indexing here if necessary.

      if (icld .ge. 1) then 
         inflag = inflgsw
         iceflag = iceflgsw
         liqflag = liqflgsw

! Move incoming GCM cloud arrays to RRTMG cloud arrays.
! For GCM input, incoming reicmcl is defined based on selected ice parameterization (inflglw)

         do l = 1, nlayers
            do ig = 1, ngptsw
               cldfmc(ig,l) = cldfmcl(ig,iplon,l)
               taucmc(ig,l) = taucmcl(ig,iplon,l)
               ssacmc(ig,l) = ssacmcl(ig,iplon,l)
               asmcmc(ig,l) = asmcmcl(ig,iplon,l)
               fsfcmc(ig,l) = fsfcmcl(ig,iplon,l)
               ciwpmc(ig,l) = ciwpmcl(ig,iplon,l)
               clwpmc(ig,l) = clwpmcl(ig,iplon,l)
            enddo
            reicmc(l) = reicmcl(iplon,l)
            relqmc(l) = relqmcl(iplon,l)
         enddo

! If an extra layer is being used in RRTMG, set all cloud properties to zero in the extra layer.

!         cldfmc(:,nlayers) = 0.0_rb
!         taucmc(:,nlayers) = 0.0_rb
!         ssacmc(:,nlayers) = 1.0_rb
!         asmcmc(:,nlayers) = 0.0_rb
!         fsfcmc(:,nlayers) = 0.0_rb
!         ciwpmc(:,nlayers) = 0.0_rb
!         clwpmc(:,nlayers) = 0.0_rb
!         reicmc(nlayers) = 0.0_rb
!         relqmc(nlayers) = 0.0_rb
      
      endif

      end subroutine inatm_sw

      end module rrtmg_sw_rad


