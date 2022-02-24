#!/bin/bash

###########################################################################
## Script to build UFS Short-Range Weather Application (UFS SRW App)     ##
##                                                                       ##
## Usage:                                                                ##
##  1. Non-coupled (FV3 stand-alone) regional modeling:                  ##
##             ./build_srw_app.sh                                        ##
##        or   ./build_srw_app.sh "FV3"                                  ##
##                                                                       ##
##  2. Coupled regional air quality modeling (RRFS-CMAQ):                ##
##             ./build_srw_app.sh "AQM"                                  ##
##                                                                       ##
###########################################################################

set -eu

if [[ $(uname -s) == Darwin ]]; then
  readonly MYDIR=$(cd "$(dirname "$(greadlink -f -n "${BASH_SOURCE[0]}" )" )" && pwd -P)
else
  readonly MYDIR=$(cd "$(dirname "$(readlink -f -n "${BASH_SOURCE[0]}" )" )" && pwd -P)
fi

SRW_APP_DIR="${MYDIR}"
AQM_DIR="${SRW_APP_DIR}/AQM"
BUILD_DIR="${SRW_APP_DIR}/build"
EXEC_DIR="${SRW_APP_DIR}/bin"
LIB_DIR="${SRW_APP_DIR}/lib"
MOD_DIR="${SRW_APP_DIR}/env"
SORC_DIR="${SRW_APP_DIR}/src"

###########################################################################
## User specific parameters                                              ##
###########################################################################
##
## Forecast model options ("FV3" or "AQM")
##    FV3  : FV3 stand-alone
##    AQM  : FV3 + AQM
##
FCST_opt="${1:-FV3}"
##
## Clean option ("YES" or not)
##    YES : clean build-related directories (bin,build,include,lib,share)
##
clean_opt="YES"
##
## Compiler
##
export COMPILER="intel"
##
## Flag for building components
##
clone_externals="YES"
build_app_base="YES"
build_app_add_aqm="YES"
##
###########################################################################

echo "Forecast model option     :" ${FCST_opt}
echo "Clean option              :" ${clean_opt}
echo "Compiler                  :" ${COMPILER}
echo "Build srw app             :" ${build_app_base}
echo "Build extra comp. for AQM :" ${build_app_add_aqm}

if [ "${clone_externals}" = "YES" ]; then
  clean_opt="YES"
fi

if [ "${clean_opt}" = "YES" ]; then
  rm -rf ${EXEC_DIR}
  rm -rf ${BUILD_DIR}
  rm -rf ${SRW_APP_DIR}/include
  rm -rf ${LIB_DIR}
  rm -rf ${SRW_APP_DIR}/share
fi

# detect PLATFORM (MACHINE)
source ${MOD_DIR}/detect_machine.sh

# Check out the external components
if [ "${clone_externals}" = "YES" ]; then
  echo "... Checking out the external components ..."
  if [ "${FCST_opt}" = "FV3" ]; then
    ./manage_externals/checkout_externals
  elif [ "${FCST_opt}" = "AQM" ]; then
    ./manage_externals/checkout_externals -e ${AQM_DIR}/Externals.cfg
  else
    echo "Fatal Error: forecast model is not on the list."
    exit 1
  fi
fi

# CMAKE settings
CMAKE_SETTINGS="-DCMAKE_INSTALL_PREFIX=${SRW_APP_DIR}"
#if [ "${FCST_opt}" = "AQM" ]; then
#  CMAKE_SETTINGS="${CMAKE_SETTINGS} -DAQM=ON"
#fi

# Make build directory
mkdir -p ${BUILD_DIR}
cd ${BUILD_DIR}

##### Build UFS SRW App ##################################################
if [ "${build_app_base}" = "YES" ]; then
  echo "... Load environment file ..."
  MOD_FILE="${MOD_DIR}/build_${PLATFORM}_${COMPILER}.env"
  module use ${MOD_DIR}
  . ${MOD_FILE}
  module list

  echo "... Generate CMAKE configuration ..."
  cmake ${SRW_APP_DIR} ${CMAKE_SETTINGS} 2>&1 | tee log.cmake.app
  echo "... Compile executables ..."
  make -j8 2>&1 | tee log.make.app
  echo "... App build completed ..."
fi

##### Build extra components for AQM #####################################
if [ "${FCST_opt}" = "FV3" ]; then
  build_app_add_aqm="NO"
fi
if [ "${build_app_add_aqm}" = "YES" ]; then
  echo "... Load environment file for extra AQM components ..."
  MOD_FILE="${MOD_DIR}/build_aqm_${PLATFORM}_${COMPILER}"
  module purge
  module use ${MOD_DIR}
  source ${MOD_FILE}
  module list

  cd ${AQM_DIR}
  ## ARL-NEXUS
  echo "... Build ARL-NEXUS ..."
  ./build_nexus.sh

  ## GEFS2CLBC
  echo "... Build gefs2clbc-para ..."
  ./build_gefs2clbc.sh

fi

exit 0