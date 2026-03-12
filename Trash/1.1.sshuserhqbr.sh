#!/bin/bash

USER_NAME="sshuser"
USER_UID="1010"
USER_PASS="P@ssw0rd"

echo "Создание пользователя $USER_NAME..."

# Проверка существует ли пользователь
if id "$USER_NAME" &>/dev/null; then
    echo "Пользователь $USER_NAME уже существует"
else
    useradd -m -u $USER_UID -s /bin/bash $USER_NAME
    echo "$USER_NAME:$USER_PASS" | chpasswd
fi

echo "Добавление пользователя в группу wheel (sudo)..."
usermod -aG wheel $USER_NAME 2>/dev/null || usermod -aG sudo $USER_NAME

echo "Настройка sudo без пароля..."
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER_NAME
chmod 440 /etc/sudoers.d/$USER_NAME

echo "Готово."