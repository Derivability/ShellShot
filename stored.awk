$1 == "BSSID:" {
	MAC = $2
	wifi[MAC]["BSSID"] = MAC
}
$1 == "ESSID:" {
	wifi[MAC]["SSID"] = $2
	printf "%s\t%s\n",wifi[MAC]["BSSID"],wifi[MAC]["SSID"]
}
