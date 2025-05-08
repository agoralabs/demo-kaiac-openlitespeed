#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 [DOMAIN] [DOMAIN_FOLDER] [WEB_ROOT] [HTTPD_CONF] [VHOST_CONF]"
    echo "Exemple: $0 ..."
    exit 1
fi

MYSQL_DB_HOST="$1"
MYSQL_ROOT_USER="$2"
MYSQL_ROOT_PASSWORD="$3"
WP_DB_NAME="$4"
WP_DB_USER="$5"
WP_DB_PASSWORD="$6"

echo "Configuration de la base de données MySQL..."
    mysql -h "${MYSQL_DB_HOST}" -u "${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS ${WP_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${WP_DB_USER}'@'%' IDENTIFIED BY '${WP_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${WP_DB_NAME}.* TO '${WP_DB_USER}'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
echo "Base de données MySQL configurée avec succès."