#!/bin/bash

# Vérification du paramètre WEB_ROOT
if [ -z "$5" ]; then
    echo "Usage: $0 /chemin/absolu/vers/wordpress [DB_HOST] [DB_NAME] [DB_USER] [DB_PASSWORD]"
    echo "{\"error\":\"Le paramètre WEB_ROOT est manquant\"}" > wp-config-report.json
    exit 1
fi

WEB_ROOT="${1%/}"
REPORT_FILE="$WEB_ROOT/wp-config-report.json"
MYSQL_DB_HOST="$2"
WP_DB_NAME="$3"
WP_DB_USER="$4"
WP_DB_PASSWORD="$5"

# Vérification de WP-CLI
if ! command -v wp &> /dev/null; then
    echo "{\"error\":\"WP-CLI n'est pas installé\"}" > "$REPORT_FILE"
    exit 1
fi

# Fonction pour exécuter une requête MySQL
mysql_query() {
    local query="$1"
    local default="$2"
    
    if [ -z "$MYSQL_DB_HOST" ] || [ -z "$WP_DB_NAME" ] || [ -z "$WP_DB_USER" ] || [ -z "$WP_DB_PASSWORD" ]; then
        echo "$default"
        return
    fi
    
    local result=$(mysql -h "$MYSQL_DB_HOST" -u "$WP_DB_USER" -p"$WP_DB_PASSWORD" "$WP_DB_NAME" -sse "$query" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        echo "$default"
    else
        # Nettoyage des sauts de ligne et guillemets
        echo "$result" | tr -d '\n\r"' | sed "s/'/\"/g"
    fi
}

# Fonction pour obtenir une option WordPress depuis la base de données
get_wp_option_from_db() {
    local option_name="$1"
    local default_value="$2"
    
    # Récupération du préfixe de table
    local table_prefix=$(wp --allow-root --path="$WEB_ROOT" config get table_prefix 2>/dev/null)
    if [ -z "$table_prefix" ]; then
        table_prefix="wp_"
    fi
    
    local query="SELECT option_value FROM ${table_prefix}options WHERE option_name = '$option_name' LIMIT 1;"
    local result=$(mysql_query "$query" "")
    
    if [ -z "$result" ]; then
        echo "$default_value"
    else
        # Convertit en JSON valide
        if [[ "$result" =~ ^[0-9]+$ ]]; then
            echo "$result"
        elif [[ "$result" =~ ^(true|false)$ ]]; then
            echo "$result"
        else
            echo "\"$result\""
        fi
    fi
}

# Fonction pour exécuter les commandes WP-CLI avec gestion des erreurs
wp_cmd() {
    local cmd="$1"
    local default="$2"
    local result
    
    # Exécution silencieuse de la commande
    result=$(wp --allow-root --path="$WEB_ROOT" $cmd --quiet 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        # Si WP-CLI échoue, essayer de récupérer depuis la base de données pour certaines commandes
        if [[ "$cmd" == "option get siteurl" ]]; then
            get_wp_option_from_db "siteurl" "$default"
        elif [[ "$cmd" == "option get home" ]]; then
            get_wp_option_from_db "home" "$default"
        elif [[ "$cmd" == "option get admin_email" ]]; then
            get_wp_option_from_db "admin_email" "$default"
        elif [[ "$cmd" == "option get blogname" ]]; then
            get_wp_option_from_db "blogname" "$default"
        elif [[ "$cmd" == "option get blogdescription" ]]; then
            get_wp_option_from_db "blogdescription" "$default"
        else
            echo "$default"
        fi
    else
        # Nettoyage des sauts de ligne et guillemets
        echo "$result" | tr -d '\n\r"' | sed "s/'/\"/g"
    fi
}

# Fonction spéciale pour les options qui nécessitent un formatage JSON
get_wp_option_json() {
    local option_name="$1"
    local default_value="$2"
    
    # Essaye d'abord avec --format=json, sinon avec format brut
    local result=$(wp --allow-root --path="$WEB_ROOT" option get "$option_name" --format=json 2>/dev/null || \
                   wp --allow-root --path="$WEB_ROOT" option get "$option_name" 2>/dev/null)
    
    if [ -z "$result" ]; then
        # Si WP-CLI échoue, essayer de récupérer depuis la base de données
        get_wp_option_from_db "$option_name" "$default_value"
    else
        # Convertit en JSON valide
        if [[ "$result" =~ ^[0-9]+$ ]]; then
            echo "$result"
        elif [[ "$result" =~ ^(true|false)$ ]]; then
            echo "$result"
        else
            echo "\"$result\""
        fi
    fi
}

# Fonction pour obtenir les constantes de configuration
get_wp_config() {
    local constant_name="$1"
    local default_value="$2"
    
    local result=$(wp --allow-root --path="$WEB_ROOT" config get "$constant_name" 2>/dev/null)
    
    if [ -z "$result" ]; then
        echo "$default_value"
    else
        # Convertit en JSON valide
        if [[ "$result" =~ ^[0-9]+$ ]]; then
            echo "$result"
        elif [[ "$result" =~ ^(true|false)$ ]]; then
            echo "$result"
        else
            echo "\"$result\""
        fi
    fi
}

# Génération du rapport JSON
{
    echo "{"
    echo "\"report_date\": \"$(date -Iseconds)\","
    echo "\"web_root\": \"$WEB_ROOT\","
    
    # 1. Informations de base
    echo "\"basic_info\": {"
    echo "\"site_url\": $(get_wp_option_json 'siteurl' '""'),"
    echo "\"home_url\": $(get_wp_option_json 'home' '""'),"
    echo "\"wp_version\": \"$(wp --allow-root --path="$WEB_ROOT" core version --quiet 2>/dev/null || echo '')\","
    echo "\"language\": $(wp_cmd 'core language list --status=active --fields=code,name --format=json' '[]')"
    echo "},"
    
    # 2. Configuration générale
    echo "\"general_config\": {"
    echo "\"blogname\": $(get_wp_option_json 'blogname' '""'),"
    echo "\"blogdescription\": $(get_wp_option_json 'blogdescription' '""'),"
    echo "\"admin_email\": $(get_wp_option_json 'admin_email' '""'),"
    echo "\"timezone_string\": $(get_wp_option_json 'timezone_string' '""'),"
    echo "\"date_format\": $(get_wp_option_json 'date_format' '""'),"
    echo "\"time_format\": $(get_wp_option_json 'time_format' '""'),"
    echo "\"start_of_week\": $(get_wp_option_json 'start_of_week' '0')"
    echo "},"
    
    # 3. Paramètres de lecture
    echo "\"reading_settings\": {"
    echo "\"show_on_front\": $(get_wp_option_json 'show_on_front' '""'),"
    echo "\"page_on_front\": $(get_wp_option_json 'page_on_front' '0'),"
    echo "\"page_for_posts\": $(get_wp_option_json 'page_for_posts' '0'),"
    echo "\"posts_per_page\": $(get_wp_option_json 'posts_per_page' '10')"
    echo "},"
    
    # 4. Paramètres de discussion
    echo "\"discussion_settings\": {"
    echo "\"default_comment_status\": $(get_wp_option_json 'default_comment_status' '""'),"
    echo "\"comment_registration\": $(get_wp_option_json 'comment_registration' '0'),"
    echo "\"require_name_email\": $(get_wp_option_json 'require_name_email' '0'),"
    echo "\"close_comments_for_old_posts\": $(get_wp_option_json 'close_comments_for_old_posts' '0'),"
    echo "\"close_comments_days_old\": $(get_wp_option_json 'close_comments_days_old' '14'),"
    echo "\"thread_comments\": $(get_wp_option_json 'thread_comments' '0'),"
    echo "\"thread_comments_depth\": $(get_wp_option_json 'thread_comments_depth' '5')"
    echo "},"
    
    # 5. Thème et extensions
    echo "\"theme\": $(wp_cmd 'theme list --status=active --fields=name,title,version,status --format=json' '[]'),"
    echo "\"plugins\": {"
    echo "\"active\": $(wp_cmd 'plugin list --status=active --fields=name,title,version,status --format=json' '[]'),"
    echo "\"must_use\": $(wp_cmd 'plugin list --status=must-use --fields=name,title,version,status --format=json' '[]')"
    echo "},"
    
    # 6. Configuration avancée
    echo "\"advanced_config\": {"
    echo "\"db_name\": $(get_wp_config 'DB_NAME' '""'),"
    echo "\"db_user\": $(get_wp_config 'DB_USER' '""'),"
    echo "\"db_host\": $(get_wp_config 'DB_HOST' '""'),"
    echo "\"table_prefix\": $(get_wp_config 'table_prefix' '""'),"
    echo "\"wp_debug\": $(get_wp_config 'WP_DEBUG' 'false'),"
    echo "\"wp_debug_log\": $(get_wp_config 'WP_DEBUG_LOG' 'false'),"
    echo "\"wp_debug_display\": $(get_wp_config 'WP_DEBUG_DISPLAY' 'true'),"
    echo "\"script_debug\": $(get_wp_config 'SCRIPT_DEBUG' 'false'),"
    echo "\"wp_cache\": $(get_wp_config 'WP_CACHE' 'false')"
    echo "}"
    echo "}"
} > "$REPORT_FILE"

# Vérification et minification du JSON
if jq -e . >/dev/null 2>&1 < "$REPORT_FILE"; then
    # Minifier le JSON
    jq -c . < "$REPORT_FILE" > "${REPORT_FILE}.tmp" && mv "${REPORT_FILE}.tmp" "$REPORT_FILE"
    echo "Rapport généré avec succès dans $REPORT_FILE"
    exit 0
else
    echo "{\"error\":\"Échec de la génération du rapport JSON\",\"details\":\"$(cat "$REPORT_FILE" | tr -d '\n')\"}" > "$REPORT_FILE"
    echo "Erreur lors de la génération du rapport JSON" >&2
    exit 1
fi