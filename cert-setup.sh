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

# Installation parameters
SERVER_DOMAIN=""
USER_EMAIL_ADDRESS="test@example.com"

# installation flags
SKIPUPDATE=false

# Parsing cycle main
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-update)
            SKIPUPDATE=true
            shift
            ;;
        --domain)
            SERVER_DOMAIN="$2"
            shift 2
            ;;     
        --email)
            USER_EMAIL_ADDRESS="$2"
            shift 2
            ;;               
        *)
            echo "An unknown parameter was passed: $1"
            echo -e "$ERROR installation was cancelled"
            exit 1
            ;;
    esac
done

install_or_update() {
    # sudo apt update -qq > /dev/null 2>&1

    for pkg in "$@"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            echo -e "$OK $pkg already installed. Checking updates..."
            sudo apt install --only-upgrade -y "$pkg" > /dev/null 2>&1
        else
            echo -e "$INFO $pkg not found. Installing..."
            sudo apt install -y "$pkg" > /dev/null 2>&1
            echo -e "$OK $pkg installed"
        fi
    done
}

update_system() {

	# Check if update is skipping
	if [ "$SKIPUPDATE" = true ]; then
		echo -e "$WARNING Skipped system update because of $SKIPUPDATE parameter --skip-update"
		return 1
	fi

	# Update the System
	sudo apt update
	sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
	clear
	echo -e "$OK System updated"

    return 0
}

check_domain_ip() {
    local domain="$1"
    local server_ip domain_ip

    server_ip=$(curl -s --connect-timeout 5 ifconfig.me)
    domain_ip=$(getent hosts "$domain" | awk '{print $1}' | head -n 1)

    if [[ "$domain_ip" != "$server_ip" ]]; then
        return 1
    fi
}

show_certificates(){
    # Shows registered certificates
    echo ""
    sudo certbot certificates
    echo ""
    return 0
}

obtaining_certificate() {

    local serv_domain_name="$SERVER_DOMAIN"
    local user_email_address="$USER_EMAIL_ADDRESS"

    # Verificate format of serv_domain_name "example.com, www.example.com and etc."
    if [[ ! "$serv_domain_name" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        echo -e "$ERROR You submitted an invalid domain name. Abort"
        return 1
    fi

    # Check if certificates throught certbot already exist
    if certbot certificates 2>/dev/null | grep -q "Certificate Name"; then
        echo -e "$WARNING There are some sertificates. You might need to manually configurate them."
        show_certificates
        return 1
    fi

    # Validation if server ip actually attached to ip of that server
    if ! check_domain_ip "$serv_domain_name"; then
        echo "$ERROR The domain does not point to this server's IP. You might forgot to attach domain name"
        return 1
    fi

    # Checks if port 80/tcp is allowed for certbot in ufw
    if sudo ufw status | grep -qw "active"; then

        # Checks if port 80 is open on UFW
        if ! sudo ufw status | grep -Ew "(80/tcp|80|http)" | grep -qw "ALLOW"; then
            sudo ufw allow 80/tcp
            return 1
        fi

        echo -e "$OK Port 80 is allowed in firewall."
        return 1
    fi

    # Checks if port 80/tcp is listening
    if ss -tln | awk '{print $4}' | grep -qE ':(80)$'; then
        echo -e "$OK Port 80 is actively being listened on."
    else
        echo -e "$ERROR Port 80 is not being listened to by any service. You need manually check port configuration."
        return 1
    fi

    # Automatic issue certificates
    sudo certbot certonly --standalone --non-interactive --agree-tos --email "$user_email_address" -d "$serv_domain_name" 
    show_certificates
    return 0
}

main(){

    update_system
    install_or_update certbot curl
    obtaining_certificate

}

main