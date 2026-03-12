#!/bin/bash

echo "Установка DHCP сервера..."
apt-get update
apt-get install -y dhcp-server ipcalc

echo ""
echo "Автонастройка DHCP сервера"
echo "=========================="
echo ""

# Функция получения списка активных интерфейсов с IP
get_interfaces() {
    echo "Доступные сетевые интерфейсы:"
    echo "------------------------------"
    
    INTERFACES=()
    IPS=()
    INDEX=1
    
    # Получаем все интерфейсы с IPv4 адресами, исключая lo
    for iface in $(ip -4 addr show | grep -E '^[0-9]+:' | awk '{print $2}' | tr -d ':' | grep -v '^lo$'); do
        IP=$(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        STATUS=$(ip link show "$iface" | grep -oP '(?<=state\s)\w+')
        
        if [ -n "$IP" ]; then
            INTERFACES+=("$iface")
            IPS+=("$IP")
            printf "%2d) %-15s %s (IP: %s)\n" "$INDEX" "$iface" "[$STATUS]" "$IP"
            ((INDEX++))
        fi
    done
    
    echo ""
}

# Функция выбора интерфейса
select_interface() {
    local prompt="$1"
    local selected_index
    
    while true; do
        read -p "$prompt" selection
        
        # Проверка на числовой ввод (выбор по номеру)
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            if [ "$selection" -ge 1 ] && [ "$selection" -le ${#INTERFACES[@]} ]; then
                selected_index=$((selection - 1))
                echo "Выбран интерфейс: ${INTERFACES[$selected_index]} (${IPS[$selected_index]})"
                echo ""
                SELECTED_IFACE="${INTERFACES[$selected_index]}"
                return 0
            else
                echo "Ошибка: введите число от 1 до ${#INTERFACES[@]}"
            fi
        # Проверка на ввод имени интерфейса
        elif [[ " ${INTERFACES[*]} " =~ " ${selection} " ]]; then
            for i in "${!INTERFACES[@]}"; do
                if [ "${INTERFACES[$i]}" == "$selection" ]; then
                    echo "Выбран интерфейс: ${INTERFACES[$i]} (${IPS[$i]})"
                    echo ""
                    SELECTED_IFACE="${INTERFACES[$i]}"
                    return 0
                fi
            done
        else
            echo "Ошибка: интерфейс '$selection' не найден. Введите номер или имя интерфейса."
        fi
    done
}

# Получаем и показываем интерфейсы
get_interfaces

# Проверка количества интерфейсов
if [ ${#INTERFACES[@]} -lt 2 ]; then
    echo "Ошибка: найдено менее 2 интерфейсов с IP-адресами."
    echo "Для работы DHCP сервера необходимо минимум 2 интерфейса."
    exit 1
fi

# Выбор интерфейсов
SELECTED_IFACE=""
select_interface "Выберите первый интерфейс (номер или имя): "
IFACE1="$SELECTED_IFACE"

select_interface "Выберите второй интерфейс (номер или имя): "
IFACE2="$SELECTED_IFACE"

# Проверка на одинаковые интерфейсы
if [ "$IFACE1" == "$IFACE2" ]; then
    echo "Ошибка: выбраны одинаковые интерфейсы. Выберите разные интерфейсы."
    exit 1
fi

echo "Будут использованы интерфейсы: $IFACE1 и $IFACE2"
echo ""

# Функция получения информации о сети
get_network_info() {
    IP=$(ip -4 addr show $1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+')
    
    if [ -z "$IP" ]; then
        echo "На интерфейсе $1 нет IP"
        exit 1
    fi

    NETWORK=$(ipcalc $IP | grep Network | awk '{print $2}' | cut -d/ -f1)
    NETMASK=$(ipcalc $IP | grep Netmask | awk '{print $2}')
    BROADCAST=$(ipcalc $IP | grep Broadcast | awk '{print $2}')

    START=$(echo $NETWORK | awk -F. '{print $1"."$2"."$3"."$4+10}')
    END=$(echo $BROADCAST | awk -F. '{print $1"."$2"."$3"."$4-1}')
    ROUTER=$(echo $IP | cut -d/ -f1)

    echo "$NETWORK $NETMASK $BROADCAST $START $END $ROUTER"
}

echo "Определение параметров сети..."

NET1_INFO=($(get_network_info $IFACE1))
NET2_INFO=($(get_network_info $IFACE2))

# Вывод информации о сетях
echo ""
echo "Параметры сети для $IFACE1:"
echo "  Сеть: ${NET1_INFO[0]}, Маска: ${NET1_INFO[1]}"
echo "  Диапазон DHCP: ${NET1_INFO[3]} - ${NET1_INFO[4]}"
echo "  Шлюз: ${NET1_INFO[5]}"
echo ""
echo "Параметры сети для $IFACE2:"
echo "  Сеть: ${NET2_INFO[0]}, Маска: ${NET2_INFO[1]}"
echo "  Диапазон DHCP: ${NET2_INFO[3]} - ${NET2_INFO[4]}"
echo "  Шлюз: ${NET2_INFO[5]}"
echo ""

echo "Создание конфигурации DHCP..."

# Проверка и очистка существующего конфига
if [ -f /etc/dhcp/dhcpd.conf ]; then
    echo "Найден существующий конфиг /etc/dhcp/dhcpd.conf - очищаем..."
    > /etc/dhcp/dhcpd.conf
fi

cat > /etc/dhcp/dhcpd.conf <<EOF
# DHCP конфигурация
# Автоматически сгенерировано: $(date)
# Интерфейсы: $IFACE1, $IFACE2

default-lease-time 600;
max-lease-time 7200;
authoritative;

# Подсеть для $IFACE1
subnet ${NET1_INFO[0]} netmask ${NET1_INFO[1]} {
  range ${NET1_INFO[3]} ${NET1_INFO[4]};
  option routers ${NET1_INFO[5]};
  option broadcast-address ${NET1_INFO[2]};
  option domain-name-servers 8.8.8.8, 8.8.4.4;
}

# Подсеть для $IFACE2
subnet ${NET2_INFO[0]} netmask ${NET2_INFO[1]} {
  range ${NET2_INFO[3]} ${NET2_INFO[4]};
  option routers ${NET2_INFO[5]};
  option broadcast-address ${NET2_INFO[2]};
  option domain-name-servers 8.8.8.8, 8.8.4.4;
}
EOF

echo "Настройка интерфейсов DHCP..."

# Проверка и очистка конфига интерфейсов
if [ -f /etc/sysconfig/dhcpd ]; then
    echo "Найден существующий конфиг /etc/sysconfig/dhcpd - очищаем..."
    > /etc/sysconfig/dhcpd
fi

cat > /etc/sysconfig/dhcpd <<EOF
# Интерфейсы для DHCP сервера
DHCPDARGS="$IFACE1 $IFACE2"
EOF

echo "Перезапуск DHCP..."

systemctl enable dhcpd
systemctl restart dhcpd

echo ""
echo "DHCP сервер настроен!"
echo "====================="
systemctl status dhcpd --no-pager
