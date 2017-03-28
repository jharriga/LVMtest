#!/bin/bash
#----------------------------------------------------------------
# runCAHE.sh - test lvmCache performance
#
# COMPONENTS:
#   Cached logical volume (/dev/<vg>/<lv>), built from:
#     * Origin logical volume (slowDEV)
#     * Cache logical volume (fastDEV)
#       > Cache data logical volume
#       > Cache metadata logical volume
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
touch $LOGFILE || error_exit "$LINENO: Unable to create LOGFILE."
updatelog "${PROGNAME} - Created logfile: $LOGFILE"

# Write key variable values to LOGFILE
updatelog "Key variable values:"
updatelog "> slowDEV=${slowDEV} - fastDEV=${fastDEV}"
updatelog "> cacheSZ=${cacheSZ} - cacheMODE=${cacheMODE}"
updatelog "> cacheLV=${cacheLV} - cacheVG=${cacheVG}"
updatelog "> metadataSZ=${metadataSZ} - metadataLV=${metadataLV}"
updatelog "> originSZ=${originSZ} - cachedLV=${originLV}"
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
#  1) write the test file/area
#  2) warmup the cache (ramp_time)
#  3) measure the throughput (run_time)

# SKIP - Cleanup the FIO dir
#  if [ -d ${cachedFIO} ]; then
#    rm -rf ${cachedFIO} || error_exit "$LINENO: Unable to remove ${cachedFIO}"
#  fi
#  mkdir ${cachedFIO} || \
#    error_exit "$LINENO: Unable to create dir ${cachedFIO}"

# Write the test area/file with random 4M blocks
  updatelog "Writing ${scratchSZ} scratch area to ${cachedLVPATH}..."
  fio --size=${scratchSZ} --blocksize=${bs} --refill_buffers=1 \
  --rw=write --ioengine=libaio --iodepth=8 \
  --filename=${cachedLVPATH} --group_reporting \
  --name=scratch >> $LOGFILE

# FILESIZE FOR LOOP
for fs in "${CACHEsize_arr[@]}"; do
#
# Run the test on the dev
  updatelog "RUNNING size ${fs} with blocksize ${bs}: ${cachedLVPATH}"

# Warmup the cache (ramp_time) and measure the performance (run_time)
# Previous measurements indicate these throughput rates for our
# devices (randomReadWrites 80/20 mix):
#   4k bs - fastDEV = 26s/GB  slowDEV = 590s/GB  PerfRatio of 22.7:1
#   4M bs - fastDEV =  6s/GB  slowDEV = 19s/GB   PerfRatio of  3.2:1
# To cover 20GB scratch area once
#   4k bs - fastDEV (20 * 26s)=520s   slowDEV (20 * 590s)= 11800s
#   4M bs - fastDEV (20 * 6s)=120s    slowDEV (20 * 19s)= 380s
#
  sync; echo 3 > /proc/sys/vm/drop_caches
  updatelog "Warming up the cache and measuring performance..."
  fio --filesize=${fs} --blocksize=${bs} --end_fsync=1 --direct=1 \
    --time_based --runtime=${runtime} --ramp_time=${ramptime} \
    --rw=randrw --rwmixread=${percentRD} --random_distribution=zipf:1.2 \
    --group_reporting --overwrite=0 --filename=${cachedLVPATH} \
    --name=cached_${size}_${bs} >> $LOGFILE
  updatelog "Measurements of ${cachedLVPATH} complete."
  du -s ${cachedLVPATH} >> $LOGFILE
  updatelog "-----------------------------------"

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

