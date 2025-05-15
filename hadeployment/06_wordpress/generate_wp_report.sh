#!/bin/bash

# Vérification du paramètre WEB_ROOT
if [ -z "$1" ]; then
    echo "Usage: $0 /chemin/absolu/vers/wordpress"
    echo "{\"error\":\"Le paramètre WEB_ROOT est manquant\"}" > wp-config-report.json
    exit 1
fi

WEB_ROOT="$1"

# Vérification de WP-CLI
if ! command -v wp &> /dev/null; then
    echo "{\"error\":\"WP-CLI n'est pas installé\"}" > "$WEB_ROOT/wp-config-report.json"
    exit 1
fi

# Vérification du contexte WordPress
if ! wp --allow-root --path="$WEB_ROOT" core is-installed 2>/dev/null; then
    echo "{\"error\":\"Ceci n'est pas une installation WordPress valide\"}" > "$WEB_ROOT/wp-config-report.json"
    exit 1
fi

# Fonction pour récupérer les données au format JSON
generate_wp_report() {
    # 1. Informations de base
    local site_url=$(wp --allow-root --path="$WEB_ROOT" option get siteurl --format=json)
    local home_url=$(wp --allow-root --path="$WEB_ROOT" option get home --format=json)
    local wp_version=$(wp --allow-root --path="$WEB_ROOT" core version --format=json)
    local language=$(wp --allow-root --path="$WEB_ROOT" core language list --status=active --fields=code,name --format=json)

    # 2. Configuration générale
    local general_config=$(wp --allow-root --path="$WEB_ROOT" option get --format=json \
        blogname \
        blogdescription \
        admin_email \
        timezone_string \
        date_format \
        time_format \
        start_of_week
    )

    # 3. Paramètres de lecture
    local reading_settings=$(wp --allow-root --path="$WEB_ROOT" option get --format=json \
        show_on_front \
        page_on_front \
        page_for_posts \
        posts_per_page
    )

    # 4. Paramètres de discussion
    local discussion_settings=$(wp --allow-root --path="$WEB_ROOT" option get --format=json \
        default_comment_status \
        comment_registration \
        require_name_email \
        close_comments_for_old_posts \
        close_comments_days_old \
        thread_comments \
        thread_comments_depth
    )

    # 5. Thème et extensions
    local active_theme=$(wp --allow-root --path="$WEB_ROOT" theme list --status=active --fields=name,title,version,status --format=json)
    local active_plugins=$(wp --allow-root --path="$WEB_ROOT" plugin list --status=active --fields=name,title,version,status --format=json)
    local mu_plugins=$(wp --allow-root --path="$WEB_ROOT" plugin list --status=must-use --fields=name,title,version,status --format=json)

    # 6. Configuration avancée
    local db_name=$(wp --allow-root --path="$WEB_ROOT" config get DB_NAME --format=json)
    local db_user=$(wp --allow-root --path="$WEB_ROOT" config get DB_USER --format=json)
    local db_host=$(wp --allow-root --path="$WEB_ROOT" config get DB_HOST --format=json)
    local table_prefix=$(wp --allow-root --path="$WEB_ROOT" config get table_prefix --format=json)
    local wp_debug=$(wp --allow-root --path="$WEB_ROOT" config get WP_DEBUG --format=json)
    local wp_debug_log=$(wp --allow-root --path="$WEB_ROOT" config get WP_DEBUG_LOG --format=json)
    local wp_debug_display=$(wp --allow-root --path="$WEB_ROOT" config get WP_DEBUG_DISPLAY --format=json)
    local script_debug=$(wp --allow-root --path="$WEB_ROOT" config get SCRIPT_DEBUG --format=json)
    local wp_cache=$(wp --allow-root --path="$WEB_ROOT" config get WP_CACHE --format=json)

    # Construction de l'objet JSON complet
    jq -n \
        --arg date "$(date -Iseconds)" \
        --arg web_root "$WEB_ROOT" \
        --argjson site_url "$site_url" \
        --argjson home_url "$home_url" \
        --argjson wp_version "$wp_version" \
        --argjson language "$language" \
        --argjson general_config "$general_config" \
        --argjson reading_settings "$reading_settings" \
        --argjson discussion_settings "$discussion_settings" \
        --argjson active_theme "$active_theme" \
        --argjson active_plugins "$active_plugins" \
        --argjson mu_plugins "$mu_plugins" \
        --argjson db_name "$db_name" \
        --argjson db_user "$db_user" \
        --argjson db_host "$db_host" \
        --argjson table_prefix "$table_prefix" \
        --argjson wp_debug "$wp_debug" \
        --argjson wp_debug_log "$wp_debug_log" \
        --argjson wp_debug_display "$wp_debug_display" \
        --argjson script_debug "$script_debug" \
        --argjson wp_cache "$wp_cache" \
        '{
            "report_date": $date,
            "web_root": $web_root,
            "basic_info": {
                "site_url": $site_url,
                "home_url": $home_url,
                "wp_version": $wp_version,
                "language": $language
            },
            "general_config": $general_config,
            "reading_settings": $reading_settings,
            "discussion_settings": $discussion_settings,
            "theme": $active_theme,
            "plugins": {
                "active": $active_plugins,
                "must_use": $mu_plugins
            },
            "advanced_config": {
                "db_name": $db_name,
                "db_user": $db_user,
                "db_host": $db_host,
                "table_prefix": $table_prefix,
                "wp_debug": $wp_debug,
                "wp_debug_log": $wp_debug_log,
                "wp_debug_display": $wp_debug_display,
                "script_debug": $script_debug,
                "wp_cache": $wp_cache
            }
        }'
}

# Génération du rapport
generate_wp_report 

# > "$WEB_ROOT/wp-config-report.json"

#echo "Rapport généré dans $WEB_ROOT/wp-config-report.json"