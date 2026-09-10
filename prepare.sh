#!/usr/bin/env bash

#Clear console before all actions
clear 

#Shortcuts of colors
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
RESET='\e[0m'

#Error codes for echo -e
INFO="${BLUE}[INFO]${RESET}"
OK="${GREEN}[OK]${RESET}"
ERROR="${RED}[ERROR]${RESET}"
WARNING="${YELLOW}[WARNING]${RESET}"

USERNAME=""
PASSWORD=''
SSHPORT="10122"
SSH_PUBLIC_KEY=""

# installation flags
ALLOW_ROOT_LOGIN=false
SKIPUPDATE=false
SKIP_SSH_KEY_SETUP=false
SKIP_FAIL2BAN_SETUP=false

# File paths
UFW_RULES_FILE="/etc/ufw/before.rules"
sshd_config_path="/etc/ssh/sshd_config"

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
            echo -e "$ERROR installation was cancelled"
            exit 1
            ;;
    esac
done

install_or_update() {
    sudo apt-get update -qq > /dev/null 2>&1
    for pkg in "$@"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            echo -e "$INFO $pkg already installed. Checking updates..."
            sudo apt-get install --only-upgrade -y "$pkg" > /dev/null 2>&1
        else
            echo -e "$WARNING $pkg not found. Installing..."
            sudo apt-get install -y "$pkg"
        fi
    done
}

update_system() {

	#Check if update is skipping
	if [ "$SKIPUPDATE" = true ]; then
		echo -e "$WARNING Skipped update becatuse of parameter --skip-update: $SKIPUPDATE"
		return 0
	fi
	
    # Отключаем интерактивные запросы для полной автоматизации
    export DEBIAN_FRONTEND=noninteractive

    # Обновляем кэш и пакеты (-yqq для максимальной тишины и авто-согласия)
    apt-get update -qq
    apt-get upgrade -yqq

	# Update the System
	#sudo apt update
	#sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
	clear
	echo -e "$OK System was sucsessfully updated"

}	

apps_install() {
    
    #Install apps
    install_or_update git curl wget ufw fail2ban

    echo -e "$OK Apps were sucsessfully installed"

}

create_user() {

    # Check if there are user's prvided paramets
    if [ -z "$USERNAME" ]; then
        echo -e "$WARNING Username pareametr was not provided. Skip sudo user creation"
        return 0
    fi

	#Check if user already exist
	if id "$USERNAME" &>/dev/null; then
		echo -e "$WARNING User $USERNAME already exists, skipping."
		return 0
	fi
	
	#Create a user
	sudo useradd -m -s /bin/bash "$USERNAME"
	echo "$USERNAME:$PASSWORD" | sudo chpasswd
	sudo usermod -aG sudo "$USERNAME"
	echo -e "$OK User $USERNAME was successfully created."
	
}

main(){

    update_system
    apps_install
    create_user
}

main