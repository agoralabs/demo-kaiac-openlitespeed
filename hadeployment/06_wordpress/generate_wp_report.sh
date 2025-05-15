#!/bin/bash

# Vérification du paramètre WEB_ROOT
if [ -z "$1" ]; then
    echo "Usage: $0 /chemin/absolu/vers/wordpress"
    echo "{\"error\":\"Le paramètre WEB_ROOT est manquant\"}" > wp-config-report.json
    exit 1
fi

WEB_ROOT="$1"
REPORT_FILE="$WEB_ROOT/wp-config-report.json"

# Vérification de WP-CLI
if ! command -v wp &> /dev/null; then
    echo "{\"error\":\"WP-CLI n'est pas installé\"}" > "$REPORT_FILE"
    exit 1
fi

# Fonction pour exécuter les commandes WP-CLI avec gestion des erreurs
wp_cmd() {
    local cmd="$1"
    local default="$2"
    local result
    
    result=$(wp --allow-root --path="$WEB_ROOT" $cmd 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        echo "$default"
    else
        echo "$result"
    fi
}

# Fonction pour obtenir les options avec formatage JSON sécurisé
get_wp_option() {
    local option_name="$1"
    local default_value="$2"
    
    wp_cmd "option get $option_name --format=json" "$default_value"
}

# Fonction pour obtenir les constantes de configuration
get_wp_config() {
    local constant_name="$1"
    local default_value="$2"
    
    wp_cmd "config get $constant_name --format=json" "$default_value"
}

# Génération du rapport JSON
{
    echo "{"
    echo "\"report_date\": \"$(date -Iseconds)\","
    echo "\"web_root\": \"$WEB_ROOT\","
    
    # 1. Informations de base
    echo "\"basic_info\": {"
    echo "\"site_url\": $(get_wp_option 'siteurl' '""'),"
    echo "\"home_url\": $(get_wp_option 'home' '""'),"
    echo "\"wp_version\": $(wp --allow-root --path="$WEB_ROOT" core version --quiet --format=json || echo '""'),"
    echo "\"language\": $(wp_cmd 'core language list --status=active --fields=code,name --format=json' '[]')"
    echo "},"
    
    # 2. Configuration générale
    echo "\"general_config\": {"
    echo "\"blogname\": $(get_wp_option 'blogname' '""'),"
    echo "\"blogdescription\": $(get_wp_option 'blogdescription' '""'),"
    echo "\"admin_email\": $(get_wp_option 'admin_email' '""'),"
    echo "\"timezone_string\": $(get_wp_option 'timezone_string' '""'),"
    echo "\"date_format\": $(get_wp_option 'date_format' '""'),"
    echo "\"time_format\": $(get_wp_option 'time_format' '""'),"
    echo "\"start_of_week\": $(get_wp_option 'start_of_week' '0')"
    echo "},"
    
    # 3. Paramètres de lecture
    echo "\"reading_settings\": {"
    echo "\"show_on_front\": $(get_wp_option 'show_on_front' '""'),"
    echo "\"page_on_front\": $(get_wp_option 'page_on_front' '0'),"
    echo "\"page_for_posts\": $(get_wp_option 'page_for_posts' '0'),"
    echo "\"posts_per_page\": $(get_wp_option 'posts_per_page' '10')"
    echo "},"
    
    # 4. Paramètres de discussion
    echo "\"discussion_settings\": {"
    echo "\"default_comment_status\": $(get_wp_option 'default_comment_status' '""'),"
    echo "\"comment_registration\": $(get_wp_option 'comment_registration' '0'),"
    echo "\"require_name_email\": $(get_wp_option 'require_name_email' '0'),"
    echo "\"close_comments_for_old_posts\": $(get_wp_option 'close_comments_for_old_posts' '0'),"
    echo "\"close_comments_days_old\": $(get_wp_option 'close_comments_days_old' '14'),"
    echo "\"thread_comments\": $(get_wp_option 'thread_comments' '0'),"
    echo "\"thread_comments_depth\": $(get_wp_option 'thread_comments_depth' '5')"
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

# Vérification du fichier JSON généré
if jq empty "$REPORT_FILE" >/dev/null 2>&1; then
    echo "Rapport généré avec succès dans $REPORT_FILE"
else
    echo "{\"error\":\"Échec de la génération du rapport JSON\"}" > "$REPORT_FILE"
    echo "Erreur lors de la génération du rapport JSON" >&2
    exit 1
fi
