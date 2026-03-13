#!/bin/bash

# Вопрос об очистке NAT таблицы
echo
echo "Очистить существующие правила NAT перед настройкой?"
select CLEAR_NAT in "Да" "Нет"
do
    case $CLEAR_NAT in
        "Да")
            echo "Очистка NAT таблицы..."
            iptables -t nat -F
            echo "NAT таблица очищена."
            break
            ;;
        "Нет")
            echo "Сохраняем существующие правила NAT."
            break
            ;;
        *)
            echo "Выберите 1 или 2"
            ;;
    esac
done

echo "===== Настройка NAT(Выберете WAN) ====="

echo "Доступные интерфейсы:"
interfaces=$(ls /sys/class/net | grep -v lo)

select WAN in $interfaces
do
    [ -n "$WAN" ] && break
done

echo "WAN интерфейс: $WAN"

echo "Выберите первый LAN интерфейс"
select LAN1 in $interfaces
do
    [ -n "$LAN1" ] && break
done

echo "Выберите второй LAN интерфейс"
select LAN2 in $interfaces
do
    [ -n "$LAN2" ] && break
done

echo
echo "Определение сетей..."

NET1=$(ip -o -f inet addr show $LAN1 | awk '{print $4}')
NET2=$(ip -o -f inet addr show $LAN2 | awk '{print $4}')

echo "Сеть $LAN1: $NET1"
echo "Сеть $LAN2: $NET2"

echo
echo "Включение IP forwarding..."

if ! grep -q "net.ipv4.ip_forward" /etc/net/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" >> /etc/net/sysctl.conf
else
    sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
fi

sysctl -p

echo
echo "Настройка NAT..."

sudo iptables -t nat -A POSTROUTING -o $WAN -s $NET1 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o $WAN -s $NET2 -j MASQUERADE

echo
echo "Настройка FORWARD..."

sudo iptables -A FORWARD -i $LAN1 -o $WAN -s $NET1 -j ACCEPT
sudo iptables -A FORWARD -i $LAN2 -o $WAN -s $NET2 -j ACCEPT

echo
echo "Сохранение правил..."

sudo iptables-save > /etc/sysconfig/iptables

systemctl enable iptables --now
systemctl restart iptables

echo
echo "===== NAT таблица ====="
iptables -t nat -L -n -v

echo
echo "Готово"