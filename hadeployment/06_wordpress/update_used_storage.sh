#!/bin/bash

# Paramètres d'entrée
KAIAC_DB_HOST="$1"
KAIAC_DB_NAME="$2"
KAIAC_DB_USER="$3"
KAIAC_DB_PASSWORD="$4"
MYSQL_DB_HOST="$5"
MYSQL_ROOT_USER="$6"
MYSQL_ROOT_PASSWORD="$7"

# Fonction pour calculer la taille d'un dossier en Mo
calculate_folder_size() {
    local folder_path="/var/www/$1"
    if [ -d "$folder_path" ]; then
        du -sm "$folder_path" | awk '{print $1}'
    else
        echo "0"
    fi
}

# Fonction pour calculer la taille d'une base de données en Mo
calculate_db_size() {
    local db_name="$1"
    local size=$(mysql -h "$MYSQL_DB_HOST" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -sN -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 0) FROM information_schema.TABLES WHERE table_schema = '$db_name' GROUP BY table_schema")
    echo "${size:-0}"
}

# Connexion à la base KAIAC pour récupérer les sites actifs
websites=$(mysql -h "$KAIAC_DB_HOST" -u "$KAIAC_DB_USER" -p"$KAIAC_DB_PASSWORD" "$KAIAC_DB_NAME" -sN -e "SELECT domain_folder, wp_db_name FROM websites WHERE is_active = 1")

# Traitement de chaque site
while IFS=$'\t' read -r domain_folder wp_db_name; do
    echo "Traitement du site: $domain_folder (DB: $wp_db_name)"
    
    # Calcul des tailles
    folder_size=$(calculate_folder_size "$domain_folder")
    db_size=$(calculate_db_size "$wp_db_name")
    total_size=$((folder_size + db_size))
    
    echo " - Taille dossier: ${folder_size}Mo"
    echo " - Taille DB: ${db_size}Mo"
    echo " - Total: ${total_size}Mo"
    
    # Mise à jour dans la base KAIAC
    mysql -h "$KAIAC_DB_HOST" -u "$KAIAC_DB_USER" -p"$KAIAC_DB_PASSWORD" "$KAIAC_DB_NAME" -e \
    "UPDATE websites SET used_storage_mb = $total_size WHERE domain_folder = '$domain_folder'"
    
    echo "Mise à jour effectuée pour $domain_folder"
    echo "----------------------------------------"
done <<< "$websites"

echo "Traitement terminé pour tous les sites actifs"