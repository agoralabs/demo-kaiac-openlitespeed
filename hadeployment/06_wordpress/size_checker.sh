#!/bin/bash

# Vérification des paramètres
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 WEB_ROOT MYSQL_DB_HOST WP_DB_NAME WP_DB_USER WP_DB_PASSWORD"
    exit 1
fi

WEB_ROOT=$1
MYSQL_DB_HOST=$2
WP_DB_NAME=$3
WP_DB_USER=$4
WP_DB_PASSWORD=$5

# Vérification que les outils nécessaires sont installés
command -v jq >/dev/null 2>&1 || { echo >&2 "jq est requis mais non installé. Installation: sudo apt-get install jq"; exit 1; }

# Fichier json à générer
JSON_FILE="$WEB_ROOT/site-size-data.json"

# Calcul de la taille du répertoire WEB_ROOT en octets
WEB_SIZE=$(du -sb "$WEB_ROOT" | cut -f1)

# Requête MySQL pour obtenir la taille du schéma en octets
DB_SIZE=$(mysql -h "$MYSQL_DB_HOST" -u "$WP_DB_USER" -p"$WP_DB_PASSWORD" --silent --skip-column-names \
    -e "SELECT SUM(data_length + index_length) FROM information_schema.tables WHERE table_schema = '$WP_DB_NAME' GROUP BY table_schema;")

# Création du JSON
JSON_CONTENT=$(jq -n \
    --arg web_root "$WEB_ROOT" \
    --arg web_size "$WEB_SIZE" \
    --arg db_name "$WP_DB_NAME" \
    --arg db_size "$DB_SIZE" \
    '{web_root: $web_root, web_size_bytes: $web_size, db_name: $db_name, db_size_bytes: $db_size}')

echo "$JSON_CONTENT" > "$JSON_FILE"

echo "Rapport généré avec succès dans $JSON_FILE"