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

# =========================================================
# НАСТРАИВАЕМЫЕ ПАРАМЕТРЫ
# =========================================================
# Измените эти значения по своему усмотрению:

DB_NAME="moodledb"              # Имя базы данных
DB_USER="moodle"                # Имя пользователя базы данных
DB_PASSWORD="P@ssw0rd"          # Пароль пользователя БД
ADMIN_PASSWORD="P@ssw0rd"       # Пароль администратора Moodle
WORKPLACE_NUMBER="1"            # Номер рабочего места (арабская цифра)

# =========================================================

echo "======================================="
echo "ПАРАМЕТРЫ УСТАНОВКИ:"
echo "======================================="
echo "База данных: $DB_NAME"
echo "Пользователь БД: $DB_USER"
echo "Пароль БД: $DB_PASSWORD"
echo "Пароль admin: $ADMIN_PASSWORD"
echo "Номер рабочего места: $WORKPLACE_NUMBER"
echo "======================================="

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

echo "=== Инициализация и перезапуск MariaDB ==="
mariadb-install-db && systemctl restart mariadb

echo "=== Создание базы данных Moodle ==="

mariadb -u root <<EOF

CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';

GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';

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

echo "=== Создание главной страницы с номером рабочего места ==="

echo "$WORKPLACE_NUMBER" > /var/www/html/index.html
chown apache2:apache2 /var/www/html/index.html

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

# Раскомментируем и устанавливаем значения (убираем ';' в начале строк)
sed -i 's/^[;[:space:]]*max_input_vars.*/max_input_vars = 5000/' $PHPINI
sed -i 's/^[;[:space:]]*upload_max_filesize.*/upload_max_filesize = 100M/' $PHPINI
sed -i 's/^[;[:space:]]*post_max_size.*/post_max_size = 100M/' $PHPINI

echo "=== Перезапуск Apache ==="

systemctl restart httpd2

echo "======================================="
echo "Moodle установлен."
echo "======================================="
echo "ОТЧЁТ ПО ПАРАМЕТРАМ:"
echo "======================================="
echo "Веб-сервер: Apache (httpd2)"
echo "СУБД: MariaDB"
echo "База данных: $DB_NAME"
echo "Пользователь БД: $DB_USER"
echo "Пароль БД: $DB_PASSWORD"
echo "Пароль admin Moodle: $ADMIN_PASSWORD"
echo "Номер рабочего места: $WORKPLACE_NUMBER"
echo "======================================="
echo "Открой в браузере:"
echo "http://SERVER-IP/moodle/install.php"
echo "======================================="
