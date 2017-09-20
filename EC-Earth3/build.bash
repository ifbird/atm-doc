#!/bin/bash

# EC-EARTH3
# =========
#
# Cray XC40 sisu.csc.fi, Cray compiler suite
# jukka-pekka.keskinen@helsinki.fi, juha.lento@csc.fi
# 2017-09-03

# Usage
# -----
#
# To simply execute everything automatically:
#     bash install.bash
#
# Just to set up current environment and define functions for running funtions one by one (development/debugging)
#     source install.bash

# Requires
# --------
# File 'config-build.xml' (with sisu-cray-craympi platform)



### Script stuff that needs to be executed first ###

[ "$0" != "$BASH_SOURCE" ] && sourced=true || sourced=false
${sourced} || set -e
thisdir=$(readlink -f $(dirname $BASH_SOURCE))



### Local/user defaults ###

: ${SVNUSER:=juha.lento}
: ${BRANCH:=trunk}
: ${REVNO:=} #leave blank to get the latest
: ${BLDROOT:=$TMPDIR/ece3}
: ${INSTALLROOT:=$USERAPPL/ece3}
: ${RUNROOT:=$WRKDIR}



### Helper functions ###

remove-path () {
    local a
    IFS=':' eval 'a=(${!2})'
    a=( $(for e in "${a[@]}"; do [ "$e" == "$1" ] || echo "$e"; done) )
    IFS=':' eval "$2=\"\${a[*]}\""
}

append-path () {
    remove-path $1 $2
    eval "$2=${!2}:$1"
}

module-set () {
    conflicts=$(awk '/^conflict/{print $2}' <(module show $* 2>&1))
    module unload $conflicts
    module load $*
}

# next-file () {
#     fname=$1
#     if [ -f "$fname" ]; then
# 	[[ "$fname" =~ ^(.+)\.([0-9]+)$ ]]
# 	if [ -n "${BASH_REMATCH[2]}" ]; then
# 	    echo "${BASH_REMATCH[1]}.$(( BASH_REMATCH[2] + 1 ))"
# 	else
# 	    echo "$fname.0"
# 	fi
#     else
# 	echo "$fname"
#     fi
# }

# backup-copy () {
#     local fname=$1
#     local nextfile=$(next-file $fname)
#     if [ -f $fname ]; then
# 	backup-copy $nextfile && rm -f $nextfile && cp -p $fname $nextfile
#     fi
# }

expand-variables () {
    local infile="$1"
    local outfile="$2"
    local tmpfile="$(mktemp)"
    eval 'echo "'"$(sed 's/\\/\\\\/g;s/\"/\\\"/g' $infile)"'"' > "$tmpfile"
    if ! diff -s "$outfile" "$tmpfile" &> /dev/null; then
	VERSION_CONTROL=t \cp -f --backup "$tmpfile" "$outfile"
    fi
}



### EC-EARTH3 related functions ###


updatesources () {
    local optional_revision="$1"
    [ "$optional_revision" ] && local revflag="-r $optional_revision"
    mkdir -p $BLDROOT
    cd $BLDROOT
    if [ -d "$BRANCH" ]; then
	cd $BRANCH
	svn update $revflag
    else
	svn --username $SVNUSER checkout $revflag https://svn.ec-earth.org/ecearth3/$BRANCH $BRANCH
    fi
}

ecconfig () {
    cd ${BLDROOT}/${BRANCH}/sources
    expand-variables ${thisdir}/config-build-sisu-cray-craympi.xml config-build.xml
    ./util/ec-conf/ec-conf --platform=sisu-cray-craympi config-build.xml
}

oasis () {
    cd ${BLDROOT}/${BRANCH}/sources/oasis3-mct/util/make_dir
    FCLIBS=" " make -f TopMakefileOasis3 BUILD_ARCH=ecconf
}

#lucia() {
#    cd ${BLDROOT}/${BRANCH}/sources/oasis3-mct/util/lucia
#    lucia -c
#}

xios () {
    cd ${BLDROOT}/${BRANCH}/sources/xios-2
    svn export http://forge.ipsl.jussieu.fr/ioserver/svn/XIOS/trunk/arch/arch-XC30_Cray.fcm arch/arch-ecconf.fcm
    sed -i -e 's/^%PROD_CFLAGS.*/%PROD_CFLAGS    -O2 -DBOOST_DISABLE_ASSERTS/' \
	   -e 's/^%PROD_FFLAGS.*/%PROD_FFLAGS    -O2 -J..\/inc/' arch/arch-ecconf.fcm
    ./make_xios --arch ecconf --job 8
#    cd obj
#    for s in idomain_attr idomaingroup_attr ifile_attr ifield_attr ifieldgroup_attr igrid_attr igridgroup_attr idata icalendar_wrapper_attr icalendar_wrapper_attr ; do
#	ftn -o $s.o -J../inc -I/tmp/jlento/ece3/trunk/sources/xios-2/inc -em -m 4 -e0 -eZ -O2 -c /tmp/jlento/ece3/trunk/sources/xios-2/ppsrc/interface/fortran_attr/$s.f90
#    done
#    cd -
#     ./make_xios --arch ecconf --job 8
}

nemo () {
    cd ${BLDROOT}/${BRANCH}/sources/nemo-3.6/CONFIG
    ./makenemo -n ORCA1L75_LIM3 -m ecconf

    # Build of statically linked nemo appears to be broken...
    #./makenemo -n ORCA1L75_LIM3 -m ecconf -j 4
    #cd $EC3SOURCES/nemo-3.6/CONFIG/ORCA1L75_LIM3/BLD/obj
    #ar curv lib__fcm__nemo.a *.o
    #ar d lib__fcm__nemo.a nemo.o
    #mv lib__fcm__nemo.a ../lib
    #cd $EC3SOURCES/nemo-3.6/CONFIG/ORCA1L75_LIM3/BLD/bin
    #ftn -o nemo.exe ../obj/nemo.o -L../lib -l__fcm__nemo -O2 -fp-model strict -r8 -L${EC3SOURCES}/xios-2/lib -lxios -lstdc++ -L${EC3SOURCES}/oasis3-mct/ecconf/lib -lpsmile.MPI1 -lmct -lmpeu -lscrip -lnetcdff -lnetcdf
}

oifs () {
    cd ${BLDROOT}/${BRANCH}/sources/ifs-36r4

    # These are clear bugs...
    patch -f -p0 <<'EOF'
--- src/ifsaux/module/stack_mix.F90.orig	2017-09-08 12:28:59.000000000 +0300
+++ src/ifsaux/module/stack_mix.F90	        2017-09-08 12:38:59.000000000 +0300
@@ -2,6 +2,7 @@
 
 USE PARKIND1  ,ONLY : JPIM     ,JPRB     ,JPIB
 USE YOMHOOK   ,ONLY : LHOOK,   DR_HOOK
+USE ISO_C_BINDING ,ONLY : C_LONG_LONG
 
 IMPLICIT NONE
 
@@ -47,13 +48,13 @@
   
 SUBROUTINE GETSTACKUSAGEB(K)
 INTEGER(KIND=JPIB),INTENT(OUT) :: K
-INTEGER(KIND=JPIB) :: GETSTACKUSAGE
+INTEGER(KIND=C_LONG_LONG) :: GETSTACKUSAGE
 K=GETSTACKUSAGE()
 END SUBROUTINE GETSTACKUSAGEB
 
 SUBROUTINE GETSTACKUSAGEM(K)
 INTEGER(KIND=JPIB),INTENT(OUT) :: K
-INTEGER(KIND=JPIM) :: GETSTACKUSAGE
+INTEGER(KIND=C_LONG_LONG) :: GETSTACKUSAGE
 K=GETSTACKUSAGE()
 END SUBROUTINE GETSTACKUSAGEM
 
--- src/ifs/module/varbc_setup.F90.orig	2017-09-08 12:51:53.000000000 +0300
+++ src/ifs/module/varbc_setup.F90	2017-09-08 12:52:19.000000000 +0300
@@ -149,7 +149,7 @@
 ! Arrays for parallel summation
 ! -----------------------------
 REAL(KIND=JPRB),    ALLOCATABLE :: aparams_comp(:,:,:)   ! aparams partial sum 
-REAL(KIND=JPRB),    ALLOCATABLE :: nparams_comp(:,:)     ! aparams number of terms
+INTEGER(KIND=JPIM), ALLOCATABLE :: nparams_comp(:,:)     ! aparams number of terms
 INTEGER(KIND=JPIM), ALLOCATABLE :: nhstfgdep_comp(:,:,:) ! nhstfgdep partial sum
 
 !-----------------------------------------------------------------------
EOF

    make BUILD_ARCH=ecconf -j 8 lib
    make BUILD_ARCH=ecconf master

    # And here is something fishy going on with the build system...
    touch $(make BUILD_ARCH=ecconf master | grep -o '^[^:]*\.F90:' | tr -d ':' | sort -u)
    make BUILD_ARCH=ecconf master
}


tm5 () {
    cd ${BLDROOT}/${BRANCH}/sources/tm5mp
    export PATH=${BLDROOT}/${BRANCH}/sources/util/makedepf90/bin:$PATH
    ./setup_tm5 -n -j 4 ecconfig-ecearth3.rc
    # Cray compiler internal error with -O2...
    cd build
    ftn -c -o ebischeme.o -h flex_mp=strict -h noomp -sreal64 -N 1023 -O1 -I/tmp/jlento/ece3/trunk/sources/oasis3-mct/ecconf/build/lib/psmile.MPI1 -I/opt/cray/netcdf-hdf5parallel/4.4.1/CRAY/8.3/include -I/opt/cray/hdf5-parallel/1.10.0.1/CRAY/8.3/include  ebischeme.F90
    cd -
    ./setup_tm5 -j 4 ecconfig-ecearth3.rc
}

runoff-mapper () {
    cd ${BLDROOT}/${BRANCH}/sources/runoff-mapper/src
    make
}

amip-forcing () {
    cd $EC3SOURCES/amip-forcing/src
    make
}

# Install
install_all () {
    cd $EC3SOURCES
    mkdir -p ${INSTALL_BIN}
    cp -f  \
	$EC3SOURCES/xios-2/bin/xios_server.exe \
	$EC3SOURCES/nemo-3.6/CONFIG/ORCA1L75_LIM3/BLD/bin/nemo.exe \
	$EC3SOURCES/ifs-36r4/bin/ifsmaster-ecconf \
	$EC3SOURCES/runoff-mapper/bin/runoff-mapper.exe \
	$EC3SOURCES/amip-forcing/bin/amip-forcing.exe \
	$EC3SOURCES/tm5mp/build/appl-tm5.x \
	/appl/climate/bin/cdo \
	$EC3SOURCES/oasis3-mct/util/lucia/lucia.exe \
	$EC3SOURCES/oasis3-mct/util/lucia/lucia \
	$EC3SOURCES/oasis3-mct/util/lucia/balance.gnu \
	${INSTALL_BIN}
}

# Create run directory and fix stuff

create_ece_run () {
    cd $WRKDIR
    mkdir -p $ECERUNTIME
    cp -fr $BDIR/$EC3/runtime/* $ECERUNTIME/
    cp -f $SCRIPTDIR/sisu.cfg.tmpl $ECERUNTIME/classic/platform/
    cd $ECERUNTIME
    cp classic/ece-esm.sh.tmpl classic/ece-ifs+nemo+tm5.sh.tmpl
    sed "s|THIS_NEEDS_TO_BE_CHANGED|${INSTALL_BIN}|" $SCRIPTDIR/rundir.patch | patch -u -p0
    mkdir -p $ECERUNTIME/tm5mp
    cd $ECERUNTIME/tm5mp
    cp -rf $EC3SOURCES/tm5mp/rc .
    cp -fr $EC3SOURCES/tm5mp/bin .
    cp -fr $EC3SOURCES/tm5mp/build .
    ln -s bin/pycasso_setup_tm5 setup_tm5
}

apply_ECE_mods() {
    cd $EC3SOURCES
    patch -u -p0 < $SCRIPTDIR/$1
}

module use --append /appl/climate/modulefiles
module load cray-hdf5-parallel cray-netcdf-hdf5parallel grib_api/1.23.1 hdf/4.2.12 libemos/4.0.7


### Execute the functions if this script is not sourced ###

if [ "$notsourced" ]; then

    updatesources

#    if [ $# -eq 1 ]; then
#	( apply_ECE_mods $1 2>&1 ) > $BDIR/$EC3/modifications.log
#    fi

    # { module list -t 2>&1 } > $BDIR/$EC3/modules.log
    # { ecconfig       2>&1 } > $BDIR/$EC3/ecconf.log
    # { oasis    2>&1 } > $BDIR/$EC3/oasis.log    &
    # wait
    # { compile_lucia    2>&1 } > $BDIR/$EC3/lucia.log    &
    # { xios     2>&1 } > $BDIR/$EC3/xios.log &
    # { tm5      2>&1 } > $BDIR/$EC3/tm5.log  &
    # wait
    # { oifs     2>&1 } > $BDIR/$EC3/ifs.log &
    # { nemo     2>&1 } > $BDIR/$EC3/nemo.log &
    # { runoff   2>&1 } > $BDIR/$EC3/runoff.log &
    # wait
    # { amipf    2>&1 } > $BDIR/$EC3/amipf.log &
    # wait
    # install_all
    # create_ece_run
fi