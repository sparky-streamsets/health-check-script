 ------""------- Linux System Health Check with StreamSets Enhancements ------""------- 

Here is a script to check the basic health status of a linux system with enhancements to check whether the system is in alignment with StreamSets best practice recommendations.

This script has been tested to run successfully on Amazon Linux. It may work on other variants as well, however, these have not been tested. These tests were run on virtual machines.

This is a small, light weight script which makes use of native Linux utilities to get the required details and doesn't need much space.

v0.1 - Tests memory settings of StreamSets Data Collector

Usage:

./health-check.sh [-h][-u useracct][-p pid][-n]

-u user account running StreamSets Data Collector (default: sdc)  
-p specific process id to evaluate (use when you either have more than one SDC or SDC and Transformer running on the same machine)  
-n turns off checks for production systems  
-h prints this usage and exits  

For more details check the below web link :-
https://www.simplylinuxfaq.com/2015/05/How-To-Check-Health-Status-Of-Linux-System.html

                                                                    Updated on : 15-Apr-2020
