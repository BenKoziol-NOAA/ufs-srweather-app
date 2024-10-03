#!/usr/bin/env bash

#
#-----------------------------------------------------------------------
#
# This ex-script is responsible for creating orography files for the FV3
# forecast.
#
# The output of this script is placed in a directory defined by OROG_DIR
#
# More about the orog for the regional configuration of the FV3:
#
#    a) Only the tile 7 orography file is created.
#
#    b) This orography file contains a halo of the same width (NHW)
#       as the grid file for tile 7 generated by the make_grid script
#
#    c) Filtered versions of the orogoraphy files are created with the
#       same width (NHW) as the unfiltered orography file and the grid
#       file. FV3 requires two filtered orography files, one with no
#       halo cells and one with 4 halo cells.
#
# This script does the following:
#
#   - Create the raw orography files by running the orog executable.
#   - Run the orog_gsl executable if any of several GSL-developed
#     physics suites is chosen by the user.
#   - Run the filter_topo executable on the raw orography files
#   - Run the shave executable for the 0- and 4-cell halo orography
#     files
#
#-----------------------------------------------------------------------
#

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. ${PARMsrw}/source_util_funcs.sh
task_global_vars=( "KMP_AFFINITY_MAKE_OROG" "OMP_NUM_THREADS_MAKE_OROG" \
  "OMP_STACKSIZE_MAKE_OROG" "PRE_TASK_CMDS" "RUN_CMD_SERIAL" \
  "CRES" "DOT_OR_USCORE" "FIXlam" "DO_SMOKE_DUST" "FIXorg" "TILE_RGNL" \
  "NHW" "CCPP_PHYS_SUITE" "NH0" "OROG_DIR" "GRID_GEN_METHOD" \
  "STRETCH_FAC" )
for var in ${task_global_vars[@]}; do
  source_config_for_task ${var} ${GLOBAL_VAR_DEFNS_FP}
done
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; set -xue; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( $READLINK -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )

print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that generates orography files.
========================================================================"
#
#-----------------------------------------------------------------------
#
# Set OpenMP variables.  The orog executable runs with OMP.
#
#-----------------------------------------------------------------------
#
export KMP_AFFINITY=${KMP_AFFINITY_MAKE_OROG}
export OMP_NUM_THREADS=${OMP_NUM_THREADS_MAKE_OROG}
export OMP_STACKSIZE=${OMP_STACKSIZE_MAKE_OROG}

eval ${PRE_TASK_CMDS}

if [ -z "${RUN_CMD_SERIAL:-}" ] ; then
  print_err_msg_exit "\
  Run command was not set in machine file. \
  Please set RUN_CMD_SERIAL for your platform"
else
  print_info_msg "All executables will be submitted with \'${RUN_CMD_SERIAL}\'."
fi
#
#-----------------------------------------------------------------------
#
# Create sub-directories for the various steps and substeps in this script.
#
#-----------------------------------------------------------------------
#
raw_dir="${DATA}/raw_topo"
mkdir -p ${raw_dir}

filter_dir="${DATA}/filtered_topo"
mkdir -p ${filter_dir}

shave_dir="${DATA}/shave_tmp"
mkdir -p ${shave_dir}

tmp_orog_data="${DATA}/tmp_orog_data"
mkdir -p "${tmp_orog_data}"

tmp_dir="${raw_dir}/tmp"
mkdir -p ${tmp_dir}
cd ${tmp_dir}
#
#-----------------------------------------------------------------------
#
# Get the grid file info from the mosaic file
#
#-----------------------------------------------------------------------
#
mosaic_fn="${CRES}${DOT_OR_USCORE}mosaic.halo${NHW}.nc"
mosaic_fp="${FIXlam}/${mosaic_fn}"

grid_fn=$( get_charvar_from_netcdf "${mosaic_fp}" "gridfiles" ) || print_err_msg_exit "\
  get_charvar_from_netcdf function failed."
grid_fp="${FIXlam}/${grid_fn}"
#
#-----------------------------------------------------------------------
#
# Set input parameters for the orog executable in a formatted text file.
# The executable takes its parameters via the command line.
# 
# Since Smoke/Dust uses the production branch of ufs-weather-model/UFS_UTILS,
# the old version of files and input namelist are necessary. Once they are
# updated, this if-statement should be updated accordingly
#
#-----------------------------------------------------------------------
#
if [ $(boolify "${DO_SMOKE_DUST}") = "TRUE" ]; then
  # Copy topography and related data files from FIXorg
  cp -p ${FIXorg}/thirty.second.antarctic.new.bin ${tmp_dir}/fort.15
  cp -p ${FIXorg}/landcover30.fixed ${tmp_dir}
  cp -p ${FIXorg}/gmted2010.30sec.int ${tmp_dir}/fort.235

  mtnres=1
  lonb=0
  latb=0
  jcap=0
  NR=0
  NF1=0
  NF2=0
  efac=0
  blat=0
  input_redirect_fn="INPS"
  orogfile="none"

  echo $mtnres $lonb $latb $jcap $NR $NF1 $NF2 $efac $blat > "${input_redirect_fn}"
  echo "\"${grid_fp}\"" >> "${input_redirect_fn}"
  echo "\"$orogfile\"" >> "${input_redirect_fn}"
  echo ".false." >> "${input_redirect_fn}" #MASK_ONLY
  echo "none" >> "${input_redirect_fn}" #MERGE_FILE
  cat "${input_redirect_fn}"

# for recent version of ufs_utils
else
  # Copy topography and related data files from FIXorg
  cp -p ${FIXorg}/topography.antarctica.ramp.30s.nc ${tmp_dir}
  cp -p ${FIXorg}/landcover.umd.30s.nc ${tmp_dir}
  cp -p ${FIXorg}/topography.gmted2010.30s.nc ${tmp_dir}

  input_redirect_fn="INPS"
  orogfile="none"

  echo "\"${grid_fp}\"" >> "${input_redirect_fn}"
  echo ".false." >> "${input_redirect_fn}" #MASK_ONLY
  echo "none" >> "${input_redirect_fn}" #MERGE_FILE
  cat "${input_redirect_fn}"
fi
#
#-----------------------------------------------------------------------
#
# Call the executable to generate the raw orography file corresponding
# to tile 7 (the regional domain) only.
#
# The script moves the output file from its temporary directory to the
# OROG_DIR and names it:
#
#   ${CRES}_raw_orog.tile7.halo${NHW}.nc
#
# Note that this file will include orography for a halo of width NHW
# cells around tile 7.
#
#-----------------------------------------------------------------------
#
print_info_msg "Starting orography file generation..."

export pgm="orog"
. prep_step

eval ${RUN_CMD_SERIAL} ${EXECsrw}/$pgm < "${input_redirect_fn}" >>$pgmout 2>errfile
export err=$?; err_chk
mv errfile ${DATA}/errfile_orog
#
# Change location to the original directory.
#
cd ${DATA}
#
#-----------------------------------------------------------------------
#
# Move the raw orography file and rename it.
#
#-----------------------------------------------------------------------
#
raw_orog_fp_orig="${tmp_dir}/out.oro.nc"
raw_orog_fn_prefix="${CRES}${DOT_OR_USCORE}raw_orog"
fn_suffix_with_halo="tile${TILE_RGNL}.halo${NHW}.nc"
raw_orog_fn="${raw_orog_fn_prefix}.${fn_suffix_with_halo}"
raw_orog_fp="${raw_dir}/${raw_orog_fn}"
mv "${raw_orog_fp_orig}" "${raw_orog_fp}"
#
#-----------------------------------------------------------------------
#
# Call the orog_gsl executable to generate the two orography statistics
# files (large- and small-scale) needed for the drag suite in certain
# GSL physics suites.
#
#-----------------------------------------------------------------------
#
suites=( "FV3_RAP" "FV3_HRRR" "FV3_HRRR_gf" "FV3_GFS_v17_p8" )
if [[ ${suites[@]} =~ "${CCPP_PHYS_SUITE}" ]] ; then
  cd ${tmp_orog_data}
  mosaic_fn_gwd="${CRES}${DOT_OR_USCORE}mosaic.halo${NH4}.nc"
  mosaic_fp_gwd="${FIXlam}/${mosaic_fn_gwd}"
  grid_fn_gwd=$( get_charvar_from_netcdf "${mosaic_fp_gwd}" "gridfiles" ) || \
    print_err_msg_exit "get_charvar_from_netcdf function failed."
  grid_fp_gwd="${FIXlam}/${grid_fn_gwd}"
  ls_fn="geo_em.d01.lat-lon.2.5m.HGT_M.nc"
  ss_fn="HGT.Beljaars_filtered.lat-lon.30s_res.nc"
  ln -nsf ${grid_fp_gwd} ${tmp_orog_data}/${grid_fn_gwd}
  ln -nsf ${FIXam}/${ls_fn} ${tmp_orog_data}/${ls_fn}
  ln -nsf ${FIXam}/${ss_fn} ${tmp_orog_data}/${ss_fn}

  input_redirect_fn="grid_info.dat"
  cat > "${input_redirect_fn}" <<EOF
${TILE_RGNL}
${CRES:1}
${NH4}
EOF

  print_info_msg "Starting orography file generation..."

  export pgm="orog_gsl"
  . prep_step

  eval ${RUN_CMD_SERIAL} ${EXECsrw}/$pgm < "${input_redirect_fn}" >>$pgmout 2>errfile
  export err=$?; err_chk
  mv errfile ${DATA}/errfile_orog_gsl

  mv "${CRES}${DOT_OR_USCORE}oro_data_ss.tile${TILE_RGNL}.halo${NH0}.nc" \
     "${CRES}${DOT_OR_USCORE}oro_data_ls.tile${TILE_RGNL}.halo${NH0}.nc" \
     "${OROG_DIR}" 
fi
#
#-----------------------------------------------------------------------
#
# Note that the orography filtering code assumes that the regional grid
# is a GFDLgrid type of grid; it is not designed to handle ESGgrid type
# regional grids.  If the flag "regional" in the orography filtering
# namelist file is set to .TRUE. (which it always is will be here; see
# below), then filtering code will first calculate a resolution (i.e.
# number of grid points) value named res_regional for the assumed GFDLgrid
# type regional grid using the formula
#
#   res_regional = res*stretch_fac*real(refine_ratio)
#
# Here res, stretch_fac, and refine_ratio are the values passed to the
# code via the namelist.  res and stretch_fac are assumed to be the
# resolution (in terms of number of grid points) and the stretch factor
# of the (GFDLgrid type) regional grid's parent global cubed-sphere grid,
# and refine_ratio is the ratio of the number of grid cells on the regional
# grid to a single cell on tile 6 of the parent global grid.  After
# calculating res_regional, the code interpolates/extrapolates between/
# beyond a set of (currently 7) resolution values for which the four
# filtering parameters (n_del2_weak, cd4, max_slope, peak_fac) are provided
# (by GFDL) to obtain the corresponding values of these parameters at a
# resolution of res_regional.  These interpolated/extrapolated values are
# then used to perform the orography filtering.
#
# To handle ESGgrid type grids, we set res in the namelist to the
# orography filtering code the equivalent global uniform cubed-sphere
# resolution of the regional grid, we set stretch_fac to 1 (since the
# equivalent resolution assumes a uniform global grid), and we set
# refine_ratio to 1.  This will cause res_regional above to be set to
# the equivalent global uniform cubed-sphere resolution, so the
# filtering parameter values will be interpolated/extrapolated to that
# resolution value.
#
#-----------------------------------------------------------------------
#
if [ "${GRID_GEN_METHOD}" = "GFDLgrid" ]; then
  res="${GFDLgrid_NUM_CELLS}"
  refine_ratio="${GFDLgrid_REFINE_RATIO}"
elif [ "${GRID_GEN_METHOD}" = "ESGgrid" ]; then
  res="${CRES:1}"
  refine_ratio="1"
fi
#
#-----------------------------------------------------------------------
#
# The filter_topo program overwrites its input file with filtered
# output, which is specified by topo_file in the namelist, but with a
# suffix ".tile7.nc" for the regional configuration. To avoid
# overwriting the output of the orog program, copy its output file to
# the filter_topo working directory and rename it. Here, the name is
# chosen such that it:
#
# (1) indicates that it contains filtered orography data (because that
#     is what it will contain once the orography filtering executable
#     successfully exits); and
# (2) ends with the string ".tile${N}.nc" expected by the orography
#     filtering code.
#
#-----------------------------------------------------------------------
#
fn_suffix_without_halo="tile${TILE_RGNL}.nc"
filtered_orog_fn_prefix="${CRES}${DOT_OR_USCORE}filtered_orog"
filtered_orog_fp_prefix="${filter_dir}/${filtered_orog_fn_prefix}"
filtered_orog_fp="${filtered_orog_fp_prefix}.${fn_suffix_without_halo}"
cp "${raw_orog_fp}" "${filtered_orog_fp}"
#
# The filter_topo program looks for the grid file specified
# in the mosaic file (more specifically, specified by the gridfiles
# variable in the mosaic file) in its own run directory. Make a symlink
# to it.
#
ln -nsf ${grid_fp} ${filter_dir}/${grid_fn}
#
# Create the namelist file (in the filter_dir directory) that the orography
# filtering executable will read in.
#
# Note that in the namelist file for the orography filtering code (created
# later below), the mosaic file name is saved in a variable called
# "grid_file".  It would have been better to call this "mosaic_file"
# instead so it doesn't get confused with the grid file for a given tile.
cat > "${filter_dir}/input.nml" <<EOF
&filter_topo_nml
  grid_file = "${mosaic_fp}"
  topo_file = "${filtered_orog_fp_prefix}"
  mask_field = "land_frac"
  regional = .true.
  stretch_fac = ${STRETCH_FAC}
  res = $res
/
EOF
#
# Change location to the filter dir directory to run. The executable
# expects to find its input.nml file in the directory from which it is
# run.
#
cd "${filter_dir}"
#
# Run the orography filtering executable.
#
print_info_msg "Starting filtering of orography..."

export pgm="filter_topo"
. prep_step

eval ${RUN_CMD_SERIAL} ${EXECsrw}/$pgm >>$pgmout 2>errfile
export err=$?; err_chk
mv errfile ${DATA}/errfile_filter_topo

#
# For clarity, rename the filtered orography file in filter_dir
# such that its new name contains the halo size.
#
filtered_orog_fn_orig=$( basename "${filtered_orog_fp}" )
filtered_orog_fn="${filtered_orog_fn_prefix}.${fn_suffix_with_halo}"
filtered_orog_fp=$( dirname "${filtered_orog_fp}" )"/${filtered_orog_fn}"
mv "${filtered_orog_fn_orig}" "${filtered_orog_fn}"
cp "${filtered_orog_fp}" "${OROG_DIR}/${CRES}${DOT_OR_USCORE}oro_data.tile${TILE_RGNL}.halo${NHW}.nc"
#
# Change location to the original directory.
#
cd ${DATA}

print_info_msg "Filtering of orography complete."
#
#-----------------------------------------------------------------------
#
# Partially "shave" the halo from the (filtered) orography file having a
# wide halo to generate two new orography files -- one without a halo and
# another with a 4-cell-wide halo.  These are needed as inputs by the
# surface climatology file generation code (sfc_climo; if it is being
# run), the initial and boundary condition generation code (chgres_cube),
# and the forecast model.
#
#-----------------------------------------------------------------------
#
unshaved_fp="${filtered_orog_fp}"
#
# We perform the work in shave_dir, so change location to that directory.
# Once it is complete, we move the resultant file from shave_dir to OROG_DIR.
#
cd "${shave_dir}"
#
# Create an input config file for the shave executable to generate an
# orography file without a halo from the one with a wide halo.  Then call
# the shave executable.  Finally, move the resultant file to the OROG_DIR
# directory.
#
export pgm="shave"

halo_num_list=('0' '4')
halo_num_list[${#halo_num_list[@]}]="${NHW}"
for halo_num in "${halo_num_list[@]}"; do

  print_info_msg "Shaving filtered orography file with ${halo_num}-cell-wide halo..."
  nml_fn="input.shave.orog.halo${halo_num}"
  shaved_fp="${shave_dir}/${CRES}${DOT_OR_USCORE}oro_data.tile${TILE_RGNL}.halo${halo_num}.nc"
  printf "%s %s %s %s %s\n" \
  $NX $NY ${halo_num} \"${unshaved_fp}\" \"${shaved_fp}\" \
  > ${nml_fn}

  . prep_step

  eval ${RUN_CMD_SERIAL} ${EXECsrw}/$pgm < ${nml_fn} >>$pgmout 2>errfile
  export err=$?; err_chk
  mv errfile ${DATA}/errfile_shave_${halo_num}
  mv ${shaved_fp} ${OROG_DIR}
done

cd ${OROG_DIR}
#
#-----------------------------------------------------------------------
#
# Add link in OROG_DIR directory to the orography file with a 4-cell-wide
# halo such that the link name does not contain the halo width.  These links
# are needed by the make_sfc_climo task.
#
# NOTE: It would be nice to modify the sfc_climo_gen_code to read in
# files that have the halo size in their names.
#
#-----------------------------------------------------------------------
#
${PARMsrw}/link_fix.py \
  --path-to-defns ${GLOBAL_VAR_DEFNS_FP} \
  --file-group "orog" || \
print_err_msg_exit "\
Call to function to create links to orography files failed."

print_info_msg "
========================================================================
Orography files with various halo widths generated successfully!!!

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/func-
# tion.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1

