#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 7 ]; then
    echo "Usage: $0 [backup_type] [s3_location] [wp_folder] [db_name] [db_host] [db_root_user] [db_root_user_pwd]"
    echo "Exemple: $0 full s3://kaiac.agoralabs.org/wordpress-backups/site1_skyscaledev_com-prod-1746408568120.zip site1_skyscaledev_com site1_skyscaledev_com_db dbols.skyscaledev.com root =Dorine11"
    exit 1
fi

WP_BACKUP_TYPE="$1"
WP_BACKUP_S3_LOCATION="$2"
WEB_ROOT="$3"
WP_DB_NAME="$4"
MYSQL_DB_HOST="$5"
MYSQL_ROOT_USER="$6"
MYSQL_ROOT_PASSWORD="$7"

create_backup() {
    local backup_type=$1
    local backup_s3_location=$2
    local wp_folder=$3
    local db_name=$4
    local db_host=$5
    local db_root_user=$6
    local db_root_user_pwd=$7
    
    echo "Création du backup..."
    
    # Créer un répertoire temporaire pour tout le travail
    local TEMP_DIR=$(mktemp -d)
    
    if [ "$backup_type" = "full" ]; then
        echo "Création d'un backup complet contenant les fichiers wordpress et la base de données..."
        
        # Sauvegarde des fichiers WordPress
        local WP_ZIP="$TEMP_DIR/wordpress_files.zip"
        cd "$wp_folder/.." && zip -r "$WP_ZIP" "$(basename "$wp_folder")" -x "*.git/*"
        
        # Sauvegarde de la base de données
        local SQL_FILE="$TEMP_DIR/database.sql"
        mysqldump -h "$db_host" -u "$db_root_user" -p"$db_root_user_pwd" "$db_name" > "$SQL_FILE"
        
        # Création de l'archive finale
        local FINAL_ZIP="$TEMP_DIR/final_backup.zip"
        cd "$TEMP_DIR" && zip "$FINAL_ZIP" "wordpress_files.zip" "database.sql"
        
        # Upload vers S3
        aws s3 cp "$FINAL_ZIP" "$backup_s3_location"
        
    elif [ "$backup_type" = "database" ]; then
        echo "Création d'un backup de la base de données..."
        
        local SQL_FILE="$TEMP_DIR/database.sql"
        local FINAL_ZIP="$TEMP_DIR/final_backup.zip"
        
        mysqldump -h "$db_host" -u "$db_root_user" -p"$db_root_user_pwd" "$db_name" > "$SQL_FILE"
        zip -j "$FINAL_ZIP" "$SQL_FILE"
        aws s3 cp "$FINAL_ZIP" "$backup_s3_location"
        
    elif [ "$backup_type" = "files" ]; then
        echo "Création d'un backup des fichiers..."
        
        local FINAL_ZIP="$TEMP_DIR/final_backup.zip"
        cd "$wp_folder/.." && zip -r "$FINAL_ZIP" "$(basename "$wp_folder")" -x "*.git/*"
        aws s3 cp "$FINAL_ZIP" "$backup_s3_location"
        
    else
        echo "Type de backup inconnu: $backup_type"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Nettoyage
    rm -rf "$TEMP_DIR"
    echo "Backup créé avec succès."
}

create_backup "$WP_BACKUP_TYPE" "$WP_BACKUP_S3_LOCATION" "$WEB_ROOT" "$WP_DB_NAME" "$MYSQL_DB_HOST" "$MYSQL_ROOT_USER" "$MYSQL_ROOT_PASSWORD"