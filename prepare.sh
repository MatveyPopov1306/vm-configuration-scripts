#!/usr/bin/env bash

# Clear console before all actions
# Shortcuts of colors
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
RESET='\e[0m'

# Error codes for echo -e
INFO="${BLUE}[INFO]${RESET}"
OK="${GREEN}[OK]${RESET}"
ERROR="${RED}[ERROR]${RESET}"
WARNING="${YELLOW}[WARNING]${RESET}"

USERNAME=""
PASSWORD=''
SSHPORT=""
SSH_PUBLIC_KEY=""

# installation flags
ALLOW_ROOT_LOGIN=false
SKIPUPDATE=false
SKIP_SSH_KEY_SETUP=false
SKIP_FAIL2BAN_SETUP=false
RESTORE_SSHD_CONFIG=false

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
        --restore-sshd-config)
            RESTORE_SSHD_CONFIG=true
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

	# Check if update is skipping
	if [ "$SKIPUPDATE" = true ]; then
		echo -e "$WARNING Skipped system update because of $SKIPUPDATE parameter --skip-update"
		return 0
	fi
	
    # Отключаем интерактивные запросы для полной автоматизации
    export DEBIAN_FRONTEND=noninteractive

    # Обновляем кэш и пакеты (-yqq для максимальной тишины и авто-согласия)
    apt-get update -qq
    apt-get upgrade -yqq

	# Update the System
	# sudo apt update
	# sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
	clear
	echo -e "$OK System was sucsessfully updated"

}	

apps_install() {
    
    # Check if update is skipping
	if [ "$SKIPUPDATE" = true ]; then
		echo -e "$WARNING Skipped apps installation because of $SKIPUPDATE parameter --skip-update"
		return 0
	fi

    # Install apps
    install_or_update git curl wget ufw fail2ban

    echo -e "$OK Apps were sucsessfully installed"

}

create_user() {

    # Check if there are user's prvided paramets
    if [ -z "$USERNAME" ]; then
        echo -e "$WARNING Username pareametr was not provided. Skip sudo user creation"
        return 0
    fi

	# Check if user already exist
	if id "$USERNAME" &>/dev/null; then

        # Check if user has an admin privileges
        if id -nG "admin" | grep -qw "sudo"; then
            echo -e "$INFO User $USERNAME already exists with right privileges, skipping."
            return 0
        fi

		sudo usermod -aG sudo "$USERNAME"
	fi
	
	# Create a user with password and sudo
	sudo useradd -m -s /bin/bash "$USERNAME"
	echo "$USERNAME:$PASSWORD" | sudo chpasswd
	sudo usermod -aG sudo "$USERNAME"
	echo -e "$OK User $USERNAME was successfully created with sudo."
	
}

setup_authorized_keys() {

	local user="$USERNAME"
    local ssh_dir="/home/$user/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"

    # Checking arguments conflict --skip-ssh-key-setup and --ssh-publickey at the same time
    if [ "$SKIP_SSH_KEY_SETUP" = true ] && \
       [ ! -z "$SSH_PUBLIC_KEY" ]; then
        echo -e "$ERROR You should not use --skip-ssh-key-setup and --ssh-publickey arguements at the same time"
        return 0;
    fi

	#Check if ssh-key setup is skipping
	if [ "$SKIP_SSH_KEY_SETUP" = true ]; then
		echo -e "$WARNING SSH-key setup was skipped."
		return 0
	fi

	#Check if authorized_keys file is already exist
    if [[ -f "$auth_keys" ]] && \
       [[ "$(stat -c %a "$auth_keys")" == "600" ]] && \
       [[ "$(stat -c %a "$ssh_dir")" == "700" ]]; then
		#sudo nano "$auth_keys"
        echo -e "$OK Authorized_keys already exists for $USERNAME with correct permissions."
    else
        #Creating an authorized_keys file
	    sudo mkdir -p "$ssh_dir"
	    sudo touch "$auth_keys"
        sudo chmod 700 "$ssh_dir"
        sudo chmod 600 "$auth_keys"
        sudo chown -R "$user:$user" "$ssh_dir"
    fi

    # if auth_keys file isn't empty and user provides ssh-key argument -
    # resolving manualy thourght nano or compare ssh keys automatically
    if [[ -s "$auth_keys" ]] && \
       [[ ! -z "$SSH_PUBLIC_KEY" ]]; then

        # if that ssh is already in auth_keys file
        file_key=$(< "$auth_keys" xargs)
        if [[ "$file_key" == "$SSH_PUBLIC_KEY" ]]; then
            echo -e "$OK Your ssh key is already in $auth_keys"
            return 0
        fi

        sudo nano "$auth_keys"
    fi

    # Checks if there are any ssh-key look like string
    if grep -qE '^[[:space:]]*(ssh-|ecdsa-|sk-|rsa-)' "$auth_keys"; then
        echo -e "$OK Your ssh key is already in $auth_keys"
        return 0
    fi

    # if auth_keys file is empty fill ssh key automatic or manually
    if [[ ! -s "$auth_keys" ]]; then
        if [ ! -z "$SSH_PUBLIC_KEY" ]; then
		    echo "$SSH_PUBLIC_KEY" >> "$auth_keys"
	    else
            echo "# You haven't provided a ssh key throught arguemtns. You can paste ssh key below" >> "$auth_keys"
            sudo nano "$auth_keys"
	    fi
    fi

	echo -e "$OK Authorized_keys was successfully created for $USERNAME with correct permissions."
	
}

change_default_ssh_port() {

	local sshd_cfg_backup="sshd_config_backup"
	local sshd_cfg="sshd_config"
	local ssh_path="/etc/ssh/"

    # Check if ssh-port arg was lived untouchable - do not change sshd_config
    if [[ -z "$SSHPORT" ]]; then 
        echo -e "$WARNING Custom ssh port configuration was skipped. You haven't provide arguments"
        return 0
    fi
	
    # Check if SSHPORT contains a valid value
    if ! [[ "$SSHPORT" =~ ^[0-9]+$ ]] || (( SSHPORT <= 0 || SSHPORT > 65535 )); then
        echo -e "$ERROR Provided port number: $SSHPORT is not allowed. Skiping ssh port edit..."
        return
    fi

	# Check is there are any backup version of sshd_config
	if [ -e "$ssh_path$sshd_cfg_backup" ]; then
		echo -e "$OK A backup copy of sshd_config is already exists with name: $ssh_path$sshd_cfg_backup"
	else
        cp -p "$ssh_path$sshd_cfg" "$ssh_path$sshd_cfg_backup"
		#cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config_backup
		echo -e "$OK A backup copy of sshd_config was made with name: $ssh_path$sshd_cfg_backup"
	fi

    # Restore sshd_config file from backup if flag --restore-sshd-config
    if [ "$RESTORE_SSHD_CONFIG" == true ]; then
        if [ -e "$ssh_path$sshd_cfg_backup" ]; then
            echo -e "$WARNING Restoring $sshd_cfg file..."
            rm -rf "$ssh_path$sshd_cfg"
            cp -p "$ssh_path$sshd_cfg_backup" "$ssh_path$sshd_cfg"
        else
            echo -e "$ERROR There is no $sshd_cfg_backup file."
        fi
    fi

    # Check if user provides default 22 port for OpenSSH
    if [[ $SSHPORT == 22 ]]; then
        echo -e "$WARNING Custom ssh port configuration was skipped. You provided default $SSHPORT port in arguments"
        return 0
    fi

	# Change default OpenSSH port to custom
	if [ -e "$sshd_config_path" ]; then
		sed -i "s|^#\?Port .*$|Port ${SSHPORT}|" "$sshd_config_path"
		echo -e "$OK Default OpenSSH port was changed to $SSHPORT"
	else
		echo -e "$ERROR There is no file $sshd_config_path."
		exit 1
	fi
}


main(){

    update_system
    apps_install

    create_user
    setup_authorized_keys
    change_default_ssh_port
    
}

main