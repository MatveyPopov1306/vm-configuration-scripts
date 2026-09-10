#!/usr/bin/env bash

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

# Отключаем интерактивные запросы для полной автоматизации
export DEBIAN_FRONTEND=noninteractive

# Обновляем кэш и пакеты (-yqq для максимальной тишины и авто-согласия)
#apt-get update -qq
#apt-get upgrade -yqq

echo "Test Debug"

