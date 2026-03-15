#!/bin/bash

# ==============================================================================
# Скрипт настройки VLAN для ALT Linux (структура /etc/net/ifaces)
# ==============================================================================

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
  echo "Пожалуйста, запустите скрипт от имени root (sudo ./setup_vlans_interactive.sh)"
  exit 1
fi

# Проверка существования директории ALT Net
if [ ! -d "/etc/net/ifaces" ]; then
    echo "Ошибка: Директория /etc/net/ifaces не найдена."
    echo "Этот скрипт предназначен для ALT Linux."
    exit 1
fi

# ==============================================================================
# ФУНКЦИИ
# ==============================================================================

get_physical_iface() {
    # Ищем первый интерфейс, который не lo и не виртуальный
    IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$" | grep -v "^docker" | grep -v "^veth" | grep -v "^virbr" | head -n 1)
    
    if [ -z "$IFACE" ]; then
        echo "Ошибка: Не удалось определить физический интерфейс."
        exit 1
    fi
    echo "$IFACE"
}

# Расчет маски по количеству хостов
calculate_cidr() {
    local hosts=$1
    local bits=1
    while (( (1 << bits) - 2 < hosts )); do
        ((bits++))
    done
    echo $((32 - bits))
}

# Создание конфига VLAN
create_vlan_config() {
    local vlan_name=$1      # Имя для вывода (HQ, Office, etc)
    local vlan_id=$2        # Номер VLAN
    local iface=$3          # Физический интерфейс
    local network_octet=$4  # Третий октет сети (для уникальности)
    local hosts=$5          # Кол-во хостов
    
    local cidr=$(calculate_cidr $hosts)
    local vlan_dir="/etc/net/ifaces/${iface}.${vlan_id}"
    local network_ip="${BASE_NETWORK}.${network_octet}.0"
    local ip_address="${network_ip%.*}.2/$cidr" # IP сервера (.2)
    local full_network="${network_ip}/${cidr}"
    
    echo ""
    echo ">>> Настройка VLAN $vlan_id ($vlan_name)..."
    
    # 1. Создаем директорию
    mkdir -p "$vlan_dir"
    
    # 2. Создаем/обновляем options
    if [ ! -f "/etc/net/ifaces/${iface}/options" ]; then
        mkdir -p "/etc/net/ifaces/${iface}"
        cat > "/etc/net/ifaces/${iface}/options" <<EOF
BOOTPROTO=static
TYPE=eth
ONBOOT=yes
EOF
    fi
    
    cp "/etc/net/ifaces/${iface}/options" "$vlan_dir/options"
    
    # Обновляем параметры для VLAN
    sed -i "s/^TYPE=.*/TYPE=vlan/" "$vlan_dir/options"
    sed -i "s/^HOST=.*/HOST=${iface}/" "$vlan_dir/options"
    
    # Удаляем старые VID/DISABLED если есть
    grep -v "^VID=" "$vlan_dir/options" > "$vlan_dir/options.tmp" && mv "$vlan_dir/options.tmp" "$vlan_dir/options"
    grep -v "^DISABLED=" "$vlan_dir/options" > "$vlan_dir/options.tmp" && mv "$vlan_dir/options.tmp" "$vlan_dir/options"
    
    cat >> "$vlan_dir/options" <<EOF
VID=${vlan_id}
DISABLED=no
CONFIG_IPV4=yes
EOF

    # 3. Создаем ipv4address
    echo "$ip_address" > "$vlan_dir/ipv4address"
    
    # Вывод информации
    echo "    - VLAN ID: $vlan_id"
    echo "    - Сеть: $full_network"
    echo "    - IP интерфейса: $ip_address"
    echo "    - Доступно адресов: $(( (1 << (32 - cidr)) - 2 ))"
    echo "    - Директория: $vlan_dir"
}

# ==============================================================================
# ИНТЕРАКТИВНЫЙ ВВОД
# ==============================================================================

echo "========================================================"
echo "  Мастер настройки VLAN для ALT Linux"
echo "========================================================"
echo ""

PHYS_IFACE=$(get_physical_iface)
echo "Обнаружен физический интерфейс: $PHYS_IFACE"
echo ""

# Базовая сеть
read -p "Введите первые два октета сети [192.168]: " BASE_NETWORK_INPUT
BASE_NETWORK=${BASE_NETWORK_INPUT:-192.168}

echo ""
echo "--- Настройка VLAN 1 (Офис HQ) ---"
read -p "Введите номер VLAN для HQ [100]: " VLAN1_ID
VLAN1_ID=${VLAN1_ID:-100}
read -p "Требуемое количество хостов для HQ [50]: " VLAN1_HOSTS
VLAN1_HOSTS=${VLAN1_HOSTS:-50}

echo ""
echo "--- Настройка VLAN 2 (Офис 2) ---"
read -p "Введите номер VLAN для Офис 2 [200]: " VLAN2_ID
VLAN2_ID=${VLAN2_ID:-200}
read -p "Требуемое количество хостов для Офис 2 [100]: " VLAN2_HOSTS
VLAN2_HOSTS=${VLAN2_HOSTS:-100}

echo ""
echo "--- Настройка VLAN 3 (Управление) ---"
read -p "Введите номер VLAN для Управления [999]: " VLAN3_ID
VLAN3_ID=${VLAN3_ID:-999}
read -p "Требуемое количество хостов для Управления [10]: " VLAN3_HOSTS
VLAN3_HOSTS=${VLAN3_HOSTS:-10}

# ==============================================================================
# ПОДТВЕРЖДЕНИЕ
# ==============================================================================

echo ""
echo "========================================================"
echo "  Проверка конфигурации перед применением"
echo "========================================================"
echo "Физический интерфейс: $PHYS_IFACE"
echo "Базовая сеть: $BASE_NETWORK.0.0"
echo ""
echo "VLAN 1: ID=$VLAN1_ID, Хостов=$VLAN1_HOSTS, Сеть=${BASE_NETWORK}.10.x"
echo "VLAN 2: ID=$VLAN2_ID, Хостов=$VLAN2_HOSTS, Сеть=${BASE_NETWORK}.20.x"
echo "VLAN 3: ID=$VLAN3_ID, Хостов=$VLAN3_HOSTS, Сеть=${BASE_NETWORK}.99.x"
echo ""
read -p "Продолжить настройку? (y/n): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Настройка отменена."
    exit 0
fi

# ==============================================================================
# ПРИМЕНЕНИЕ НАСТРОЕК
# ==============================================================================

echo ""
echo "Применение настроек..."
echo "------------------------------------------------"

# Создаем VLAN (используем разные 3-и октеты для разделения сетей)
create_vlan_config "HQ" "$VLAN1_ID" "$PHYS_IFACE" 10 "$VLAN1_HOSTS"
create_vlan_config "Office2" "$VLAN2_ID" "$PHYS_IFACE" 20 "$VLAN2_HOSTS"
create_vlan_config "Management" "$VLAN3_ID" "$PHYS_IFACE" 99 "$VLAN3_HOSTS"

echo ""
echo "------------------------------------------------"
echo "Конфигурация завершена!"
echo ""

# Перезапуск сети
read -p "Перезапустить сетевую службу сейчас? (y/n): " RESTART_NET

if [[ "$RESTART_NET" =~ ^[Yy]$ ]]; then
    echo "Перезапуск службы сети..."
    if systemctl restart network 2>/dev/null; then
        echo "✓ Сеть перезагружена успешно."
    else
        echo "⚠ Не удалось перезапустить через systemctl."
        echo "  Попробуйте вручную: /etc/init.d/network restart"
    fi
fi

# Итоговый вывод
echo ""
echo "========================================================"
echo "  Итоговая информация"
echo "========================================================"
echo "Интерфейсы:"
ip addr show | grep -E "$PHYS_IFACE|${VLAN1_ID}|${VLAN2_ID}|${VLAN3_ID}" | head -20

echo ""
echo "Структура файлов:"
ls -la /etc/net/ifaces/ | grep -E "$PHYS_IFACE"

echo ""
echo "Готово!"
