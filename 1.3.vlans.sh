#!/bin/sh

# ==============================================================================
# Скрипт настройки VLAN для ALT Linux (Интерактивный выбор интерфейса и кол-ва VLAN)
# POSIX sh compatible
# ==============================================================================

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then 
  echo "Пожалуйста, запустите скрипт от имени root (sudo ./setup_vlans.sh)"
  exit 1
fi

# Проверка существования директории ALT Net
if [ ! -d "/etc/net/ifaces" ]; then
    echo "Ошибка: Директория /etc/net/ifaces не найдена."
    echo "Этот скрипт предназначен для ALT Linux."
    exit 1
fi

# ==============================================================================
# ВЫБОР ФИЗИЧЕСКОГО ИНТЕРФЕЙСА (САМОЕ НАЧАЛО)
# ==============================================================================

echo ""
echo "========================================================"
echo "  Обнаружение сетевых интерфейсов системы"
echo "========================================================"
echo ""

# Получаем список интерфейсов, исключая lo, docker, veth, virbr, sit и др.
# Сохраняем во временный файл для POSIX совместимости
IFACES_FILE=$(mktemp)
ip -o link show | awk -F': ' '{print $2}' | grep -v -E "^(lo|docker|veth|virbr|sit|br-|flannel|cni|tun|tap|bond)" > "$IFACES_FILE"

# Подсчитываем количество интерфейсов
IFACE_COUNT=$(wc -l < "$IFACES_FILE")

if [ "$IFACE_COUNT" -eq 0 ]; then
    echo "Ошибка: Не найдено подходящих сетевых интерфейсов."
    rm -f "$IFACES_FILE"
    exit 1
fi

# Выводим список интерфейсов с детальной информацией
echo "Обнаружены следующие сетевые интерфейсы:"
echo ""
printf "  %-4s %-16s %-10s %-20s\n" "№" "Интерфейс" "Статус" "MAC-адрес"
echo "  --------------------------------------------------------"

i=1
while IFS= read -r IFACE_NAME; do
    # Получаем статус UP/DOWN
    STATUS=$(ip -o link show "$IFACE_NAME" | awk '{print $9}')
    [ -z "$STATUS" ] && STATUS="UNKNOWN"
    
    # Получаем MAC-адрес
    MAC=$(ip -o link show "$IFACE_NAME" | awk '{print $17}')
    [ -z "$MAC" ] && MAC="N/A"
    
    # Вывод с цветом (если терминал поддерживает)
    if [ "$STATUS" = "UP" ]; then
        printf "  [%-2d] %-16s \033[32m%-10s\033[0m %-20s\n" "$i" "$IFACE_NAME" "$STATUS" "$MAC"
    else
        printf "  [%-2d] %-16s \033[31m%-10s\033[0m %-20s\n" "$i" "$IFACE_NAME" "$STATUS" "$MAC"
    fi
    
    i=$((i + 1))
done < "$IFACES_FILE"

echo ""
echo "  \033[32mUP\033[0m = интерфейс активен, \033[31mDOWN\033[0m = интерфейс неактивен"
echo ""

# Запрос выбора интерфейса
while true; do
    printf "Введите номер интерфейса для настройки VLAN [1]: "
    read -r SELECTION
    SELECTION=${SELECTION:-1}
    
    # Проверяем, что это число
    case "$SELECTION" in
        ''|*[!0-9]*)
            echo "Неверный ввод. Пожалуйста, введите число от 1 до $IFACE_COUNT."
            continue
            ;;
    esac
    
    if [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le "$IFACE_COUNT" ]; then
        # Получаем имя выбранного интерфейса
        PHYS_IFACE=$(sed -n "${SELECTION}p" "$IFACES_FILE")
        break
    else
        echo "Неверный ввод. Пожалуйста, введите число от 1 до $IFACE_COUNT."
    fi
done

# Удаляем временный файл
rm -f "$IFACES_FILE"

echo ""
echo "========================================================"
echo "  Выбран интерфейс: \033[1;33m$PHYS_IFACE\033[0m"
echo "========================================================"

# ==============================================================================
# ФУНКЦИИ
# ==============================================================================

# Расчет маски по количеству хостов
calculate_cidr() {
    hosts=$1
    bits=1
    while [ $(( (1 << bits) - 2 )) -lt "$hosts" ]; do
        bits=$((bits + 1))
    done
    echo $((32 - bits))
}

# Создание конфига VLAN
create_vlan_config() {
    vlan_name=$1       # Имя/Описание
    vlan_id=$2         # Номер VLAN
    iface=$3           # Физический интерфейс
    network_octet=$4   # Третий октет
    hosts=$5           # Кол-во хостов
    base_net=$6        # Базовая сеть (192.168)
    
    cidr=$(calculate_cidr "$hosts")
    vlan_iface_name="${iface}.${vlan_id}"
    vlan_dir="/etc/net/ifaces/${vlan_iface_name}"
    network_ip="${base_net}.${network_octet}.0"
    
    # Формируем IP адрес (заменяем последний октет на .2)
    ip_address=$(echo "$network_ip" | sed 's/\.[0-9]*$/.2/')"/${cidr}"
    full_network="${network_ip}/${cidr}"
    
    echo "    -> Создание $vlan_iface_name ($vlan_name)..."
    
    # 1. Создаем директорию
    mkdir -p "$vlan_dir"
    
    # 2. Создаем корректный конфиг options (перезаписываем, если есть)
    cat > "$vlan_dir/options" <<EOF
BOOTPROTO=static
TYPE=vlan
ONBOOT=yes
HOST=${iface}
VID=${vlan_id}
DISABLED=no
CONFIG_IPV4=yes
EOF

    # 3. Создаем ipv4address
    echo "$ip_address" > "$vlan_dir/ipv4address"
    
    echo "       Сеть: $full_network, IP: $ip_address"
}

# ==============================================================================
# ОБЩИЕ ПАРАМЕТРЫ
# ==============================================================================

echo ""
printf "Введите первые два октета сети [192.168]: "
read -r BASE_NETWORK_INPUT
BASE_NETWORK=${BASE_NETWORK_INPUT:-192.168}

# Убедимся, что физический интерфейс имеет корректный конфиг
PHYS_DIR="/etc/net/ifaces/${PHYS_IFACE}"
if [ ! -d "$PHYS_DIR" ]; then
    mkdir -p "$PHYS_DIR"
    cat > "$PHYS_DIR/options" <<EOF
BOOTPROTO=static
TYPE=eth
ONBOOT=yes
EOF
fi

# ==============================================================================
# ВВОД ДАННЫХ ПО VLAN
# ==============================================================================

echo ""
printf "Сколько VLAN нужно создать? [2]: "
read -r VLAN_COUNT
VLAN_COUNT=${VLAN_COUNT:-2}

# Временные файлы для хранения данных VLAN (вместо массивов)
VLANS_FILE=$(mktemp)

echo ""
echo "--------------------------------------------------------"
echo "  Настройка параметров для $VLAN_COUNT VLAN(s)"
echo "--------------------------------------------------------"

i=1
while [ "$i" -le "$VLAN_COUNT" ]; do
    echo ""
    echo "--- VLAN #$i ---"
    
    # Имя/Описание
    printf "Название/Описание (например, Office): "
    read -r V_NAME
    [ -z "$V_NAME" ] && V_NAME="VLAN_$i"
    
    # ID VLAN
    while true; do
        printf "VLAN ID (число): "
        read -r V_ID
        case "$V_ID" in
            ''|*[!0-9]*)
                echo "Ошибка: VLAN ID должен быть числом от 1 до 4094."
                continue
                ;;
        esac
        if [ "$V_ID" -ge 1 ] && [ "$V_ID" -le 4094 ]; then
            break
        else
            echo "Ошибка: VLAN ID должен быть числом от 1 до 4094."
        fi
    done

    # Третий октет подсети
    default_octet=$((i * 10))
    while true; do
        printf "3-й октет подсети (для %s.X.0) [%d]: " "$BASE_NETWORK" "$default_octet"
        read -r V_OCTET
        V_OCTET=${V_OCTET:-$default_octet}
        case "$V_OCTET" in
            ''|*[!0-9]*)
                echo "Ошибка: Октет должен быть числом от 0 до 255."
                continue
                ;;
        esac
        if [ "$V_OCTET" -ge 0 ] && [ "$V_OCTET" -le 255 ]; then
            break
        else
            echo "Ошибка: Октет должен быть числом от 0 до 255."
        fi
    done

    # Кол-во хостов
    printf "Требуемое кол-во хостов [254]: "
    read -r V_HOSTS
    V_HOSTS=${V_HOSTS:-254}

    # Сохраняем данные в файл (формат: name|id|octet|hosts)
    echo "${V_NAME}|${V_ID}|${V_OCTET}|${V_HOSTS}" >> "$VLANS_FILE"
    
    i=$((i + 1))
done

# ==============================================================================
# ПОДТВЕРЖДЕНИЕ
# ==============================================================================

echo ""
echo "========================================================"
echo "  Проверка конфигурации перед применением"
echo "========================================================"
echo "Физический интерфейс: $PHYS_IFACE"
echo "Базовая сеть: $BASE_NETWORK.0.0"
echo ""

printf "%-5s %-15s %-10s %-15s %-10s\n" "ID" "Название" "VLAN ID" "Сеть" "Хостов"
echo "-----------------------------------------------------------"

# Читаем и выводим данные
i=1
while IFS='|' read -r v_name v_id v_octet v_hosts; do
    cidr=$(calculate_cidr "$v_hosts")
    printf "%-5s %-15s %-10s %-15s %-10s\n" \
        "#$i" \
        "$v_name" \
        "$v_id" \
        "${BASE_NETWORK}.${v_octet}.0/${cidr}" \
        "$v_hosts"
    i=$((i + 1))
done < "$VLANS_FILE"

echo ""
printf "Продолжить настройку? (y/n): "
read -r CONFIRM

case "$CONFIRM" in
    [Yy]|[Yy][Ee][Ss])
        ;;
    *)
        echo "Настройка отменена."
        rm -f "$VLANS_FILE"
        exit 0
        ;;
esac

# ==============================================================================
# ПРИМЕНЕНИЕ НАСТРОЕК
# ==============================================================================

echo ""
echo "Применение настроек..."
echo "------------------------------------------------"

# Читаем и применяем
while IFS='|' read -r v_name v_id v_octet v_hosts; do
    create_vlan_config "$v_name" "$v_id" "$PHYS_IFACE" "$v_octet" "$v_hosts" "$BASE_NETWORK"
done < "$VLANS_FILE"

# Удаляем временный файл
rm -f "$VLANS_FILE"

echo ""
echo "------------------------------------------------"
echo "Конфигурация завершена!"
echo ""

# Перезапуск сети
printf "Перезапустить сетевую службу сейчас? (y/n): "
read -r RESTART_NET

case "$RESTART_NET" in
    [Yy]|[Yy][Ee][Ss])
        echo "Перезапуск службы сети..."
        if command -v systemctl > /dev/null 2>&1; then
            systemctl restart network
        else
            /etc/init.d/network restart
        fi
        
        if [ $? -eq 0 ]; then
            echo "✓ Сеть перезагружена успешно."
        else
            echo "⚠ Произошла ошибка при перезагрузке."
        fi
        ;;
esac

# Итоговый вывод
echo ""
echo "========================================================"
echo "  Итоговый список интерфейсов"
echo "========================================================"
# Показываем физический интерфейс и созданные VLAN
ip -brief addr show 2>/dev/null | grep -E "$PHYS_IFACE|${PHYS_IFACE}\." || ip addr show | grep -E "$PHYS_IFACE|${PHYS_IFACE}\."

echo ""
echo "Готово!"