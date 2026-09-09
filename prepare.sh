#!/usr/bin/env bash

#Shortcuts of colors
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
RESET='\e[0m'

#Error codes for echo -e
OK="${GREEN}[OK]${RESET}"
ERROR="${RED}[ERROR]${RESET}"
WARNING="${YELLOW}[WARNING]${RESET}"

# Parsing cycle
while [[ $# -gt 0 ]]; do
    case "$1" in
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --userpassword)
            PASSWORD="$2"
            shift 2
            ;;
        --sshport)
            SSHPORT="$2"
            shift 2
            ;;
        --ssh-publickey)
            SSH_PUBLIC_KEY="$2"
            shift 2
            ;;
        --skip-update)
            SKIPUPDATE=true
            shift
            ;;
        --skip-ssh-key-setup)
            SKIP_SSH_KEY_SETUP=true
            shift
            ;;
        --skip-fail2ban-setup)
            SKIP_FAIL2BAN_SETUP=true
            shift
            ;;
        --allow-root-login)
            ALLOW_ROOT_LOGIN=true
            shift
            ;;
        *)
            echo "An unknown parameter was passed: $1"
            echo "$ERROR installation was cancelled"
            exit 1
            ;;
    esac
done

update_system() {

	#Check if update is skipping
	if [ "$SKIPUPDATE" = true ]; then
		echo -e "$WARNING Skipped update becatuse of parameter --skip-update: $SKIPUPDATE"
		return 0
	fi
	
	#Update the System
	sudo apt update
	sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
	clear
	echo -e "$OK System was sucsessfully updated"
	
}

main(){
    
	#Clear console before all actions
	clear 

    update_system
}

main