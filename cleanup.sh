#!/bin/bash
#----------------------------------------------------------------
# cleanup.sh - cleanup/teardown lvm device configuration
#
# CONFIGURATION:
#   HDD = slowDEV = /dev/sdX (WD320G /dev/sdb)
#   SSD = fastDEV = /dev/nvme0n1   
#
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

# Assign LOGFILE
LOGFILE="./LOGFILEcleanup"

#--------------------------------------
# Housekeeping

# Check for correct number of ARGS
if [ $# -ne 1 ]; then
    echo "need one argument - type of config to cleanup"
    echo "Valid values are: LVM, LVMCACHE"
    exit 1
fi

# check mountpts 
for dev in ${slowDEV} ${fastDEV}; do
  echo "Checking if ${dev} is in use, if yes abort"
  mount | grep ${dev}
  if [ $? == 0 ]; then
    echo "Device ${dev} is mounted - ABORTING!" 
    echo "User must manually unmount ${slowDEV} and ${fastDEV}"
    exit 1
  fi
done

# Create new log file
if [ -e $LOGFILE ]; then
  rm -f $LOGFILE
fi
touch $LOGFILE || error_exit "$LINENO: Unable to create LOGFILE."
updatelog "$PROGNAME - Created logfile: $LOGFILE"

case "$1" in
    "LVM")
# TEARDOWN LVM configuration
        updatelog "Starting: LVM TEARDOWN"
        source "$myPath/Utils/teardownLVM.shinc"
        updatelog "Completed: LVM TEARDOWN"
        ;;
    "LVMCACHE")
# TEARDOWN CACHE configuration
        updatelog "Starting: CACHE TEARDOWN"
        source "$myPath/Utils/teardownCACHE.shinc"
        updatelog "Completed: CACHE TEARDOWN"
        ;;
    *) 
        updatelog "Invalid Selection - nothing done - exiting"
        ;;
esac

updatelog "$PROGNAME - END"
echo "END ${PROGNAME}**********************"
exit 0

