#!/bin/bash
#
# Скрипт настройки службы сетевого времени (NTP) на базе chrony
# Для Alt Linux (Маршрутизатор ISP)
#
# Задание:
# - Вышестоящий сервер NTP - на выбор (используем pool.ntp.org)
# - Стратум сервера - 5
# - Клиенты NTP: HQ-SRV, HQ-CLI, BR-RTR, BR-SRV
#

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
    log_success "Проверка прав root пройдена"
}

# Определение сетей клиентов NTP
# Укажите здесь IP-адреса или сети ваших клиентов
NTP_CLIENTS=(
    "HQ-SRV:192.168.1.10"      # Замените на реальный IP
    "HQ-CLI:192.168.1.20"      # Замените на реальный IP
    "BR-RTR:192.168.2.1"       # Замените на реальный IP
    "BR-SRV:192.168.2.10"      # Замените на реальный IP
)

# Сети клиентов для доступа к NTP (можно указать подсети)
CLIENT_NETWORKS=(
    "192.168.1.0/24"    # Сеть HQ
    "192.168.2.0/24"    # Сеть BR
)

# Установка chrony
install_chrony() {
    log_info "Установка пакета chrony..."
    
    if command -v apt-get &> /dev/null; then
        # Alt Linux использует apt-get (apt-rpm)
        apt-get update
        apt-get install -y chrony
    elif command -v yum &> /dev/null; then
        yum install -y chrony
    elif command -v dnf &> /dev/null; then
        dnf install -y chrony
    else
        log_error "Не удалось определить менеджер пакетов"
        exit 1
    fi
    
    log_success "Пакет chrony успешно установлен"
}

# Создание конфигурационного файла chrony
configure_chrony() {
    log_info "Настройка конфигурации chrony..."
    
    # Резервное копирование оригинального конфига
    if [[ -f /etc/chrony.conf ]]; then
        cp /etc/chrony.conf /etc/chrony.conf.backup.$(date +%Y%m%d_%H%M%S)
        log_info "Создана резервная копия конфигурации"
    fi
    
    # Создание нового конфигурационного файла
    cat > /etc/chrony.conf << 'EOF'
# =============================================================================
# Конфигурация NTP сервера на базе chrony
# Маршрутизатор ISP
# =============================================================================

# -----------------------------------------------------------------------------
# Вышестоящие NTP серверы (публичные пулы)
# -----------------------------------------------------------------------------
# Используем пул NTP серверов (можно заменить на конкретные серверы)
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst
server 2.pool.ntp.org iburst
server 3.pool.ntp.org iburst

# Альтернативные серверы (раскомментируйте при необходимости):
# server ntp1.vniiftri.ru iburst
# server ntp2.vniiftri.ru iburst
# server ntp.msk-ix.ru iburst

# -----------------------------------------------------------------------------
# Локальные настройки сервера
# -----------------------------------------------------------------------------
# Установка стратума 5 для данного сервера
# (сервер будет сообщать клиентам, что он на stratum 5)
local stratum 5

# -----------------------------------------------------------------------------
# Настройки синхронизации
# -----------------------------------------------------------------------------
# driftfile для хранения информации о частоте часов
driftfile /var/lib/chrony/drift

# Логирование
logdir /var/log/chrony
log measurements statistics tracking

# -----------------------------------------------------------------------------
# Настройки доступа
# -----------------------------------------------------------------------------
# Разрешить локальному хосту полный доступ
allow 127.0.0.1

# Разрешить клиентам из сети HQ (HQ-SRV, HQ-CLI)
allow 192.168.1.0/24

# Разрешить клиентам из сети BR (BR-RTR, BR-SRV)
allow 192.168.2.0/24

# -----------------------------------------------------------------------------
# Дополнительные настройки
# -----------------------------------------------------------------------------
# Количество шагов для начальной синхронизации
makestep 1.0 3

# Включить RTC (аппаратные часы)
rtcsync

# Увеличить точность синхронизации
hwtimestamp *

# -----------------------------------------------------------------------------
# Настройки для клиентов
# -----------------------------------------------------------------------------
# Указываем сеть для обслуживания клиентов
# serve time to clients even when not synchronized to a time source
# (раскомментируйте если нужно обслуживать клиентов без синхронизации)
# local stratum 5 orphan

EOF
    
    # Создание директории для логов если её нет
    mkdir -p /var/log/chrony
    mkdir -p /var/lib/chrony
    
    log_success "Конфигурация chrony создана"
}

# Настройка firewalld (если используется)
configure_firewall() {
    log_info "Настройка фаервола..."
    
    if command -v firewall-cmd &> /dev/null; then
        # Проверяем, запущен ли firewalld
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --add-service=ntp
            firewall-cmd --permanent --add-port=123/udp
            
            # Добавляем правила для сетей клиентов
            for network in "${CLIENT_NETWORKS[@]}"; do
                firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$network' service name='ntp' accept"
            done
            
            firewall-cmd --reload
            log_success "Правила firewalld настроены"
        else
            log_warning "firewalld не активен, пропускаем настройку"
        fi
    else
        log_warning "firewall-cmd не найден, проверьте настройки фаервола вручную"
    fi
}

# Настройка iptables (альтернатива firewalld)
configure_iptables() {
    log_info "Настройка iptables (если используется)..."
    
    if command -v iptables &> /dev/null; then
        # Разрешаем NTP трафик
        iptables -I INPUT -p udp --dport 123 -j ACCEPT
        iptables -I INPUT -p tcp --dport 123 -j ACCEPT
        
        # Сохраняем правила (для Alt Linux)
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        fi
        
        log_success "Правила iptables настроены"
    fi
}

# Запуск и включение службы chrony
enable_chrony() {
    log_info "Запуск службы chrony..."
    
    # Останавливаем ntpd если запущен (конфликт)
    if systemctl is-active --quiet ntpd 2>/dev/null; then
        systemctl stop ntpd
        systemctl disable ntpd
        log_info "Служба ntpd остановлена (конфликт с chrony)"
    fi
    
    # Включаем и запускаем chrony
    systemctl enable chronyd
    systemctl start chronyd
    
    log_success "Служба chrony запущена и включена"
}

# Проверка статуса синхронизации
check_status() {
    log_info "Проверка статуса синхронизации..."
    
    echo ""
    echo "=========================================="
    echo "СТАТУС СЛУЖБЫ CHRONY"
    echo "=========================================="
    
    # Статус службы
    systemctl status chronyd --no-pager || true
    
    echo ""
    echo "=========================================="
    echo "ИСТОЧНИКИ NTP"
    echo "=========================================="
    chronyc sources -v || true
    
    echo ""
    echo "=========================================="
    echo "ДЕТАЛИ СИНХРОНИЗАЦИИ"
    echo "=========================================="
    chronyc tracking || true
    
    echo ""
    echo "=========================================="
    echo "СТАТИСТИКА"
    echo "=========================================="
    chronyc sourcestats || true
}

# Создание скрипта для клиентов
create_client_scripts() {
    log_info "Создание скриптов настройки для клиентов..."
    
    local client_dir="/root/ntp_client_scripts"
    mkdir -p "$client_dir"
    
    # IP маршрутизатора ISP (NTP сервера)
    # Определяем IP локального интерфейса
    LOCAL_IP=$(ip route get 1 | awk '{print $7; exit}')
    
    # Скрипт для клиента
    cat > "$client_dir/setup_ntp_client.sh" << 'CLIENTSCRIPT'
#!/bin/bash
#
# Скрипт настройки NTP клиента (chrony) для Alt Linux
# Автоматически определяет IP NTP сервера
#

set -e

NTP_SERVER="NTP_SERVER_IP_PLACEHOLDER"

echo "[INFO] Установка chrony..."
apt-get update && apt-get install -y chrony

echo "[INFO] Настройка chrony клиента..."

cat > /etc/chrony.conf << EOF
# NTP клиент - синхронизация с маршрутизатором ISP
server $NTP_SERVER iburst prefer

# Дополнительные публичные серверы (резерв)
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst

# driftfile
driftfile /var/lib/chrony/drift

# Локальные настройки
makestep 1.0 3
rtcsync

# Логирование
logdir /var/log/chrony
EOF

echo "[INFO] Запуск службы chrony..."
systemctl enable chronyd
systemctl restart chronyd

echo "[SUCCESS] NTP клиент настроен!"
echo "NTP сервер: $NTP_SERVER"
chronyc sources
CLIENTSCRIPT
    
    # Заменяем плейсхолдер на реальный IP
    sed -i "s/NTP_SERVER_IP_PLACEHOLDER/$LOCAL_IP/g" "$client_dir/setup_ntp_client.sh"
    chmod +x "$client_dir/setup_ntp_client.sh"
    
    # Создаем инструкции для каждого клиента
    for client in "${NTP_CLIENTS[@]}"; do
        IFS=':' read -r name ip <<< "$client"
        echo "Настройка для $name ($ip):" > "$client_dir/instruction_${name}.txt"
        echo "" >> "$client_dir/instruction_${name}.txt"
        echo "1. Скопируйте скрипт на $name:" >> "$client_dir/instruction_${name}.txt"
        echo "   scp $client_dir/setup_ntp_client.sh root@$ip:/root/" >> "$client_dir/instruction_${name}.txt"
        echo "" >> "$client_dir/instruction_${name}.txt"
        echo "2. Выполните на $name:" >> "$client_dir/instruction_${name}.txt"
        echo "   chmod +x /root/setup_ntp_client.sh" >> "$client_dir/instruction_${name}.txt"
        echo "   /root/setup_ntp_client.sh" >> "$client_dir/instruction_${name}.txt"
        echo "" >> "$client_dir/instruction_${name}.txt"
        echo "3. Проверьте синхронизацию:" >> "$client_dir/instruction_${name}.txt"
        echo "   chronyc sources" >> "$client_dir/instruction_${name}.txt"
        echo "   chronyc tracking" >> "$client_dir/instruction_${name}.txt"
    done
    
    log_success "Скрипты для клиентов созданы в директории: $client_dir"
}

# Вывод информации о настройках
show_info() {
    echo ""
    echo "=========================================="
    echo "НАСТРОЙКА NTP СЕРВЕРА ЗАВЕРШЕНА"
    echo "=========================================="
    echo ""
    echo "Параметры сервера:"
    echo "  - Stratum: 5"
    echo "  - Вышестоящие серверы: pool.ntp.org"
    echo ""
    echo "Разрешённые клиенты:"
    echo "  - HQ-SRV (192.168.1.0/24)"
    echo "  - HQ-CLI (192.168.1.0/24)"
    echo "  - BR-RTR (192.168.2.0/24)"
    echo "  - BR-SRV (192.168.2.0/24)"
    echo ""
    echo "Полезные команды:"
    echo "  chronyc sources    - показать источники времени"
    echo "  chronyc tracking   - показать статус синхронизации"
    echo "  chronyc clients    - показать подключённых клиентов"
    echo "  chronyc makestep   - принудительная синхронизация"
    echo ""
    echo "Конфигурационный файл: /etc/chrony.conf"
    echo "Логи: /var/log/chrony/"
    echo ""
}

# Главная функция
main() {
    clear
    echo "=========================================="
    echo "НАСТРОЙКА NTP СЕРВЕРА (CHRONY)"
    echo "Маршрутизатор ISP - Alt Linux"
    echo "=========================================="
    echo ""
    
    check_root
    install_chrony
    configure_chrony
    configure_firewall
    configure_iptables
    enable_chrony
    create_client_scripts
    check_status
    show_info
    
    log_success "Настройка завершена успешно!"
}

# Запуск
main "$@"
