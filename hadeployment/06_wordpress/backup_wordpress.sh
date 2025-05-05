#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 7 ]; then
    echo "Usage: $0 [backup_type] [s3_location] [wp_folder] [db_name] [db_host] [db_root_user] [db_root_user_pwd]"
    echo "Exemple: $0 full s3://kaiac.agoralabs.org/wordpress-backups/site1_skyscaledev_com-prod-1746408568120.zip site1_skyscaledev_com site1_skyscaledev_com_db dbols.skyscaledev.com root =Dorine11"
    exit 1
fi

WP_BACKUP_TYPE="$1" # provient du message SQS
WP_BACKUP_S3_LOCATION="$2" # provient du message SQS
DOMAIN_FOLDER="$3" # provient du message SQS
WP_DB_NAME="$4" # provient du message SQS
MYSQL_DB_HOST="$5" # provient des variables d'environnement
MYSQL_ROOT_USER="$6" # provient des variables d'environnement
MYSQL_ROOT_PASSWORD="$7" # provient des variables d'environnement
WEB_ROOT="/var/www/$DOMAIN_FOLDER"


create_backup() {
    local backup_type=$1 # 'full', 'database', 'files'
    local backup_s3_location=$2
    local wp_folder=$3
    local db_name=$4
    local db_host=$5
    local db_root_user=$6
    local db_root_user_pwd=$7
    
    
    echo "Création du backup..."

    # Création du zip
    # Sauvegarde dans S3
    if [ "$backup_type" = "full" ]; then
        echo "Création d'un backup complet contenant les fichiers wordpress et la base de données..."
        # Zip wordpress
        TEMP_BACKUP_FILE=$(mktemp)
        zip -r "$TEMP_BACKUP_FILE" "$wp_folder"
        TEMP_SQL_FILE=$(mktemp)
        mysqldump -h "$db_host" -u "$db_root_user" -p"$db_root_user_pwd" "$db_name" > "$TEMP_SQL_FILE"
        # Zip contenant $TEMP_BACKUP_FILE et $TEMP_SQL_FILE
        # Create a temporary directory for combining files
        TEMP_COMBINED_DIR=$(mktemp -d)

        # Copy files to combined directory
        cp "$TEMP_BACKUP_FILE" "$TEMP_COMBINED_DIR/wordpress_files.zip"
        cp "$TEMP_SQL_FILE" "$TEMP_COMBINED_DIR/database.sql"

        # Create final zip containing both files
        TEMP_FINAL_ZIP=$(mktemp)
        cd "$TEMP_COMBINED_DIR"
        zip -r "$TEMP_FINAL_ZIP" ./*
        
        # Clean up temporary files and directory
        aws s3 cp "$TEMP_FINAL_ZIP" "$backup_s3_location"

        rm -rf "$TEMP_BACKUP_FILE"
        rm -rf "$TEMP_SQL_FILE"
        rm -rf "$TEMP_COMBINED_DIR"
        rm -rf "$TEMP_FINAL_ZIP"

    elif [ "$backup_type" = "database" ]; then
        echo "Création d'un backup de la base de données..."
        TEMP_SQL_FILE=$(mktemp)
        mysqldump -h "$db_host" -u "$db_root_user" -p"$db_root_user_pwd" "$db_name" > "$TEMP_SQL_FILE"
        TEMP_FINAL_ZIP=$(mktemp)
        zip -j "$TEMP_FINAL_ZIP" "$TEMP_SQL_FILE"        
        aws s3 cp "$TEMP_FINAL_ZIP" "$backup_s3_location"

        rm -rf "$TEMP_SQL_FILE"
        rm -rf "$TEMP_FINAL_ZIP"
    elif [ "$backup_type" = "files" ]; then
        echo "Création d'un backup des fichiers..."
        TEMP_BACKUP_FILE=$(mktemp)
        zip -r "$TEMP_BACKUP_FILE" "$wp_folder"

        aws s3 cp "$TEMP_BACKUP_FILE" "$backup_s3_location"

        rm -rf "$TEMP_BACKUP_FILE"
    else
        echo "Type de backup inconnu: $backup_type"
        exit 1
    fi


    echo "Backup créé avec succès."
}

create_backup "$WP_BACKUP_TYPE" "$WP_BACKUP_S3_LOCATION" "$WEB_ROOT" "$WP_DB_NAME" "$MYSQL_DB_HOST" "$MYSQL_ROOT_USER" "$MYSQL_ROOT_PASSWORD"