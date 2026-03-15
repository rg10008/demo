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

if [ "$ROOT_MODE" = "nopasswd" ]; then
    # Используем perl для надёжной работы с regex
    perl -i -pe 's/^#\s*root\s+ALL=\(ALL\)\s+NOPASSWD:\s*ALL$/root ALL=(ALL) NOPASSWD: ALL/' $SUDOERS
    perl -i -pe 's/^#\s*root\s+ALL=\(ALL\)\s+ALL$/root ALL=(ALL) NOPASSWD: ALL/' $SUDOERS
    perl -i -pe 's/^root\s+ALL=\(ALL\)\s+ALL$/root ALL=(ALL) NOPASSWD: ALL/' $SUDOERS
    echo "root: установлен NOPASSWD"
else
    perl -i -pe 's/^#\s*root\s+ALL=\(ALL\)\s+NOPASSWD:\s*ALL$/root ALL=(ALL) ALL/' $SUDOERS
    perl -i -pe 's/^#\s*root\s+ALL=\(ALL\)\s+ALL$/root ALL=(ALL) ALL/' $SUDOERS
    perl -i -pe 's/^root\s+ALL=\(ALL\)\s+NOPASSWD:\s*ALL$/root ALL=(ALL) ALL/' $SUDOERS
    echo "root: установлен режим с паролем"
fi

# ============================================
# Обработка WHEEL_USERS
# ============================================
echo "Обработка прав WHEEL_USERS..."

if [ "$WHEEL_MODE" = "nopasswd" ]; then
    perl -i -pe 's/^#\s*WHEEL_USERS\s+ALL=\(ALL\)\s+NOPASSWD:\s*ALL$/WHEEL_USERS ALL=(ALL) NOPASSWD: ALL/' $SUDOERS
    perl -i -pe 's/^#\s*WHEEL_USERS\s+ALL=\(ALL\)\s+ALL$/WHEEL_USERS ALL=(ALL) NOPASSWD: ALL/' $SUDOERS
    perl -i -pe 's/^WHEEL_USERS\s+ALL=\(ALL\)\s+ALL$/WHEEL_USERS ALL=(ALL) NOPASSWD: ALL/' $SUDOERS
    echo "WHEEL_USERS: установлен NOPASSWD"
else
    perl -i -pe 's/^#\s*WHEEL_USERS\s+ALL=\(ALL\)\s+NOPASSWD:\s*ALL$/WHEEL_USERS ALL=(ALL) ALL/' $SUDOERS
    perl -i -pe 's/^#\s*WHEEL_USERS\s+ALL=\(ALL\)\s+ALL$/WHEEL_USERS ALL=(ALL) ALL/' $SUDOERS
    perl -i -pe 's/^WHEEL_USERS\s+ALL=\(ALL\)\s+NOPASSWD:\s*ALL$/WHEEL_USERS ALL=(ALL) ALL/' $SUDOERS
    echo "WHEEL_USERS: установлен режим с паролем"
fi

echo ""
echo "========================================="
echo "Готово!"
echo "========================================="
echo ""
echo "Текущие настройки:"
grep -E '^root\s+ALL=\(ALL\)' $SUDOERS 2>/dev/null && echo ""
grep -E '^WHEEL_USERS\s+ALL=\(ALL\)' $SUDOERS 2>/dev/null && echo ""
echo "Резервная копия: ${SUDOERS}.bak"