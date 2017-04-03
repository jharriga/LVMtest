#!/bin/bash
#----------------------------------------------------------------
# runCACHE.sh - test lvmCache performance
#
# DEPENDENCIES: (must be in search path)
#   I/O workload generator: fio
#   partition tools: fdisk, parted
#   LVM utils: pvs, pvcreate, vgcreate, lvcreate, lvs
#   FS utils: mkfs.xfs
#
# COMPONENTS:
#   Cached logical volume (/dev/<vg>/<lv>), built from:
#     * Origin logical volume (slowDEV)
#     * Cache logical volume (fastDEV)
#       > Cache data logical volume (cachedataLV)
#       > Cache metadata logical volume (cachemetaLV)
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

# Write key variable values to LOGFILE
updatelog "Key variable values:"
updatelog "> slowDEV=${slowDEV} - fastDEV=${fastDEV}"
updatelog "> cacheSZ=${cacheSZ} - cacheMODE=${cacheMODE}"
updatelog "> metadataSZ=${metadataSZ} - metadataLV=${cachemetaLV}"
updatelog "> originSZ=${originSZ} - cachedLV=${originLV}"
updatelog "> cachedLVPATH=${cachedLVPATH} - cachedMNT=${cachedMNT}"
updatelog "> cachedSCRATCH=${cachedSCRATCH}"
updatelog "> accessTYPE=${accessTYPE}"
updatelog "FIO variable settings:"
updatelog "> fioOP=${fioOP} - read%=${percentRD}"
updatelog "> randDIST=${randDIST} iodepth=${iod}"
updatelog "> runtime=${runtime} - ramptime=${ramptime}"
updatelog "---------------------------------"

# Ensure that devices to be tested are not in use
# First check LVM vol groups
for vg in ${cacheVG}; do
  pvs --all | grep ${vg}
  if [ $? == 0 ]; then
    updatelog "Volume Group ${vg} exists - ABORTING Test!" 
    echo "Be sure it is unmounted and then use appropriate LVM cmds:"
    echo "> lvdisplay/lvremove, vgdisplay/vgremove, pvdisplay/pvremove"
    exit 1
  fi
done

# Now check mountpts and clean up partitions
for dev in ${slowDEV} ${fastDEV}; do
  updatelog "Checking if ${dev} is in use, if yes abort"
  mount | grep ${dev}
  if [ $? == 0 ]; then
    updatelog "Device ${dev} is mounted - ABORTING Test!" 
    exit 1
  fi

# Prep device partitions for pvcreate/vgcreate/lvcreate cmds
  updatelog "Preparing ${dev} device partitions"
# Clears any existing partition table and create a new one
#   with a single partion that is the entire disk
    (echo o; echo n; echo p; echo 1; echo; echo; echo w) | \
      fdisk ${dev} >> $LOGFILE
# Now delete that partition 
  for partition in $(parted -s ${dev} print|awk '/^ / {print $1}'); do
    updatelog "Removing parition: dev=${dev} - partition=${partition}"
    parted -s $dev rm ${partition} || \
      error_exit "$LINENO: Unable to remove ${partition} from ${dev}"
  done
done

updatelog "Device checks complete - continuing..." 
# Devices should now be ready for LVM use
#
# END: Housekeeping
#--------------------------------------

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# LVM CACHE TEST SECTION - Section one of two
############################
# SETUP for LVM CACHE Test
# based on:
#----------------------------------------
updatelog "Starting: LVM CACHE SETUP"

source "$myPath/Utils/setupCACHE.shinc"

updatelog "Completed: LVM CACHE SETUP"

#############################
# TEST the LVM CACHE Devices
#----------------------------------------

updatelog "Starting: LVM CACHE Device TESTING"
# Test sequence:
#  1) write the test scratch file/area
#  2) warmup the cache (ramp_time)
#  3) measure the throughput (run_time)

# Write the test area/file with random 4M blocks
updatelog "START: Writing the scratch area"
write_scratch $cachedSCRATCH $scratchCACHE_SZ
updatelog "COMPLETED: Writing the scratch area"

updatelog "Starting: LVM CACHE Device TESTING"

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
#
# FileSize FOR loop
  for size in "${CACHEsize_arr[@]}"; do
#
# Run the test on the CACHED scratch area
    cachedOUT="${RESULTSDIR}/cached_${size}_${bs}.fio"
    if [ -e $cachedOUT ]; then
      rm -f $cachedOUT
    fi
    updatelog "RUNNING filesize ${size} with blocksize ${bs}: ${cachedSCRATCH}"

# Clear the inode and dentry caches
# With directIO this should not matter
  sync; echo 3 > /proc/sys/vm/drop_caches

# Warmup the cache (ramp_time) and measure the performance (run_time)
#
    updatelog "Warming up the cache and measuring performance..."
    fio --filesize=${size} --blocksize=${bs} \
    --rw=${fioOP} --rwmixread=${percentRD} --random_distribution=${randDIST} \
    --ioengine=libaio --iodepth=${iod} --direct=1 \
    --overwrite=0 --fsync_on_close=1 \
    --time_based --runtime=${runtime} --ramp_time=${ramptime} \
    --filename=${cachedSCRATCH} --group_reporting \
    --name=cached_${size}_${bs} --output=${cachedOUT} >> $LOGFILE
    if [ ! -e $cachedOUT ]; then
      error_exit "fio failed ${cachedSCRATCH}"
    fi
    updatelog "COMPLETED: Testing ${cachedSCRATCH} with size ${size}"
    updatelog "SUMMARY filesize ${size} with blocksize ${bs}: ${cachedSCRATCH}"
    fio_print $cachedOUT
    echo "FIO output:" >> $LOGFILE
    cat ${cachedOUT} >> $LOGFILE
    updatelog "-----------------------"
  done
  updatelog "*****************************************"
done

updatelog "Completed: LVM CACHE TESTING"

##############################
# TEARDOWN LVM CACHE configuration
updatelog "Starting: LVM CACHE TEARDOWN"

source "$myPath/Utils/teardownCACHE.shinc"

updatelog "Completed: LVM CACHE TEARDOWN"

updatelog "END ${PROGNAME}**********************"
updatelog "${PROGNAME} - Closed logfile: $LOGFILE"
exit 0

