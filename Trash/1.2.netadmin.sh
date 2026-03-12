#!/bin/bash

USER_NAME="net_admin"
USER_PASS="P@$$word"

echo "Создание пользователя $USER_NAME..."

if id "$USER_NAME" &>/dev/null; then
    echo "Пользователь $USER_NAME уже существует"
else
    useradd -m -s /bin/bash $USER_NAME
    echo "$USER_NAME:$USER_PASS" | chpasswd
fi

echo "Добавление в sudo..."
usermod -aG wheel $USER_NAME 2>/dev/null || usermod -aG sudo $USER_NAME

echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER_NAME
chmod 440 /etc/sudoers.d/$USER_NAME

echo "Готово."