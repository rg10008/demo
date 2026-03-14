#!/bin/bash

# =========================================================
# УСТАНОВКА MOODLE НА ALT LINUX
# =========================================================
# Скрипт выполняет:
# 1. Установку Apache
# 2. Установку MariaDB
# 3. Установку PHP и модулей
# 4. Скачивание Moodle
# 5. Настройку Apache
# 6. Создание базы данных
# =========================================================

echo "=== Обновление пакетов ==="
apt-get update

echo "=== Установка Apache, MariaDB и PHP ==="
apt-get install -y apache2 mariadb-server php8.2 apache2-mod_php8.2

echo "=== Установка PHP модулей для Moodle ==="
apt-get install -y \
php8.2-opcache \
php8.2-curl \
php8.2-gd \
php8.2-intl \
php8.2-mysqlnd-mysqli \
php8.2-xmlrpc \
php8.2-zip \
php8.2-soap \
php8.2-mbstring \
php8.2-xmlreader \
php8.2-fileinfo \
php8.2-sodium \
wget

echo "=== Включение служб ==="
systemctl enable --now httpd2
systemctl enable --now mariadb

echo "=== Создание базы данных Moodle ==="

mariadb -u root <<EOF

CREATE DATABASE moodle DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'moodle'@'localhost' IDENTIFIED BY 'P@ssw0rd';

GRANT ALL PRIVILEGES ON moodle.* TO 'moodle'@'localhost';

FLUSH PRIVILEGES;

EXIT;

EOF

echo "=== Скачивание Moodle ==="

cd /tmp

wget https://download.moodle.org/download.php/direct/stable405/moodle-latest-405.tgz

tar -xf moodle-latest-405.tgz

mv moodle /var/www/html/

echo "=== Создание директории moodledata ==="

mkdir /var/www/moodledata

echo "=== Установка прав ==="

chown -R apache2:apache2 /var/www/html
chown -R apache2:apache2 /var/www/moodledata

echo "=== Удаление стандартной страницы Apache ==="

rm -f /var/www/html/index.html

echo "=== Настройка Apache VirtualHost ==="

cat > /etc/httpd2/conf/sites-available/default.conf <<EOF

<VirtualHost *:80>

DocumentRoot /var/www/html/moodle
ServerName moodle.local

<Directory /var/www/html/moodle>

Options FollowSymLinks
AllowOverride All
Require all granted

</Directory>

</VirtualHost>

EOF

echo "=== Настройка PHP для Moodle ==="

PHPINI="/etc/php/8.2/apache2-mod_php/php.ini"

sed -i 's/^max_input_vars.*/max_input_vars = 5000/' $PHPINI
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 100M/' $PHPINI
sed -i 's/^post_max_size.*/post_max_size = 100M/' $PHPINI

echo "=== Перезапуск Apache ==="

systemctl restart httpd2

echo "======================================="
echo "Moodle установлен."
echo "Открой в браузере:"
echo "http://SERVER-IP/install.php"
echo "======================================="