#!/usr/bin/env bash
clear

# --- Константы и цвета ---
readonly RED='\e[31m' GREEN='\e[32m' YELLOW='\e[33m' BLUE='\e[34m' RESET='\e[0m'
readonly UFW_RULES_FILE="/etc/ufw/before.rules"
readonly SSHD_CONFIG_PATH="/etc/ssh/sshd_config"
readonly SSHD_CLOUD_INIT_PATH="/etc/ssh/sshd_config.d/50-cloud-init.conf"

# --- Глобальные переменные ---
USERNAME=""
PASSWORD=""
SSHPORT=""
SSH_PUBLIC_KEY=""

ALLOW_ROOT_LOGIN=false
SKIPUPDATE=false
SKIP_SSH_KEY_SETUP=false
SKIP_FAIL2BAN_SETUP=false
RESTORE_SSHD_CONFIG=false

# --- Вспомогательные функции ---
log_info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
log_ok() { echo -e "${GREEN}[OK]${RESET} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${RESET} $1"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $1" >&2; }
die() { log_error "$1"; exit 1; }

check_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "File '$file' does not exist."
        return 1
    fi
    return 0
}

get_config() {
    local file="$1" key="$2"
    local regex="^[[:space:]]*#?[[:space:]]*${key}([[:space:]]+.*)?$"
    check_file_exists "$file" || return 0
    grep -m 1 -E "$regex" "$file" || echo "Parameter '$key' not found."
}

set_config() {
    local file="$1" key="$2" val="$3"
    local regex="^[[:space:]]*#?[[:space:]]*${key}([[:space:]]+.*)?$"
    
    check_file_exists "$file" || return 0

    if grep -qE "$regex" "$file"; then
        sudo sed -i -E "/${regex}/{s@.*@${key} ${val}@; :a; n; ba;}" "$file"
    else
        echo "${key} ${val}" | sudo tee -a "$file" > /dev/null
    fi
    log_ok "Set: ${key} ${val}"
}

install_or_update() {
    for pkg in "$@"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            log_info "$pkg already installed. Checking updates..."
            sudo apt-get install --only-upgrade -y "$pkg" > /dev/null 2>&1
        else
            log_warn "$pkg not found. Installing..."
            sudo apt-get install -y "$pkg" > /dev/null 2>&1
        fi
    done
}

# --- Основные функции ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --username) USERNAME="$2"; shift 2 ;;
            --userpassword) PASSWORD="$2"; shift 2 ;;
            --sshport) SSHPORT="$2"; shift 2 ;;
            --ssh-publickey) SSH_PUBLIC_KEY="$2"; shift 2 ;;
            --skip-update) SKIPUPDATE=true; shift ;;
            --restore-sshd-config) RESTORE_SSHD_CONFIG=true; shift ;;
            --skip-ssh-key-setup) SKIP_SSH_KEY_SETUP=true; shift ;;
            --skip-fail2ban-setup) SKIP_FAIL2BAN_SETUP=true; shift ;;
            --allow-root-login) ALLOW_ROOT_LOGIN=true; shift ;;
            *) die "An unknown parameter was passed: $1\nInstallation cancelled." ;;
        esac
    done
}

update_system() {
    if [[ "$SKIPUPDATE" == true ]]; then
        log_warn "Skipped system update because of --skip-update"
        return 0
    fi
    
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -yqq
    sudo apt-get upgrade -yqq
    
    clear
    log_ok "System updated"
}   

apps_install() {
    if [[ "$SKIPUPDATE" == true ]]; then
        log_warn "Skipped apps installation because of --skip-update"
        return 0
    fi
    install_or_update ufw fail2ban
    log_ok "Apps were successfully installed"
}

create_user() {
    if [[ -z "$USERNAME" ]]; then
        log_warn "Username parameter was not provided. Skip sudo user creation"
        return 0
    fi

    if id "$USERNAME" &>/dev/null; then
        if id -nG "$USERNAME" | grep -qw "sudo"; then
            log_info "User $USERNAME already exists with right privileges, skipping."
            return 0
        fi
        sudo usermod -aG sudo "$USERNAME"
    fi
    
    if getent group "$USERNAME" > /dev/null; then
        sudo useradd -m -s /bin/bash -g "$USERNAME" "$USERNAME"
    else
        sudo useradd -m -s /bin/bash "$USERNAME"
    fi

    echo "$USERNAME:$PASSWORD" | sudo chpasswd
    sudo usermod -aG sudo "$USERNAME"
    log_ok "User $USERNAME was successfully created with sudo."
}

setup_authorized_keys() {
    local user="$USERNAME"
    local ssh_dir="/home/$user/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"

    if [[ "$SKIP_SSH_KEY_SETUP" == true ]] && [[ -n "$SSH_PUBLIC_KEY" ]]; then
        log_error "Conflicting arguments: --skip-ssh-key-setup and --ssh-publickey"
        return 0
    fi

    if [[ "$SKIP_SSH_KEY_SETUP" == true ]]; then
        log_warn "SSH-key setup was skipped."
        return 0
    fi

    if [[ -f "$auth_keys" && "$(stat -c %a "$auth_keys")" == "600" && "$(stat -c %a "$ssh_dir")" == "700" ]]; then
        log_ok "Authorized_keys already exists for $USERNAME with correct permissions."
    else
        sudo mkdir -p "$ssh_dir"
        sudo touch "$auth_keys"
        sudo chmod 700 "$ssh_dir"
        sudo chmod 600 "$auth_keys"
        sudo chown -R "$user:$user" "$ssh_dir"
    fi

    if [[ -s "$auth_keys" && -n "$SSH_PUBLIC_KEY" ]]; then
        local file_key
        file_key=$(< "$auth_keys" xargs)
        if [[ "$file_key" == "$SSH_PUBLIC_KEY" ]]; then
            log_ok "Your ssh key is already in $auth_keys"
            return 0
        fi
        sudo nano "$auth_keys"
    fi

    if grep -qE '^[[:space:]]*(ssh-|ecdsa-|sk-|rsa-)' "$auth_keys"; then
        log_ok "Your ssh key is already in $auth_keys"
        return 0
    fi

    if [[ ! -s "$auth_keys" ]]; then
        if [[ -n "$SSH_PUBLIC_KEY" ]]; then
            echo "$SSH_PUBLIC_KEY" | sudo tee -a "$auth_keys" > /dev/null
        else
            echo "# You haven't provided an ssh key. Paste it below:" | sudo tee -a "$auth_keys" > /dev/null
            sudo nano "$auth_keys"
        fi
    fi

    log_ok "Authorized_keys configured for $USERNAME."
}

change_default_ssh_port() {
    local ssh_path="/etc/ssh/"
    local sshd_cfg="${ssh_path}sshd_config"
    local sshd_cfg_backup="${ssh_path}sshd_config_backup"

    if [[ ! -f "$sshd_cfg" && -f "$sshd_cfg_backup" ]]; then
        log_warn "File sshd_config does not exist. Restoring from backup..."
        sudo cp -p "$sshd_cfg_backup" "$sshd_cfg"
    fi

    if [[ -z "$SSHPORT" ]]; then 
        log_warn "Custom ssh port config skipped (no port provided)."
        return 0
    fi
    
    if ! [[ "$SSHPORT" =~ ^[0-9]+$ ]] || (( SSHPORT <= 0 || SSHPORT > 65535 )); then
        log_error "Port $SSHPORT is not allowed. Skipping..."
        return 0
    fi

    if [[ -e "$sshd_cfg_backup" ]]; then
        log_ok "Backup $sshd_cfg_backup already exists."
    else
        sudo cp -p "$sshd_cfg" "$sshd_cfg_backup"
        log_ok "Backup created: $sshd_cfg_backup"
    fi

    if [[ "$RESTORE_SSHD_CONFIG" == true ]]; then
        if [[ -e "$sshd_cfg_backup" ]]; then
            log_warn "Restoring sshd_config file..."
            sudo cp -p "$sshd_cfg_backup" "$sshd_cfg"
        else
            log_error "No backup file found."
        fi
    fi

    if [[ "$SSHPORT" == "22" ]]; then
        log_warn "Custom ssh port config skipped (default 22 provided)."
        return 0
    fi

    set_config "$SSHD_CONFIG_PATH" "Port" "$SSHPORT"
}

sshd_config_configuration(){
    change_default_ssh_port

    set_config "$SSHD_CONFIG_PATH" "PasswordAuthentication" "no"
    set_config "$SSHD_CONFIG_PATH" "PubkeyAuthentication" "yes"
    set_config "$SSHD_CLOUD_INIT_PATH" "PasswordAuthentication" "no"

    if [[ "$ALLOW_ROOT_LOGIN" == true ]]; then
        set_config "$SSHD_CONFIG_PATH" "PermitRootLogin" "yes"
    fi

    set_config "$SSHD_CONFIG_PATH" "PermitEmptyPasswords" "no"
    set_config "$SSHD_CONFIG_PATH" "X11Forwarding" "no"

    if [[ -n "$USERNAME" ]]; then
        set_config "$SSHD_CONFIG_PATH" "AllowUsers" "$USERNAME"
    fi

    log_ok "$SSHD_CONFIG_PATH configured"
}

applying_sshd_config() {
    sudo sshd -t
    sudo systemctl daemon-reload && sudo systemctl restart ssh
    log_ok "sshd_config file was validated and applied"
}

ufw_config_configuration() {
    check_file_exists "$UFW_RULES_FILE" || return 0

    sudo ufw --force reset > /dev/null 2>&1

    local icmp_types=("destination-unreachable" "time-exceeded" "parameter-problem" "echo-request")
    for type in "${icmp_types[@]}"; do
        sudo sed -i "s/-A ufw-before-input -p icmp --icmp-type $type -j ACCEPT/-A ufw-before-input -p icmp --icmp-type $type -j DROP/" "$UFW_RULES_FILE"
        sudo sed -i "s/-A ufw-before-forward -p icmp --icmp-type $type -j ACCEPT/-A ufw-before-forward -p icmp --icmp-type $type -j DROP/" "$UFW_RULES_FILE"
    done

    sudo sed -i '/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' "$UFW_RULES_FILE"

    log_ok "Server ping was disabled"

    sudo ufw default deny incoming > /dev/null 2>&1
    sudo ufw default allow outgoing > /dev/null 2>&1
    sudo ufw allow http > /dev/null 2>&1
    sudo ufw allow https > /dev/null 2>&1

    if [[ -z "$SSHPORT" || "$SSHPORT" == "22" ]]; then
        sudo ufw allow OpenSSH > /dev/null 2>&1
    else
        local current_ssh_port
        current_ssh_port=$(get_config "$SSHD_CONFIG_PATH" "Port" | awk '{print $NF}')
        sudo ufw allow "$current_ssh_port" > /dev/null 2>&1
    fi 

    sudo ufw --force enable > /dev/null 2>&1
    log_ok "UFW was configured and enabled"
}

fail2ban_config_configuration() {
    local f2b_localconf_path="/etc/fail2ban/jail.local"

    if [[ "$SKIP_FAIL2BAN_SETUP" == true ]]; then
        log_warn "Fail2ban setup was skipped."
        return 0
    fi
    
    printf '%s\n' '[sshd]' 'enabled = true' 'maxretry = 3' 'findtime = 10m' 'bantime = 3h' | sudo tee "$f2b_localconf_path" > /dev/null
    
    sudo systemctl enable --now fail2ban > /dev/null 2>&1
    sudo systemctl restart fail2ban > /dev/null 2>&1
    
    log_ok "Fail2ban configured and enabled"
}

main() {
    parse_args "$@"
    
    update_system
    apps_install
    create_user
    setup_authorized_keys
    
    sshd_config_configuration
    applying_sshd_config
    
    ufw_config_configuration
    fail2ban_config_configuration
}

main "$@"