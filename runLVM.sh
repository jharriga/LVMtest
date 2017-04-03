#!/bin/bash
#----------------------------------------------------------------
# runLVM.sh - test lvm device performance
#
# DEPENDENCIES: (must be in search path)
#   I/O workload generator: fio
#   partition tools: fdisk, parted
#   LVM utils: pvs, pvcreate, vgcreate, lvcreate, lvs
#   FS utils: mkfs.xfs 
# 
# COMPONENTS:
#   slowDEV --> Origin logical volume
#   fastDEV --> Cache logical volume
#     > Cache data logical volume
#     > Cache metadata logical volume
#
# PHYSICAL DEVICE CONFIGURATION:
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
#
# Check dependencies are met
chk_dependencies

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
updatelog "> fastSZ=${fastSZ} - fastLV=${fastLV} - fastVG=${fastVG}"
updatelog "> slowSZ=${slowSZ} - slowLV=${slowLV} - slowVG=${slowVG}"
updatelog "> slowLVPATH=${slowLVPATH} - fastLVPATH=${fastLVPATH}"
updatelog "> slowSCRATCH=${slowSCRATCH} - fastSCRATCH=${fastSCRATCH}"
updatelog "> accessTYPE=${accessTYPE}"
updatelog "FIO variable settings:"
updatelog "> iodepth=${iod} - read%=${percentRD}"
updatelog "---------------------------------"

# Ensure that devices to be tested are not in use
# First check LVM vol groups
for vg in ${slowVG} ${fastVG}; do
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
# LVM TEST SECTION - Section one of two
############################
# SETUP for LVM Test
# based on:
#----------------------------------------
updatelog "Starting: LVM SETUP"

source "$myPath/Utils/setupLVM.shinc"

updatelog "Completed: LVM SETUP"

#############################
# TEST the LVM Devices
#----------------------------------------
# Write the test area/file with random 4M blocks

updatelog "START: Writing the scratch areas"

# slowDEV - create scratch 
write_scratch $slowSCRATCH $scratchLVM_SZ

# fastDEV - create scratch
write_scratch $fastSCRATCH $scratchLVM_SZ

updatelog "COMPLETED: Writing the scratch areas"

updatelog "Starting: LVM Device TESTING"

#####
# Main for loops for executing FIO tests
# Note that the FIO output files get over-written on every run
#   but the output is logged in $LOGFILE
# Summary information is added to $LOGFILE by 'fio_print' function 
#
# Size FOR loop
for size in "${LVMsize_arr[@]}"; do
#
# BlockSize FOR loop
  for bs in "${BLOCKsize_arr[@]}"; do
#
# Run the test on SLOW dev
    slowOUT="${RESULTSDIR}/slow_${size}_${bs}.fio"
    if [ -e $slowOUT ]; then
      rm -f $slowOUT
    fi
    updatelog "RUNNING size ${size}, blocksize ${bs}, \
      iodepth ${iod}: ${slowSCRATCH}"

    sync; echo 3 > /proc/sys/vm/drop_caches
    fio --size=${size} --blocksize=${bs} \
    --rw=randrw --rwmixread=${percentRD} --random_distribution=zipf:1.2 \
    --ioengine=libaio --iodepth=${iod} --direct=1 \
    --overwrite=0 --fsync_on_close=1 \
    --filename=${slowSCRATCH} --group_reporting \
    --name=slow_${size}_${bs} --output=${slowOUT} >> $LOGFILE
    if [ ! -e $slowOUT ]; then
      error_exit "fio failed ${slowSCRATCH}"
    fi
    updatelog "COMPLETED: Testing ${slowSCRATCH} with size ${size}"
    updatelog "SUMMARY size ${size} with blocksize ${bs}: ${slowSCRATCH}"
    fio_print $slowOUT
    echo "FIO output:" >> $LOGFILE
    cat ${slowOUT} >> $LOGFILE
    updatelog "-----------------------"

# Run the test on FAST dev
    fastOUT="${RESULTSDIR}/fast_${size}_${bs}.fio"
    if [ -e $fastOUT ]; then
      rm -f $fastOUT
    fi
    updatelog "RUNNING size ${size} with blocksize ${bs}: ${fastSCRATCH}"

    sync; echo 3 > /proc/sys/vm/drop_caches
    fio --size=${size} --blocksize=${bs} \
    --rw=randrw --rwmixread=${percentRD} --random_distribution=zipf:1.2 \
    --ioengine=libaio --iodepth=${iod} --direct=1 \
    --overwrite=0 --fsync_on_close=1 \
    --filename=${fastSCRATCH} --group_reporting \
    --name=fast_${size}_${bs} --output=${fastOUT} >> $LOGFILE
    if [ ! -e $fastOUT ]; then
      error_exit "fio failed ${fastSCRATCH}"
    fi
    updatelog "COMPLETED: Testing ${fastSCRATCH}"
    updatelog "SUMMARY size ${size} with blocksize ${bs}: ${fastSCRATCH}"
    fio_print $fastOUT
    echo "FIO output:" >> $LOGFILE
    cat ${fastOUT} >> $LOGFILE
    updatelog "-----------------------"
  done
done

updatelog "Completed: LVM Device TESTING"

##############################
# TEARDOWN LVM configuration
#  - umount the LVs
#  - Remove the two LVs
#  - Remove the two VGs
#  - Remove the two PVs
updatelog "Starting: LVM TEARDOWN"

source "$myPath/Utils/teardownLVM.shinc"

updatelog "Completed: LVM TEARDOWN"

updatelog "END ${PROGNAME}**********************"
updatelog "${PROGNAME} - Closed logfile: $LOGFILE"
exit 0

