#!/bin/bash

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo "Этот скрипт должен быть запущен от имени root."
    exit 1
fi

# ==============================================================================
# 1. АВТОМАТИЧЕСКИЙ ВЫБОР ФИЗИЧЕСКОГО ИНТЕРФЕЙСА
# ==============================================================================

echo "Поиск доступных физических интерфейсов..."

# Ищем интерфейсы, исключая lo и виртуальные (содержат точку или являются bridges)
INTERFACES=()
for iface in /sys/class/net/*; do
    name=$(basename "$iface")
    # Проверяем, что это физическое устройство (есть папка device) и это не loopback
    if [[ "$name" != "lo" && "$name" != *.* && -d "$iface/device" ]]; then
        INTERFACES+=("$name")
    fi
done

if [ ${#INTERFACES[@]} -eq 0 ]; then
    echo "Ошибка: Физические интерфейсы не найдены."
    exit 1
fi

# Предлагаем выбор пользователю
PS3="Выберите номер интерфейса для настройки: "
select IFACE in "${INTERFACES[@]}"; do
    if [ -n "$IFACE" ]; then
        echo "Выбран интерфейс: $IFACE"
        break
    else
        echo "Неверный выбор. Попробуйте еще раз."
    fi
done

# ==============================================================================
# 2. НАСТРОЙКА ФИЗИЧЕСКОГО ИНТЕРФЕЙСА (TYPE=eth)
# ==============================================================================

# Создаем директорию конфигурации
mkdir -p /etc/net/ifaces/$IFACE

# Записываем параметры, которые вы передали
cat > /etc/net/ifaces/$IFACE/options <<EOF
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

# Создаем пустой файл ipv4address, чтобы система знала, что это статика без IP
touch /etc/net/ifaces/$IFACE/ipv4address

echo "[OK] Физический интерфейс $IFACE настроен."

# ==============================================================================
# 3. НАСТРОЙКА VLAN (Основная часть скрипта)
# ==============================================================================

# Запрос VLAN ID у пользователя
read -p "Введите список VLAN ID через пробел (например: 10 20 30): " VLANS

if [ -z "$VLANS" ]; then
    echo "VLAN не указаны. Настраиваем только физический интерфейс."
else
    for VLAN_ID in $VLANS; do
        # Формируем имя интерфейса (например eth0.10)
        VLAN_IF="${IFACE}.${VLAN_ID}"
        mkdir -p /etc/net/ifaces/${VLAN_IF}
        
        # Конфигурация VLAN
        cat > /etc/net/ifaces/${VLAN_IF}/options <<EOF
TYPE=vlan
HOST=$IFACE
VID=$VLAN_ID
DISABLED=no
NM_CONTROLLED=no
SYSTEMD_CONTROLLED=no
ONBOOT=yes
EOF

        echo "[OK] VLAN $VLAN_ID создан ($VLAN_IF)."
    done
fi

# ==============================================================================
# 4. АВТОМАТИЧЕСКОЕ ПОДНЯТИЕ ИНТЕРФЕЙСА
# ==============================================================================

echo ""
echo "Применение конфигурации (перезапуск network)..."
systemctl restart network

if [ $? -eq 0 ]; then
    echo "Сеть успешно перезапущена. Интерфейсы подняты."
else
    echo "Ошибка при перезапуске сети. Проверьте конфигурацию."
fi
