#!/bin/bash

#===============================================================================
# Скрипт автоматического создания VLAN интерфейсов
# Для Linux систем с /etc/net/ifaces/ (Alt Linux и подобные)
#===============================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Базовый путь к конфигурации сети
NET_BASE="/etc/net/ifaces"

#-------------------------------------------------------------------------------
# Функция для расчёта маски подсети на основе количества хостов
#-------------------------------------------------------------------------------
calculate_mask() {
    local hosts_needed=$1
    local mask_bits=0
    local hosts=1
    
    # Находим минимальное количество бит для хостов
    while [ $hosts -lt $((hosts_needed + 2)) ]; do
        hosts=$((hosts * 2))
        mask_bits=$((mask_bits + 1))
    done
    
    # Маска подсети в битах (32 - количество бит для хостов)
    local prefix=$((32 - mask_bits))
    
    echo $prefix
}

#-------------------------------------------------------------------------------
# Функция для преобразования префикса в маску вида x.x.x.x
#-------------------------------------------------------------------------------
prefix_to_netmask() {
    local prefix=$1
    local mask=""
    local full_octets=$((prefix / 8))
    local partial_octet=$((prefix % 8))
    
    for ((i=0; i<4; i++)); do
        if [ $i -lt $full_octets ]; then
            mask+="255"
        elif [ $i -eq $full_octets ]; then
            mask+="$((256 - (1 << (8 - partial_octet))))"
        else
            mask+="0"
        fi
        if [ $i -lt 3 ]; then
            mask+="."
        fi
    done
    
    echo $mask
}

#-------------------------------------------------------------------------------
# Функция для автоматического определения физического интерфейса
#-------------------------------------------------------------------------------
detect_physical_interface() {
    echo -e "${BLUE}[*] Поиск физического интерфейса...${NC}"
    
    # Ищем интерфейсы, исключая lo и VLAN интерфейсы (с точкой в имени)
    local interfaces=()
    
    for iface in /sys/class/net/*; do
        local name=$(basename $iface)
        
        # Пропускаем loopback и VLAN интерфейсы
        if [[ "$name" == "lo" ]] || [[ "$name" == *"."* ]]; then
            continue
        fi
        
        # Проверяем, что это реальный сетевой интерфейс
        if [ -d "$iface/device" ] || [ -f "$iface/operstate" ]; then
            # Проверяем, не является ли он bridge, bond, vlan и т.д.
            if [ ! -L "$iface/master" ]; then
                # Получаем тип интерфейса
                local iface_type=$(cat "$iface/type" 2>/dev/null || echo "1")
                
                # Тип 1 = ethernet (ARPHRD_ETHER)
                if [ "$iface_type" == "1" ]; then
                    interfaces+=("$name")
                fi
            fi
        fi
    done
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        echo -e "${RED}[!] Физический интерфейс не найден!${NC}"
        return 1
    fi
    
    # Если найден только один интерфейс
    if [ ${#interfaces[@]} -eq 1 ]; then
        echo "${interfaces[0]}"
        return 0
    fi
    
    # Если несколько интерфейсов - показываем список
    echo -e "${YELLOW}[*] Найдено несколько интерфейсов:${NC}"
    local idx=1
    for iface in "${interfaces[@]}"; do
        local ip=$(ip -4 addr show $iface 2>/dev/null | grep inet | awk '{print $2}' | cut -d'/' -f1)
        local status=$(cat /sys/class/net/$iface/operstate 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}$idx${NC}) $iface ${YELLOW}[IP: ${ip:-нет}, Статус: $status]${NC}"
        ((idx++))
    done
    
    echo -ne "${BLUE}Выберите номер интерфейса: ${NC}"
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#interfaces[@]} ]; then
        echo "${interfaces[$((choice-1))]}"
        return 0
    else
        echo -e "${RED}[!] Неверный выбор!${NC}"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Функция для получения IP физического интерфейса
#-------------------------------------------------------------------------------
get_interface_ip() {
    local iface=$1
    local ip_info=$(ip -4 addr show $iface 2>/dev/null | grep inet)
    
    if [ -z "$ip_info" ]; then
        echo ""
        return
    fi
    
    local ip=$(echo $ip_info | awk '{print $2}' | cut -d'/' -f1)
    local prefix=$(echo $ip_info | awk '{print $2}' | cut -d'/' -f2)
    
    echo "$ip/$prefix"
}

#-------------------------------------------------------------------------------
# Функция для создания директории интерфейса
#-------------------------------------------------------------------------------
create_interface_dir() {
    local iface_path=$1
    
    if [ ! -d "$iface_path" ]; then
        mkdir -p "$iface_path"
        echo -e "${GREEN}[+] Создана директория: $iface_path${NC}"
    else
        echo -e "${YELLOW}[*] Директория уже существует: $iface_path${NC}"
    fi
}

#-------------------------------------------------------------------------------
# Функция для создания options файла для физического интерфейса
#-------------------------------------------------------------------------------
create_physical_options() {
    local iface=$1
    local iface_path="$NET_BASE/$iface"
    
    create_interface_dir "$iface_path"
    
    local options_file="$iface_path/options"
    
    cat > "$options_file" << EOF
BOOTPROTO=static
TYPE=eth
EOF
    
    echo -e "${GREEN}[+] Создан файл: $options_file${NC}"
}

#-------------------------------------------------------------------------------
# Функция для создания VLAN интерфейса
#-------------------------------------------------------------------------------
create_vlan_interface() {
    local physical_iface=$1
    local vlan_id=$2
    local vlan_ip=$3
    local vlan_prefix=$4
    
    local vlan_iface="${physical_iface}.${vlan_id}"
    local vlan_path="$NET_BASE/$vlan_iface"
    
    echo -e "${BLUE}[*] Создание VLAN $vlan_id ($vlan_iface)...${NC}"
    
    # Создаём директорию
    create_interface_dir "$vlan_path"
    
    # Создаём options файл
    local options_file="$vlan_path/options"
    cat > "$options_file" << EOF
TYPE=vlan
HOST=$physical_iface
VID=$vlan_id
DISABLED=no
BOOTPROTO=static
ONBOOT=yes
CONFIG_IPV4=yes
EOF
    echo -e "${GREEN}[+] Создан файл: $options_file${NC}"
    
    # Создаём файл ipv4address
    local ipv4_file="$vlan_path/ipv4address"
    echo "${vlan_ip}/${vlan_prefix}" > "$ipv4_file"
    echo -e "${GREEN}[+] Создан файл: $ipv4_file${NC}"
    echo -e "${GREEN}    IP-адрес: ${vlan_ip}/${vlan_prefix}${NC}"
}

#-------------------------------------------------------------------------------
# Функция для расчёта IP-адреса VLAN на основе базового IP
#-------------------------------------------------------------------------------
calculate_vlan_ip() {
    local base_ip=$1
    local vlan_number=$2
    local octet3=$3
    
    # Извлекаем первые два октета из базового IP
    local octet1=$(echo $base_ip | cut -d'.' -f1)
    local octet2=$(echo $base_ip | cut -d'.' -f2)
    
    # Формируем IP для VLAN: первые два октета берём из базового,
    # третий задаём, четвёртый = 1 (шлюз/маршрутизатор)
    echo "${octet1}.${octet2}.${octet3}.1"
}

#-------------------------------------------------------------------------------
# Главная функция
#-------------------------------------------------------------------------------
main() {
    echo -e "${GREEN}"
    echo "=========================================="
    echo "   Автоматическое создание VLAN"
    echo "=========================================="
    echo -e "${NC}"
    
    # Проверка прав root
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}[!] Скрипт должен запускаться от root!${NC}"
        exit 1
    fi
    
    # 1. Определяем физический интерфейс
    PHYSICAL_IFACE=$(detect_physical_interface)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    echo -e "${GREEN}[+] Выбран физический интерфейс: $PHYSICAL_IFACE${NC}"
    
    # 2. Получаем текущий IP интерфейса
    CURRENT_IP=$(get_interface_ip "$PHYSICAL_IFACE")
    echo -e "${GREEN}[+] Текущий IP интерфейса: ${CURRENT_IP:-не назначен}${NC}"
    
    # 3. Создаём options для физического интерфейса
    echo -e "\n${BLUE}[*] Настройка физического интерфейса...${NC}"
    create_physical_options "$PHYSICAL_IFACE"
    
    # 4. Запрашиваем параметры для VLAN
    echo -e "\n${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}  Настройка параметров VLAN${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    
    # Базовый IP для VLAN (берём из физического интерфейса или спрашиваем)
    if [ -n "$CURRENT_IP" ]; then
        BASE_IP=$(echo $CURRENT_IP | cut -d'/' -f1)
        echo -e "${BLUE}[*] Базовый IP: $BASE_IP${NC}"
        echo -ne "${YELLOW}Использовать этот IP как основу для VLAN? (y/n) [y]: ${NC}"
        read -r use_base
        if [[ "$use_base" == "n" ]] || [[ "$use_base" == "N" ]]; then
            echo -ne "${BLUE}Введите базовый IP (например, 192.168.0.0): ${NC}"
            read -r BASE_IP
        fi
    else
        echo -ne "${BLUE}Введите базовый IP (например, 192.168.0.0): ${NC}"
        read -r BASE_IP
    fi
    
    # Массив для хранения VLAN конфигураций
    declare -A VLAN_CONFIG
    
    # 5. Настройка VLAN 100
    echo -e "\n${GREEN}=== VLAN 100 (Офис HQ) ===${NC}"
    echo -ne "${BLUE}Количество хостов для VLAN 100 [62]: ${NC}"
    read -r hosts_100
    hosts_100=${hosts_100:-62}
    prefix_100=$(calculate_mask $hosts_100)
    echo -e "${GREEN}[+] Маска: /$prefix_100 ($(prefix_to_netmask $prefix_100))${NC}"
    
    echo -ne "${BLUE}Третий октет IP для VLAN 100 [10]: ${NC}"
    read -r octet3_100
    octet3_100=${octet3_100:-10}
    
    vlan_ip_100=$(calculate_vlan_ip "$BASE_IP" 100 "$octet3_100")
    echo -ne "${BLUE}IP-адрес VLAN 100 [$vlan_ip_100]: ${NC}"
    read -r custom_ip_100
    vlan_ip_100=${custom_ip_100:-$vlan_ip_100}
    
    VLAN_CONFIG[100]="$vlan_ip_100:$prefix_100:$octet3_100"
    
    # 6. Настройка VLAN 200
    echo -e "\n${GREEN}=== VLAN 200 (Офис HQ) ===${NC}"
    echo -ne "${BLUE}Количество хостов для VLAN 200 [62]: ${NC}"
    read -r hosts_200
    hosts_200=${hosts_200:-62}
    prefix_200=$(calculate_mask $hosts_200)
    echo -e "${GREEN}[+] Маска: /$prefix_200 ($(prefix_to_netmask $prefix_200))${NC}"
    
    echo -ne "${BLUE}Третий октет IP для VLAN 200 [20]: ${NC}"
    read -r octet3_200
    octet3_200=${octet3_200:-20}
    
    vlan_ip_200=$(calculate_vlan_ip "$BASE_IP" 200 "$octet3_200")
    echo -ne "${BLUE}IP-адрес VLAN 200 [$vlan_ip_200]: ${NC}"
    read -r custom_ip_200
    vlan_ip_200=${custom_ip_200:-$vlan_ip_200}
    
    VLAN_CONFIG[200]="$vlan_ip_200:$prefix_200:$octet3_200"
    
    # 7. Настройка VLAN 999
    echo -e "\n${GREEN}=== VLAN 999 (Управление) ===${NC}"
    echo -ne "${BLUE}Количество хостов для VLAN 999 [14]: ${NC}"
    read -r hosts_999
    hosts_999=${hosts_999:-14}
    prefix_999=$(calculate_mask $hosts_999)
    echo -e "${GREEN}[+] Маска: /$prefix_999 ($(prefix_to_netmask $prefix_999))${NC}"
    
    echo -ne "${BLUE}Третий октет IP для VLAN 999 [99]: ${NC}"
    read -r octet3_999
    octet3_999=${octet3_999:-99}
    
    vlan_ip_999=$(calculate_vlan_ip "$BASE_IP" 999 "$octet3_999")
    echo -ne "${BLUE}IP-адрес VLAN 999 [$vlan_ip_999]: ${NC}"
    read -r custom_ip_999
    vlan_ip_999=${custom_ip_999:-$vlan_ip_999}
    
    VLAN_CONFIG[999]="$vlan_ip_999:$prefix_999:$octet3_999"
    
    # 8. Подтверждение
    echo -e "\n${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}  Сводка конфигурации${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "Физический интерфейс: ${GREEN}$PHYSICAL_IFACE${NC}"
    echo -e "Базовый IP: ${GREEN}$BASE_IP${NC}"
    echo ""
    echo -e "VLAN 100: ${GREEN}${vlan_ip_100}/${prefix_100}${NC} (до $hosts_100 хостов)"
    echo -e "VLAN 200: ${GREEN}${vlan_ip_200}/${prefix_200}${NC} (до $hosts_200 хостов)"
    echo -e "VLAN 999: ${GREEN}${vlan_ip_999}/${prefix_999}${NC} (до $hosts_999 хостов)"
    echo ""
    
    echo -ne "${YELLOW}Применить конфигурацию? (y/n) [y]: ${NC}"
    read -r confirm
    
    if [[ "$confirm" == "n" ]] || [[ "$confirm" == "N" ]]; then
        echo -e "${RED}[!] Отменено пользователем.${NC}"
        exit 0
    fi
    
    # 9. Создание VLAN интерфейсов
    echo -e "\n${BLUE}[*] Создание VLAN интерфейсов...${NC}"
    
    create_vlan_interface "$PHYSICAL_IFACE" 100 "$vlan_ip_100" "$prefix_100"
    create_vlan_interface "$PHYSICAL_IFACE" 200 "$vlan_ip_200" "$prefix_200"
    create_vlan_interface "$PHYSICAL_IFACE" 999 "$vlan_ip_999" "$prefix_999"
    
    # 10. Предложение перезапустить сеть
    echo -e "\n${YELLOW}=========================================${NC}"
    echo -ne "${YELLOW}Перезапустить сеть? (y/n) [y]: ${NC}"
    read -r restart_network
    
    if [[ "$restart_network" != "n" ]] && [[ "$restart_network" != "N" ]]; then
        echo -e "${BLUE}[*] Перезапуск сети...${NC}"
        systemctl restart network
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[+] Сеть успешно перезапущена!${NC}"
        else
            echo -e "${RED}[!] Ошибка при перезапуске сети!${NC}"
        fi
    fi
    
    # 11. Показать результат
    echo -e "\n${GREEN}=========================================${NC}"
    echo -e "${GREEN}  VLAN интерфейсы созданы!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "Проверьте командой: ${YELLOW}ip addr show${NC}"
    echo -e "Или: ${YELLOW}ip link show type vlan${NC}"
}

#-------------------------------------------------------------------------------
# Запуск скрипта
#-------------------------------------------------------------------------------
main "$@"