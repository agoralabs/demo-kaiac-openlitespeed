#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 19 ]; then
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

# Variables dérivées
EMAIL_ADMIN="admin@${DOMAIN}"
WEB_ROOT="/var/www/${DOMAIN_FOLDER}"
VHOST_CONF="/usr/local/lsws/conf/vhosts/${DOMAIN_FOLDER}/vhconf.conf"
HTTPD_CONF="/usr/local/lsws/conf/httpd_config.conf"


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

# Installation selon la méthode choisie
case "$INSTALLATION_METHOD" in
    "standard")
        install_wordpress_standard "$WEB_ROOT" "$WP_VERSION"
        ;;
    "git")
        install_wordpress_git "$WEB_ROOT" "$GIT_REPO_URL" "$GIT_BRANCH" "$GIT_USERNAME" "$GIT_TOKEN"
        ;;
    *)
        echo "Méthode d'installation non reconnue: $INSTALLATION_METHOD"
        echo "Utilisez 'standard' ou 'git'"
        exit 1
        ;;
esac

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

    echo "Enregistrement DNS $RECORD_NAME.$DOMAIN créé/modifié pour pointer vers $ALB_DNS_NAME"
}


create_record


echo "=== Déploiement terminé avec succès ==="
echo "URL: http://${DOMAIN}"
echo "Methode: ${INSTALLATION_METHOD}"
echo "Répertoire WordPress: ${WEB_ROOT}"
echo "Base de données: ${WP_DB_NAME}"
echo "======================================"