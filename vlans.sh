#!/bin/bash

# ==============================================================================
# КОНФИГУРАЦИЯ
# ==============================================================================

# Укажите здесь требуемое количество адресов для каждой сети
# (Скрипт сам подберет оптимальную маску)
REQ_HOSTS_VLAN100=50   # Офис HQ
REQ_HOSTS_VLAN200=100  # Офис 2
REQ_HOSTS_VLAN999=10   # Управление

# Базовая сеть для расчета (можно изменить на 10.0.0.0 или другую)
BASE_NETWORK="192.168"

# ==============================================================================
# ФУНКЦИИ
# ==============================================================================

# Функция для определения физического интерфейса
get_physical_iface() {
    # Ищем первый интерфейс, который не lo и не начинается на docker/veth
    IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$" | grep -v "^docker" | grep -v "^veth" | head -n 1)
    
    if [ -z "$IFACE" ]; then
        echo "Ошибка: Не удалось определить физический интерфейс."
        exit 1
    fi
    echo "$IFACE"
}

# Функция расчета маски и сети по количеству хостов
# Возвращает: "NetworkIP CIDR"
calculate_subnet() {
    local hosts=$1
    local start_octet=$2
    
    # Находим степень двойки, которая вмещает хосты + 2 (сеть и бродкаст)
    local bits=1
    while (( (1 << bits) - 2 < hosts )); do
        ((bits++))
    done
    
    local cidr=$((32 - bits))
    local mask_decimal=$((0xFFFFFFFF << bits & 0xFFFFFFFF))
    
    # Формируем IP сети. 
    # Для простоты используем третий октет равный start_octet (например 10, 20, 99)
    # Это гарантирует, что сети не пересекутся, если октеты разные.
    local network_ip="${BASE_NETWORK}.${start_octet}.0"
    
    echo "$network_ip/$cidr"
}

# Функция создания конфига VLAN
create_vlan_config() {
    local vlan_id=$1
    local iface=$2
    local network_cidr=$3
    local server_ip_suffix=$4 # Обычно .2
    
    local vlan_dir="/etc/net/ifaces/${iface}.${vlan_id}"
    
    echo ">>> Настройка VLAN $vlan_id на интерфейсе $iface..."
    
    # 1. Создаем директорию
    mkdir -p "$vlan_dir"
    
    # 2. Создаем файл options
    # Копируем шаблон из физического интерфейса, если он есть, иначе создаем новый
    if [ -f "/etc/net/ifaces/${iface}/options" ]; then
        cp "/etc/net/ifaces/${iface}/options" "$vlan_dir/options"
    else
        # Создаем базовый options для физ. интерфейса, если его нет
        mkdir -p "/etc/net/ifaces/${iface}"
        cat > "/etc/net/ifaces/${iface}/options" <<EOF
BOOTPROTO=static
TYPE=eth
ONBOOT=yes
EOF
        cp "/etc/net/ifaces/${iface}/options" "$vlan_dir/options"
    fi

    # Редактируем options под VLAN
    # Мы используем sed для замены строк, чтобы не стирать лишнее
    sed -i "s/^TYPE=.*/TYPE=vlan/" "$vlan_dir/options"
    sed -i "s/^HOST=.*/HOST=${iface}/" "$vlan_dir/options"
    
    # Добавляем или обновляем специфичные для VLAN параметры
    # Удаляем старые записи VID/DISABLED если были, чтобы продублировать
    grep -v "^VID=" "$vlan_dir/options" > "$vlan_dir/options.tmp" && mv "$vlan_dir/options.tmp" "$vlan_dir/options"
    grep -v "^DISABLED=" "$vlan_dir/options" > "$vlan_dir/options.tmp" && mv "$vlan_dir/options.tmp" "$vlan_dir/options"
    
    cat >> "$vlan_dir/options" <<EOF
VID=${vlan_id}
DISABLED=no
CONFIG_IPV4=yes
EOF

    # 3. Создаем файл ipv4address
    # Берем сеть из CIDR, заменяем последний октет на .2
    local network_part=$(echo $network_cidr | cut -d'/' -f1 | cut -d'.' -f1-3)
    local ip_address="${network_part}.${server_ip_suffix}/${network_cidr#*/}"
    
    echo "$ip_address" > "$vlan_dir/ipv4address"
    
    echo "    - Сеть: $network_cidr"
    echo "    - IP Интерфейса: $ip_address"
    echo "    - Файлы созданы в: $vlan_dir"
    echo ""
}

# ==============================================================================
# ОСНОВНОЙ СЦЕНАРИЙ
# ==============================================================================

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
  echo "Пожалуйста, запустите скрипт от имени root (sudo)"
  exit 1
fi

# Проверка существования директории ALT Net
if [ ! -d "/etc/net/ifaces" ]; then
    echo "Ошибка: Директория /etc/net/ifaces не найдена."
    echo "Этот скрипт предназначен для ALT Linux (или систем с аналогичной структурой netconfig)."
    exit 1
fi

PHYS_IFACE=$(get_physical_iface)
echo "Обнаружен физический интерфейс: $PHYS_IFACE"
echo "Начинаем настройку VLAN..."
echo "------------------------------------------------"

# --- VLAN 100 (HQ) ---
# Используем 3-й октет 10 для наглядности
SUBNET_100=$(calculate_subnet $REQ_HOSTS_VLAN100 10)
create_vlan_config 100 "$PHYS_IFACE" "$SUBNET_100" 2

# --- VLAN 200 (Office) ---
# Используем 3-й октет 20
SUBNET_200=$(calculate_subnet $REQ_HOSTS_VLAN200 20)
create_vlan_config 200 "$PHYS_IFACE" "$SUBNET_200" 2

# --- VLAN 999 (Management) ---
# Используем 3-й октет 99
SUBNET_999=$(calculate_subnet $REQ_HOSTS_VLAN999 99)
create_vlan_config 999 "$PHYS_IFACE" "$SUBNET_999" 2

echo "------------------------------------------------"
echo "Конфигурация завершена."
echo "Перезапуск службы сети..."

# Перезапуск сети (команда может отличаться в зависимости от версии ALT)
if systemctl restart network 2>/dev/null; then
    echo "Сеть перезагружена успешно."
else
    echo "Предупреждение: Не удалось перезапустить сеть через systemctl. Попробуйте /etc/init.d/network restart"
fi

# Вывод итоговой информации
echo ""
echo "Итоговые настройки:"
ip addr show | grep -A 2 "$PHYS_IFACE"
