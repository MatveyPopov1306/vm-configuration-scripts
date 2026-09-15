#!/usr/bin/env bash

clear

# Shortcuts of colors
readonly RED='\e[31m'
readonly GREEN='\e[32m'
readonly YELLOW='\e[33m'
readonly BLUE='\e[34m'
readonly RESET='\e[0m'

# Error codes for echo -e
readonly INFO="${BLUE}[INFO]${RESET}"
readonly OK="${GREEN}[OK]${RESET}"
readonly ERROR="${RED}[ERROR]${RESET}"
readonly WARNING="${YELLOW}[WARNING]${RESET}"

# installation flags
SKIPUPDATE=false

# Parsing cycle main
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-update)
            SKIPUPDATE=true
            shift
            ;;
        *)
            echo "An unknown parameter was passed: $1"
            echo -e "$ERROR installation was cancelled"
            exit 1
            ;;
    esac
done

update_system() {

	# Check if update is skipping
	if [ "$SKIPUPDATE" = true ]; then
		echo -e "$WARNING Skipped system update because of $SKIPUPDATE parameter --skip-update"
		return 0
	fi

	# Update the System
	sudo apt update
	sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
	clear
	echo -e "$OK System updated"

}

main(){

    update_system

}

main