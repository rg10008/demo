#!/bin/bash

################################################################################
#                                                                              #
#                  OPEN vSWITCH VLAN CONFIGURATION TOOL                        #
#                                                                              #
#  All-in-One скрипт для настройки и управления VLAN в Open vSwitch           #
#                                                                              #
#  Возможности:                                                                #
#  - Интерактивная настройка VLAN                                              #
#  - Автоматическая установка OVS                                              #
#  - Миграция IP адресов с роутера                                            #
#  - Мониторинг и управление                                                   #
#  - Автовосстановление после перезагрузки                                     #
#                                                                              #
################################################################################

# Версия
VERSION="2.0.0"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Глобальные переменные
BRIDGE_NAME="br0"
CONFIG_FILE="/etc/ovs-vlan-config.conf"
BACKUP_FILE="/etc/ovs-vlan-config.conf.backup"
LOG_FILE="/var/log/ovs-vlan-restore.log"
SERVICE_FILE="/etc/systemd/system/ovs-vlan-restore.service"

# Пути установки
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="ovs-vlan.sh"

################################################################################
#                              ОТОБРАЖЕНИЕ                                     #
################################################################################

print_header() {
    clear
    echo -e "${CYAN}"
    cat << 'LOGO'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║     ██████╗ ██████╗  ██████╗ ██████╗     █████╗   ██╗██╗   ██╗            ║
║    ██╔════╝██╔═══██╗██╔════╝██╔════╝    ██╔══██╗ ██║██║   ██║            ║
║    ██║     ██║   ██║██║     ██║         ███████║██║██║   ██║            ║
║    ██║     ██║   ██║██║     ██║         ██╔══██║██║╚██╗ ██╔╝            ║
║    ╚██████╗╚██████╔╝╚██████╗╚██████╗    ██║  ██║██║ ╚████╔╝             ║
║     ╚═════╝ ╚═════╝  ╚═════╝ ╚═════╝    ╚═╝  ╚═╝╚═╝  ╚═══╝              ║
║                                                                           ║
║                    VLAN Configuration Tool                                ║
LOGO
    echo -e "║                    Версия ${VERSION} | $(date '+%Y-%m-%d')                              ║"
    echo -e "╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_separator() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
}

print_section() {
    echo ""
    echo -e "${MAGENTA}▶ $1${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────${NC}"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_step() {
    echo -e "\n${CYAN}[ШАГ $1]${NC} ${BOLD}$2${NC}"
}

################################################################################
#                              ПРОВЕРКИ                                        #
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен с правами root"
        echo "Используйте: sudo $0 $@"
        exit 1
    fi
}

check_ovs_installed() {
    if ! command -v ovs-vsctl &> /dev/null; then
        return 1
    fi
    return 0
}

check_ovs_running() {
    if systemctl is-active --quiet openvswitch-switch 2>/dev/null || \
       systemctl is-active --quiet ovs-vswitchd 2>/dev/null; then
        return 0
    fi
    return 1
}

install_ovs() {
    print_info "Установка Open vSwitch..."
    
    if command -v apt &> /dev/null; then
        apt update && apt install -y openvswitch-switch openvswitch-common
    elif command -v yum &> /dev/null; then
        yum install -y openvswitch
        systemctl enable openvswitch
        systemctl start openvswitch
    elif command -v dnf &> /dev/null; then
        dnf install -y openvswitch
        systemctl enable openvswitch
        systemctl start openvswitch
    else
        print_error "Не удалось определить пакетный менеджер (apt/yum/dnf)"
        exit 1
    fi
    
    print_success "Open vSwitch успешно установлен"
}

ensure_ovs_ready() {
    if ! check_ovs_installed; then
        print_warning "Open vSwitch не установлен"
        echo ""
        echo -e "${YELLOW}Хотите установить Open vSwitch?${NC}"
        read -p "[Y/n]: " install_choice
        
        if [[ "$install_choice" =~ ^[Nn]$ ]]; then
            print_error "Open vSwitch необходим для работы скрипта"
            exit 1
        fi
        
        install_ovs
    else
        print_success "Open vSwitch установлен"
    fi
    
    if ! check_ovs_running; then
        print_warning "Сервис Open vSwitch не запущен, запускаем..."
        systemctl start openvswitch-switch 2>/dev/null || \
        systemctl start ovs-vswitchd 2>/dev/null || \
        {
            print_error "Не удалось запустить Open vSwitch"
            exit 1
        }
    fi
    print_success "Сервис Open vSwitch запущен"
}

################################################################################
#                         ПОЛУЧЕНИЕ ИНФОРМАЦИИ                                 #
################################################################################

get_physical_interfaces() {
    local interfaces=()
    
    while IFS= read -r iface; do
        if [[ "$iface" != "lo" ]] && \
           [[ ! "$iface" =~ ^docker ]] && \
           [[ ! "$iface" =~ ^veth ]] && \
           [[ ! "$iface" =~ ^br- ]] && \
           [[ ! "$iface" =~ ^ovs ]] && \
           [[ ! "$iface" =~ ^${BRIDGE_NAME}$ ]] && \
           [[ -d "/sys/class/net/$iface" ]]; then
            
            local device_path="/sys/class/net/$iface/device"
            if [[ -d "$device_path" ]] || [[ "$iface" =~ \. ]]; then
                interfaces+=("$iface")
            fi
        fi
    done < <(ls /sys/class/net/)
    
    echo "${interfaces[@]}"
}

get_interface_info() {
    local iface=$1
    local info=""
    
    local ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+')
    if [[ -n "$ip_addr" ]]; then
        info+="IP: ${GREEN}$ip_addr${NC}"
    else
        info+="IP: ${YELLOW}--${NC}"
    fi
    
    local mac_addr=$(cat /sys/class/net/$iface/address 2>/dev/null)
    info+=" | MAC: $mac_addr"
    
    local state=$(cat /sys/class/net/$iface/operstate 2>/dev/null)
    if [[ "$state" == "up" ]]; then
        info+=" | ${GREEN}UP${NC}"
    else
        info+=" | ${RED}$state${NC}"
    fi
    
    local speed=$(cat /sys/class/net/$iface/speed 2>/dev/null)
    if [[ -n "$speed" && "$speed" != "-1" ]]; then
        info+=" | ${speed}Mbps"
    fi
    
    if [[ "$iface" =~ \.([0-9]+)$ ]]; then
        local vlan_id="${BASH_REMATCH[1]}"
        info+=" | ${CYAN}VLAN: $vlan_id${NC}"
    fi
    
    echo "$info"
}

get_ip_for_vlan() {
    local iface=$1
    ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d./]+'
}

detect_vlans_from_interface() {
    local trunk_iface=$1
    local vlans=()
    
    print_info "Сканирование VLAN на интерфейсе $trunk_iface..."
    
    for iface in $(ls /sys/class/net/ 2>/dev/null); do
        if [[ "$iface" =~ ^${trunk_iface}\.([0-9]+)$ ]]; then
            local vlan_id="${BASH_REMATCH[1]}"
            local ip=$(get_ip_for_vlan "$iface")
            vlans+=("$vlan_id:$iface:$ip")
        fi
    done
    
    echo "${vlans[@]}"
}

get_used_ports() {
    ovs-vsctl list-ports "$BRIDGE_NAME" 2>/dev/null
}

################################################################################
#                         КОНФИГУРАЦИЯ OVS                                     #
################################################################################

backup_config() {
    print_info "Создание резервной копии..."
    ovs-vsctl show > "$BACKUP_FILE" 2>/dev/null
    print_success "Резервная копия: $BACKUP_FILE"
}

create_bridge() {
    print_info "Настройка моста $BRIDGE_NAME..."
    
    if ovs-vsctl br-exists "$BRIDGE_NAME" 2>/dev/null; then
        print_warning "Мост $BRIDGE_NAME уже существует"
        echo -e "${YELLOW}Пересоздать? (удалит текущую конфигурацию)${NC}"
        read -p "[y/N]: " recreate
        
        if [[ "$recreate" =~ ^[Yy]$ ]]; then
            ovs-vsctl del-br "$BRIDGE_NAME"
            ovs-vsctl add-br "$BRIDGE_NAME"
            print_success "Мост пересоздан"
        fi
    else
        ovs-vsctl add-br "$BRIDGE_NAME"
        print_success "Мост создан"
    fi
}

configure_trunk_port() {
    local trunk_iface=$1
    local vlan_list=$2
    
    print_info "Настройка trunk порта $trunk_iface..."
    
    ovs-vsctl --if-exists del-port "$BRIDGE_NAME" "$trunk_iface"
    ovs-vsctl add-port "$BRIDGE_NAME" "$trunk_iface"
    
    if [[ -n "$vlan_list" ]]; then
        ovs-vsctl set port "$trunk_iface" trunks="$vlan_list"
    fi
    
    print_success "Trunk порт настроен (VLAN: $vlan_list)"
}

configure_access_port() {
    local access_iface=$1
    local vlan_id=$2
    
    print_info "Настройка access порта $access_iface для VLAN $vlan_id..."
    
    ovs-vsctl --if-exists del-port "$BRIDGE_NAME" "$access_iface"
    ovs-vsctl add-port "$BRIDGE_NAME" "$access_iface"
    ovs-vsctl set port "$access_iface" tag="$vlan_id"
    
    ip link set "$access_iface" up 2>/dev/null
    
    print_success "Access порт $access_iface настроен (VLAN $vlan_id)"
}

migrate_ip() {
    local from_iface=$1
    local to_iface=$2
    
    local ip=$(get_ip_for_vlan "$from_iface")
    
    if [[ -z "$ip" ]]; then
        print_warning "IP не найден на $from_iface"
        return 1
    fi
    
    print_info "Миграция IP $ip с $from_iface на $to_iface..."
    
    # Удаляем с исходного интерфейса
    ip addr del "$ip" dev "$from_iface" 2>/dev/null
    
    # Добавляем на целевой
    ip addr add "$ip" dev "$to_iface" 2>/dev/null
    ip link set "$to_iface" up
    
    # Сохраняем для восстановления
    echo "$ip" > "/tmp/ovs_vlan_migrated_ip"
    
    print_success "IP $ip перенесён"
    return 0
}

save_vlan_config() {
    local trunk=$1
    shift
    local vlans=("$@")
    
    cat > "$CONFIG_FILE" << EOF
# Open vSwitch VLAN Configuration
# Generated: $(date)

BRIDGE_NAME=$BRIDGE_NAME
TRUNK_INTERFACE=$trunk

EOF
    
    local i=1
    for vlan_info in "${vlans[@]}"; do
        IFS=':' read -r vlan_id vlan_iface ip access_iface <<< "$vlan_info"
        echo "VLAN_${i}_ID=$vlan_id" >> "$CONFIG_FILE"
        echo "VLAN_${i}_ACCESS=$access_iface" >> "$CONFIG_FILE"
        echo "VLAN_${i}_IP=$ip" >> "$CONFIG_FILE"
        echo "" >> "$CONFIG_FILE"
        ((i++))
    done
    
    print_success "Конфигурация сохранена: $CONFIG_FILE"
}

################################################################################
#                         ИНТЕРАКТИВНОЕ МЕНЮ                                   #
################################################################################

show_interfaces_menu() {
    local interfaces=($(get_physical_interfaces))
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        print_error "Физические интерфейсы не найдены"
        exit 1
    fi
    
    echo ""
    printf "${CYAN}%-4s %-18s %s${NC}\n" "#" "Интерфейс" "Информация"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────${NC}"
    
    local i=1
    for iface in "${interfaces[@]}"; do
        local info=$(get_interface_info "$iface")
        printf "%-4s %-18s %b\n" "[$i]" "$iface" "$info"
        ((i++))
    done
    
    echo ""
}

select_interface() {
    local prompt=$1
    local interfaces=($(get_physical_interfaces))
    local exclude=$2
    
    while true; do
        echo -e "${YELLOW}$prompt${NC}"
        read -p "Номер [1-${#interfaces[@]}]: " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && \
           [[ "$choice" -ge 1 ]] && \
           [[ "$choice" -le ${#interfaces[@]} ]]; then
            
            local selected="${interfaces[$((choice-1))]}"
            
            if [[ -n "$exclude" ]] && [[ "$selected" == "$exclude" ]]; then
                print_error "Этот интерфейс уже используется"
                continue
            fi
            
            echo "$selected"
            return 0
        fi
        
        print_error "Неверный выбор"
    done
}

show_vlans_menu() {
    local vlans=("$@")
    
    echo ""
    printf "${CYAN}%-4s %-10s %-18s %-20s${NC}\n" "#" "VLAN" "Интерфейс" "IP"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────${NC}"
    
    local i=1
    for vlan_info in "${vlans[@]}"; do
        IFS=':' read -r vlan_id iface ip <<< "$vlan_info"
        printf "%-4s %-10s %-18s %-20s\n" "[$i]" "$vlan_id" "$iface" "${ip:---}"
        ((i++))
    done
    
    printf "%-4s %s\n" "[$i]" "Добавить VLAN вручную"
    printf "%-4s %s\n" "[0]" "Завершить настройку VLAN"
    echo ""
}

################################################################################
#                         ОСНОВНАЯ НАСТРОЙКА                                   #
################################################################################

do_setup() {
    print_header
    
    # Проверки
    print_step "1" "Проверка системы"
    print_separator
    ensure_ovs_ready
    backup_config
    
    # Выбор trunk
    print_step "2" "Выбор Trunk интерфейса (от роутера)"
    print_separator
    echo -e "${BOLD}Этот порт будет принимать все VLAN теги${NC}"
    show_interfaces_menu
    
    TRUNK_INTERFACE=$(select_interface "Выберите trunk порт:")
    print_success "Trunk: $TRUNK_INTERFACE"
    
    # Обнаружение VLAN
    print_step "3" "Обнаружение и настройка VLAN"
    print_separator
    
    local detected_vlans=($(detect_vlans_from_interface "$TRUNK_INTERFACE"))
    declare -a VLAN_CONFIGS
    declare -a USED_INTERFACES
    USED_INTERFACES+=("$TRUNK_INTERFACE")
    
    if [[ ${#detected_vlans[@]} -eq 0 ]]; then
        print_warning "VLAN не обнаружены автоматически"
        detected_vlans+=("manual:::")
    fi
    
    # Настройка VLAN
    while true; do
        show_vlans_menu "${detected_vlans[@]}"
        local max_choice=$((${#detected_vlans[@]}+1))
        
        echo -e "${YELLOW}Выберите VLAN для настройки [0-$max_choice]:${NC}"
        read -p "> " choice
        
        if [[ "$choice" == "0" ]]; then
            break
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && \
           [[ "$choice" -ge 1 ]] && \
           [[ "$choice" -le ${#detected_vlans[@]} ]]; then
            
            local vlan_info="${detected_vlans[$((choice-1))]}"
            IFS=':' read -r vlan_id vlan_iface ip <<< "$vlan_info"
            
            # Выбор access порта
            echo ""
            echo -e "${BOLD}Настройка VLAN $vlan_id${NC}"
            echo -e "${YELLOW}Выберите access порт для этого VLAN:${NC}"
            show_interfaces_menu
            
            ACCESS_INTERFACE=$(select_interface "Access порт для VLAN $vlan_id:" "$TRUNK_INTERFACE")
            
            # Проверяем что порт не занят
            if [[ " ${USED_INTERFACES[@]} " =~ " $ACCESS_INTERFACE " ]]; then
                print_error "Порт $ACCESS_INTERFACE уже используется"
                continue
            fi
            
            # Миграция IP
            if [[ -n "$ip" ]]; then
                echo ""
                echo -e "${YELLOW}Перенести IP $ip на $ACCESS_INTERFACE?${NC}"
                read -p "[Y/n]: " migrate
                
                if [[ ! "$migrate" =~ ^[Nn]$ ]]; then
                    migrate_ip "$vlan_iface" "$ACCESS_INTERFACE"
                fi
            fi
            
            VLAN_CONFIGS+=("$vlan_id:$vlan_iface:$ip:$ACCESS_INTERFACE")
            USED_INTERFACES+=("$ACCESS_INTERFACE")
            
            print_success "VLAN $vlan_id → $ACCESS_INTERFACE"
            
        elif [[ "$choice" -eq $max_choice ]]; then
            # Добавить вручную
            echo ""
            echo -e "${CYAN}Добавление VLAN вручную:${NC}"
            read -p "Номер VLAN: " vlan_id
            read -p "IP адрес (например 192.168.100.1/24): " ip
            
            echo ""
            show_interfaces_menu
            ACCESS_INTERFACE=$(select_interface "Access порт:" "$TRUNK_INTERFACE")
            
            if [[ -n "$ip" ]]; then
                echo -e "${YELLOW}Добавить IP $ip на $ACCESS_INTERFACE?${NC}"
                read -p "[Y/n]: " add_ip
                
                if [[ ! "$add_ip" =~ ^[Nn]$ ]]; then
                    ip addr add "$ip" dev "$ACCESS_INTERFACE"
                    ip link set "$ACCESS_INTERFACE" up
                fi
            fi
            
            VLAN_CONFIGS+=("$vlan_id:manual:$ip:$ACCESS_INTERFACE")
            USED_INTERFACES+=("$ACCESS_INTERFACE")
            detected_vlans+=("$vlan_id:manual:$ip")
            
            print_success "VLAN $vlan_id добавлен"
        fi
    done
    
    # Настройка интернета
    print_step "4" "Настройка интернета (untagged трафик)"
    print_separator
    
    echo -e "${YELLOW}Настроить передачу интернета через native VLAN?${NC}"
    read -p "[y/N]: " internet
    
    local native_vlan=""
    if [[ "$internet" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Native VLAN (untagged трафик):${NC}"
        read -p "[1 по умолчанию]: " native_vlan
        native_vlan=${native_vlan:-1}
        
        # Перенос IP с trunk на bridge
        local trunk_ip=$(get_ip_for_vlan "$TRUNK_INTERFACE")
        if [[ -n "$trunk_ip" ]]; then
            echo -e "${YELLOW}Найден IP $trunk_ip на $TRUNK_INTERFACE. Перенести на $BRIDGE_NAME?${NC}"
            read -p "[Y/n]: " move_ip
            
            if [[ ! "$move_ip" =~ ^[Nn]$ ]]; then
                ip addr del "$trunk_ip" dev "$TRUNK_INTERFACE" 2>/dev/null
                ip addr add "$trunk_ip" dev "$BRIDGE_NAME"
                ip link set "$BRIDGE_NAME" up
                
                # Шлюз
                local gw=$(ip route | grep default | awk '{print $3}')
                if [[ -n "$gw" ]]; then
                    ip route del default 2>/dev/null
                    ip route add default via "$gw" dev "$BRIDGE_NAME"
                fi
                
                print_success "IP перенесён на $BRIDGE_NAME"
            fi
        fi
    fi
    
    # Применение
    print_step "5" "Применение конфигурации"
    print_separator
    
    create_bridge
    
    # Собираем список VLAN
    local vlan_list=""
    for vlan_info in "${VLAN_CONFIGS[@]}"; do
        IFS=':' read -r vlan_id vlan_iface ip access_iface <<< "$vlan_info"
        vlan_list+="$vlan_id,"
    done
    vlan_list="${vlan_list%,}"
    
    configure_trunk_port "$TRUNK_INTERFACE" "$vlan_list"
    
    for vlan_info in "${VLAN_CONFIGS[@]}"; do
        IFS=':' read -r vlan_id vlan_iface ip access_iface <<< "$vlan_info"
        configure_access_port "$access_iface" "$vlan_id"
    done
    
    # Сохраняем
    save_vlan_config "$TRUNK_INTERFACE" "${VLAN_CONFIGS[@]}"
    
    # Результат
    print_step "6" "Результат"
    print_separator
    
    show_status
    
    # Предложение установить сервис
    echo ""
    echo -e "${YELLOW}Установить сервис автозагрузки?${NC}"
    read -p "[Y/n]: " install_svc
    
    if [[ ! "$install_svc" =~ ^[Nn]$ ]]; then
        do_install_service
    fi
    
    echo ""
    print_success "Настройка завершена!"
}

################################################################################
#                         КОМАНДЫ УПРАВЛЕНИЯ                                   #
################################################################################

show_status() {
    echo -e "${BOLD}${CYAN}Bridge:${NC}"
    ovs-vsctl list-br 2>/dev/null | while read br; do
        echo -e "  ${GREEN}●${NC} $br"
    done
    
    echo -e "\n${BOLD}${CYAN}Ports:${NC}"
    ovs-vsctl show 2>/dev/null | grep -E "Bridge|Port \"[a-z]" | while read line; do
        if [[ "$line" =~ Bridge ]]; then
            echo ""
            echo -e "${YELLOW}$line${NC}"
        else
            local port=$(echo "$line" | grep -oP 'Port "\K[^"]+')
            local tag=$(ovs-vsctl get port "$port" tag 2>/dev/null)
            local trunks=$(ovs-vsctl get port "$port" trunks 2>/dev/null)
            
            if [[ "$tag" != "[]" ]] && [[ -n "$tag" ]]; then
                echo -e "  ${GREEN}●${NC} $port ${CYAN}(Access VLAN: $tag)${NC}"
            elif [[ "$trunks" != "[]" ]] && [[ -n "$trunks" ]]; then
                echo -e "  ${GREEN}●${NC} $port ${MAGENTA}(Trunk: $trunks)${NC}"
            else
                echo -e "  ${GREEN}●${NC} $port"
            fi
        fi
    done
    
    echo ""
}

show_mac_table() {
    echo -e "${BOLD}${CYAN}MAC Address Table:${NC}\n"
    printf "${YELLOW}%-6s %-20s %-15s${NC}\n" "VLAN" "MAC" "Port"
    echo -e "${BLUE}────────────────────────────────────────────${NC}"
    
    ovs-appctl fdb/show "$BRIDGE_NAME" 2>/dev/null | tail -n +2 | while read line; do
        printf "%-6s %-20s %-15s\n" $line
    done
    
    echo ""
}

show_flows() {
    echo -e "${BOLD}${CYAN}OpenFlow Rules:${NC}\n"
    ovs-ofctl dump-flows "$BRIDGE_NAME" 2>/dev/null | head -20
    echo ""
}

show_stats() {
    echo -e "${BOLD}${CYAN}Interface Statistics:${NC}\n"
    
    for port in $(ovs-vsctl list-ports "$BRIDGE_NAME" 2>/dev/null); do
        echo -e "${YELLOW}$port:${NC}"
        ovs-vsctl get interface "$port" statistics 2>/dev/null | tr ',' '\n' | head -8 | while read stat; do
            echo -e "  $stat"
        done
        echo ""
    done
}

add_vlan_cmd() {
    local vlan_id=$1
    local access_port=$2
    local trunk_port=$3
    
    if [[ -z "$vlan_id" ]] || [[ -z "$access_port" ]]; then
        print_error "Использование: $0 add-vlan <vlan-id> <access-port> [trunk-port]"
        exit 1
    fi
    
    trunk_port=${trunk_port:-$(ovs-vsctl show | grep -B2 "trunks" | grep Port | head -1 | cut -d'"' -f2)}
    
    print_info "Добавление VLAN $vlan_id на $access_port..."
    
    configure_access_port "$access_port" "$vlan_id"
    
    # Обновляем trunk
    if [[ -n "$trunk_port" ]]; then
        local current=$(ovs-vsctl get port "$trunk_port" trunks 2>/dev/null)
        current=${current//[/}
        current=${current//]/}
        
        if [[ -n "$current" ]]; then
            ovs-vsctl set port "$trunk_port" trunks="$current,$vlan_id"
        else
            ovs-vsctl set port "$trunk_port" trunks="$vlan_id"
        fi
    fi
    
    print_success "VLAN $vlan_id добавлен"
}

remove_vlan_cmd() {
    local vlan_id=$1
    
    if [[ -z "$vlan_id" ]]; then
        print_error "Использование: $0 remove-vlan <vlan-id>"
        exit 1
    fi
    
    print_info "Удаление VLAN $vlan_id..."
    
    # Находим порты с этим VLAN
    for port in $(ovs-vsctl list-ports "$BRIDGE_NAME"); do
        local tag=$(ovs-vsctl get port "$port" tag 2>/dev/null)
        if [[ "$tag" == "$vlan_id" ]]; then
            ovs-vsctl del-port "$BRIDGE_NAME" "$port"
            print_info "Порт $port удалён"
        fi
    done
    
    # Обновляем trunk
    for port in $(ovs-vsctl list-ports "$BRIDGE_NAME"); do
        local trunks=$(ovs-vsctl get port "$port" trunks 2>/dev/null)
        if [[ "$trunks" != "[]" ]] && [[ "$trunks" =~ $vlan_id ]]; then
            trunks=${trunks//[/}
            trunks=${trunks//]/}
            trunks=${trunks//$vlan_id/}
            trunks=${trunks//,,/,}
            trunks=${trunks%,}
            trunks=${trunks#,}
            ovs-vsctl set port "$port" trunks="$trunks" 2>/dev/null
        fi
    done
    
    print_success "VLAN $vlan_id удалён"
}

monitor_traffic() {
    local interface=$1
    
    if [[ -z "$interface" ]]; then
        echo -e "${CYAN}Доступные интерфейсы:${NC}"
        ovs-vsctl list-ports "$BRIDGE_NAME" 2>/dev/null
        echo ""
        read -p "Выберите интерфейс: " interface
    fi
    
    print_info "Мониторинг $interface (Ctrl+C для остановки)..."
    tcpdump -i "$interface" -n -e "not port 22" 2>/dev/null || \
        print_error "Не удалось запустить tcpdump"
}

reset_config() {
    print_warning "Это удалит всю конфигурацию OVS!"
    read -p "Продолжить? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        ovs-vsctl del-br "$BRIDGE_NAME" 2>/dev/null
        rm -f "$CONFIG_FILE"
        print_success "Конфигурация сброшена"
    fi
}

################################################################################
#                         СЕРВИС АВТОЗАГРУЗКИ                                  #
################################################################################

get_script_path() {
    local script_path="$INSTALL_DIR/$SCRIPT_NAME"
    
    # Если скрипт уже установлен
    if [[ -f "$script_path" ]]; then
        echo "$script_path"
        return
    fi
    
    # Иначе используем текущий путь
    local current_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    echo "$current_script"
}

do_install_service() {
    local script_path=$(get_script_path)
    
    # Если скрипт не установлен в систему
    if [[ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        print_info "Установка скрипта в $INSTALL_DIR..."
        cp "${BASH_SOURCE[0]}" "$INSTALL_DIR/$SCRIPT_NAME"
        chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
        print_success "Скрипт установлен"
        script_path="$INSTALL_DIR/$SCRIPT_NAME"
    fi
    
    print_info "Создание systemd сервиса..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Open vSwitch VLAN Configuration Restore
After=network.target openvswitch-switch.service ovs-vswitchd.service
Requires=openvswitch-switch.service

[Service]
Type=oneshot
ExecStart=$script_path restore
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ovs-vlan-restore
    
    print_success "Сервис установлен и включён"
    echo ""
    echo -e "${CYAN}Команды управления сервисом:${NC}"
    echo "  systemctl status ovs-vlan-restore  - статус"
    echo "  systemctl start ovs-vlan-restore   - запуск восстановления"
    echo "  journalctl -u ovs-vlan-restore     - логи"
}

do_remove_service() {
    print_info "Удаление systemd сервиса..."
    
    systemctl disable ovs-vlan-restore 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    
    print_success "Сервис удалён"
}

do_restore() {
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
        [[ -t 1 ]] && echo "$1"
    }
    
    log "Восстановление конфигурации OVS VLAN..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "Конфигурация не найдена: $CONFIG_FILE"
        exit 0
    fi
    
    source "$CONFIG_FILE"
    
    sleep 2
    
    if ! ovs-vsctl br-exists "$BRIDGE_NAME" 2>/dev/null; then
        log "Создание моста $BRIDGE_NAME..."
        ovs-vsctl add-br "$BRIDGE_NAME"
    fi
    
    # Восстановление портов
    local i=1
    while true; do
        local vlan_id_var="VLAN_${i}_ID"
        local access_var="VLAN_${i}_ACCESS"
        
        if [[ -z "${!vlan_id_var}" ]]; then
            break
        fi
        
        local vlan_id="${!vlan_id_var}"
        local access="${!access_var}"
        
        if [[ -n "$access" ]]; then
            log "Настройка VLAN $vlan_id на $access..."
            ovs-vsctl --if-exists del-port "$BRIDGE_NAME" "$access"
            ovs-vsctl add-port "$BRIDGE_NAME" "$access"
            ovs-vsctl set port "$access" tag="$vlan_id"
            ip link set "$access" up 2>/dev/null
        fi
        
        ((i++))
    done
    
    # Trunk
    if [[ -n "$TRUNK_INTERFACE" ]]; then
        log "Настройка trunk $TRUNK_INTERFACE..."
        ovs-vsctl --if-exists del-port "$BRIDGE_NAME" "$TRUNK_INTERFACE"
        ovs-vsctl add-port "$BRIDGE_NAME" "$TRUNK_INTERFACE"
        
        local vlan_list=""
        i=1
        while true; do
            local vlan_id_var="VLAN_${i}_ID"
            [[ -z "${!vlan_id_var}" ]] && break
            vlan_list+="${!vlan_id_var},"
            ((i++))
        done
        vlan_list="${vlan_list%,}"
        
        [[ -n "$vlan_list" ]] && ovs-vsctl set port "$TRUNK_INTERFACE" trunks="$vlan_list"
    fi
    
    log "Восстановление завершено"
}

################################################################################
#                         УСТАНОВКА В СИСТЕМУ                                   #
################################################################################

do_install() {
    print_info "Установка $SCRIPT_NAME в систему..."
    
    cp "${BASH_SOURCE[0]}" "$INSTALL_DIR/$SCRIPT_NAME"
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    
    print_success "Установлено в $INSTALL_DIR/$SCRIPT_NAME"
    echo ""
    echo -e "${CYAN}Теперь можно запускать:${NC}"
    echo "  sudo ovs-vlan.sh setup    - настройка VLAN"
    echo "  sudo ovs-vlan.sh status   - статус"
    echo "  sudo ovs-vlan.sh help     - справка"
    
    echo ""
    echo -e "${YELLOW}Установить сервис автозагрузки?${NC}"
    read -p "[Y/n]: " install_svc
    
    if [[ ! "$install_svc" =~ ^[Nn]$ ]]; then
        do_install_service
    fi
}

do_uninstall() {
    print_warning "Удаление $SCRIPT_NAME из системы..."
    
    do_remove_service
    
    rm -f "$INSTALL_DIR/$SCRIPT_NAME"
    rm -f "$CONFIG_FILE"
    rm -f "$BACKUP_FILE"
    
    print_success "Удаление завершено"
}

################################################################################
#                              СПРАВКА                                         #
################################################################################

show_help() {
    print_header
    
    cat << EOF
${BOLD}ИСПОЛЬЗОВАНИЕ:${NC}
    $0 <команда> [аргументы]

${BOLD}КОМАНДЫ НАСТРОЙКИ:${NC}
    setup              Интерактивная настройка VLAN (по умолчанию)
    add-vlan <id> <port> [trunk]    Добавить VLAN на порт
    remove-vlan <id>   Удалить VLAN
    reset              Сбросить всю конфигурацию OVS

${BOLD}КОМАНДЫ МОНИТОРИНГА:${NC}
    status             Показать статус OVS
    mac                Показать MAC таблицу
    flows              Показать OpenFlow правила
    stats              Показать статистику интерфейсов
    monitor [iface]    Мониторинг трафика (tcpdump)

${BOLD}СИСТЕМНЫЕ КОМАНДЫ:${NC}
    install            Установить скрипт в систему
    uninstall          Удалить скрипт из системы
    install-service    Установить сервис автозагрузки
    remove-service     Удалить сервис автозагрузки
    restore            Восстановить конфигурацию (для systemd)

${BOLD}ПРИМЕРЫ:${NC}
    # Интерактивная настройка
    sudo $0 setup

    # Добавить VLAN 100 на порт eth1
    sudo $0 add-vlan 100 eth1

    # Показать статус
    sudo $0 status

    # Мониторинг трафика
    sudo $0 monitor eth1

${BOLD}ФАЙЛЫ:${NC}
    $CONFIG_FILE    Конфигурация VLAN
    $BACKUP_FILE    Резервная копия
    $LOG_FILE       Лог восстановления
    $SERVICE_FILE   Systemd unit

${BOLD}БЫСТРЫЙ СТАРТ:${NC}
    sudo $0 install     # Установить в систему
    sudo ovs-vlan.sh    # Запустить настройку

EOF
}

################################################################################
#                              ТОЧКА ВХОДА                                     #
################################################################################

main() {
    local command=${1:-setup}
    shift || true
    
    case "$command" in
        setup|'')
            check_root "$command"
            do_setup
            ;;
        status)
            show_status
            ;;
        mac)
            show_mac_table
            ;;
        flows)
            show_flows
            ;;
        stats)
            show_stats
            ;;
        add-vlan)
            check_root "$command"
            add_vlan_cmd "$@"
            ;;
        remove-vlan)
            check_root "$command"
            remove_vlan_cmd "$@"
            ;;
        monitor)
            monitor_traffic "$@"
            ;;
        reset)
            check_root "$command"
            reset_config
            ;;
        install)
            check_root "$command"
            do_install
            ;;
        uninstall)
            check_root "$command"
            do_uninstall
            ;;
        install-service)
            check_root "$command"
            do_install_service
            ;;
        remove-service)
            check_root "$command"
            do_remove_service
            ;;
        restore)
            check_root "$command"
            do_restore
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Неизвестная команда: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
