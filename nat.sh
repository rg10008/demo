#!/bin/bash

echo "===== Настройка NAT и маршрутизации ====="

echo
echo "Доступные интерфейсы:"
interfaces=$(ls /sys/class/net | grep -v lo)

select WAN in $interfaces
do
    if [ -n "$WAN" ]; then
        break
    fi
done

echo "Выбран внешний интерфейс: $WAN"

echo
echo "Выберите интерфейс для сети 172.16.4.0/28"
select LAN1 in $interfaces
do
    if [ -n "$LAN1" ]; then
        break
    fi
done

echo
echo "Выберите интерфейс для сети 172.16.5.0/28"
select LAN2 in $interfaces
do
    if [ -n "$LAN2" ]; then
        break
    fi
done

echo
echo "Включение IP forwarding..."

if ! grep -q "net.ipv4.ip_forward" /etc/net/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" >> /etc/net/sysctl.conf
else
    sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
fi

sysctl -p

echo
echo "Перезапуск сети..."
systemctl restart network

echo
echo "Настройка NAT..."

iptables -t nat -A POSTROUTING -o $WAN -s 172.16.4.0/28 -j MASQUERADE
iptables -t nat -A POSTROUTING -o $WAN -s 172.16.5.0/28 -j MASQUERADE

echo
echo "Настройка FORWARD..."

iptables -A FORWARD -i $LAN1 -o $WAN -s 172.16.4.0/28 -j ACCEPT
iptables -A FORWARD -i $LAN2 -o $WAN -s 172.16.5.0/28 -j ACCEPT

echo
echo "Сохранение правил..."

iptables-save > /etc/sysconfig/iptables

systemctl enable iptables --now
systemctl restart iptables

echo
echo "===== Статус iptables ====="
systemctl status iptables --no-pager

echo
echo "===== NAT таблица ====="
iptables -t nat -L -n -v

echo
echo "Настройка завершена"