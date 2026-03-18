#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Путь к папке со скриптами
SCRIPTS_DIR="./demo1"

# Функция для отображения заголовка
show_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     МЕНЕДЖЕР ЗАПУСКА СКРИПТОВ     ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════╝${NC}"
    echo ""
}

# Функция для проверки существования папки
check_directory() {
    if [ ! -d "$SCRIPTS_DIR" ]; then
        echo -e "${RED}Ошибка: Папка $SCRIPTS_DIR не найдена!${NC}"
        exit 1
    fi
}

# Функция для получения списка скриптов
get_scripts_list() {
    # Ищем все .sh файлы в папке и сортируем их
    scripts=($(ls "$SCRIPTS_DIR"/*.sh 2>/dev/null | sort -V))
    
    if [ ${#scripts[@]} -eq 0 ]; then
        echo -e "${RED}В папке $SCRIPTS_DIR не найдено .sh скриптов!${NC}"
        exit 1
    fi
}

# Функция для отображения меню
show_menu() {
    echo -e "${YELLOW}Доступные скрипты:${NC}\n"
    
    for i in "${!scripts[@]}"; do
        # Получаем имя файла без пути
        script_name=$(basename "${scripts[$i]}")
        
        # Выбираем цвет в зависимости от типа скрипта
        if [[ $script_name == 0.* ]]; then
            color=$RED
        elif [[ $script_name == 1.* ]]; then
            color=$GREEN
        elif [[ $script_name == 2.* ]]; then
            color=$BLUE
        else
            color=$PURPLE
        fi
        
        # Форматируем вывод
        printf "${CYAN}%2d)${NC} ${color}%-25s${NC}" $((i+1)) "$script_name"
        
        # Добавляем описание скрипта
        case $script_name in
            "0.1.sudoers.sh") echo -e " ${YELLOW}(Настройка sudoers)${NC}" ;;
            "1.1.ipnet.sh") echo -e " ${YELLOW}(Настройка сети/IP)${NC}" ;;
            "1.2.nat.sh") echo -e " ${YELLOW}(Настройка NAT)${NC}" ;;
            "1.3.dhcp-install.sh") echo -e " ${YELLOW}(Установка DHCP)${NC}" ;;
            "1.4.users.sh") echo -e " ${YELLOW}(Управление пользователями)${NC}" ;;
            "1.5.ssh.sh") echo -e " ${YELLOW}(Настройка SSH)${NC}" ;;
            "2.2.docker.sh") echo -e " ${YELLOW}(Установка Docker)${NC}" ;;
            "2.3.moodle.sh") echo -e " ${YELLOW}(Установка Moodle)${NC}" ;;
            *) echo -e "" ;;
        esac
    done
    
    echo -e "\n${PURPLE}0)${NC} ${RED}Выход${NC}"
    echo ""
}

# Функция для запуска скрипта
run_script() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    
    echo -e "\n${GREEN}Запуск скрипта: $script_name${NC}"
    echo -e "${YELLOW}Нажмите Enter для продолжения или Ctrl+C для отмены...${NC}"
    read
    
    # Проверяем, исполняемый ли файл
    if [ ! -x "$script_path" ]; then
        echo -e "${YELLOW}Файл не исполняемый. Добавляю права на выполнение...${NC}"
        chmod +x "$script_path"
    fi
    
    # Запускаем скрипт
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    "$script_path"
    local exit_code=$?
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ Скрипт $script_name успешно выполнен${NC}"
    else
        echo -e "${RED}✗ Скрипт $script_name завершился с ошибкой (код: $exit_code)${NC}"
    fi
    
    echo -e "\n${YELLOW}Нажмите Enter, чтобы вернуться в меню...${NC}"
    read
}

# Основная функция
main() {
    check_directory
    get_scripts_list
    
    while true; do
        show_header
        show_menu
        
        echo -e -n "${GREEN}Выберите скрипт для запуска (0-${#scripts[@]}): ${NC}"
        read choice
        
        # Проверка на выход
        if [ "$choice" = "0" ]; then
            echo -e "\n${PURPLE}До свидания!${NC}"
            exit 0
        fi
        
        # Проверка корректности ввода
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#scripts[@]} ]; then
            echo -e "\n${RED}Ошибка: Неверный выбор. Пожалуйста, введите число от 0 до ${#scripts[@]}.${NC}"
            echo -e "${YELLOW}Нажмите Enter, чтобы продолжить...${NC}"
            read
            continue
        fi
        
        # Запуск выбранного скрипта
        run_script "${scripts[$((choice-1))]}"
    done
}

# Запуск основной функции
main