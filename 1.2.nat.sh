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
            iptables -F FORWARD
            echo "NAT таблица и FORWARD цепочка очищены."
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

echo
echo "===== Настройка NAT (Выберите WAN) ====="

# Получаем список всех интерфейсов кроме loopback
all_interfaces=$(ls /sys/class/net | grep -v lo)

echo "Доступные интерфейсы: $all_interfaces"
echo

select WAN in $all_interfaces
do
    [ -n "$WAN" ] && break
done

echo "WAN интерфейс: $WAN"

# Автоматически определяем LAN интерфейсы (все кроме WAN и lo)
LAN_INTERFACES=()
for iface in $all_interfaces; do
    if [ "$iface" != "$WAN" ]; then
        LAN_INTERFACES+=("$iface")
    fi
done

# Проверяем, есть ли LAN интерфейсы
if [ ${#LAN_INTERFACES[@]} -eq 0 ]; then
    echo "Ошибка: Не найдено LAN интерфейсов!"
    exit 1
fi

echo
echo "===== Автоматически определены LAN интерфейсы ====="
for i in "${!LAN_INTERFACES[@]}"; do
    echo "LAN$((i+1)): ${LAN_INTERFACES[$i]}"
done

echo
echo "Определение сетей..."

# Массивы для хранения сетей
declare -a LAN_NETS

for i in "${!LAN_INTERFACES[@]}"; do
    iface="${LAN_INTERFACES[$i]}"
    net=$(ip -o -f inet addr show "$iface" | awk '{print $4}')
    
    if [ -z "$net" ]; then
        echo "Предупреждение: Интерфейс $iface не имеет IPv4 адреса, пропускаем..."
        continue
    fi
    
    LAN_NETS+=("$net")
    echo "Сеть $iface: $net"
done

# Проверяем, есть ли сети для настройки
if [ ${#LAN_NETS[@]} -eq 0 ]; then
    echo "Ошибка: Ни один LAN интерфейс не имеет IPv4 адреса!"
    exit 1
fi

echo
echo "Включение IP forwarding..."

SYSCTL_FILE="/etc/sysctl.conf"
if [ -f /etc/net/sysctl.conf ]; then
    SYSCTL_FILE="/etc/net/sysctl.conf"
fi

if ! grep -q "net.ipv4.ip_forward" "$SYSCTL_FILE"; then
    echo "net.ipv4.ip_forward = 1" >> "$SYSCTL_FILE"
else
    sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' "$SYSCTL_FILE"
fi

sysctl -p

echo
echo "Настройка NAT..."

for i in "${!LAN_INTERFACES[@]}"; do
    iface="${LAN_INTERFACES[$i]}"
    net="${LAN_NETS[$i]}"
    
    if [ -n "$net" ]; then
        echo "  Настройка NAT для $iface ($net)..."
        iptables -t nat -A POSTROUTING -o "$WAN" -s "$net" -j MASQUERADE
    fi
done

echo
echo "Настройка FORWARD..."

for i in "${!LAN_INTERFACES[@]}"; do
    iface="${LAN_INTERFACES[$i]}"
    net="${LAN_NETS[$i]}"
    
    if [ -n "$net" ]; then
        echo "  Настройка FORWARD для $iface ($net)..."
        iptables -A FORWARD -i "$iface" -o "$WAN" -s "$net" -j ACCEPT
    fi
done

# Добавляем разрешение для установленных соединений
echo "  Добавляем правила для установленных соединений..."
iptables -A FORWARD -i "$WAN" -m state --state ESTABLISHED,RELATED -j ACCEPT

echo
echo "Сохранение правил..."

# Проверяем наличие директории для сохранения
if [ -d /etc/sysconfig ]; then
    iptables-save > /etc/sysconfig/iptables
    echo "Правила сохранены в /etc/sysconfig/iptables"
elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4
    echo "Правила сохранены в /etc/iptables/rules.v4"
else
    echo "Предупреждение: Не найдена стандартная директория для сохранения правил."
    echo "Вывод правил iptables-save:"
    iptables-save
fi

# Перезапуск сервиса iptables если доступен
if systemctl list-unit-files | grep -q "^iptables.service"; then
    systemctl enable iptables --now 2>/dev/null
    systemctl restart iptables 2>/dev/null
    echo "Сервис iptables перезапущен"
fi

echo
echo "===== NAT таблица ====="
iptables -t nat -L -n -v --line-numbers

echo
echo "===== FORWARD цепочка ====="
iptables -L FORWARD -n -v --line-numbers

echo
echo "===== Итоговая конфигурация ====="
echo "WAN интерфейс: $WAN"
echo "LAN интерфейсы: ${LAN_INTERFACES[*]}"
echo "Количество LAN сетей: ${#LAN_NETS[@]}"

echo
echo "Готово!"
