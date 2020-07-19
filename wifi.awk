$3 == iface {
	MAC = $2
	wifi[MAC]["BSSID"] = MAC
}
$1 == "SSID:" {
	wifi[MAC]["SSID"] = $2
}
$1 == "signal:" {
	wifi[MAC]["SIG"] = $2
}
$1 == "*" {
	if ($4 == "locked:") {
		wifi[MAC]["LOCKED"] = 1
	}
	else {
		if (wifi[MAC]["LOCKED"] != 1) {
			wifi[MAC]["LOCKED"] = 0
		}
	}
}
$3 == "Bands:"{
	printf "%s\t%s\t%s\t%s\n",wifi[MAC]["BSSID"],wifi[MAC]["SSID"],wifi[MAC]["SIG"],wifi[MAC]["LOCKED"]
	wifi[MAC]["LOCKED"] = 0
}
