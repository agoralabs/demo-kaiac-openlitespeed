#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 31 ]; then
    echo "Usage: $0 <domain> <domain_folder> <wp_db_name> <wp_db_user> <wp_db_password> <mysql_host> <mysql_root_user> <mysql_root_password> <php_version> <wp_version>..."
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
INSTALLATION_METHOD="${11}" # provient du message SQS
GIT_REPO_URL="${12}" # provient du message SQS
GIT_BRANCH="${13}" # provient du message SQS
GIT_USERNAME="${14}" # provient du message SQS
GIT_TOKEN="${15}" # provient du message SQS
RECORD_NAME="${16}" # provient du message SQS
TOP_DOMAIN="${17}" # provient du message SQS
ALB_TAG_NAME="${18}" # provient des variables d'environnement
ALB_TAG_VALUE="${19}" # provient des variables d'environnement
WP_ZIP_LOCATION="${20}" # provient du message SQS
WP_DB_DUMP_LOCATION="${21}" # provient du message SQS
WP_SOURCE_DOMAIN="${22}" # provient du message SQS
WP_SOURCE_DOMAIN_FOLDER="${23}" # provient du message SQS
WP_SOURCE_DB_NAME="${24}" # provient du message SQS
WP_PUSH_LOCATION="${25}" # provient du message SQS
WP_SFTP_USER="${26}" # provient du message SQS
WP_SFTP_PWD="${27}" # provient du message SQS
WP_MAINTENANCE_MODE="${28}" # provient du message SQS
WP_LSCACHE="${29}" # provient du message SQS
WP_BACKUP_TYPE="${30}" # provient du message SQS
WP_BACKUP_S3_LOCATION="${31}" # provient du message SQS

# Variables dérivées
EMAIL_ADMIN="admin@${DOMAIN}"
WEB_ROOT="/var/www/${DOMAIN_FOLDER}"
WEB_ROOT_SOURCE="/var/www/${WP_SOURCE_DOMAIN_FOLDER}"
VHOST_CONF="/usr/local/lsws/conf/vhosts/${DOMAIN_FOLDER}/vhconf.conf"
HTTPD_CONF="/usr/local/lsws/conf/httpd_config.conf"
#Variables utilisées dans le mode push
CONFIG_GROUP_NAME=""
CONFIG_SOURCE_ENV=""
CONFIG_TARGET_ENV=""
CONFIG_FILE_SELECTION=""
CONFIG_SELECTED_FILES=""
CONFIG_DB_SELECTION=""
CONFIG_SELECTED_TABLES=""
CONFIG_PERFORM_SEARCH_REPLACE=""
WP_SFTP_ADD_USER_SCRIPT="/home/ubuntu/add_sftp_user.sh"
WP_TOGGLE_MAINTENANCE_SCRIPT="/home/ubuntu/toggle_wp_maintenance.sh"
WP_TOGGLE_LSCACHE_SCRIPT="/home/ubuntu/toggle_wp_lscache.sh"
WP_BACKUP_SCRIPT="/home/ubuntu/backup_wordpress.sh"
WP_REWRITE_RULES_SCRIPT="/home/ubuntu/update_ols_rewrite_rules.sh"

# Fonction pour vérifier si l'installation nécessite une configuration complète
needs_full_config() {
    local method=$1
    case "$method" in
        "push"|"maintenance"|"cache"|"backup"|"redirect")
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

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
    local commands=("wget" "mysql" "systemctl" "aws" "unzip")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Erreur: $cmd n'est pas installé"
            exit 1
        fi
    done
}

# Fonction pour récupérer et parser la configuration
get_push_config() {
    local config_s3_location=$1
    local temp_file=$(mktemp)
    
    echo "Téléchargement de la configuration depuis ${config_s3_location}..."
    aws s3 cp "$config_s3_location" "$temp_file" || {
        echo "Erreur lors du téléchargement de la configuration"
        exit 1
    }

    # Vérification que jq est installé
    if ! command -v jq &> /dev/null; then
        echo "Installation de jq pour le parsing JSON..."
        sudo apt-get install -y jq
    fi

    # Extraction des valeurs
    CONFIG_GROUP_NAME=$(jq -r '.groupName' "$temp_file")
    CONFIG_SOURCE_ENV=$(jq -r '.sourceEnv' "$temp_file")
    CONFIG_TARGET_ENV=$(jq -r '.targetEnv' "$temp_file")
    CONFIG_FILE_SELECTION=$(jq -r '.fileSelection' "$temp_file")
    CONFIG_SELECTED_FILES=$(jq -r '.selectedFiles[]' "$temp_file" | tr '\n' ' ')
    CONFIG_DB_SELECTION=$(jq -r '.databaseSelection' "$temp_file")
    CONFIG_SELECTED_TABLES=$(jq -r '.selectedTables[]' "$temp_file" | tr '\n' ' ')
    CONFIG_PERFORM_SEARCH_REPLACE=$(jq -r '.performSearchReplace' "$temp_file")

    rm "$temp_file"
    
    echo "Configuration chargée:"
    echo " - Groupe: ${CONFIG_GROUP_NAME}"
    echo " - Environnement source: ${CONFIG_SOURCE_ENV}"
    echo " - Environnement cible: ${CONFIG_TARGET_ENV}"
}

# Fonction pour copier les fichiers selon la configuration
copy_selected_files() {
    local source_folder=$1
    local target_folder=$2
    
    echo "Copie des fichiers sélectionnés..."
    
    if [ "$CONFIG_FILE_SELECTION" = "all" ]; then
        echo "Copie de tous les fichiers (sauf wp-config.php)"
        sudo rsync -a "${source_folder}/" "${target_folder}/" --exclude="wp-config.php"
    else
        echo "Copie sélective des fichiers: ${CONFIG_SELECTED_FILES}"
        for file_path in $CONFIG_SELECTED_FILES; do
            local source_path="${source_folder}/${file_path}"
            local target_path="${target_folder}/${file_path}"
            
            echo "Copie de ${source_path} vers ${target_path}"
            sudo mkdir -p "$(dirname "$target_path")"
            sudo rsync -a "$source_path" "$target_path"
        done
    fi
    
    echo "Copie des fichiers terminée."
}

# Fonction pour effectuer le search-replace
perform_search_replace() {
    local source_pattern=$1
    local target_pattern=$2
    local target_file=$3

    if [ "$CONFIG_PERFORM_SEARCH_REPLACE" = "true" ]; then

        # Ignorer les instructions CREATE DATABASE/USE dans le dump avec sed
        echo "Ignorer les instructions CREATE DATABASE/USE dans le dump..."
        sed -i '/^CREATE DATABASE/d;/^USE/d' "$target_file"

        # Remplacer l'ancien domaine par le nouveau domaine
        if [ -n "$source_pattern" ] && [ -n "$target_pattern" ]; then
            echo "Remplacement des URLs dans le dump SQL..."
            echo "Remplacement de $source_pattern par $target_pattern dans le dump SQL..."
            sed -i "s/$source_pattern/$target_pattern/g" "$target_file"
        fi
    fi
}

# Fonction pour copier les tables de la base de données
copy_selected_tables() {
    local source_db=$1
    local target_db=$2
    local db_host=$3
    local source_domain=$4
    local target_domain=$5
    
    echo "Copie des tables sélectionnées..."
    
    if [ "$CONFIG_DB_SELECTION" = "all" ]; then
        echo "Copie de toute la base de données"
        TEMP_SQL_FILE=$(mktemp)
        mysqldump -h "$db_host" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" "$source_db" > "$TEMP_SQL_FILE"

        perform_search_replace "$source_domain" "$target_domain" "$TEMP_SQL_FILE"

        mysql -h "$db_host" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" "$target_db" < "$TEMP_SQL_FILE"
        rm "$TEMP_SQL_FILE"
    else
        echo "Copie sélective des tables: ${CONFIG_SELECTED_TABLES}"
        for table in $CONFIG_SELECTED_TABLES; do
            echo "Copie de la table ${table}"
            
            # Dump de la table
            TEMP_SQL_FILE=$(mktemp)
            mysqldump -h "$db_host" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" "$source_db" "$table" > "$TEMP_SQL_FILE"

            perform_search_replace "$source_domain" "$target_domain" "$TEMP_SQL_FILE"

            # Import dans la nouvelle base
            mysql -h "$db_host" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" "$target_db" < "$TEMP_SQL_FILE"
            
            rm "$TEMP_SQL_FILE"
        done
    fi
    
    echo "Copie des tables terminée."
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

# Fonction pour installer WordPress standard
install_wordpress_standard() {
    local folder=$1
    local version=$2
    
    echo "Téléchargement de WordPress version ${version}..."
    WP_DOWNLOAD_URL="https://wordpress.org/wordpress-${version}.tar.gz"
    [ "$version" = "latest" ] && WP_DOWNLOAD_URL="https://wordpress.org/latest.tar.gz"


    # Création d'un dossier temporaire
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1

    # Téléchargement et extraction
    wget -q "$WP_DOWNLOAD_URL" -O wordpress.tar.gz
    if [ $? -ne 0 ]; then
        echo "Échec du téléchargement de WordPress"
        exit 1
    fi

    tar -xzf wordpress.tar.gz
    rm wordpress.tar.gz

    # Déplacement vers le dossier cible
    if [ -d "$folder" ]; then
        # Suppression du contenu existant
        rm -rf "${folder:?}/"*
    else
        mkdir -p "$folder"
    fi

    mv wordpress/* "$folder"
    rm -r wordpress

    echo "WordPress ${version} installé avec succès dans ${folder}"
}

# Fonction pour installer via Git
install_wordpress_git() {
    local folder=$1
    local repo_url=$2
    local branch=$3
    local username=$4
    local token=$5

    # Construction de l'URL avec les credentials
    CLEAN_URL=${repo_url#https://}
    AUTH_URL="https://${username}:${token}@${CLEAN_URL}"

    # Fonction pour vérifier si un dossier est un dépôt Git
    is_git_repo() {
        [ -d "$1/.git" ]
    }

    # Vérification si le dossier local existe
    if [ -d "$folder" ]; then
        if is_git_repo "$folder"; then
            echo "Dépôt Git existant détecté. Mise à jour..."
            cd "$folder" || exit 1
            
            # Réinitialisation des changements locaux éventuels
            git reset --hard
            
            # Vérification de la branche
            CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
            if [ "$CURRENT_BRANCH" != "$branch" ]; then
                git checkout "$branch" || git checkout -b "$branch" --track "origin/$branch"
            fi
            
            # Pull des derniers changements
            git pull "$AUTH_URL" "$branch"
        else
            echo "Le dossier existe mais n'est pas un dépôt Git."
            echo "Suppression du contenu existant et nouveau clonage..."
            rm -rf "${folder:?}/"*
            git clone -b "$branch" "$AUTH_URL" "$folder"
        fi
    else
        echo "Clonage du dépôt dans un nouveau dossier..."
        git clone -b "$branch" "$AUTH_URL" "$folder"
    fi
}

# Fonction pour installer WordPress à partir de fichiers Backup zip
install_wordpress_from_backup() {
    local folder=$1
    local backup_type=$2
    local backup_location=$3
    local db_host=$4
    local db_user=$5
    local db_password=$6
    local db_name=$7
    local wp_source_domain=$8
    local wp_new_domain=$9


    echo "Installation de WordPress à partir des fichiers..."
    
    # Créer un dossier temporaire
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1

    # Télécharger l'archive WordPress depuis S3
    echo "Téléchargement de l'archive depuis ${backup_location}..."
    aws s3 cp "$backup_location" final_backup.zip

    # Extraire l'archive finale
    echo "Extraction de l'archive..."
    unzip -q final_backup.zip -d "$TEMP_DIR"

    if [ $? -ne 0 ]; then
        echo "Échec du téléchargement de l'archive WordPress"
        exit 1
    fi

    if [ "$backup_type" = "full" ] || [ "$backup_type" = "files" ] ; then
        # Extraire les fichiers wordpress
        unzip -q "$TEMP_DIR/wordpress_files.zip" -d "$folder"
    fi

    if [ "$backup_type" = "full" ] || [ "$backup_type" = "database" ] ; then

        perform_search_replace "$wp_source_domain" "$wp_new_domain" "$TEMP_DIR/database.sql"

        # Importer la base de données
        echo "Importation de la base de données..."
        mysql -h "$db_host" -u "$db_user" -p"$db_password" "$db_name" < $TEMP_DIR/database.sql
    fi

    rm -rf $TEMP_DIR

    echo "WordPress déployé avec succès à partir du backup ${backup_location}"
}

# Fonction pour installer WordPress à partir de fichiers (ZIP + SQL)
install_wordpress_from_files() {
    local folder=$1
    local zip_location=$2
    local sql_location=$3
    local db_name=$4
    local db_user=$5
    local db_password=$6
    local db_host=$7
    local wp_source_domain=$8
    local wp_new_domain=$9

    echo "Installation de WordPress à partir des fichiers..."
    
    # Créer un dossier temporaire
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1

    # Télécharger l'archive WordPress depuis S3
    echo "Téléchargement de l'archive WordPress depuis ${zip_location}..."
    aws s3 cp "$zip_location" wordpress.zip
    if [ $? -ne 0 ]; then
        echo "Échec du téléchargement de l'archive WordPress"
        exit 1
    fi

    # Extraire l'archive
    echo "Extraction de l'archive..."
    unzip -q wordpress.zip -d "$folder"
    rm wordpress.zip

    # Télécharger le dump SQL depuis S3
    echo "Téléchargement du dump SQL depuis ${sql_location}..."
    aws s3 cp "$sql_location" database.sql
    if [ $? -ne 0 ]; then
        echo "Échec du téléchargement du dump SQL"
        exit 1
    fi

    # Ignorer les instructions CREATE DATABASE/USE dans le dump avec sed
    sed -i '/^CREATE DATABASE/d;/^USE/d' database.sql

    # Remplacer l'ancien domaine par le nouveau domaine
    if [ -n "$wp_source_domain" ] && [ -n "$wp_new_domain" ]; then
        echo "Remplacement de l'ancien domaine par le nouveau dans le dump..."
        sed -i "s/$wp_source_domain/$wp_new_domain/g" database.sql
    fi

    # Importer la base de données
    echo "Importation de la base de données..."
    mysql -h "$db_host" -u "$db_user" -p"$db_password" "$db_name" < database.sql
    rm database.sql

    echo "WordPress déployé avec succès à partir des fichiers dans ${folder}"
}

# Fonction pour copier un site WordPress existant
copy_wordpress_site() {
    local target_folder=$1
    local source_folder=$2
    local target_db_name=$3
    local source_db_name=$4
    local db_host=$5
    local wp_source_domain=$6
    local wp_new_domain=$7

    echo "Copie du site WordPress depuis ${source_folder} vers ${target_folder}..."

    # 1. Copie des fichiers
    echo "Copie des fichiers WordPress..."
    sudo mkdir -p "${target_folder}"
    sudo rsync -a "${source_folder}/" "${target_folder}/" --exclude="wp-config.php"

    # 2. Copie de la base de données
    echo "Copie de la base de données ${source_db_name} vers ${target_db_name}..."
    
    # Création de la nouvelle base
#     mysql -h "${db_host}" -u "${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" <<MYSQL_SCRIPT
# CREATE DATABASE IF NOT EXISTS ${target_db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
# GRANT ALL PRIVILEGES ON ${target_db_name}.* TO '${db_user}'@'%';
# FLUSH PRIVILEGES;
# MYSQL_SCRIPT

    # Export/Import de la base
    TEMP_SQL_FILE=$(mktemp)
    mysqldump -h "${db_host}" -u "${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${source_db_name}" > "${TEMP_SQL_FILE}"

    # Ignorer les instructions CREATE DATABASE/USE dans le dump avec sed
    sed -i '/^CREATE DATABASE/d;/^USE/d' "${TEMP_SQL_FILE}"

    # Remplacer l'ancien domaine par le nouveau domaine
    if [ -n "$wp_source_domain" ] && [ -n "$wp_new_domain" ]; then
        echo "Remplacement de l'ancien domaine par le nouveau dans le dump..."
        sed -i "s/$wp_source_domain/$wp_new_domain/g" "${TEMP_SQL_FILE}"
    fi

    mysql -h "${db_host}" -u "${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" "${target_db_name}" < "${TEMP_SQL_FILE}"
    rm "${TEMP_SQL_FILE}"

#     # 3. Mise à jour des URLs dans la base (si nécessaire)
#     echo "Mise à jour des URLs dans la base de données..."
#     mysql -h "${db_host}" -u "${db_user}" -p"${db_password}" "${target_db_name}" <<MYSQL_SCRIPT
# UPDATE wp_options SET option_value = REPLACE(option_value, '${source_folder}', '${target_folder}') WHERE option_name IN ('siteurl', 'home');
# MYSQL_SCRIPT

    echo "Copie terminée avec succès."
}

# Fonction principale pour le mode push
push_wordpress_site() {
    local config_s3_location=$1
    local source_folder=$2
    local target_folder=$3
    local source_db=$4
    local target_db=$5
    local db_host=$6
    local source_domain=$7
    local target_domain=$8
    
    # Récupération de la configuration
    get_push_config "$config_s3_location"
    
    # Création de la structure de base
    sudo mkdir -p "$target_folder"
    
    # Copie des fichiers
    copy_selected_files "$source_folder" "$target_folder"
    
    # Création de la base de données
#     mysql -h "$db_host" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" <<MYSQL_SCRIPT
# CREATE DATABASE IF NOT EXISTS ${target_db} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
# GRANT ALL PRIVILEGES ON ${target_db}.* TO '${db_user}'@'%';
# FLUSH PRIVILEGES;
# MYSQL_SCRIPT

    # Copie des tables
    copy_selected_tables "$source_db" "$target_db" "$db_host" "$source_domain" "$target_domain"
    
    # Search-replace si nécessaire
    # perform_search_replace "$target_db" "$db_user" "$db_password" "$db_host" "$source_domain" "$target_domain"
    
    # Création du wp-config.php
#     echo "Configuration de wp-config.php..."
#     sudo cat > "${target_folder}/wp-config.php" <<EOL
# <?php
# define( 'DB_NAME', '${target_db}' );
# define( 'DB_USER', '${db_user}' );
# define( 'DB_PASSWORD', '${db_password}' );
# define( 'DB_HOST', '${db_host}' );
# [... reste du contenu inchangé ...]
# EOL
    
    # Définition des permissions
    sudo chown -R www-data:www-data "$target_folder"
    sudo find "$target_folder" -type d -exec chmod 755 {} \;
    sudo find "$target_folder" -type f -exec chmod 644 {} \;
    
    echo "Déploiement en mode push terminé avec succès."
}

# Configurer la base de données
if needs_full_config "$INSTALLATION_METHOD"; then
echo "Configuration de la base de données MySQL..."
    mysql -h "${MYSQL_DB_HOST}" -u "${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS ${WP_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${WP_DB_USER}'@'%' IDENTIFIED BY '${WP_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${WP_DB_NAME}.* TO '${WP_DB_USER}'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
fi

# Installation selon la méthode choisie
case "$INSTALLATION_METHOD" in
    "standard")
        install_wordpress_standard "$WEB_ROOT" "$WP_VERSION"
        ;;
    "git")
        install_wordpress_git "$WEB_ROOT" "$GIT_REPO_URL" "$GIT_BRANCH" "$GIT_USERNAME" "$GIT_TOKEN"
        ;;
    "zip_and_sql")
        if [ -z "$WP_ZIP_LOCATION" ] || [ -z "$WP_DB_DUMP_LOCATION" ]; then
            echo "Les emplacements des fichiers ZIP et SQL sont requis pour la méthode zip_and_sql"
            exit 1
        fi
        install_wordpress_from_files "$WEB_ROOT" "$WP_ZIP_LOCATION" "$WP_DB_DUMP_LOCATION" \
                                   "$WP_DB_NAME" "$WP_DB_USER" "$WP_DB_PASSWORD" "$MYSQL_DB_HOST" \
                                   "$WP_SOURCE_DOMAIN" "$DOMAIN"
        ;;
    "copy")
        copy_wordpress_site "$WEB_ROOT" "$WEB_ROOT_SOURCE" \
                            "$WP_DB_NAME" "$WP_SOURCE_DB_NAME" \
                            "$MYSQL_DB_HOST" "$WP_SOURCE_DOMAIN" "$DOMAIN"             
        ;;
    "push")
        push_wordpress_site "$WP_PUSH_LOCATION" "$WEB_ROOT_SOURCE" "$WEB_ROOT" \
                          "$WP_SOURCE_DB_NAME" "$WP_DB_NAME" \
                          "$MYSQL_DB_HOST" "$WP_SOURCE_DOMAIN" "$DOMAIN"
        ;;
    "maintenance")
        $WP_TOGGLE_MAINTENANCE_SCRIPT "$WP_MAINTENANCE_MODE" "$DOMAIN_FOLDER"
        ;;
    "cache")
        $WP_TOGGLE_LSCACHE_SCRIPT "$WP_LSCACHE" "$DOMAIN_FOLDER"
        ;;
    "backup")
        $WP_BACKUP_SCRIPT "$WP_BACKUP_TYPE" "$WP_BACKUP_S3_LOCATION" "$WEB_ROOT" "$WP_DB_NAME" "$MYSQL_DB_HOST" "$MYSQL_ROOT_USER" "$MYSQL_ROOT_PASSWORD"
        ;;
    "restore")
        install_wordpress_from_backup "$WEB_ROOT" "$WP_BACKUP_TYPE" "$WP_BACKUP_S3_LOCATION" \
                    "$MYSQL_DB_HOST" "$MYSQL_ROOT_USER" "$MYSQL_ROOT_PASSWORD" "$WP_DB_NAME" \
                    "$WP_SOURCE_DOMAIN" "$DOMAIN"
        ;;
    "redirect")
        $WP_REWRITE_RULES_SCRIPT "$DOMAIN_FOLDER"
        ;;
    *)
        echo "Méthode d'installation non reconnue: $INSTALLATION_METHOD"
        echo "Utilisez 'standard', 'git', 'zip_and_sql', 'copy', 'push', 'maintenance', 'cache', 'backup' ou 'restore' "
        exit 1
        ;;
esac




if needs_full_config "$INSTALLATION_METHOD"; then
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


# Variables AWS
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$TOP_DOMAIN" --query "HostedZones[0].Id" --output text | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "Zone hébergée pour le domaine $TOP_DOMAIN introuvable"
    exit 1
fi

# Fonction pour créer l'enregistrement DNS
create_record() {
    # Trouver l'ARN de l'ALB basé sur le tag
    ALB_ARN=$(aws resourcegroupstaggingapi get-resources \
        --tag-filters "Key=$ALB_TAG_NAME,Values=$ALB_TAG_VALUE" \
        --resource-type-filters elasticloadbalancing:loadbalancer \
        --query "ResourceTagMappingList[0].ResourceARN" \
        --output text \
        --region $AWS_REGION)

    if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
        echo "ALB avec le tag $ALB_TAG_NAME=$ALB_TAG_VALUE introuvable"
        exit 1
    fi

    # Récupérer le DNS name de l'ALB
    ALB_DNS_NAME=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --query "LoadBalancers[0].DNSName" \
        --output text \
        --region $AWS_REGION)

    if [ -z "$ALB_DNS_NAME" ]; then
        echo "Impossible de récupérer le DNS name pour l'ALB $ALB_ARN"
        exit 1
    fi

    # Créer le fichier JSON pour la modification DNS
    TMP_FILE=$(mktemp)
    cat > "$TMP_FILE" <<EOF
{
    "Comment": "Création de l'enregistrement $RECORD_NAME.$TOP_DOMAIN",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$RECORD_NAME.$TOP_DOMAIN",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "$ALB_DNS_NAME"
                    }
                ]
            }
        }
    ]
}
EOF

    # Appliquer les changements DNS
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "file://$TMP_FILE"

    # Nettoyer le fichier temporaire
    rm -f "$TMP_FILE"

    echo "Enregistrement DNS $RECORD_NAME.$TOP_DOMAIN créé/modifié pour pointer vers $ALB_DNS_NAME"
}


create_record
fi


# Créer un utilisateur SFTP
if needs_full_config "$INSTALLATION_METHOD"; then

    if [ -f "$WP_SFTP_ADD_USER_SCRIPT" ]; then
        $WP_SFTP_ADD_USER_SCRIPT "$DOMAIN_FOLDER" "$WP_SFTP_USER" "$WP_SFTP_PWD"
    else
        echo "Le script d'ajout d'utilisateur SFTP $WP_SFTP_ADD_USER_SCRIPT n'est pas présent."
    fi
fi

echo "=== Déploiement terminé avec succès ==="
echo "URL: http://${DOMAIN}"
echo "Methode: ${INSTALLATION_METHOD}"
echo "Répertoire WordPress: ${WEB_ROOT}"
echo "Base de données: ${WP_DB_NAME}"
echo "======================================"

