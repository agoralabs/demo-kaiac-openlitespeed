#!/bin/bash

# Paramètres
DOMAIN="$1"
DOMAIN_FOLDER="$2"
WP_DB_NAME="$3"
MYSQL_ROOT_USER="$4"
MYSQL_ROOT_PASSWORD="$5"

# 1. Supprimer la base de données
mysql -h localhost -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" <<MYSQL_SCRIPT
DROP DATABASE IF EXISTS ${WP_DB_NAME};
DROP USER IF EXISTS '${WP_DB_NAME}_user'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# 2. Supprimer les fichiers
rm -rf "/var/www/${DOMAIN_FOLDER}"

# 3. Supprimer la configuration OpenLiteSpeed
rm -rf "/usr/local/lsws/conf/vhosts/${DOMAIN_FOLDER}"
sed -i "/virtualhost ${DOMAIN_FOLDER}/,/^}/d" /usr/local/lsws/conf/httpd_config.conf
sed -i "/map \+${DOMAIN_FOLDER} \+${DOMAIN}/d" /usr/local/lsws/conf/httpd_config.conf

# 4. Redémarrer OpenLiteSpeed
systemctl restart lsws

echo "Suppression de ${DOMAIN} terminée"