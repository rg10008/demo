#!/bin/bash

SUDOERS="/etc/sudoers"

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "Запустите скрипт от root"
    exit 1
fi

# Функция для выбора режима
select_mode() {
    local prompt="$1"
    local var_name="$2"
    
    echo ""
    echo "========================================="
    echo "$prompt"
    echo "========================================="
    echo "1) С NOPASSWD (без пароля)"
    echo "2) С паролем (обычный режим)"
    echo "========================================="
    
    while true; do
        read -p "Выберите вариант [1/2]: " choice
        case $choice in
            1)
                eval "$var_name='nopasswd'"
                break
                ;;
            2)
                eval "$var_name='password'"
                break
                ;;
            *)
                echo "Неверный выбор. Введите 1 или 2"
                ;;
        esac
    done
}

# Выбор режима для root
select_mode "Настройка прав ROOT" "ROOT_MODE"

# Выбор режима для WHEEL_USERS
select_mode "Настройка прав WHEEL_USERS" "WHEEL_MODE"

echo ""
echo "========================================="
echo "Выбранные настройки:"
echo "========================================="
echo "ROOT:        $([ "$ROOT_MODE" = "nopasswd" ] && echo "NOPASSWD" || echo "С паролем")"
echo "WHEEL_USERS: $([ "$WHEEL_MODE" = "nopasswd" ] && echo "NOPASSWD" || echo "С паролем")"
echo "========================================="
read -p "Продолжить? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Отмена операции"
    exit 0
fi

echo ""
echo "Создание резервной копии sudoers..."
cp $SUDOERS ${SUDOERS}.bak

# ============================================
# Обработка ROOT
# ============================================
echo "Обработка прав root..."

# Проверяем есть ли активная строка root
if grep -qE '^root\s+ALL=\(ALL' $SUDOERS; then
    echo "Найдена активная строка root"
    ACTIVE_ROOT=1
else
    echo "Активная строка root не найдена, раскомментируем..."
    ACTIVE_ROOT=0
    
    if [ "$ROOT_MODE" = "nopasswd" ]; then
        # Раскомментируем первую закомментированную строку root с NOPASSWD
        sed -i '0,/^#[[:space:]]*root[[:space:]]*ALL=(ALL:ALL)[[:space:]]*ALL/s/^#[[:space:]]*root[[:space:]]*ALL=(ALL:ALL)[[:space:]]*ALL/root ALL=(ALL:ALL) NOPASSWD: ALL/' $SUDOERS
        sed -i '0,/^#[[:space:]]*root[[:space:]]*ALL=(ALL)[[:space:]]*ALL/s/^#[[:space:]]*root[[:space:]]*ALL=(ALL)[[:space:]]*ALL/root ALL=(ALL) NOPASSWD: ALL/' $SUDOERS
    else
        # Раскомментируем первую закомментированную строку root без NOPASSWD
        sed -i '0,/^#[[:space:]]*root[[:space:]]*ALL=(ALL:ALL)[[:space:]]*ALL/s/^#[[:space:]]*root[[:space:]]*ALL=(ALL:ALL)[[:space:]]*ALL/root ALL=(ALL:ALL) ALL/' $SUDOERS
        sed -i '0,/^#[[:space:]]*root[[:space:]]*ALL=(ALL)[[:space:]]*ALL/s/^#[[:space:]]*root[[:space:]]*ALL=(ALL)[[:space:]]*ALL/root ALL=(ALL) ALL/' $SUDOERS
    fi
fi

# Меняем активные строки
if [ "$ROOT_MODE" = "nopasswd" ]; then
    sed -i 's/^root[[:space:]]*ALL=(ALL:ALL)[[:space:]]*ALL$/root ALL=(ALL:ALL) NOPASSWD: ALL/' $SUDOERS
    sed -i 's/^root[[:space:]]*ALL=(ALL)[[:space:]]*ALL$/root ALL=(ALL) NOPASSWD: ALL/' $SUDOERS
    echo "root: установлен NOPASSWD"
else
    sed -i 's/^root[[:space:]]*ALL=(ALL:ALL)[[:space:]]*NOPASSWD:[[:space:]]*ALL$/root ALL=(ALL:ALL) ALL/' $SUDOERS
    sed -i 's/^root[[:space:]]*ALL=(ALL)[[:space:]]*NOPASSWD:[[:space:]]*ALL$/root ALL=(ALL) ALL/' $SUDOERS
    echo "root: установлен режим с паролем"
fi

# ============================================
# Обработка WHEEL_USERS
# ============================================
echo "Обработка прав WHEEL_USERS..."

# Проверяем есть ли активная строка WHEEL_USERS
if grep -qE '^WHEEL_USERS[[:space:]]+ALL=\(ALL' $SUDOERS; then
    echo "Найдена активная строка WHEEL_USERS"
    ACTIVE_WHEEL=1
else
    echo "Активная строка WHEEL_USERS не найдена, раскомментируем..."
    ACTIVE_WHEEL=0
    
    if [ "$WHEEL_MODE" = "nopasswd" ]; then
        # Раскомментируем ТОЛЬКО первую закомментированную строку WHEEL_USERS
        sed -i '0,/^#[[:space:]]*WHEEL_USERS[[:space:]]*ALL=(ALL:ALL)[[:space:]]*ALL/s/^#[[:space:]]*WHEEL_USERS[[:space:]]*ALL=(ALL:ALL)[[:space:]]*ALL/WHEEL_USERS ALL=(ALL:ALL) NOPASSWD: ALL/' $SUDOERS
        sed -i '0,/^#[[:space:]]*WHEEL_USERS[[:space:]]*ALL=(ALL)[[:space:]]*ALL/s/^#[[:space:]]*WHEEL_USERS[[:space:]]*ALL=(ALL)[[:space:]]*ALL/WHEEL_USERS ALL=(ALL) NOPASSWD: ALL/' $SUDOERS
    else
        sed -i '0,/^#[[:space:]]*WHEEL_USERS[[:space:]]*ALL=(ALL:ALL)[[:space:]]*ALL/s/^#[[:space:]]*WHEEL_USERS[[:space:]]*ALL=(ALL:ALL)[[:space:]]*ALL/WHEEL_USERS ALL=(ALL:ALL) ALL/' $SUDOERS
        sed -i '0,/^#[[:space:]]*WHEEL_USERS[[:space:]]*ALL=(ALL)[[:space:]]*ALL/s/^#[[:space:]]*WHEEL_USERS[[:space:]]*ALL=(ALL)[[:space:]]*ALL/WHEEL_USERS ALL=(ALL) ALL/' $SUDOERS
    fi
fi

# Меняем активные строки
if [ "$WHEEL_MODE" = "nopasswd" ]; then
    sed -i 's/^WHEEL_USERS[[:space:]]*ALL=(ALL:ALL)[[:space:]]*ALL$/WHEEL_USERS ALL=(ALL:ALL) NOPASSWD: ALL/' $SUDOERS
    sed -i 's/^WHEEL_USERS[[:space:]]*ALL=(ALL)[[:space:]]*ALL$/WHEEL_USERS ALL=(ALL) NOPASSWD: ALL/' $SUDOERS
    echo "WHEEL_USERS: установлен NOPASSWD"
else
    sed -i 's/^WHEEL_USERS[[:space:]]*ALL=(ALL:ALL)[[:space:]]*NOPASSWD:[[:space:]]*ALL$/WHEEL_USERS ALL=(ALL:ALL) ALL/' $SUDOERS
    sed -i 's/^WHEEL_USERS[[:space:]]*ALL=(ALL)[[:space:]]*NOPASSWD:[[:space:]]*ALL$/WHEEL_USERS ALL=(ALL) ALL/' $SUDOERS
    echo "WHEEL_USERS: установлен режим с паролем"
fi

echo ""
echo "========================================="
echo "Готово!"
echo "========================================="
echo ""
echo "Текущие настройки:"
grep -E '^root[[:space:]]+ALL=\(ALL' $SUDOERS 2>/dev/null && echo ""
grep -E '^WHEEL_USERS[[:space:]]+ALL=\(ALL' $SUDOERS 2>/dev/null && echo ""
echo ""
echo "Резервная копия: ${SUDOERS}.bak"