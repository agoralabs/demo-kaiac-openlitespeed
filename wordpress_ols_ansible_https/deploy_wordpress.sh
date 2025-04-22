#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 10 ]; then
    echo "Usage: $0 <domain> <domain_folder> <wp_db_name> <wp_db_user> <wp_db_password> <mysql_host> <mysql_root_user> <mysql_root_password> <php_version> <wp_version>"
    echo "Example: $0 example.com example wordpress_db wp_user secure_password localhost root root_password lsphp81 6.5.2"
    echo "Note: Pour la dernière version, utiliser 'latest' comme version"
    exit 1
fi

# Paramètres passés en arguments
DOMAIN="$1" # provient du message SQS
DOMAIN_FOLDER="$2" # provient du message SQS
WP_DB_NAME="$3" # provient du message SQS
WP_DB_USER="$4" # provient du message SQS
WP_DB_PASSWORD="$5" # provient du message SQS
MYSQL_DB_HOST="$6" # provient des variables d'environnement
MYSQL_ROOT_USER="$7" # provient des variables d'environnement
MYSQL_ROOT_PASSWORD="$8" # provient des variables d'environnement
PHP_VERSION="$9" # provient du message SQS
WP_VERSION="${10}" # provient du message SQS

# Variables dérivées
EMAIL_ADMIN="admin@${DOMAIN}"
WEB_ROOT="/var/www/${DOMAIN_FOLDER}"
VHOST_CONF="/usr/local/lsws/conf/vhosts/${DOMAIN_FOLDER}/vhconf.conf"
HTTPD_CONF="/usr/local/lsws/conf/httpd_config.conf"
WP_DOWNLOAD_URL="https://wordpress.org/wordpress-${WP_VERSION}.tar.gz"
[ "$WP_VERSION" = "latest" ] && WP_DOWNLOAD_URL="https://wordpress.org/latest.tar.gz"

# Fonction pour générer des clés aléatoires sécurisées
generate_wordpress_key() {
    local chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?'
    local key=''
    for i in {1..64}; do
        key+="${chars:RANDOM%${#chars}:1}"
    done
    echo "$key"
}

# Fonction pour vérifier les commandes nécessaires
check_requirements() {
    local commands=("wget" "mysql" "systemctl")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Erreur: $cmd n'est pas installé"
            exit 1
        fi
    done
}

# Afficher la configuration
echo "=== Configuration du déploiement WordPress ==="
echo "Domaine: ${DOMAIN}"
echo "Dossier: ${WEB_ROOT}"
echo "Version WordPress: ${WP_VERSION}"
echo "Base de données: ${WP_DB_NAME}"
echo "Utilisateur DB: ${WP_DB_USER}"
echo "Hôte MySQL: ${MYSQL_DB_HOST}"
echo "Version PHP: ${PHP_VERSION}"
echo "============================================"

# Vérifier les prérequis
check_requirements

# Installer les dépendances
echo "Installation des dépendances..."
sudo apt-get update > /dev/null
sudo apt-get install -y python3-pymysql > /dev/null

# Créer le dossier du site
echo "Création du dossier du site..."
sudo mkdir -p "${WEB_ROOT}"
sudo chown nobody:nogroup "${WEB_ROOT}"
sudo chmod 755 "${WEB_ROOT}"

# Télécharger et extraire WordPress
echo "Téléchargement de WordPress ${WP_VERSION}..."
if ! wget -q -O /tmp/wordpress.tar.gz "${WP_DOWNLOAD_URL}"; then
    echo "Erreur: Impossible de télécharger WordPress version ${WP_VERSION}"
    echo "Veuillez vérifier que la version existe sur https://wordpress.org/download/releases/"
    exit 1
fi

echo "Extraction de WordPress..."
sudo tar -xzf /tmp/wordpress.tar.gz --strip-components=1 -C "${WEB_ROOT}"
rm -f /tmp/wordpress.tar.gz

# Générer les clés de sécurité
echo "Génération des clés de sécurité..."
AUTH_KEY=$(generate_wordpress_key)
SECURE_AUTH_KEY=$(generate_wordpress_key)
LOGGED_IN_KEY=$(generate_wordpress_key)
NONCE_KEY=$(generate_wordpress_key)
AUTH_SALT=$(generate_wordpress_key)
SECURE_AUTH_SALT=$(generate_wordpress_key)
LOGGED_IN_SALT=$(generate_wordpress_key)
NONCE_SALT=$(generate_wordpress_key)

# Créer wp-config.php
echo "Configuration de wp-config.php..."
sudo cat > "${WEB_ROOT}/wp-config.php" <<EOL
<?php
define( 'DB_NAME', '${WP_DB_NAME}' );
define( 'DB_USER', '${WP_DB_USER}' );
define( 'DB_PASSWORD', '${WP_DB_PASSWORD}' );
define( 'DB_HOST', '${MYSQL_DB_HOST}' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );

define('AUTH_KEY',         '${AUTH_KEY}');
define('SECURE_AUTH_KEY',  '${SECURE_AUTH_KEY}');
define('LOGGED_IN_KEY',    '${LOGGED_IN_KEY}');
define('NONCE_KEY',        '${NONCE_KEY}');
define('AUTH_SALT',        '${AUTH_SALT}');
define('SECURE_AUTH_SALT', '${SECURE_AUTH_SALT}');
define('LOGGED_IN_SALT',   '${LOGGED_IN_SALT}');
define('NONCE_SALT',       '${NONCE_SALT}');

\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );
if ( ! defined( 'ABSPATH' ) ) {
  define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOL

sudo chown www-data:www-data "${WEB_ROOT}/wp-config.php"
sudo chmod 644 "${WEB_ROOT}/wp-config.php"

# Configurer la base de données
echo "Configuration de la base de données MySQL..."
mysql -h "${MYSQL_DB_HOST}" -u "${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS ${WP_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${WP_DB_USER}'@'%' IDENTIFIED BY '${WP_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${WP_DB_NAME}.* TO '${WP_DB_USER}'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Configurer OpenLiteSpeed
echo "Configuration d'OpenLiteSpeed..."

# Configurer le listener http80 si nécessaire
if ! grep -q "listener http80 {" "${HTTPD_CONF}"; then
    echo "Ajout du listener http80..."
    sudo tee -a "${HTTPD_CONF}" > /dev/null <<EOL

# BEGIN WordPress listener
listener http80 {
    address                 *:80
    secure                  0
}
# END WordPress listener
EOL
fi

# Créer le répertoire du virtual host
sudo mkdir -p "/usr/local/lsws/conf/vhosts/${DOMAIN_FOLDER}"

# Créer la configuration du virtual host
echo "Configuration du virtual host..."
sudo tee "${VHOST_CONF}" > /dev/null <<EOL
docRoot                   \$VH_ROOT/
index  {
  useServer               0
  indexFiles              index.php
}

context / {
  location                \$VH_ROOT
  allowBrowse             1
  indexFiles              index.php

  rewrite  {
    enable                1
    inherit               1
    rewriteFile           /var/www/${DOMAIN_FOLDER}/.htaccess
  }
}

rewrite  {
  enable                  1
  autoLoadHtaccess        1
}
EOL

# Ajouter le virtualhost à la configuration principale
if ! grep -q "virtualhost ${DOMAIN_FOLDER}" "${HTTPD_CONF}"; then
    echo "Ajout du virtualhost..."
    sudo tee -a "${HTTPD_CONF}" > /dev/null <<EOL

# BEGIN WordPress virtualhost
virtualhost ${DOMAIN_FOLDER} {
    vhRoot                  ${WEB_ROOT}
    configFile              ${VHOST_CONF}
    allowSymbolLink         1
    enableScript            1
    restrained              0
}
# END WordPress virtualhost
EOL
fi

# Ajouter la règle map
if ! grep -q "map\s\+${DOMAIN_FOLDER}\s\+${DOMAIN}" "${HTTPD_CONF}"; then
    echo "Ajout de la règle map..."
    sudo sed -i "/listener http80\s*{/a \ \ map                     ${DOMAIN_FOLDER} ${DOMAIN}" "${HTTPD_CONF}"
fi

# Redémarrer OpenLiteSpeed
echo "Redémarrage du service OpenLiteSpeed..."
sudo systemctl restart lsws

echo "=== Déploiement terminé avec succès ==="
echo "URL: http://${DOMAIN}"
echo "Version WordPress: ${WP_VERSION}"
echo "Répertoire WordPress: ${WEB_ROOT}"
echo "Base de données: ${WP_DB_NAME}"
echo "======================================"