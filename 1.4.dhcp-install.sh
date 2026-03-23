#!/bin/bash

echo "Установка DHCP сервера..."
apt-get update -y
apt-get install -y isc-dhcp-server ipcalc

echo ""
echo "Автонастройка DHCP сервера"
echo "=========================="
echo ""

INTERFACES=()
IPS=()

# Получение интерфейсов (FIXED)
get_interfaces() {
    echo "Доступные сетевые интерфейсы:"
    echo "------------------------------"

    INDEX=1

    for iface in $(ip -4 -o addr show | awk '{print $2}' | cut -d@ -f1 | sort -u); do
        [ "$iface" = "lo" ] && continue

        IP=$(ip -4 -o addr show "$iface" | awk '{print $4}' | cut -d/ -f1)
        STATUS=$(ip link show "$iface" | grep -oP '(?<=state\s)\w+')

        if [ -n "$IP" ]; then
            INTERFACES+=("$iface")
            IPS+=("$IP")

            printf "%2d) %-15s [%s] (IP: %s)\n" "$INDEX" "$iface" "$STATUS" "$IP"
            ((INDEX++))
        fi
    done

    echo ""
}

# Выбор интерфейса
select_interface() {
    local prompt="$1"
    local selected_index

    while true; do
        read -p "$prompt" selection

        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            if [ "$selection" -ge 1 ] && [ "$selection" -le ${#INTERFACES[@]} ]; then
                selected_index=$((selection - 1))
                SELECTED_IFACE="${INTERFACES[$selected_index]}"
                echo "Выбран: $SELECTED_IFACE (${IPS[$selected_index]})"
                echo ""
                return 0
            else
                echo "Ошибка: введите число от 1 до ${#INTERFACES[@]}"
            fi
        elif [[ " ${INTERFACES[*]} " =~ " ${selection} " ]]; then
            SELECTED_IFACE="$selection"
            echo "Выбран: $SELECTED_IFACE"
            echo ""
            return 0
        else
            echo "Ошибка: неверный ввод"
        fi
    done
}

# Получение сети
get_network_info() {
    local iface=$1

    CIDR=$(ip -4 -o addr show "$iface" | awk '{print $4}')
    IP=$(echo "$CIDR" | cut -d/ -f1)

    NETWORK=$(ipcalc "$CIDR" | grep Network | awk '{print $2}' | cut -d/ -f1)
    NETMASK=$(ipcalc "$CIDR" | grep Netmask | awk '{print $2}')
    BROADCAST=$(ipcalc "$CIDR" | grep Broadcast | awk '{print $2}')

    START=$(echo $NETWORK | awk -F. '{print $1"."$2"."$3"."$4+10}')
    END=$(echo $BROADCAST | awk -F. '{print $1"."$2"."$3"."$4-1}')

    echo "$NETWORK $NETMASK $BROADCAST $START $END $IP"
}

# --- Запуск ---
get_interfaces

if [ ${#INTERFACES[@]} -lt 2 ]; then
    echo "Ошибка: нужно минимум 2 интерфейса с IP"
    exit 1
fi

select_interface "Выбери первый интерфейс: "
IFACE1="$SELECTED_IFACE"

select_interface "Выбери второй интерфейс: "
IFACE2="$SELECTED_IFACE"

if [ "$IFACE1" == "$IFACE2" ]; then
    echo "Ошибка: интерфейсы должны быть разные"
    exit 1
fi

echo "Используем: $IFACE1 и $IFACE2"
echo ""

echo "Определение параметров сети..."

NET1=($(get_network_info $IFACE1))
NET2=($(get_network_info $IFACE2))

echo ""
echo "$IFACE1 -> ${NET1[0]} / ${NET1[1]}"
echo "DHCP: ${NET1[3]} - ${NET1[4]}"
echo ""

echo "$IFACE2 -> ${NET2[0]} / ${NET2[1]}"
echo "DHCP: ${NET2[3]} - ${NET2[4]}"
echo ""

# Конфиг DHCP
echo "Создание /etc/dhcp/dhcpd.conf..."

cat > /etc/dhcp/dhcpd.conf <<EOF
default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet ${NET1[0]} netmask ${NET1[1]} {
  range ${NET1[3]} ${NET1[4]};
  option routers ${NET1[5]};
  option broadcast-address ${NET1[2]};
  option domain-name-servers 8.8.8.8, 8.8.4.4;
}

subnet ${NET2[0]} netmask ${NET2[1]} {
  range ${NET2[3]} ${NET2[4]};
  option routers ${NET2[5]};
  option broadcast-address ${NET2[2]};
  option domain-name-servers 8.8.8.8, 8.8.4.4;
}
EOF

# Интерфейсы DHCP
echo "Настройка интерфейсов..."

cat > /etc/default/isc-dhcp-server <<EOF
INTERFACESv4="$IFACE1 $IFACE2"
EOF

# Включение IP forwarding
echo "Включение маршрутизации..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Перезапуск
echo "Перезапуск DHCP..."
systemctl enable isc-dhcp-server
systemctl restart isc-dhcp-server

echo ""
echo "Готово!"
systemctl status isc-dhcp-server --no-pager