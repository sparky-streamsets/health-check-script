 ------""------- Linux System Health Check with StreamSets Enhancements ------""------- 

Here is a script to check the basic health status of a linux system with enhancements to check whether the system is in alignment with StreamSets best practice recommendations.

This script has been tested on all operating systems certified to run StreamSets products. It may work on other variants as well, however, these have not been tested. These tests were run on virtual machines.

This is a small, light weight script which makes use of native Linux utilities to get the required details and doesn't need much space.

v1.0 - Tests required platform minimums, memory settings and available disk space. Does not require a StreamSets product to be installed, but some tests will be disabled without one.

Usage:

health-check.sh (-h|--help) (-u|--user) <svcacct> (-p|--process) <pid> --exclude <functionlist> --include <functionlist> (-n|--no-prod) (-t|--target <targetapp>)

Options:<br />
-h | --help                        print this help message and exit<br />
-u | --user <uid>                  optional name of service account running StreamSets as a service (default: sdc)<br />
-p | --pid <pid>                   optional process id. Set when using more than one StreamSets process or if not a service<br />
-n | --no-prod                     set this to turn off certain warnings for non-production environments<br />
-x | --exclude <functionlist>      comma-separated list of functions not to execute<br />
-i | --include <functionlist>      comma-separated list of functions to execute (only execute these functions)<br />
-t | --target <targetproduct>      run product-specific tests (possible values: *sdc*,dpm|sch,transformer|xfm)

Available functions: CheckSupportedOS,CheckJVMVersion,CheckUlimit,PrintOSDetails,PrintSystemUptime,
FindReadOnlyFileSystems,FindCurrentlyMountedFileSystems,CheckDiskUsage,FindZombieProcesses,
CheckSwapUtilization,CheckProcessorUtilization,CheckMemorySettingsMatch,CheckMinSysMemory,CheckMinMemory,
CheckMaxMemory,CheckMinSysMemory,CheckPctOfSysMemory

For more details check the below web link :-
https://www.simplylinuxfaq.com/2015/05/How-To-Check-Health-Status-Of-Linux-System.html

                                                                    Updated on : 15-June-2020
