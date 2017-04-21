#!/bin/bash
#----------------------------------------------------------------
# runICAS.sh - test Intel iCAS performance
#
# Verifies slowDEV, icasDEV, icasSCRATCH exist (as set in vars.shinc)
#
# DEPENDENCIES: (must be in search path)
#   I/O workload generator: fio
#   partition tools: fdisk, parted
#
# COMPONENTS:
#   Cached block device built from:
#     * Core/Origin block device (slowDEV=/dev/sdb)
#     * Cache block device (icasDEV=/dev/nvme0n1p1)
#   Global vars: slowDEV; icasDEV; icasSCRATCH
#
# CONFIGURATION:
#   HDD = slowDEV = /dev/sdX (WD320G /dev/sdb)
#   SSD = fastDEV = /dev/nvme0n1   
#
# NOTE caches are dropped prior to each testrun as described here:
#   https://linux-mm.org/Drop_Caches
#----------------------------------------

# Bring in other script files
myPath="${BASH_SOURCE%/*}"
if [[ ! -d "$myPath" ]]; then
    myPath="$PWD" 
fi
# Variables
source "$myPath/vars.shinc"

# Functions
source "$myPath/Utils/functions.shinc"

#--------------------------------------
# Housekeeping
# Create log file - named in vars.shinc
if [ ! -d $RESULTSDIR ]; then
  mkdir -p $RESULTSDIR || \
    error_exit "$LINENO: Unable to create RESULTSDIR."
fi
touch $LOGFILE || error_exit "$LINENO: Unable to create LOGFILE."
updatelog "${PROGNAME} - Created logfile: $LOGFILE"

# Record runtime versions and key variable values to LOGFILE
print_Runtime LVMcache

# Now check devices exist and aren't currently mounted
for dev in ${icasSLOW} ${icasFAST}; do
  updatelog "Checking if ${dev} exists, if not - abort"
  devname=$(echo "${dev}" | sed -e "s%/dev/%%")
#  echo $devname
  lsblk | grep ${devname}
  if [ $? != 0 ]; then
    updatelog "Device ${dev} does not exist - ABORTING Test!" 
    exit 1
  fi

  updatelog "Checking if ${dev} is mounted, if yes - abort"
  mount | grep ${dev}
  if [ $? == 0 ]; then
    updatelog "Device ${dev} is mounted - ABORTING Test!" 
    exit 1
  fi
done

updatelog "Device checks complete - continuing..." 

# Devices should now be ready for iCAS use
#
# END: Housekeeping
#--------------------------------------


#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# iCAS TEST SECTION - Section one of two
############################

# SETUP for iCAS CACHE Test
#----------------------------------------
updatelog "Starting: iCAS SETUP"
#
#source "$myPath/Utils/setupCACHE.shinc"
#
# RESET the CACHE
# if it is running, stop it
casadm -T -i 1
# Re-initialize the CACHE instead of loading the old/existing state
casadm -S -d $icasFAST -f || error_exit "starting iCAS on ${icasFAST}"
casadm -A -i 1 -d $icasSLOW || error_exit "adding ${icasSLOW}"

# Verify that icasSCRATCH exists
casadm -L | grep "${icasSCRATCH}"
if [ $? != 0 ]; then
  updatelog "Device ${icasSCRATCH} does not exist - ABORTING Test!" 
  exit 1
fi

updatelog "Completed: iCAS SETUP"

#############################
# TEST the INTEL iCAS Device
#----------------------------------------

updatelog "Starting: INTEL iCAS Device TESTING"
# Test sequence:
#  1) write the test scratch file/area
#  2) warmup the cache (ramp_time)
#  3) measure the throughput (run_time)

#
# Write the test area/file with random 4M blocks
updatelog "START: Writing the scratch area"
write_scratch $icasSCRATCH $scratchCACHE_SZ
updatelog "COMPLETED: Writing the scratch area"

# Output lvmcache statistics before any runs
# this call should not emit any delta values since
# it is the first call to the function
#cacheStats $cachedLVPATH
casadm -P -i 1 -j 1 -f usage,req
casadm --reset-counters -i 1 -j 1

#####
# Main for loops for executing FIO tests
# Note that the FIO output files get over-written on every run
#   but the output is logged in $LOGFILE
# Summary information is added to $LOGFILE by 'fio_print' function 
#
# BlockSize FOR loop
for bs in "${BLOCKsize_arr[@]}"; do
#
  updatelog "*****************************************"
# loop counter - used to determine offset for fio
  let loopcntr=0

# Hard-code these arrays locally for testing
CACHEsize_arr=("10G" "21G" "27G" "29G")
declare -ia OFFSET_arr=(0 11 22 28)

#
# FileSize FOR loop
  for size in "${CACHEsize_arr[@]}"; do

# Run the test on the CACHED scratch area
    cachedOUT="${RESULTSDIR}/cached_${size}_${bs}.fio"
    if [ -e $cachedOUT ]; then
      rm -f $cachedOUT
    fi
    updatelog "-----------------------"
    updatelog "RUNNING filesize ${size} with blocksize ${bs}: ${icasSCRATCH}"

# Clear the inode and dentry caches
# With directIO this should not matter
    sync; echo 3 > /proc/sys/vm/drop_caches

# Set the 'offset' based on loop counter
#
    offcalc=${OFFSET_arr[loopcntr]}
    offset="$offcalc$unitSZ"
    sizecalc=${size::-1}
    areacalc=$((sizecalc - offcalc))
    area="$areacalc$unitSZ" 
# Print out the values (with units)
    echo -n ">> Test settings: FILESIZE = ${size} | OFFSET = ${offset}"
    echo " | TEST-AREA = ${area}"
    echo ">> Range within scratch area is: ${offset} --> ${size}"

# Prepare loocntr value for next loop iteration
    loopcntr=$((loopcntr + 1))

# Warmup the cache (ramp_time) and measure the performance (run_time)
#
    updatelog "Warming up the cache and then measuring performance..."
    fio --offset=${offset} --filesize=${size} --blocksize=${bs} \
    --rw=${fioOP} --rwmixread=${percentRD} --random_distribution=${randDIST} \
    --ioengine=libaio --iodepth=${iod} --direct=1 \
    --overwrite=0 --fsync_on_close=1 \
    --time_based --runtime=${runtime} --ramp_time=${ramptime} \
    --filename=${icasSCRATCH} --group_reporting \
    --name=cached_${size}_${bs} --output=${cachedOUT} >> $LOGFILE
    if [ ! -e $cachedOUT ]; then
      error_exit "fio failed ${icasSCRATCH}"
    fi
    updatelog "COMPLETED: Testing ${icasSCRATCH} with size ${size}"
# Output the FIO results
    updatelog "SUMMARY filesize ${size} with blocksize ${bs}: ${icasSCRATCH}"
    fio_print $cachedOUT
    echo "FIO output:" >> $LOGFILE
    cat ${cachedOUT} >> $LOGFILE
#
# Output iCAS statistics after each run
# reset the counters so the calls emit delta values
#    cacheStats $cachedLVPATH
  casadm -P -i 1 -j 1 -f usage,req
  casadm --reset-counters -i 1 -j 1

  done
  updatelog "*****************************************"
done

updatelog "*****************************************"
updatelog "Completed: iCAS TESTING"

updatelog "END ${PROGNAME}**********************"
updatelog "${PROGNAME} - Closed logfile: $LOGFILE"
exit 0

