#!/bin/bash

# ssinspect.sh - Inspects JVMs used by StreamSets
# Written by Tim Smith 2020-06-11
#
# ssinspect.sh               # Lists all streamsets JVMs
# ---- TODO - Implement the following
# ssinspect.sh {processid}   # Gives detailed analysis of StreamSets process: Memory, file rights on any JVM parameters begining with "/", etc.

#com.streamsets.datatransformer.main.DataTransformerMain
#com.streamsets.datacollector.main.DataCollectorMain

# Loop through java processes looking for a StreamSets process
# It is a StreamSets process if:
# 1) It has a mainClass parameter
# 2) The mainClass begins with com.streamsets
declare -a all_streamsets_pid
declare -A pid_main_class
declare -A pid_files_open_count
declare -A pid_files_open_max
declare -A pid_user_name
declare -A pid_group_name
declare -A pid_user_id
declare -A pid_group_id


add_on="File Handles Current / Max"
javaPid="PID"
app="StreamSets App"

echo
printf "%-7s %-30s %s\n" "${javaPid}" "${app}" "${add_on}"
for javaPid in $( pgrep --exact java )
do
   mainClass=$(cat /proc/${javaPid}/cmdline | xargs -0 -n 1 | sed -n '/^-mainClass/{n;p}')
   if [[ ${mainClass} == com.streamsets.* ]]
   then
      app=${mainClass/com.streamsets./}
      app=${app/.*/}

      all_streamsets_pid+=(${javaPid})

      if ps -p ${javaPid} > /dev/null
      then 
         if [ ! -r /proc/${javaPid}/limits ]
         then 
            echo "ERROR: You do not have rights to /proc/${javaPid}/limits Try: sudo $0 $@"
            exit 1
         fi
      else
         # This process isn't running anymore.
         continue
      fi

      if [ ! -r /proc/${javaPid}/fd ]
      then
         echo "ERROR: You do not have rights to /proc/${javaPid}/fd Try: sudo $0 $@"
         exit 1
      fi
#      current_files_open=$( ls /proc/${javaPid}/fd | wc -l )
#      current_files_open=$( lsof -p ${javaPid} | wc -l )

      pid_main_class[$javaPid]="${app}"
      pid_files_open_count[$javaPid]=$( ls /proc/${javaPid}/fd | wc -l )
      pid_files_open_max[$javaPid]=$( sed '/Max open files/!d; s/Max open files \+//; s/ .\+//' /proc/${javaPid}/limits )
      pid_user_id[$javaPid]=$( grep Uid: /proc/${javaPid}/status | cut -f2 )
      pid_user_name[$javaPid]=$( getent passwd ${pid_user_id[$javaPid]} | cut -d: -f1 )
      pid_group_id[$javaPid]=$( grep Gid: /proc/${javaPid}/status | cut -f2 )
      pid_group_name[$javaPid]=$( getent passwd ${pid_group_id[$javaPid]} | cut -d: -f1 )

      LC_ALL=en_US.UTF-8 printf -v add_on "%'20d / %'6d" ${pid_files_open_count[$javaPid]} ${pid_files_open_max[$javaPid]}
      printf "%-7s %-30s %s\n" "${javaPid}" "${app}" "${add_on}"
   fi
done


declare -A java_properties
function getProcessJavaProperties() {
   local config # "variable=value"
   java_properties=()
   IFS=$'\n'
   for config in $( xargs -0 -n 1 --arg-file /proc/$1/cmdline | sed '/^-D/!d; s/^-D//;' )
   do
      config=$(echo ${config} | sed -e 's/^M//g')
      # Parse name=value and replace periods in the name with underscores.
      local config_name="${config%%=*}"
      local config_value="${config#*=}"
      java_properties["${config_name}"]="${config_value}"
   done
}

getProcessJavaProperties $javaPid

echo
echo The value for sdc.data.dir in process $javaPid is ${java_properties["sdc.data.dir"]}
