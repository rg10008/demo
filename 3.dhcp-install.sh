#!/bin/bash

echo "Установка DHCP сервера..."
apt-get update
apt-get install -y dhcp-server ipcalc

echo "Автонастройка DHCP сервера"

read -p "Введите первый интерфейс: " IFACE1
read -p "Введите второй интерфейс: " IFACE2

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

echo "Создание конфигурации DHCP..."

cat > /etc/dhcp/dhcpd.conf <<EOF
default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet ${NET1_INFO[0]} netmask ${NET1_INFO[1]} {
  range ${NET1_INFO[3]} ${NET1_INFO[4]};
  option routers ${NET1_INFO[5]};
  option broadcast-address ${NET1_INFO[2]};
  option domain-name-servers 8.8.8.8;
}

subnet ${NET2_INFO[0]} netmask ${NET2_INFO[1]} {
  range ${NET2_INFO[3]} ${NET2_INFO[4]};
  option routers ${NET2_INFO[5]};
  option broadcast-address ${NET2_INFO[2]};
  option domain-name-servers 8.8.8.8;
}
EOF

echo "Настройка интерфейсов DHCP..."

cat > /etc/sysconfig/dhcpd <<EOF
DHCPDARGS="$IFACE1 $IFACE2"
EOF

echo "Перезапуск DHCP..."

systemctl enable dhcpd
systemctl restart dhcpd

echo "DHCP настроен."
systemctl status dhcpd --no-pager