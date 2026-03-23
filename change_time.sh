#!/bin/bash

# Интерактивный скрипт для синхронизации времени и установки часового пояса
# Требует прав суперпользователя (sudo)

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Выбранный NTP сервер (по умолчанию пул)
SELECTED_NTP="pool.ntp.org"

# Список NTP серверов
declare -A NTP_SERVERS=(
    ["1"]="pool.ntp.org|Глобальный пул NTP (рекомендуется)"
    ["2"]="time.google.com|Google Public NTP"
    ["3"]="time.cloudflare.com|Cloudflare NTP"
    ["4"]="time.windows.com|Microsoft NTP"
    ["5"]="time.nist.gov|NIST (США)"
    ["6"]="ntp.ubuntu.com|Ubuntu NTP"
    ["7"]="ru.pool.ntp.org|Российский пул NTP"
    ["8"]="europe.pool.ntp.org|Европейский пул NTP"
    ["9"]="asia.pool.ntp.org|Азиатский пул NTP"
    ["10"]="north-america.pool.ntp.org|Североамериканский пул NTP"
    ["11"]="clock.isc.org|Internet Systems Consortium"
    ["12"]="time.apple.com|Apple NTP"
    ["13"]="navobs1.gatech.edu|Georgia Tech (США)"
    ["14"]="_custom|Ввести свой сервер..."
)

# Функция очистки экрана
clear_screen() {
    clear
}

# Функция отображения текущего времени
show_current_time() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           ТЕКУЩЕЕ СИСТЕМНОЕ ВРЕМЯ                        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Дата и время:${NC} $(date '+%d.%m.%Y %H:%M:%S')"
    echo -e "${GREEN}Часовой пояс:${NC} $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo 'Не определён')"
    echo -e "${GREEN}NTP сервер:  ${NC} ${MAGENTA}$SELECTED_NTP${NC}"
    echo -e "${GREEN}Синхронизация:${NC} $(timedatectl show --property=NTP --value 2>/dev/null || echo 'Неизвестно')"
    echo ""
}

# Функция проверки прав суперпользователя
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}⚠ ВНИМАНИЕ: Для изменения времени требуются права суперпользователя!${NC}"
        echo -e "${YELLOW}  Запустите скрипт с sudo: sudo bash $0${NC}"
        echo ""
        return 1
    fi
    return 0
}

# Функция выбора NTP сервера
select_ntp_server() {
    clear_screen
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              ВЫБОР NTP СЕРВЕРА                           ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Текущий NTP сервер:${NC} ${MAGENTA}$SELECTED_NTP${NC}"
    echo ""
    echo -e "${YELLOW}Доступные NTP серверы:${NC}"
    echo ""
    
    for key in $(echo "${!NTP_SERVERS[@]}" | tr ' ' '\n' | sort -n); do
        IFS='|' read -r server desc <<< "${NTP_SERVERS[$key]}"
        if [[ "$server" == "_custom" ]]; then
            printf "  ${GREEN}%2s.${NC} %s\n" "$key" "$desc"
        else
            printf "  ${GREEN}%2s.${NC} %-25s %s\n" "$key" "$server" "($desc)"
        fi
    done
    
    echo ""
    read -p "$(echo -e ${BLUE}"Выберите NTP сервер [1-14]: "${NC})" choice
    
    if [[ -n "${NTP_SERVERS[$choice]}" ]]; then
        IFS='|' read -r server desc <<< "${NTP_SERVERS[$choice]}"
        
        if [[ "$server" == "_custom" ]]; then
            echo ""
            read -p "$(echo -e ${BLUE}"Введите адрес NTP сервера: "${NC})" custom_server
            if [[ -n "$custom_server" ]]; then
                SELECTED_NTP="$custom_server"
                echo -e "${GREEN}✓ Выбран пользовательский сервер:${NC} $SELECTED_NTP"
            else
                echo -e "${RED}Ошибка: пустой адрес сервера!${NC}"
            fi
        else
            SELECTED_NTP="$server"
            echo -e "${GREEN}✓ Выбран NTP сервер:${NC} $SELECTED_NTP"
        fi
    else
        echo -e "${RED}Неверный выбор!${NC}"
    fi
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Функция проверки соединения с NTP сервером
test_ntp_connection() {
    local server="$1"
    echo -e "${YELLOW}Проверка соединения с $server...${NC}"
    
    # Проверка через ntpdate или chronyd
    if command -v ntpdate &> /dev/null; then
        if ntpdate -q "$server" &> /dev/null; then
            return 0
        fi
    elif command -v ntpd &> /dev/null; then
        if ntpq -p "$server" &> /dev/null; then
            return 0
        fi
    elif command -v chronyc &> /dev/null; then
        if chronyc sources | grep -q "$server"; then
            return 0
        fi
    fi
    
    # Простая проверка через ping
    if ping -c 1 -W 2 "$server" &> /dev/null; then
        return 0
    fi
    
    return 1
}

# Функция настройки NTP сервера в системе
configure_ntp_server() {
    local server="$1"
    
    # systemd-timesyncd
    if command -v timedatectl &> /dev/null && systemctl is-active systemd-timesyncd &> /dev/null; then
        mkdir -p /etc/systemd/timesyncd.conf.d
        cat > /etc/systemd/timesyncd.conf.d/ntp.conf << EOF
[Time]
NTP=$server
FallbackNTP=pool.ntp.org
EOF
        systemctl restart systemd-timesyncd 2>/dev/null
        return 0
    fi
    
    # chrony
    if command -v chronyd &> /dev/null; then
        if [[ -f /etc/chrony/chrony.conf ]]; then
            sed -i '/^pool\|^server/d' /etc/chrony/chrony.conf 2>/dev/null
            echo "pool $server iburst" >> /etc/chrony/chrony.conf
            systemctl restart chrony 2>/dev/null || systemctl restart chronyd 2>/dev/null
            return 0
        elif [[ -f /etc/chrony.conf ]]; then
            sed -i '/^pool\|^server/d' /etc/chrony.conf 2>/dev/null
            echo "pool $server iburst" >> /etc/chrony.conf
            systemctl restart chronyd 2>/dev/null
            return 0
        fi
    fi
    
    # ntpd
    if command -v ntpd &> /dev/null; then
        if [[ -f /etc/ntp.conf ]]; then
            sed -i '/^pool\|^server/d' /etc/ntp.conf 2>/dev/null
            echo "pool $server iburst" >> /etc/ntp.conf
            systemctl restart ntp 2>/dev/null || systemctl restart ntpd 2>/dev/null
            return 0
        fi
    fi
    
    return 1
}

# Функция синхронизации с NTP сервером
sync_ntp() {
    clear_screen
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           СИНХРОНИЗАЦИЯ С NTP СЕРВЕРОМ                   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Выбранный NTP сервер:${NC} ${MAGENTA}$SELECTED_NTP${NC}"
    echo ""
    
    if ! check_root; then
        read -p "Нажмите Enter для продолжения..."
        return
    fi
    
    # Проверка соединения
    if test_ntp_connection "$SELECTED_NTP"; then
        echo -e "${GREEN}✓ Соединение с сервером установлено${NC}"
    else
        echo -e "${YELLOW}⚠ Не удалось проверить соединение, продолжаю...${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Настройка NTP сервера в системе...${NC}"
    
    # Настройка NTP сервера
    if configure_ntp_server "$SELECTED_NTP"; then
        echo -e "${GREEN}✓ NTP сервер настроен в системе${NC}"
    else
        echo -e "${YELLOW}⚠ Автоматическая настройка не удалась, использую стандартный метод${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Включение NTP синхронизации...${NC}"
    
    if timedatectl set-ntp true 2>/dev/null; then
        echo -e "${GREEN}✓ NTP синхронизация включена!${NC}"
        echo ""
        echo -e "${YELLOW}Ожидание синхронизации с $SELECTED_NTP...${NC}"
        sleep 3
        echo ""
        echo -e "${GREEN}────────────────────────────────────${NC}"
        echo -e "${GREEN}Результат:${NC}"
        echo -e "${GREEN}────────────────────────────────────${NC}"
        echo -e "${GREEN}Текущее время:${NC} $(date '+%d.%m.%Y %H:%M:%S')"
        echo -e "${GREEN}NTP сервер:   ${NC} ${MAGENTA}$SELECTED_NTP${NC}"
        
        # Показать статус синхронизации
        if command -v timedatectl &> /dev/null; then
            echo ""
            timedatectl status 2>/dev/null | head -10
        fi
    else
        echo -e "${RED}✗ Ошибка при включении NTP!${NC}"
        echo ""
        echo -e "${YELLOW}Возможные решения:${NC}"
        echo ""
        echo "  Ubuntu/Debian:"
        echo "    sudo apt install systemd-timesyncd"
        echo "    sudo apt install ntp"
        echo "    sudo apt install chrony"
        echo ""
        echo "  CentOS/RHEL/Rocky:"
        echo "    sudo yum install chrony"
        echo "    sudo systemctl enable --now chronyd"
        echo ""
        echo "  Arch Linux:"
        echo "    sudo pacman -S ntp"
        echo "    sudo systemctl enable --now ntpd"
    fi
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Функция выбора часового пояса
set_timezone() {
    clear_screen
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              ВЫБОР ЧАСОВОГО ПОЯСА                        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Популярные часовые пояса:${NC}"
    echo ""
    echo "  1) Europe/Moscow        (Москва, UTC+3)"
    echo "  2) Europe/Kiev          (Киев, UTC+2)"
    echo "  3) Europe/London        (Лондон, UTC+0/+1)"
    echo "  4) Europe/Paris         (Париж, UTC+1/+2)"
    echo "  5) Europe/Berlin        (Берлин, UTC+1/+2)"
    echo "  6) America/New_York     (Нью-Йорк, UTC-5/-4)"
    echo "  7) America/Los_Angeles  (Лос-Анджелес, UTC-8/-7)"
    echo "  8) Asia/Tokyo           (Токио, UTC+9)"
    echo "  9) Asia/Shanghai        (Шанхай, UTC+8)"
    echo " 10) Asia/Dubai           (Дубай, UTC+4)"
    echo " 11) Asia/Almaty          (Алматы, UTC+6)"
    echo " 12) Asia/Tashkent        (Ташкент, UTC+5)"
    echo " 13) Asia/Singapore       (Сингапур, UTC+8)"
    echo " 14) Asia/Hong_Kong       (Гонконг, UTC+8)"
    echo " 15) Australia/Sydney     (Сидней, UTC+10/+11)"
    echo " 16) UTC                  (Универсальное время)"
    echo ""
    echo " 17) Показать все пояса"
    echo " 18) Ввести вручную"
    echo ""
    
    read -p "$(echo -e ${BLUE}"Выберите опцию [1-18]: "${NC})" choice
    
    case $choice in
        1) tz="Europe/Moscow" ;;
        2) tz="Europe/Kiev" ;;
        3) tz="Europe/London" ;;
        4) tz="Europe/Paris" ;;
        5) tz="Europe/Berlin" ;;
        6) tz="America/New_York" ;;
        7) tz="America/Los_Angeles" ;;
        8) tz="Asia/Tokyo" ;;
        9) tz="Asia/Shanghai" ;;
        10) tz="Asia/Dubai" ;;
        11) tz="Asia/Almaty" ;;
        12) tz="Asia/Tashkent" ;;
        13) tz="Asia/Singapore" ;;
        14) tz="Asia/Hong_Kong" ;;
        15) tz="Australia/Sydney" ;;
        16) tz="UTC" ;;
        17) 
            echo ""
            echo -e "${YELLOW}Список всех часовых поясов:${NC}"
            echo ""
            timedatectl list-timezones 2>/dev/null | less -S || ls /usr/share/zoneinfo/ 2>/dev/null
            echo ""
            read -p "$(echo -e ${BLUE}"Введите часовой пояс: "${NC})" tz
            ;;
        18)
            echo ""
            read -p "$(echo -e ${BLUE}"Введите часовой пояс (например, Europe/Moscow): "${NC})" tz
            ;;
        *)
            echo -e "${RED}Неверный выбор!${NC}"
            read -p "Нажмите Enter для продолжения..."
            return
            ;;
    esac
    
    if [[ -n "$tz" ]]; then
        echo ""
        echo -e "${YELLOW}Будет установлен часовой пояс:${NC} $tz"
        read -p "$(echo -e ${BLUE}"Подтвердить? (y/n): "${NC})" confirm
        
        if [[ "$confirm" =~ ^[YyДд]$ ]]; then
            if check_root; then
                if timedatectl set-timezone "$tz" 2>/dev/null; then
                    echo -e "${GREEN}✓ Часовой пояс успешно изменён!${NC}"
                    echo ""
                    echo -e "${GREEN}Текущее время:${NC} $(date '+%d.%m.%Y %H:%M:%S')"
                    echo -e "${GREEN}Часовой пояс:${NC} $tz"
                elif ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime 2>/dev/null; then
                    echo -e "${GREEN}✓ Часовой пояс успешно изменён!${NC}"
                    echo ""
                    echo -e "${GREEN}Текущее время:${NC} $(date '+%d.%m.%Y %H:%M:%S')"
                    echo -e "${GREEN}Часовой пояс:${NC} $tz"
                else
                    echo -e "${RED}✗ Ошибка при изменении часового пояса!${NC}"
                    echo -e "${YELLOW}Проверьте правильность имени часового пояса.${NC}"
                fi
            fi
        else
            echo -e "${YELLOW}Отменено пользователем.${NC}"
        fi
    fi
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Функция показа подробной информации
show_info() {
    clear_screen
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           ПОДРОБНАЯ ИНФОРМАЦИЯ О ВРЕМЕНИ                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${GREEN}Выбранный NTP сервер:${NC} ${MAGENTA}$SELECTED_NTP${NC}"
    echo ""
    
    if command -v timedatectl &> /dev/null; then
        timedatectl status 2>/dev/null
        echo ""
        echo -e "${CYAN}────────────────────────────────────${NC}"
        echo -e "${CYAN}Информация о NTP:${NC}"
        timedatectl timesync-status 2>/dev/null || echo "Детальная информация недоступна"
    else
        echo -e "${GREEN}Дата и время:${NC} $(date '+%d.%m.%Y %H:%M:%S')"
        echo -e "${GREEN}Часовой пояс:${NC} $(cat /etc/timezone 2>/dev/null || echo 'Не определён')"
        echo -e "${GREEN}Аппаратные часы:${NC} $(hwclock --show 2>/dev/null || echo 'Не доступны')"
    fi
    
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# Главное меню
main_menu() {
    while true; do
        clear_screen
        show_current_time
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                    ГЛАВНОЕ МЕНЮ                          ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}1.${NC} Выбрать NTP сервер                               ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}2.${NC} Синхронизировать время с NTP                      ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}3.${NC} Выбрать часовой пояс                               ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}4.${NC} Показать подробную информацию                      ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}0.${NC} Выход                                              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "$(echo -e ${BLUE}"Ваш выбор [0-4]: "${NC})" choice
        
        case $choice in
            1) select_ntp_server ;;
            2) sync_ntp ;;
            3) set_timezone ;;
            4) show_info ;;
            0) 
                echo ""
                echo -e "${GREEN}До свидания!${NC}"
                exit 0
                ;;
            *) 
                echo -e "${RED}Неверный выбор! Попробуйте снова.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Точка входа
clear_screen
echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║              СИНХРОНИЗАЦИЯ ВРЕМЕНИ И ЧАСОВОЙ ПОЯС            ║"
echo "║                                                               ║"
echo "║        Скрипт для управления системным временем Linux        ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Запуск главного меню
main_menu
