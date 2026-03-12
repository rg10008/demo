#!/bin/bash

echo "Выберите тип устройства:"
echo "1 - Server (HQ-SRV / BR-SRV)"
echo "2 - Router (HQ-RTR / BR-RTR)"
read -p "Введите номер: " DEVICE

create_user () {

USERNAME=$1
PASSWORD=$2
USER_UID=$3

echo "Проверка пользователя $USERNAME..."

if id "$USERNAME" &>/dev/null; then
    echo "Пользователь уже существует"

    CURRENT_UID=$(id -u $USERNAME)

    if [ ! -z "$USER_UID" ] && [ "$CURRENT_UID" != "$USER_UID" ]; then
        echo "UID отличается. Текущий: $CURRENT_UID Требуемый: $USER_UID"
    fi
else
    echo "Создание пользователя..."

    if [ -z "$USER_UID" ]; then
        useradd -m -s /bin/bash $USERNAME
    else
        useradd -m -u $USER_UID -s /bin/bash $USERNAME
    fi

    echo "$USERNAME:$PASSWORD" | sudo chpasswd
fi

echo "Настройка sudo..."

if getent group wheel >/dev/null; then
    usermod -aG wheel $USERNAME
elif getent group sudo >/dev/null; then
    usermod -aG sudo $USERNAME
fi

echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USERNAME
chmod 440 /etc/sudoers.d/$USERNAME

echo "Пользователь $USERNAME готов"
}

case $DEVICE in

1)
echo "Настройка Server..."
create_user "sshuser" "P@ssw0rd" "1010"
;;

2)
echo "Настройка Router (Linux)..."
create_user "net_admin" "P@$$word"
;;

*)
echo "Неверный выбор"
exit 1
;;

esac

echo "Настройка завершена"