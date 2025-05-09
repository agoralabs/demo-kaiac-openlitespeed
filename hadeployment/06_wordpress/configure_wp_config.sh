#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 [DOMAIN_FOLDER] [WEB_ROOT] [WP_DB_NAME] [WP_DB_USER] [WP_DB_PASSWORD] [MYSQL_DB_HOST]"
    echo "Exemple: $0 ..."
    exit 1
fi

DOMAIN_FOLDER="$1"
WEB_ROOT="$2"
WP_DB_NAME="$3"
WP_DB_USER="$4"
WP_DB_PASSWORD="$5"
MYSQL_DB_HOST="$6"

WP_DEBUG_FILENAME="wpDebug.log"

# Fonction pour générer des clés aléatoires sécurisées
generate_wordpress_key() {
    local chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?'
    local key=''
    for i in {1..64}; do
        key+="${chars:RANDOM%${#chars}:1}"
    done
    echo "$key"
}

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
define('WP_DEBUG', false);  // true Active le mode débogage
define('WP_DEBUG_LOG', '/usr/local/lsws/logs/vhosts/${DOMAIN_FOLDER}/${WP_DEBUG_FILENAME}'); // par défaut écrit dans /wp-content/debug.log
define('WP_DEBUG_DISPLAY', false); // false désactive l'affichage à l'écran

if ( ! defined( 'ABSPATH' ) ) {
  define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOL

sudo chown www-data:www-data "${WEB_ROOT}/wp-config.php"
sudo chmod 644 "${WEB_ROOT}/wp-config.php"


