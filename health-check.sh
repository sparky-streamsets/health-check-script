#!/bin/bash

# Set defaults and initialize variables
declare -a TESTS_ALL          # Test functions should add their name to this array
declare -a TESTS_EXCLUDE      # List of tests that should not be executed
declare -a TESTS_INCLUDE      # List of tests that should be excecuted.
declare -A TESTS_DESCRIPTION  # Description of test.  Indexed by the test name.
declare -a TESTS_TARGET       # Capture whether to run a test based on the selected target product
declare -a REQUIRED_PROGRAMS  # Add any dependencies into this array
declare -a LOGOUTPUT          # capture string output to be displayed in log file
TARGET_PRODUCT=all # Can be all, sdc, dpm|sch, transformer|xfm  # Tests can use this to know what configurations to test
NONPROD=false
OWNER="sdc"
LOGFILE="health_check_result_$(date +%s).log"


S="************************************"
D="-------------------------------------"
COLOR="y"

GCOLOR=" [OK  ] "
WCOLOR=" [WARN] "
CCOLOR=" [FAIL] "
ICOLOR=" [INFO] "
if [ $COLOR == y ]; then
{
 GCOLOR="\e[47;32m${GCOLOR}\e[0m"
 WCOLOR="\e[43;31m${WCOLOR}\e[0m"
 CCOLOR="\e[47;31m${CCOLOR}\e[0m"
}
fi

#=================================== Base functions ===================================#
function HelpFunction()
{
    echo ""
    echo "Usage:$0 (-h|--help) (-u|--user) <svcacct> (-p|--process) <pid> --exclude <functionlist> --include <functionlist> (-n|--no-prod) (-t|--target <targetapp>)"
    echo -e "\n\n\tAvailable functions: CheckSupportedOS,CheckJVMVersion,CheckUlimit,PrintOSDetails,PrintSystemUptime,"
    echo -e "\tFindReadOnlyFileSystems,FindCurrentlyMountedFileSystems,CheckDiskUsage,FindZombieProcesses,"
    echo -e "\tCheckSwapUtilization,CheckProcessorUtilization,CheckMemorySettingsMatch,CheckMinMemory,"
    echo -e "\tCheckMaxMemory,CheckPctOfSysMemory"
    echo -e "\n\nOptions:"
    echo -e "\t-h | --help                        print this help message and exit"
    echo -e "\t-u | --user <uid>                  optional name of service account running StreamSets as a service (default: sdc)"
    echo -e "\t-p | --pid <pid>                   optional process id. Set when using more than one StreamSets process or if not a service"
    echo -e "\t-n | --no-prod                     set this to turn off certain warnings for non-production environments"
    echo -e "\t-x | --exclude <functionlist>      comma-separated list of functions not to execute"
    echo -e "\t-i | --include <functionlist>      comma-separated list of functions to execute (only execute these functions)\n"
    echo -e "\t-t | --target <targetproduct>      run only product-specific tests (possible values: *all*,sdc,dpm|sch,transformer|xfm)"
    exit 1 # Exit script after printing help
}
function RegisterTest()
{
    # RegisterTest TestFunctionName "Description of the test" "target product(s)" "any,programs,this,is,dependent,on"
    #echo "Registering ${#TESTS_ALL[@]} $1"
    TESTS_ALL+=($1)
    [ -n "$2" ] && TESTS_DESCRIPTION[$1]="$2"
    [ -n "$3" ] && TESTS_TARGET[$1]="$3"
    [ -n "$4" ] && REQUIRED_PROGRAMS+=( $( echo "$3" | sed 's/,/ /g') )
}
function ResultOutput
{
    # ResultOutput pass_fail_warn_info short_message optional_long_message
    case "$1" in
        OK|PASS|0)
            echo -e "$GCOLOR ${FUNCNAME[1]} $2"
            pass_fail=OK
            ;;
        ERR|ERROR|FAIL|1)
            echo -e "$CCOLOR ${FUNCNAME[1]} $2"
            pass_fail=FAIL
            ;;
        WARN|2)
            echo -e "$WCOLOR ${FUNCNAME[1]} $2"
            pass_fail=WARN
            ;;
        *)
            echo -e "$ICOLOR $2"
            pass_fail=UNKNOWN
            ;;
    esac
	[ -n "$3" ] && declare -a LOG_OUTPUT=("${!3}")
    LOGOUTPUT+="==================== [$pass_fail] ${FUNCNAME[1]} ====================\n${LOG_OUTPUT[@]}" &> $LOGFILE
}

function LogOutput
{
	[ -n "$1" ] && declare -a LOG_OUTPUT=("${!1}")
    LOGOUTPUT+="==================== ${FUNCNAME[1]} ====================\n${LOG_OUTPUT[@]}" &> $LOGFILE
}

unset PARAMS
while (( "$#" )); do
    case "$1" in
        '-?'|-h|--help)
            HelpFunction
            exit 0
            ;;
        --product)
            # Specify which StreamSets product this should execute for
            TARGET_PRODUCT=$2
            shift 2
            ;;
        -u|--user)
            OWNER=$2
            shift 2
            ;;
        -p|--pid)
            PID=$2
            shift 2
            ;;
        --exclude)
        	IFS=',' read -a TESTS_EXCLUDE <<< "$2"
            shift 2
            ;;
        --include)
        	IFS=',' read -a TESTS_INCLUDE <<< "$2"
            shift 2
            ;;
        -n|--no-prod)
            NONPROD="true"
            shift
            ;;
        -t|--target)
            TARGET_PRODUCT=$2
            shift 2
            ;;
        --) # end argument parsing
            shift
            break
            ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            exit 1
            ;;
        *) # preserve positional arguments in case we want to use them later (for now we should error)
            PARAMS="$PARAMS $1"
            shift
            ;;
    esac
done

#------variables used------#
MOUNT=$(mount|egrep -iw "ext4|ext3|xfs|gfs|gfs2|btrfs"|grep -v "loop"|sort -u -t' ' -k1,2)
FS_USAGE=$(df -PTh|egrep -iw "ext4|ext3|xfs|gfs|gfs2|btrfs"|grep -v "loop"|sort -k6n|awk '!seen[$1]++')
IUSAGE=$(df -PThi|egrep -iw "ext4|ext3|xfs|gfs|gfs2|btrfs"|grep -v "loop"|sort -k6n|awk '!seen[$1]++')

#=================================== PreflightChecks ===================================#
#=================================== Check supported OS ===================================#
RegisterTest "CheckSupportedOS" "Ensure that this is a supported operating system" "all"
function CheckSupportedOS() {
    # Per SDC and SCH install guides, we officially supported the OSes listed in the supported_os variable below
    # Our products may run on other OSes, but they have not been tested and verified by StreamSets
    # Possible results:
    # WARN - Detected OS is not listed among StreamSets certified platforms
    # OK - Detected OS has been certified by StreamSets

	local testResult=OK
	local report="Mac OSX is a supported OS"
	local logOut
    local supportedOS=("CentOS release 6" "CentOS Linux release 7" 
        "Oracle Linux Server release 6" "Oracle Linux Server release 7" 
        "Red Hat Enterprise Linux Server release 6" "Red Hat Enterprise Linux Server release 7" 
        "Ubuntu 14.04" "Ubuntu 16.04")
        
    if [[ `uname` == "Darwin" ]]; then
        logOut=("Mac OSX is a supported OS"
                    "\n \n")
    else
        local os=`[ -x /usr/bin/lsb_release ] &&  echo -e "Operating System :" $(lsb_release -d|awk -F: '{print $2}'|sed -e 's/^[ \t]*//')  || \
        echo -e "\nOperating System :" $(cat /etc/system-release)`
        local found="false"
        for i in $( echo "$supportedOS")
        do
        {
            if [[ "$os" == *"$i"* ]]; then
                found="true"
                report="$os is a supported OS"
                logOut=("$os is a supported OS"
                    "\n \n")
        	fi
        }
        done
        if [[ $found == "false" ]]; then
        	testResult=WARN
        	report="$os is not an officially supported OS"
            logOut=("The following operating systems are officially supported by StreamSets: Mac OSX,"
                "CentOS 6.x or 7.x, Oracle Linux 6.x or 7.x, RHEL 6.x or 7.x, and Ubuntu 14.04 or 16.04 LTS."
                "Other operating systems may still work but haven't been tested and certified by StreamSets"
                "\n \n")
        fi
    fi
    
    ResultOutput $testResult "${report}" logOut[@]
}

#=================================== Check compatible JVM version ===================================#
RegisterTest "CheckJVMVersion" "Ensure that a compatible JVM is installed and available"
function CheckJVMVersion() {
    # Per SDC and SCH install guides, the only currently supported JVM that hasn't reached EOL is
    # OpenJDK 8. TODO: revisit this once JVM 11 support is officially added
    # Possible results:
    # FAIL - No JVM installed or detected
    # WARN - JVM is not officially supported or has reached EOL
    # OK - OpenJDK 8 detected and available
    
    local testResult=OK
    local report="StreamSets-recommended OpenJDK 8 installed and available"
    local logOut
    
    if type -p java &>/dev/null
    then
        _java=java
    elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]]
    then
        _java="$JAVA_HOME/bin/java"
    else
        testResult=FAIL
        report="No JVM installed. Please install OpenJDK 8."
        logOut=("${report}"
            "\n \n")
    fi
    
    if [[ "$_java" ]]
    then
        vendor=$("$_java" -version 2>&1 | awk -F '"' '/version/ {print $1}')
        version=$("$_java" -version 2>&1 | head -1 | cut -d'"' -f2 | sed '/^1\./s///' | cut -d'.' -f1)
        if [[ "$vendor" != *"openjdk"* ]]; then
            testResult=WARN
            report="JVM vendor is not OpenJDK"
            logOut=("We noticed that you're not using a JVM provided by OpenJDK. JVMs provided by other"
                "vendors (i.e. Oracle, IBM, JRocket) will either not be compatible or will have reached EOL"
                "on JVM version 8. StreamSets recommends installing OpenJDK 8."
                "\n \n")
        elif [[ "$version" != 8 ]]
        then
            testResult=WARN
            report="JVM version is not 8"
        	logOut=("We noticed that your JVM version is not 8. Unfortunately, StreamSets is not yet"
        	    "compatible with newer versions of the JVM, and older versions have reached EOL. StreamSets"
        	    "recommends installing OpenJDK 8"
                "\n \n")
        else
            logOut=("${report}"
                "\n \n")
        fi
    fi
    
    ResultOutput $testResult "${report}" logOut[@]
}

#=================================== Check ulimit max file handle setting ===================================#
RegisterTest "CheckUlimit" "Ensure that hard and soft open file limit setting is set to required maximum: 32768"
function CheckUlimit() {
    # Per SDC install guide, the maximum hard and soft file limit should be at least 32768. On most Linux OSes
    # the default limit is 1024
    # Possible results:
    # FAIL - ulimit setting is too low
    # OK - ulimit setting is good
    
    local testResult=OK
    local report="Hard and soft open file limit setting is correct"
    local logOut
    
    if [[ `ulimit -n` < 32768 ]]
    then
        testResult=FAIL
        report="Open file limit setting too low (< 32768)"
        logOut=("StreamSets Data Collector requires maximum hard and soft open file limit setting of 32768."
        	"See https://access.redhat.com/solutions/61334 for info on how to set file limit"
            "\n \n")
    else
        logOut=("${report}"
            "\n \n") 
    fi
    
    ResultOutput $testResult "${report}" logOut[@]
}

#=================================== Check NTP service ===================================#
RegisterTest "SchPrereqNtp" "Verify ntp service is running and working."
function SchPrereqNtp() {
    # Per SCH install guide, Time must be syncrhonized using NTP
    # Method: https://www.cyberciti.biz/faq/linux-unix-bsd-is-ntp-client-working/
    # Possible results:
    # ERROR - NTP is not running.  ntpq outputs "ntpq: read: Connection refused"
    # WARN - NTP is running and reachable.  But the server is not in sync.
    # OK - NTP is running and ntpq output indicates it is synced with a server

    local testResult=FAIL
    local report="ntp service required but no ntp utilities found.  ntpstat missing."
    
    if ( which ntpstat >/dev/null )
    then
        # ntpstat exists.  Use it to determine if ntp is working
        ntpstat 2>/dev/null >/dev/null
        stat=$?
        case "$stat" in
            0)
                local ntpServer="$(ntpstat 2>/dev/null | head -n 1)"
                if [ "$ntpServer" = "unsynchronised" ]
                then
                    testResult=FAIL
                    report="ntp service is running but not in sync."
                else
                    testResult=OK
                    report="ntp service is running and in sync.  $ntpServer"
                fi
            ;;
            1)
                testResult=FAIL
                report="ntp service is running but not in sync."
            ;;
            2)
                testResult=FAIL
                report="ntp service cannot be reached and may not be running."
            ;;
        esac
    elif ( which ntpq >/dev/null )
    then
        # ntpq exists
        local linecount=$( ntpq -pn 2>&1 | wc -l )
        local selected_server=$( ntpq -pn 2>/dev/null | sed '/^\*/!d; s/ .*//' )  # Selected server starts with "*"
        if [ $linecount -le 1 ]
        then
            testResult=FAIL
            report="ntp service cannot be reached and may not be running."
        elif [ "$selected_server" = "" ]
        then
            testResult=FAIL
            report="ntp service is running but not in sync with a server.  Test with: ntpq -pn"
        else
            testResult=OK
            report="ntp service is running and in sync with ${selected_server}"
        fi
    fi
    
    local logOut=("${report}"
        "\n \n")
    ResultOutput $testResult "${report}" logOut[@]
}

#=================================== Check CPU Thread Count ===================================#
RegisterTest "SchPrereqCPUThreads" "Verify the number of CPU threads meets requirements"
function SchPrereqCPUThreads() {
    # Per SCH install guide, need at least 8 cores (threads) though 4 is okay for multiple node HA installs.
    # Method: https://www.cyberciti.biz/faq/check-how-many-cpus-are-there-in-linux-system/
    # Possible results:
    # ERROR - Did not meet minimum
    # WARN - Met minimum exactly
    # OK - Have more than minimum

    sch_min_threads=8
    local testResult=FAIL
    local report="Unable to access core and thread counts in /proc/cpuinfo"
    local num_cores=$( sed -n '/cpu cores/ {s/.* //g;p;q}' /proc/cpuinfo )
    local num_threads=$( grep -c processor /proc/cpuinfo )
    if [ $? -eq 0 ]
    then
        if [ $num_threads -lt $sch_min_threads ]
        then
            testResult=FAIL
            report="Number of CPU threads/cores is $num_threads which is less than minimum of $sch_min_threads"
        elif [ $num_threads -eq $sch_min_threads ]
        then
            testResult=WARN
            report="Number of CPU threads/cores is $num_threads which only meets the minimum of $sch_min_threads"
        else
            testResult=OK
            report="Number of CPU threads/cores is $num_threads which exceeds the minimum of $sch_min_threads"
        fi
    fi
    
    local logOut=("${report}"
        "\n \n")
        
    ResultOutput $testResult "${report}" logOut[@]
}

#=================================== Print Operating System Details ===================================#
RegisterTest "PrintOSDetails" "Logs system details (Hostname, Kernel, and OS architecture)"
function PrintOSDetails() {
    # Log-only function that prints additional information about the runtime environment
    # Possible results:
    # N/A
    
    local hostname=`hostname -f &> /dev/null && printf "Hostname : $(hostname -f)" || printf "Hostname : $(hostname -s)"`
    local kernel=$(echo -e "Kernel Version : " $(uname -r))
    local osarch=$(printf "OS Architecture : "$(arch | grep x86_64 &> /dev/null) && printf " 64 Bit OS\n"  || printf " 32 Bit OS\n")
    
    local logOut=("${hostname}"
        "\n${kernel}"
        "\n${osarch}"
        "\n \n")
    LogOutput logOut[@]
}

#=================================== Print system uptime ===================================#
RegisterTest "PrintSystemUptime" "Shows how long the host system has been running"
function PrintSystemUptime() {
    # Log-only function that prints the current system runtime
    # Possible results:
    # N/A
    
    local uptime=$(uptime)
    local currUptime=`echo $uptime|grep day &> /dev/null`
    local sysUptime=""
    
    if [ $? != 0 ]
        then
            currUptime=`echo $uptime|grep -w min &> /dev/null` && sysUptime=$(echo -e "System Uptime : "$(echo $uptime|awk '{print $2" by "$3}'|sed -e 's/,.*//g')" minutes") \
            || sysUptime=`echo -e "System Uptime : "$(echo $uptime|awk '{print $2" by "$3" "$4}'|sed -e 's/,.*//g')" hours"`
    else
        sysUptime=`echo -e "System Uptime : " $(echo $uptime|awk '{print $2" by "$3" "$4" "$5" hours"}'|sed -e 's/,//g')`
    fi
    
    local currDateTime=$(echo -e "Current System Date & Time : "$(date +%c))
    
    local logOut=("${sysUptime}"
        "\n${currDateTime}"
        "\n \n")
    LogOutput logOut[@]
}
        
#=================================== Check for any read-only file systems ===================================#
RegisterTest "FindReadOnlyFileSystems" "Checks to see if any read-only file systems are mounted in this environment"
function FindReadOnlyFileSystems() {
    # Log-only function that prints any read-only file systems
    # Possible results:
    # N/A
    
    local readonly=`echo "$MOUNT"|grep -w \(ro\) && echo -e "\n.....Read Only file system[s] found"|| echo -e ".....No read-only file system[s] found. "`
    local logOut=("${readonly}"
        "\n \n")
    LogOutput logOut[@]
}

#=================================== Check for currently mounted file systems ===================================#
RegisterTest "FindCurrentlyMountedFileSystems" "List currently mounted file systems"
function FindCurrentlyMountedFileSystems() {
    # Log-only function that prints the currently mounted file systems
    # Possible results:
    # N/A
    
    local currentMountFS=`echo "$MOUNT"|column -t`
    local logOut=("${currentMountFS}"
        "\n \n")
    LogOutput logOut[@]
}

#=================================== Check disk usage on all mounted file systems ===================================#
RegisterTest "CheckDiskUsage" "List mounted disk usage"
function CheckDiskUsage() {
    # Prints disk usage and generates a warning if the OS is about to run out of disk space
    # Possible results:
    # FAIL: At least one mounted disk is over 95% usage
    # WARN: At least one mounted disk is between 90 and 95% usage
    # OK: Mounted disc usage less than 90%
    
    local col1=$(echo "$FS_USAGE"|awk '{print $1 " "$7}')
    local col2=$(echo "$FS_USAGE"|awk '{print $6}'|sed -e 's/%//g')

    local testResult=OK
    local report="disk usage under 90%: $(echo $col1 $i)%"
    local logOut
    
    for i in $(echo "$col2"); do
    {
        if [ $i -ge 95 ]; then
            testResult=FAIL 
            report="disk usage exceeds 95%: $(echo $col1 $i)%"
        elif [[ $i -ge 90 && $i -lt 95 ]]; then
            testResult=WARN 
            report="disk usage high (90 - 95%): $(echo $col1 $i)%"
        fi
        
        logOut=("${report}"
            "\n \n")
        ResultOutput $testResult "${report}" logOut[@]
    }
    done
}

#=================================== Check for any zombie processes ===================================#
RegisterTest "FindZombieProcesses" "Look for non-responsive UNIX processes"
function FindZombieProcesses() {
    # Prints any non-responsive UNIX processes
    # Possible results:
    # WARN: Non-responsive processes listed in the logs
    # OK: No non-responsive processes found
    
    local testResult=OK
    local report="No zombie processes found on the system."
    local logOut
    
    ps -eo stat|grep -w Z 1>&2 > /dev/null
    if [ $? == 0 ]; then
        testResult=WARN
        report="Zombie processes found on system. Check log for more info."
        logOut=("Number of zombie process on the system are : $(ps -eo stat|grep -w Z|wc -l)"
            "\n  Details of each zombie processes found   "
            "  $D")
        ZPROC=$(ps -eo stat,pid|grep -w Z|awk '{print $2}')
        for i in $(echo "$ZPROC"); do
            logOut+=(`ps -o pid,ppid,user,stat,args -p $i`)
        done
    else
        logOut=("${report}"
            "\n \n")
    fi
    
    ResultOutput $testResult "${report}" logOut[@]
}

#=================================== Check for SWAP Utilization ===================================#
RegisterTest "CheckSwapUtilization" "Check the amount of swap disk usage"
function CheckSwapUtilization() {
    # Log-only function that prints the amount of swap space used in the system
    # Possible results:
    # N/A
    
    local swap1=`echo -e "Total Swap Memory in MiB : "$(grep -w SwapTotal /proc/meminfo|awk '{print $2/1024}')", in GiB : "\
    $(grep -w SwapTotal /proc/meminfo|awk '{print $2/1024/1024}')`
    local swap2=`echo -e "Swap Free Memory in MiB : "$(grep -w SwapFree /proc/meminfo|awk '{print $2/1024}')", in GiB : "\
    $(grep -w SwapFree /proc/meminfo|awk '{print $2/1024/1024}')`
    local logOut=("$(echo $swap1)" 
        "\n$(echo $swap2)"
        "\n \n")
    LogOutput logOut[@]
}

#=================================== Check for Processor Utilization (current data) ===================================#
RegisterTest "CheckProcessorUtilization" "Check to see the current CPU usage" "mpstat"
function CheckProcessorUtilization() {
    # Log-only function that prints the current CPU usage
    # Possible results:
    # N/A
    
    local logOut=("Current CPU Utilization Summary :\n"
        "\n`mpstat|tail -2`"
        "\n \n")
    LogOutput logOut[@]
}

#=================================== ServiceChecks ===================================#
#=================================== Pre-calc memory settings ===================================#
function CalcMemorySettings() {
    # Helper function that pre-calculates memory usage for specified process
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
RegisterTest "CheckMemorySettingsMatch" "Checks initial and heap sizes match."
function CheckMemorySettingsMatch() {
    # Checks to see if the initial and maximum heap sizes match, per industry-standard recommendations
    # Possible results:
    # WARN: initial and maximum heap sizes do not match
    # OK: initial and maximum heap sizes match
    
	CalcMemorySettings
	
	local testResult=OK
	local report="Current Initial and Maximum heap sizes match. Xms: $STREAMSETS_SDC_XMS    Xmx: $STREAMSETS_SDC_XMX"
	local logOut
	
    if [ $STREAMSETS_SDC_RAW_XMS -ne $STREAMSETS_SDC_RAW_XMX ]; then
        testResult=WARN 
        report="Initial and maximum heap sizes different. Xms: $STREAMSETS_SDC_XMS    Xmx: $STREAMSETS_SDC_XMX"
        logOut=("StreamSets recommends following the industry-standard best practice of setting the"
            "\ninitial and maximum heap sizes to the same value."
            "\nCurrent Xms: $STREAMSETS_SDC_XMS    Current Xmx: $STREAMSETS_SDC_XMX"
            "\n \n")
    else
        logOut=("${report}"
            "\n \n")
    fi
    
    ResultOutput $testResult "${report}" logOut[@]
}

#=================================== Check current against min recommended memory ===================================#
RegisterTest "CheckMinMemory" "Check current against min recommended memory"
function CheckMinMemory() {
    # Checks to see if the heap memory is at least 8 GB or 16 GB for production systems
    # Production warning can be disabled with the -n flag
    # Possible results:
    # FAIL: Heap memory is below 8 GB
    # WARN: Heap memory is below 16 GB for production systems (can be disabled)
    # OK: At least 8 GB (non-prod) or 16 GB (prod) heap space has been allocated
    
    CalcMemorySettings
    
    local testResult=INFO
    local report="Heap memory at or over recommended minimums. Xmx: $STREAMSETS_SDC_XMX"
    local logOut

    if [ $STREAMSETS_SDC_RAW_XMX -lt 8589934592 ]; then
        testResult=FAIL 
        report="At least 8 GB of heap memory required. Xmx: $STREAMSETS_SDC_XMX"
        logOut=("StreamSets recommends at least 8 GB of heap memory available for both production and non-production"
            "\nenvironments: Current Xmx: $STREAMSETS_SDC_XMX"
            "\n \n")
    elif [[ $STREAMSETS_SDC_RAW_XMX -lt 17179869184 && -z "$NONPROD" ]]; then
        testResult=WARN 
        report="At least 16 GB of heap memory required for production. Xmx: $STREAMSETS_SDC_XMX"
        logOut=("StreamSets recommends at least 16 GB of heap memory available for production environments."
            "\nTo suppress this warning in the future, set the -n flag. Current Xmx: $STREAMSETS_SDC_XMX"
            "\n \n")
    else
        logOut=("Sufficient memory is available to run StreamSets. Current Xmx: $STREAMSETS_SDC_XMX"
            "\n \n")
    fi
    
    ResultOutput $testResult "${report}" logOut[@]
}

#=================================== Check current against max recommended memory ===================================#
RegisterTest "CheckMaxMemory" "Check current against max recommended memory"
function CheckMaxMemory() {
    # Check to see if more than 64 GB has been allocated. According to some industry literature, garbage collection
    # will begin to become a bottleneck when the heap size is larger than 64 GB, regardless of which GC algorithm is used
    # Possible results:
    # ERROR: More than 64 GB heap space detected
    # OK: Less than 64 GB heap space detected
    
    CalcMemorySettings
    
    local testResult=OK
    local report="Heap memory under 64 GB limit. Xmx: $STREAMSETS_SDC_XMX"
    local logOut

    if [ $STREAMSETS_SDC_RAW_XMX -ge 68719476736 ]; then
        testResult=ERROR 
        report="64 GB max heap memory exceeded. Xmx: $STREAMSETS_SDC_XMX" 
        logOut=("StreamSets recommends no more than 64 GB of heap memory be available. Requiring more memory is often an"
            "\nindicator that the SDC has reached its carrying capacity. Current Xmx: $STREAMSETS_SDC_XMX"
            "\n \n")
    else
        logOut=("Available memory is not excessive (i.e. > 64 GB). Current Xmx: $STREAMSETS_SDC_XMX"
            "\n \n")
    fi
    
    ResultOutput $testResult "${report}" logOut[@]
}

#=================================== Check % of memory used by StreamSets ===================================#
RegisterTest "CheckPctOfSysMemory" "Check that % of memory in use by StreamSets is okay." "bc"
function CheckPctOfSysMemory() {
    # Check to see if the percentage of heap memory allocated to StreamSets is more than 75% of the total available system memory.
    # We should note that 75% is a heuristic that assumes that the StreamSets application is the only significant application
    # deployed on the system. This percentage may need to be adjusted up or down depending on circumstances
    # (e.g. other applications, low system memory, etc.)
    # Possible results:
    # WARN: More than 75% of available system memory allocated to StreamSets
    # OK: StreamSets consumes less than 75% of available system memory
    
    CalcMemorySettings
    
    local testResult=OK
    local report=""
    local logOut
    local sysmem="$(awk '/MemTotal/ { printf "%.0f \n", $2*1024 }' /proc/meminfo)"
    local sysmemInGB="$(awk '/MemTotal/ { printf "%.0f \n", $2/1024/1024 }' /proc/meminfo)"
    local pctOfSysmem="$(echo $STREAMSETS_SDC_RAW_XMX/$sysmem |bc -l)"
    pctOfSysmem=$(echo $pctOfSysmem*100 | bc -l)
    pctOfSysmem=$(printf %0.f $pctOfSysmem)
    if [ $pctOfSysmem -gt 75 ]; then
        testResult=WARN 
        report="Heap memory exceeds 75% of system memory. Xmx: $STREAMSETS_SDC_XMX    System: ${sysmemInGB}g"
        logOut=("StreamSets recommends that the heap size setting be no larger than 75% of"
            "\nthe available system memory.Current Xmx: $STREAMSETS_SDC_XMX   Total system memory: ${sysmemInGB}g"
            "\n \n")
    else
    	report="Heap memory under 75% of system memory. Xmx: $STREAMSETS_SDC_XMX    System: ${sysmemInGB}g"
        logOut=("Available heap memory is below 75% of total system memory."
            "Current Xmx: $STREAMSETS_SDC_XMX   Total system memory: ${sysmemInGB}g"
            "\n \n")
    fi
    
    ResultOutput $testResult "${report}" logOut[@]
}

#======================================================================================================================#
#================================================ Begin actual work ===================================================#
#======================================================================================================================#

# Test that required programs are installed
missing_programs=()
for c in $(printf '%s\n' "${REQUIRED_PROGRAMS[@]}" | sort -u )
do
   # Verify required programs are installed
   command -v ${c} >/dev/null 2>/dev/null || {
      missing_programs+=(${c})
   }
done
if [ ${#missing_programs[@]} -ne 0 ]
then
   echo ""
   echo "This script requires these program(s): ${missing_programs[@]}"
   echo "Please install using your package manager"
   echo ""
   exit 1
fi

# If they specified a list of tests to include then that becomes our list of tests
if [ ${#TESTS_INCLUDE[@]} -gt 0 ]
then
  TESTS_ALL=( ${TESTS_INCLUDE[@]} )
fi
# Now remove any tests in TESTS_EXCLUDE
for del in ${TESTS_EXCLUDE[@]}
do
   TESTS_ALL=("${TESTS_ALL[@]/$del}")
done

#=================================== Execute functions in TESTS_ALL variable ===================================#
for func in $(echo ${TESTS_ALL[@]} | sed "s/,/ /g"); do
    ${func}
done

#=================================== Print Log Output ===================================#
echo -e "${LOGOUTPUT}" &> $LOGFILE
