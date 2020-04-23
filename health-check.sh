#!/bin/bash
##========== Original author : Sadashiva Murthy M ===========================================##
##========== Github page : https://github.com/streamsets/health-check-script ================##
##========== Purpose : To to ensure host settings match StreamSets best practices  ==========##
##========== Tested on : RHEL8(beta)/7/6/5/, SLES/SLED 12/11, Ubuntu14/16/18, Mint16, =======## 
##========== Boss6(Debian) variants. It may work on others, but they have not been tested. ==##
##========== Updated version : v0.3 (Updated on 23 Apr 2020) ================================##
##========== NOTE: This script requires either root or sudo privileges ======================##
##========== "sudo /bin/bash health-check.sh" ===============================================##

#------variables used------#
S="************************************"
D="-------------------------------------"
COLOR="y"

MOUNT=$(mount|egrep -iw "ext4|ext3|xfs|gfs|gfs2|btrfs"|grep -v "loop"|sort -u -t' ' -k1,2)
FS_USAGE=$(df -PTh|egrep -iw "ext4|ext3|xfs|gfs|gfs2|btrfs"|grep -v "loop"|sort -k6n|awk '!seen[$1]++')
IUSAGE=$(df -PThi|egrep -iw "ext4|ext3|xfs|gfs|gfs2|btrfs"|grep -v "loop"|sort -k6n|awk '!seen[$1]++')

if [ $COLOR == y ]; then
{
 GCOLOR="\e[47;32m ------ OK/HEALTHY \e[0m"
 WCOLOR="\e[43;31m ------ WARNING \e[0m"
 CCOLOR="\e[47;31m ------ CRITICAL \e[0m"
}
else
{
 GCOLOR=" ------ OK/HEALTHY "
 WCOLOR=" ------ WARNING "
 CCOLOR=" ------ CRITICAL "
}
fi

echo -e "$S"
echo -e "\tSystem Health Status"
echo -e "$S"

#=================================== HelpFunction ===================================#
HelpFunction()
{
    echo ""
    echo "Usage:$0 (-h|--help) (-u|--user) <svcacct> (-p|--process) <pid> --exclude <functionlist> --include <functionlist> -n"
    echo -e "\n\n\tAvailable functions: ServiceChecks,PrintOSDetails,PrintSystemUptime,FindReadOnlyFileSystems,"
    echo -e "\tFindCurrentlyMountedFileSystems,CheckDiskUsage,FindZombieProcesses,CheckInodeUsage,CheckSwapUtilization,"
    echo -e "\tCheckProcessorUtilization,CheckLoadAverage,CheckMostRecentReboots,CheckShutdownEvents,"
    echo -e "\tCheckTopFiveMemoryConsumers,CheckTopFiveCPUConsumers"
    echo -e "\n\nOptions:"
    echo -e "\t-h | --help                        print this help message and exit"
    echo -e "\t-u | --user <uid>                  optional name of service account running StreamSets as a service (default: sdc)"
    echo -e "\t-p | --pid <pid>                   optional process id. Set when using more than one StreamSets process or if not a service"
    echo -e "\t-n | --no-prod                     set this to turn off certain warnings for non-production environments"
    echo -e "\t-x | --exclude <functionlist>      comma-separated list of functions not to execute"
    echo -e "\t-i | --include <functionlist>      comma-separated list of functions to execute (only execute these functions)\n"
    exit 1 # Exit script after printing help
}

#=================================== Process Options ===================================#
TEMP_OPTS=`getopt -u -o u:p:nhx:i: -l help,no-prod,user:,pid:,exclude:,include: -n 'health-check' -- "$@"`

if [ $? != 0 ]; then echo "Terminating..." >&2; exit 1; fi

eval set -- "$TEMP_OPTS"

OWNER="sdc"
FUNCTIONS_TO_RUN='ServiceChecks,PrintOSDetails,PrintSystemUptime,FindReadOnlyFileSystems,FindCurrentlyMountedFileSystems,CheckDiskUsage,FindZombieProcesses,CheckInodeUsage,CheckSwapUtilization,CheckProcessorUtilization,CheckLoadAverage,CheckMostRecentReboots,CheckShutdownEvents,CheckTopFiveMemoryConsumers,CheckTopFiveCPUConsumers'
FUNCTIONS_TO_SKIP=''
while true; do
    case "$1" in
        -u | --user ) OWNER="$2"; shift 2 ;;
        -p | --pid ) PID="$2"; shift 2 ;;
        -n | --no-prod ) NONPROD="true"; shift ;;
        -x | --exclude ) FUNCTIONS_TO_SKIP="$2"; shift 2 ;;
        -i | --include ) FUNCTIONS_TO_RUN="$2"; shift 2 ;;
        -h | --help ) HelpFunction ;; # Print helpFunction in case parameter is non-existent
        -- ) shift; break ;;
        * ) break ;;
    esac
done

if [ $FUNCTIONS_TO_SKIP!='' ]; then
    for func in $(echo $FUNCTIONS_TO_SKIP | sed "s/,/ /g"); do
        FUNCTIONS_TO_RUN=$(echo $FUNCTIONS_TO_RUN | sed "s/$func,//g")
    done
fi

#=================================== ServiceChecks ===================================#
ServiceChecks()
{   
    CheckForBCFunction
    StreamSetsCalcMemorySettings
    StreamSetsCheckMemorySettingsMatch
    StreamSetsCheckMinMemory
    StreamSetsCheckMaxMemory
    StreamSetsCheckPctOfSysMemory
}

#=================================== Check to see if bc function is present ===================================#
CheckForBCFunction()
{
   if ! type bc &> /dev/null; then
	   echo "You need to install the bc command to run the StreamSets-specific system checks"
	   echo "On Ubuntu/Debian, run:  sudo apt-get update & sudo apt-get install bc"
	   echo "On RHEL/CentOs, run:  sudo yum install bc"
	   exit 1
	fi
}

#=================================== Pre-calc memory settings ===================================#
StreamSetsCalcMemorySettings()
{
    if [ -z $PID ]; then
        STREAMSETS_SDC_XMX="$(ps -f -u $OWNER | grep -Eo 'Xmx[[:digit:]]+(k|K|m|M|g|G|[[:space:]])' | sed 's/Xmx//g')"
    else
        STREAMSETS_SDC_XMX="$(ps -f -p $PID | grep -Eo 'Xmx[[:digit:]]+(k|K|m|M|g|G|[[:space:]])' | sed 's/Xmx//g')"
    fi
    MULTIPLE=1
    if [[ "$STREAMSETS_SDC_XMX" =~ (k|K)$ ]]; then
        MULTIPLE=2**10
    elif [[ "$STREAMSETS_SDC_XMX" =~ (m|M)$ ]]; then
        MULTIPLE=2**20
    elif [[ "$STREAMSETS_SDC_XMX" =~ (g|G)$ ]]; then
        MULTIPLE=2**30
    fi
    STREAMSETS_SDC_RAW_XMX="$(echo $STREAMSETS_SDC_XMX | tr -d '[:space:]' | tr -d '[:alpha:]')"
    STREAMSETS_SDC_RAW_XMX=$(echo $((STREAMSETS_SDC_RAW_XMX * MULTIPLE)))

    if [ -z $PID ]; then
        STREAMSETS_SDC_XMS="$(ps -f -u $OWNER | grep -Eo 'Xms[[:digit:]]+(k|K|m|M|g|G|[[:space:]])' | sed 's/Xms//g')"
    else
        STREAMSETS_SDC_XMS="$(ps -f -p $PID | grep -Eo 'Xmx[[:digit:]]+(k|K|m|M|g|G|[[:space:]])' | sed 's/Xmx//g')"
    fi
    MULTIPLE=1
    if [[ "$STREAMSETS_SDC_XMS" =~ (k|K)$ ]]; then
        MULTIPLE=2**10
    elif [[ "$STREAMSETS_SDC_XMS" =~ (m|M)$ ]]; then
        MULTIPLE=2**20
    elif [[ "$STREAMSETS_SDC_XMS" =~ (g|G)$ ]]; then
        MULTIPLE=2**30
    fi
    STREAMSETS_SDC_RAW_XMS="$(echo $STREAMSETS_SDC_XMS | tr -d '[:space:]' | tr -d '[:alpha:]')"
    STREAMSETS_SDC_RAW_XMS=$(echo $((STREAMSETS_SDC_RAW_XMS * MULTIPLE)))
}

#=================================== Check initial and heap sizes match ===================================#
StreamSetsCheckMemorySettingsMatch()
{
    if [ $STREAMSETS_SDC_RAW_XMS -ne $STREAMSETS_SDC_RAW_XMX ]; then
        echo -e "\nStreamSets recommends following the industry-standard best practice of setting the"
        echo -e "\ninitial and maximum heap sizes to the same value."
        echo -e "\nCurrent Xms: $STREAMSETS_SDC_XMS    Current Xmx: $STREAMSETS_SDC_XMX  $WCOLOR"
    else
        echo -e "\nCurrent Initial and Maximum heap sizes match. Current Xms: $STREAMSETS_SDC_XMS   \
Current Xmx: $STREAMSETS_SDC_XMX  $GCOLOR"
    fi
}

#=================================== Check current against min recommended memory ===================================#
StreamSetsCheckMinMemory()
{
    if [ $STREAMSETS_SDC_RAW_XMX -lt 8589934592 ]; then
        echo -e "\nStreamSets recommends at least 8 GB of heap memory available for both production and non-production"
        echo -e "environments: Current Xmx: $STREAMSETS_SDC_XMX  $CCOLOR" 
    elif [[ $STREAMSETS_SDC_RAW_XMX -lt 17179869184 && -z "$NONPROD" ]]; then
        echo -e "\nStreamSets recommends at least 16 GB of heap memory available for production environments."
        echo -e "To suppress this warning in the future, set the -n flag. Current Xmx: $STREAMSETS_SDC_XMX  $WCOLOR"
    else
        echo -e "\nSufficient memory is available to run StreamSets. Current Xmx: $STREAMSETS_SDC_XMX  $GCOLOR"
    fi
}

#=================================== Check current against max recommended memory ===================================#
StreamSetsCheckMaxMemory()
{
    if [ $STREAMSETS_SDC_RAW_XMX -ge 68719476736 ]; then
        echo -e "\nStreamSets recommends no more than 64 GB of heap memory be available. Requiring more memory is often an"
        echo -e "indicator that the SDC has reached its carrying capacity. Current Xmx: $STREAMSETS_SDC_XMX  $CCOLOR" 
    else
        echo -e "\nAvailable memory is not excessive (i.e. > 64 GB). Current Xmx: $STREAMSETS_SDC_XMX  $GCOLOR"
    fi
}

#=================================== Check % of memory used by StreamSets ===================================#
StreamSetsCheckPctOfSysMemory()
{
    SYSMEM="$(awk '/MemFree/ { printf "%.0f \n", $2*1024 }' /proc/meminfo)"
    SYSMEM_IN_GB="$(awk '/MemFree/ { printf "%.0f \n", $2/1024/1024 }' /proc/meminfo)"
    PCT_OF_SYSMEM="$(echo $STREAMSETS_SDC_RAW_XMX/$SYSMEM |bc -l)"
    PCT_OF_SYSMEM=$(echo $PCT_OF_SYSMEM*100 | bc -l)
    PCT_OF_SYSMEM=$(printf %0.f $PCT_OF_SYSMEM)
    if [ $PCT_OF_SYSMEM -gt 75 ]; then
        echo -e "\nStreamSets recommends that the heap size setting be no larger than 75% of the available system memory."
        echo -e "Current Xmx: $STREAMSETS_SDC_XMX   Total system memory: ${SYSMEM_IN_GB}g  $WCOLOR"
    else
        echo -e "\nAvailable heap memory is below 75% of total system memory."
        echo -e "Current Xmx: $STREAMSETS_SDC_XMX   Total system memory: ${SYSMEM_IN_GB}g  $GCOLOR"
    fi
}

#=================================== Print Operating System Details ===================================#
PrintOSDetails()
{
    echo -e "\n\nPrint Operating System Details"
    echo -e "$D"

    hostname -f &> /dev/null && printf "Hostname : $(hostname -f)" || printf "Hostname : $(hostname -s)"

    [ -x /usr/bin/lsb_release ] &&  echo -e "\nOperating System :" $(lsb_release -d|awk -F: '{print $2}'|sed -e 's/^[ \t]*//')  || \
    echo -e "\nOperating System :" $(cat /etc/system-release)

    echo -e "Kernel Version : " $(uname -r)

    printf "OS Architecture : "$(arch | grep x86_64 &> /dev/null) && printf " 64 Bit OS\n"  || printf " 32 Bit OS\n"
}

#=================================== Print system uptime ===================================#
PrintSystemUptime()
{
    UPTIME=$(uptime)
    echo $UPTIME|grep day &> /dev/null
    if [ $? != 0 ]
        then
            echo $UPTIME|grep -w min &> /dev/null && echo -e "System Uptime : "$(echo $UPTIME|awk '{print $2" by "$3}'|sed -e 's/,.*//g')" minutes" \
            || echo -e "System Uptime : "$(echo $UPTIME|awk '{print $2" by "$3" "$4}'|sed -e 's/,.*//g')" hours"
    else
        echo -e "System Uptime : " $(echo $UPTIME|awk '{print $2" by "$3" "$4" "$5" hours"}'|sed -e 's/,//g')
    fi
    echo -e "Current System Date & Time : "$(date +%c)
}
        
#=================================== Check for any read-only file systems ===================================#
FindReadOnlyFileSystems()
{
    echo -e "\nChecking For Read-only File System[s]"
    echo -e "$D"
    echo "$MOUNT"|grep -w \(ro\) && echo -e "\n.....Read Only file system[s] found"|| echo -e ".....No read-only file system[s] found. "
}

#=================================== Check for currently mounted file systems ===================================#
FindCurrentlyMountedFileSystems()
{
    echo -e "\n\nChecking For Currently Mounted File System[s]"
    echo -e "$D$D"
    echo "$MOUNT"|column -t
}

#=================================== Check disk usage on all mounted file systems ===================================#
CheckDiskUsage()
{
    echo -e "\n\nChecking For Disk Usage On Mounted File System[s]"
    echo -e "$D$D"
    echo -e "( 0-90% = OK/HEALTHY, 90-95% = WARNING, 95-100% = CRITICAL )"
    echo -e "$D$D"
    echo -e "Mounted File System[s] Utilization (Percentage Used):\n"

    COL1=$(echo "$FS_USAGE"|awk '{print $1 " "$7}')
    COL2=$(echo "$FS_USAGE"|awk '{print $6}'|sed -e 's/%//g')

    for i in $(echo "$COL2"); do
    {
        if [ $i -ge 95 ]; then
            COL3="$(echo -e $i"% $CCOLOR\n$COL3")"
        elif [[ $i -ge 90 && $i -lt 95 ]]; then
            COL3="$(echo -e $i"% $WCOLOR\n$COL3")"
        else
            COL3="$(echo -e $i"% $GCOLOR\n$COL3")"
        fi
    }
    done
    COL3=$(echo "$COL3"|sort -k1n)
    paste  <(echo "$COL1") <(echo "$COL3") -d' '|column -t
}

#=================================== Check for any zombie processes ===================================#
FindZombieProcesses()
{
    echo -e "\n\nChecking For Zombie Processes"
    echo -e "$D"
    ps -eo stat|grep -w Z 1>&2 > /dev/null
    if [ $? == 0 ]; then
        echo -e "Number of zombie process on the system are :" $(ps -eo stat|grep -w Z|wc -l)
        echo -e "\n  Details of each zombie processes found   "
        echo -e "  $D"
        ZPROC=$(ps -eo stat,pid|grep -w Z|awk '{print $2}')
        for i in $(echo "$ZPROC"); do
            ps -o pid,ppid,user,stat,args -p $i
        done
    else
        echo -e "No zombie processes found on the system."
    fi
}

#=================================== Check Inode usage ===================================#
CheckInodeUsage()
{
    echo -e "\n\nChecking For INode Usage"
    echo -e "$D$D"
    echo -e "( 0-90% = OK/HEALTHY, 90-95% = WARNING, 95-100% = CRITICAL )"
    echo -e "$D$D"
    echo -e "INode Utilization (Percentage Used):\n"

    COL11=$(echo "$IUSAGE"|awk '{print $1" "$7}')
    COL22=$(echo "$IUSAGE"|awk '{print $6}'|sed -e 's/%//g')

    for i in $(echo "$COL22"); do
    {
        if [[ $i = *[[:digit:]]* ]]; then
        {
            if [ $i -ge 95 ]; then
                COL33="$(echo -e $i"% $CCOLOR\n$COL33")"
            elif [[ $i -ge 90 && $i -lt 95 ]]; then
                COL33="$(echo -e $i"% $WCOLOR\n$COL33")"
            else
                COL33="$(echo -e $i"% $GCOLOR\n$COL33")"
            fi
        }
        else
            COL33="$(echo -e $i"% (Inode Percentage details not available)\n$COL33")"
        fi
    }
    done

    COL33=$(echo "$COL33"|sort -k1n)
    paste  <(echo "$COL11") <(echo "$COL33") -d' '|column -t
}

#=================================== Check for SWAP Utilization ===================================#
CheckSwapUtilization()
{
    echo -e "\n\nChecking SWAP Details"
    echo -e "$D"
    echo -e "Total Swap Memory in MiB : "$(grep -w SwapTotal /proc/meminfo|awk '{print $2/1024}')", in GiB : "\
    $(grep -w SwapTotal /proc/meminfo|awk '{print $2/1024/1024}')
    echo -e "Swap Free Memory in MiB : "$(grep -w SwapFree /proc/meminfo|awk '{print $2/1024}')", in GiB : "\
    $(grep -w SwapFree /proc/meminfo|awk '{print $2/1024/1024}')
}

#=================================== Check for Processor Utilization (current data) ===================================#
CheckProcessorUtilization()
{
    echo -e "\n\nChecking For Processor Utilization"
    echo -e "$D"
    echo -e "\nCurrent Processor Utilization Summary :\n"
    mpstat|tail -2
}

#=================================== Check for load average (current data) ===================================#
CheckLoadAverage()
{
    echo -e "\n\nChecking For Load Average"
    echo -e "$D"
    echo -e "Current Load Average : $(uptime|grep -o "load average.*"|awk '{print $3" " $4" " $5}')"
}

#=================================== Print most recent 3 reboot events if available ===================================#
CheckMostRecentReboots()
{
    echo -e "\n\nMost Recent 3 Reboot Events"
    echo -e "$D$D"
    last -x 2> /dev/null|grep reboot 1> /dev/null && /usr/bin/last -x 2> /dev/null|grep reboot|head -3 || \
    echo -e "No reboot events are recorded."
}

#=================================== Print most recent 3 shutdown events if available ===================================#
CheckShutdownEvents()
{
    echo -e "\n\nMost Recent 3 Shutdown Events"
    echo -e "$D$D"
    last -x 2> /dev/null|grep shutdown 1> /dev/null && /usr/bin/last -x 2> /dev/null|grep shutdown|head -3 || \
    echo -e "No shutdown events are recorded."
}

#=================================== Print top 5 most memory consuming resources ===================================#
CheckTopFiveMemoryConsumers()
{
    echo -e "\n\nTop 5 Memory Resource Hog Processes"
    echo -e "$D$D"
    ps -eo pmem,pcpu,pid,ppid,user,stat,args | sort -k 1 -r | head -6|sed 's/$/\n/'
}

#=================================== Print top 5 most CPU consuming resources ===================================#
CheckTopFiveCPUConsumers()
{
    echo -e "\n\nTop 5 CPU Resource Hog Processes"
    echo -e "$D$D"
    ps -eo pcpu,pmem,pid,ppid,user,stat,args | sort -k 1 -r | head -6|sed 's/$/\n/'
}

#=================================== Execute functions in FUNCTIONS_TO_RUN variable ===================================#
for func in $(echo $FUNCTIONS_TO_RUN | sed "s/,/ /g"); do
    ${func}
done

#=================================== End of Script ===================================#
