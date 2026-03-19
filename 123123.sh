#!/bin/bash

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите этот скрипт от имени root (sudo)."
    exit 1
fi

# ==============================================================================
# 1. АВТОМАТИЧЕСКИЙ ПОИСК И ВЫБОР ФИЗИЧЕСКОГО ИНТЕРФЕЙСА
# ==============================================================================

# Функция получения списка физических интерфейсов
get_physical_ifaces() {
    local ifaces=()
    for iface in /sys/class/net/*; do
        name=$(basename "$iface")
        
        # Фильтрация:
        # 1. Не loopback (lo)
        # 2. Не VLAN (не содержат точку, например eth0.10)
        # 3. Физическое устройство (наличие папки device)
        if [[ "$name" != "lo" && "$name" != *.* && -d "$iface/device" ]]; then
            ifaces+=("$name")
        fi
    done
    echo "${ifaces[@]}"
}

IFACE_LIST=$(get_physical_ifaces)

if [ -z "$IFACE_LIST" ]; then
    echo "Ошибка: Физические интерфейсы не найдены."
    exit 1
fi

echo "=============================================="
echo " Настройка физического интерфейса и VLAN"
echo "=============================================="
echo "Доступные физические интерфейсы:"

# Меню выбора для пользователя
PS3="Выберите номер интерфейса для настройки: "
select IFACE in $IFACE_LIST; do
    if [ -n "$IFACE" ]; then
        echo "Вы выбрали интерфейс: $IFACE"
        break
    else
        echo "Неверный выбор. Пожалуйста, введите номер из списка."
    fi
done

# ==============================================================================
# 2. НАСТРОЙКА ФИЗИЧЕСКОГО ИНТЕРФЕЙСА (TYPE=eth)
# ==============================================================================

CONFIG_DIR="/etc/net/ifaces/$IFACE"

echo "Создание конфигурации для $IFACE..."
mkdir -p "$CONFIG_DIR"

# Записываем файл options с вашими параметрами
cat > "$CONFIG_DIR/options" <<EOF
TYPE=eth
CONFIG_WIRELESS=no
BOOTPROTO=static
SYSTEMD_BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
ONBOOT=yes
EOF

# Если нужна статика, но IP не задан, создаем пустой файл ipv4address, 
# чтобы система знала, что интерфейс управляется вручную (иначе может быть dhcp)
touch "$CONFIG_DIR/ipv4address"

echo "[OK] Физический интерфейс $IFACE настроен."

# ==============================================================================
# 3. НАСТРОЙКА VLAN
# ==============================================================================

echo ""
echo "Настройка VLAN интерфейсов."
read -p "Введите список VLAN ID через пробел (например: 10 20 30): " VLAN_LIST

if [ -z "$VLAN_LIST" ]; then
    echo "VLAN не указаны. Настройка завершена только для физического интерфейса."
    exit 0
fi

for VLAN_ID in $VLAN_LIST; do
    # Проверка на корректность ID
    if ! [[ "$VLAN_ID" =~ ^[0-9]+$ ]]; then
        echo "Пропуск некорректного VLAN ID: $VLAN_ID"
        continue
    fi

    VLAN_IF="${IFACE}.${VLAN_ID}"
    VLAN_DIR="/etc/net/ifaces/${VLAN_IF}"
    
    echo "Настройка VLAN $VLAN_ID ($VLAN_IF)..."
    mkdir -p "$VLAN_DIR"

    # Конфигурация VLAN интерфейса
    cat > "$VLAN_DIR/options" <<EOF
TYPE=vlan
HOST=$IFACE
VID=$VLAN_ID
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
ONBOOT=yes
EOF

    # Спрашиваем IP для VLAN (опционально, можно убрать, если IP не нужны)
    read -p "Введите IP адрес для VLAN $VLAN_ID (например 192.168.${VLAN_ID}.1/24) или оставьте пустым: " VLAN_IP
    if [ -n "$VLAN_IP" ]; then
        echo "$VLAN_IP" > "$VLAN_DIR/ipv4address"
    fi

    echo "[OK] VLAN $VLAN_ID создан."
done

# ==============================================================================
# 4. ЗАВЕРШЕНИЕ
# ==============================================================================

echo ""
echo "Настройка сохранена в файлах."
echo "Для применения изменений выполните: systemctl restart network"
