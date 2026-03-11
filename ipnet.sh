#!/bin/bash

echo "===== Настройка сети ====="

# список интерфейсов
echo "Доступные интерфейсы:"
interfaces=$(ls /sys/class/net | grep -v lo)
select IFACE in $interfaces
do
    if [ -n "$IFACE" ]; then
        break
    else
        echo "Неверный выбор"
    fi
done

DIR="/etc/net/ifaces/$IFACE"

echo "Выбран интерфейс: $IFACE"

echo "Тип настройки:"
echo "1 - DHCP"
echo "2 - Статический IP"

read -p "Выберите вариант: " mode

sudo mkdir -p $DIR

if [ "$mode" == "1" ]; then

    echo "Настройка DHCP..."

    echo "TYPE=eth" > $DIR/options
    echo "BOOTPROTO=dhcp" >> $DIR/options
    echo "ONBOOT=yes" >> $DIR/options

    echo "DHCP=yes" > $DIR/ipv4address

elif [ "$mode" == "2" ]; then

    read -p "Введите IP (пример 192.168.1.10/24): " IP
    read -p "Введите шлюз (route): " GW
    read -p "Введите DNS: " DNS

    echo "TYPE=eth" > $DIR/options
    echo "BOOTPROTO=static" >> $DIR/options
    echo "ONBOOT=yes" >> $DIR/options

    echo "$IP" > $DIR/ipv4address
    echo "default via $GW" > $DIR/ipv4route
    echo "nameserver $DNS" > $DIR/resolv.conf

else
    echo "Неверный выбор"
    exit 1
fi

echo "Перезапуск сети..."
sudo systemctl restart network

echo "Настройка завершена"