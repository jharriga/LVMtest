# LVMtest
LVMcache performance test automation

A collection of bash shell scripts which run FIO tests comparing performance of two physical storage devices (slowDEV and fastDEV).
The tests run in one of two modes:
  * LVM - tests the two physical storage devices (fastDEV and slowDEV) seperately
  * LVMCache - test a LVMcache logical volume built from the two storage devices (fastDEV and slowDEV) 
  
The scripts follow this basic workflow:
  * Setup the configuration
  * Run the tests
  * Teardown the configuration

All of the scripts include the 'vars.shinc' file, which defines all the global variables. This file should be edited before running any of the scripts. See the 'CONFIGURING FOR YOUR DEVICES' section below. 

The 'setup' and 'teardown' scripts are located in the 'Utils' directory. They are called by the 'runLVM.sh' and 'runCACHE.sh' scripts, but can also be executed directly by running 'cleanup.sh' and 'create.sh' scripts.

CONFIGURING FOR YOUR DEVICES: Edit 'vars.shinc'
Certain variables must be configured for your test environment.
  * slowDEV=/dev/sdc  <-- your slow storage device (HDD)
  * fastDEV=/dev/nvme0n1  <-- your fast storage device (SDD)
  * cacheSZ=10  <-- size of cache to be created
  * unitSZ=G  <-- units G=GB, M=MB
  
EXECUTION: The scripts must be run as root.
To run the LVM tests:
  * runLVM.sh
To run the LVMCache tests:
  * runCACHE.sh
 
RECOVERING FROM INCOMPLETE or FAILED TESTs:
  * df
  * umount /dev/vg_slow/lv_slow
  * lvdisplay
  * lvremove /dev/vg_slow/lv_slow
  * vgdisplay
  * vgremove vg_slow
  * pvdisplay
  * pvremove /dev/sdb
  * { repeat as needed for other devices... } 

