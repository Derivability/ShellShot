#!/bin/sh

TEMPDIR=$(mktemp -d)
TEMPFILE="${TEMPDIR}.conf"
IFACE="wlan0"

BSSID=""
PIN="12345670"

function cleanup() 
{
	PID=$(jobs -l | awk '{print $2}')
	kill $PID
	rm -rf $TEMPDIR $TEMPFILE $PIPE
}

function gethex()
{
	echo $1 | cut -d : -f 3 | sed --expression='s/ //g'
}

echo -e "ctrl_interface=${TEMPDIR}\nctrl_interface_group=root\nupdate_config=1\n" > $TEMPFILE

echo "wps_reg $BSSID $PIN" | wpa_cli -B -i $IFACE -p $TEMPDIR &
wpa_supplicant -K -d -D nl80211 -i $IFACE -c $TEMPFILE

cleanup
wait
