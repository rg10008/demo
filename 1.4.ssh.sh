#!/bin/bash

CONFIG="/etc/openssh/sshd_config"
BANNER="/etc/openssh/banner"
USER_ALLOWED="sshuser"
PORT="2024"

echo "=== Настройка безопасного SSH ==="

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo "Запустите скрипт от root"
  exit 1
fi

# Проверка пользователя
if id "$USER_ALLOWED" &>/dev/null; then
  echo "Пользователь $USER_ALLOWED найден"
else
  echo "Ошибка: пользователь $USER_ALLOWED не существует"
  exit 1
fi

# Резервная копия конфигурации
echo "Создание резервной копии sshd_config"
cp $CONFIG ${CONFIG}.backup

# Функция изменения параметров
set_param () {
    PARAM=$1
    VALUE=$2

    if grep -q "^$PARAM" $CONFIG; then
        sed -i "s/^$PARAM.*/$PARAM $VALUE/" $CONFIG
    else
        echo "$PARAM $VALUE" >> $CONFIG
    fi
}

echo "Настройка параметров SSH"

set_param "Port" "$PORT"
set_param "AllowUsers" "$USER_ALLOWED"
set_param "MaxAuthTries" "2"
set_param "PasswordAuthentication" "yes"
set_param "Banner" "$BANNER"

echo "Создание баннера"
echo "Authorized access only." > $BANNER

# Проверка конфигурации
echo "Проверка конфигурации sshd"
sshd -t

if [ $? -ne 0 ]; then
  echo "Ошибка в конфигурации SSH. Проверьте файл."
  exit 1
fi

# Перезапуск службы
echo "Перезапуск SSH"
systemctl restart sshd

echo "=== Настройка завершена ==="
echo "SSH порт: $PORT"
echo "Разрешенный пользователь: $USER_ALLOWED"