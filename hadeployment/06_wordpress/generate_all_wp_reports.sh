#!/bin/bash

# Vérification des paramètres requis
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
    echo "Usage: $0 [MYSQL_DB_HOST] [MYSQL_DB_NAME] [MYSQL_ROOT_USER] [MYSQL_ROOT_PASSWORD]"
    echo "{\"error\":\"Paramètres manquants\"}" > websites_report.json
    exit 1
fi

MYSQL_DB_HOST="$1"
MYSQL_DB_NAME="$2"  # Nouveau paramètre pour le nom de la base de données
MYSQL_ROOT_USER="$3"
MYSQL_ROOT_PASSWORD="$4"
WEB_ROOT="/var/www"

# Fonction pour échapper les caractères spéciaux dans les chaînes JSON
escape_json() {
    local string="$1"
    string=${string//\\/\\\\}
    string=${string//\"/\\\"}
    string=${string//$'\n'/\\n}
    string=${string//$'\r'/\\r}
    string=${string//$'\t'/\\t}
    echo "$string"
}

# Fonction pour exécuter une requête MySQL
mysql_query() {
    local query="$1"
    local default="$2"
    
    local result=$(mysql -h "$MYSQL_DB_HOST" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -sse "$query" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        echo "$default"
    else
        echo "$result"
    fi
}

# Récupération de la liste des sites actifs
get_active_websites() {
    local query="SELECT domain, folder_name FROM websites WHERE is_active = 1;"
    local result=$(mysql -h "$MYSQL_DB_HOST" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DB_NAME" -sse "$query" 2>/dev/null)
    
    if [ -z "$result" ]; then
        echo "[]"
    else
        # Convertir le résultat en tableau JSON
        echo "$result" | while read -r line; do
            domain=$(echo "$line" | awk '{print $1}')
            folder=$(echo "$line" | awk '{print $2}')
            echo "{\"domain\":\"$(escape_json "$domain")\",\"folder\":\"$(escape_json "$folder")\"}"
        done | jq -s .
    fi
}

# Fonction pour obtenir une option WordPress depuis la base de données
get_wp_option_from_db() {
    local site_root="$1"
    local option_name="$2"
    local default_value="$3"
    local db_name="$4"
    local db_user="$5"
    local db_password="$6"
    
    # Récupération du préfixe de table
    local table_prefix=$(wp --allow-root --path="$site_root" config get table_prefix 2>/dev/null)
    if [ -z "$table_prefix" ]; then
        table_prefix="wp_"
    fi
    
    local query="SELECT option_value FROM ${table_prefix}options WHERE option_name = '$option_name' LIMIT 1;"
    local result=$(mysql -h "$MYSQL_DB_HOST" -u "$db_user" -p"$db_password" "$db_name" -sse "$query" 2>/dev/null)
    
    if [ -z "$result" ]; then
        echo "$default_value"
    else
        echo "$result"
    fi
}

# Fonction pour formater une valeur en JSON
format_json_value() {
    local value="$1"
    local default="$2"
    
    if [ -z "$value" ]; then
        echo "$default"
        return
    fi

    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    elif [[ "$value" =~ ^(true|false)$ ]]; then
        echo "$value"
    else
        escaped_value=$(escape_json "$value")
        echo "\"$escaped_value\""
    fi
}

# Fonction pour exécuter les commandes WP-CLI avec gestion des erreurs
wp_cmd() {
    local site_root="$1"
    local cmd="$2"
    local default="$3"
    local db_name="$4"
    local db_user="$5"
    local db_password="$6"
    local result
    
    # Exécution silencieuse de la commande
    result=$(wp --allow-root --path="$site_root" $cmd --quiet 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        # Si WP-CLI échoue, essayer de récupérer depuis la base de données pour certaines commandes
        if [[ "$cmd" == "option get siteurl" ]]; then
            get_wp_option_from_db "$site_root" "siteurl" "$default" "$db_name" "$db_user" "$db_password"
        elif [[ "$cmd" == "option get home" ]]; then
            get_wp_option_from_db "$site_root" "home" "$default" "$db_name" "$db_user" "$db_password"
        elif [[ "$cmd" == "option get admin_email" ]]; then
            get_wp_option_from_db "$site_root" "admin_email" "$default" "$db_name" "$db_user" "$db_password"
        elif [[ "$cmd" == "option get blogname" ]]; then
            get_wp_option_from_db "$site_root" "blogname" "$default" "$db_name" "$db_user" "$db_password"
        elif [[ "$cmd" == "option get blogdescription" ]]; then
            get_wp_option_from_db "$site_root" "blogdescription" "$default" "$db_name" "$db_user" "$db_password"
        else
            echo "$default"
        fi
    else
        echo "$result"
    fi
}

# Fonction spéciale pour les options qui nécessitent un formatage JSON
get_wp_option_json() {
    local site_root="$1"
    local option_name="$2"
    local default_value="$3"
    local db_name="$4"
    local db_user="$5"
    local db_password="$6"
    
    # Essaye d'abord avec --format=json, sinon avec format brut
    local result=$(wp --allow-root --path="$site_root" option get "$option_name" --format=json 2>/dev/null || \
                   wp --allow-root --path="$site_root" option get "$option_name" 2>/dev/null)
    
    if [ -z "$result" ]; then
        # Si WP-CLI échoue, essayer de récupérer depuis la base de données
        result=$(get_wp_option_from_db "$site_root" "$option_name" "$default_value" "$db_name" "$db_user" "$db_password")
    fi
    
    format_json_value "$result" "$default_value"
}

# Fonction pour obtenir les constantes de configuration
get_wp_config() {
    local site_root="$1"
    local constant_name="$2"
    local default_value="$3"
    
    local result=$(wp --allow-root --path="$site_root" config get "$constant_name" 2>/dev/null)
    
    format_json_value "$result" "$default_value"
}

# Fonction pour obtenir la liste des thèmes ou plugins au format JSON valide
get_wp_list_json() {
    local site_root="$1"
    local type="$2" # 'theme' ou 'plugin'
    local status="$3" # 'active', 'must-use', etc.
    
    local result=$(wp --allow-root --path="$site_root" $type list --status=$status --fields=name,title,version,status --format=json 2>/dev/null)
    
    if [ -z "$result" ]; then
        echo "[]"
    else
        if jq -e . >/dev/null 2>&1 <<<"$result"; then
            echo "$result"
        else
            echo "[]"
        fi
    fi
}

# Générer un rapport complet pour un site
generate_full_report() {
    local domain="$1"
    local folder="$2"
    local site_root="$WEB_ROOT/$folder"
    local report_file="$site_root/wp-config-report.json"
    
    # Vérifier si le répertoire existe
    if [ ! -d "$site_root" ]; then
        echo "{\"error\":\"Répertoire du site non trouvé\"}" > "$report_file"
        return 1
    fi
    
    # Vérifier si wp-config.php existe
    if [ ! -f "$site_root/wp-config.php" ]; then
        echo "{\"error\":\"Fichier wp-config.php non trouvé\"}" > "$report_file"
        return 1
    fi
    
    # Vérifier si WP-CLI est disponible
    if ! command -v wp &> /dev/null; then
        echo "{\"error\":\"WP-CLI n'est pas installé\"}" > "$report_file"
        return 1
    fi
    
    # Extraire les credentials depuis wp-config.php
    extract_wp_config_value() {
        local config_file="$site_root/wp-config.php"
        local constant_name="$1"
        grep -E "define\(.*'$constant_name'" "$config_file" | sed -E "s/.*'$constant_name'\\s*,\\s*'(.*)'.*/\1/" | tail -1
    }
    
    DB_NAME=$(extract_wp_config_value "DB_NAME")
    DB_USER=$(extract_wp_config_value "DB_USER")
    DB_PASSWORD=$(extract_wp_config_value "DB_PASSWORD")
    
    # Générer le rapport complet
    {
        echo "{"
        echo "\"domain\": \"$(escape_json "$domain")\","
        echo "\"folder\": \"$(escape_json "$folder")\","
        echo "\"report_date\": \"$(date -Iseconds)\","
        echo "\"web_root\": \"$(escape_json "$site_root")\","
        
        # 1. Informations de base
        echo "\"basic_info\": {"
        echo "\"site_url\": $(get_wp_option_json "$site_root" 'siteurl' '\"\"' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"home_url\": $(get_wp_option_json "$site_root" 'home' '\"\"' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"wp_version\": \"$(wp --allow-root --path="$site_root" core version --quiet 2>/dev/null || echo '')\","
        echo "\"language\": $(wp_cmd "$site_root" 'core language list --status=active --fields=code,name --format=json' '[]' "$DB_NAME" "$DB_USER" "$DB_PASSWORD")"
        echo "},"
        
        # 2. Configuration générale
        echo "\"general_config\": {"
        echo "\"blogname\": $(get_wp_option_json "$site_root" 'blogname' '\"\"' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"blogdescription\": $(get_wp_option_json "$site_root" 'blogdescription' '\"\"' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"admin_email\": $(get_wp_option_json "$site_root" 'admin_email' '\"\"' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"timezone_string\": $(get_wp_option_json "$site_root" 'timezone_string' '\"\"' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"date_format\": $(get_wp_option_json "$site_root" 'date_format' '\"\"' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"time_format\": $(get_wp_option_json "$site_root" 'time_format' '\"\"' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"start_of_week\": $(get_wp_option_json "$site_root" 'start_of_week' '0' "$DB_NAME" "$DB_USER" "$DB_PASSWORD")"
        echo "},"
        
        # 3. Paramètres de lecture
        echo "\"reading_settings\": {"
        echo "\"show_on_front\": $(get_wp_option_json "$site_root" 'show_on_front' '\"\"' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"page_on_front\": $(get_wp_option_json "$site_root" 'page_on_front' '0' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"page_for_posts\": $(get_wp_option_json "$site_root" 'page_for_posts' '0' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"posts_per_page\": $(get_wp_option_json "$site_root" 'posts_per_page' '10' "$DB_NAME" "$DB_USER" "$DB_PASSWORD")"
        echo "},"
        
        # 4. Paramètres de discussion
        echo "\"discussion_settings\": {"
        echo "\"default_comment_status\": $(get_wp_option_json "$site_root" 'default_comment_status' '\"\"' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"comment_registration\": $(get_wp_option_json "$site_root" 'comment_registration' '0' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"require_name_email\": $(get_wp_option_json "$site_root" 'require_name_email' '0' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"close_comments_for_old_posts\": $(get_wp_option_json "$site_root" 'close_comments_for_old_posts' '0' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"close_comments_days_old\": $(get_wp_option_json "$site_root" 'close_comments_days_old' '14' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"thread_comments\": $(get_wp_option_json "$site_root" 'thread_comments' '0' "$DB_NAME" "$DB_USER" "$DB_PASSWORD"),"
        echo "\"thread_comments_depth\": $(get_wp_option_json "$site_root" 'thread_comments_depth' '5' "$DB_NAME" "$DB_USER" "$DB_PASSWORD")"
        echo "},"
        
        # 5. Thème et extensions
        echo "\"theme\": $(get_wp_list_json "$site_root" 'theme' 'active'),"
        echo "\"plugins\": {"
        echo "\"active\": $(get_wp_list_json "$site_root" 'plugin' 'active'),"
        echo "\"must_use\": $(get_wp_list_json "$site_root" 'plugin' 'must-use')"
        echo "},"
        
        # 6. Configuration avancée
        echo "\"advanced_config\": {"
        echo "\"db_name\": $(get_wp_config "$site_root" 'DB_NAME' '\"\"'),"
        echo "\"db_user\": $(get_wp_config "$site_root" 'DB_USER' '\"\"'),"
        echo "\"db_host\": $(get_wp_config "$site_root" 'DB_HOST' '\"\"'),"
        echo "\"table_prefix\": $(get_wp_config "$site_root" 'table_prefix' '\"\"'),"
        echo "\"wp_debug\": $(get_wp_config "$site_root" 'WP_DEBUG' 'false'),"
        echo "\"wp_debug_log\": $(get_wp_config "$site_root" 'WP_DEBUG_LOG' 'false'),"
        echo "\"wp_debug_display\": $(get_wp_config "$site_root" 'WP_DEBUG_DISPLAY' 'true'),"
        echo "\"script_debug\": $(get_wp_config "$site_root" 'SCRIPT_DEBUG' 'false'),"
        echo "\"wp_cache\": $(get_wp_config "$site_root" 'WP_CACHE' 'false')"
        echo "}"
        echo "}"
    } > "$report_file"
    
    # Vérifier si le rapport a été généré avec succès
    if [ -s "$report_file" ]; then
        echo "Rapport complet généré pour $domain dans $report_file"
        return 0
    else
        echo "{\"error\":\"Échec de la génération du rapport\"}" > "$report_file"
        return 1
    fi
}

# Main execution
echo "Début de la génération des rapports..."

# Récupérer la liste des sites actifs
ACTIVE_WEBSITES=$(get_active_websites)

# Traiter chaque site actif
echo "$ACTIVE_WEBSITES" | jq -c '.[]' | while read -r site; do
    domain=$(echo "$site" | jq -r '.domain')
    folder=$(echo "$site" | jq -r '.folder')
    
    echo "Traitement du site: $domain (dossier: $folder)"
    generate_full_report "$domain" "$folder"
done

echo "Génération des rapports terminée."