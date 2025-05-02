#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 [on|off] [site_name]"
    echo "Exemple: $0 on site1_skyscaledev_com"
    exit 1
fi

MAINTENANCE_MODE="$1"
WP_SITE_NAME="$2"
WEB_ROOT="/var/www/$WP_SITE_NAME"

# Vérification de l'installation WordPress
if [ ! -f "$WEB_ROOT/wp-config.php" ]; then
    echo "Erreur : wp-config.php introuvable dans $WEB_ROOT"
    exit 1
fi

# Récupération du thème actif (avec fallback SQL si WP-CLI échoue)
get_active_theme() {
    # Méthode WP-CLI
    if [ -x "$(command -v wp)" ]; then
        THEME_NAME=$(wp option get stylesheet --path="$WEB_ROOT" --allow-root 2>/dev/null)
    fi
    
    # Fallback: méthode SQL directe
    if [ -z "$THEME_NAME" ]; then
        DB_NAME=$(grep -oP "DB_NAME',\s*'\K[^']+" "$WEB_ROOT/wp-config.php")
        DB_USER=$(grep -oP "DB_USER',\s*'\K[^']+" "$WEB_ROOT/wp-config.php")
        DB_PASS=$(grep -oP "DB_PASSWORD',\s*'\K[^']+" "$WEB_ROOT/wp-config.php")
        THEME_NAME=$(mysql -N -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT option_value FROM wp_options WHERE option_name = 'stylesheet' LIMIT 1;" 2>/dev/null)
    fi

    if [ -z "$THEME_NAME" ]; then
        echo "Erreur : Impossible de détecter le thème actif"
        exit 1
    fi
    echo "$WEB_ROOT/wp-content/themes/$THEME_NAME"
}

THEME_DIR=$(get_active_theme)
MAINTENANCE_HTML="$THEME_DIR/maintenance-page.php"
LSCACHE_EXCLUSION="/usr/local/lsws/conf/vhosts/$WP_SITE_NAME.d/maintenance-exclude.conf"

# Fonctions
create_maintenance_page() {
    cat << 'EOF' > "$MAINTENANCE_HTML"
<!DOCTYPE html>
<html>
<head>
    <title>Maintenance en cours</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #d9534f; }
    </style>
</head>
<body>
    <h1>🚧 Maintenance en cours</h1>
    <p>Nous effectuons des mises à jour. Merci de revenir plus tard.</p>
</body>
</html>
EOF
    echo "→ Page de maintenance créée : $MAINTENANCE_HTML"
}

add_wp_hook() {
    HOOK_FILE="$THEME_DIR/functions.php"
    if [ ! -f "$HOOK_FILE" ]; then
        echo "Erreur : $HOOK_FILE introuvable"
        exit 1
    fi

    if ! grep -q "custom_maintenance_mode" "$HOOK_FILE"; then
        cat << 'EOF' >> "$HOOK_FILE"

// Mode maintenance activé par script
function custom_maintenance_mode() {
    if (!current_user_can('administrator')) {
        header('HTTP/1.1 503 Service Temporarily Unavailable');
        header('Retry-After: 3600');
        include(get_template_directory() . '/maintenance-page.php');
        exit();
    }
}
add_action('template_redirect', 'custom_maintenance_mode', 1);
EOF
        echo "→ Hook ajouté à $HOOK_FILE"
    fi
}

configure_lscache() {
    mkdir -p "/usr/local/lsws/conf/vhosts/$WP_SITE_NAME.d/"
    cat << 'EOF' > "$LSCACHE_EXCLUSION"
RewriteCond %{DOCUMENT_ROOT}/wp-content/themes/*/maintenance-page.php -f
RewriteRule .* - [E=Cache-Control:no-cache]
EOF
    /usr/local/lsws/bin/lswsctrl reload >/dev/null 2>&1
    echo "→ Configuration LSCache mise à jour"
}

disable_maintenance() {
    [ -f "$MAINTENANCE_HTML" ] && rm -f "$MAINTENANCE_HTML"
    [ -f "$LSCACHE_EXCLUSION" ] && rm -f "$LSCACHE_EXCLUSION"
    
    if [ -f "$THEME_DIR/functions.php" ]; then
        sed -i '/custom_maintenance_mode/,/add_action/d' "$THEME_DIR/functions.php"
    fi
    
    /usr/local/lsws/bin/lswsctrl reload >/dev/null 2>&1
    echo "→ Maintenance désactivée"
}

# Exécution
case "$MAINTENANCE_MODE" in
    on)
        create_maintenance_page
        add_wp_hook
        configure_lscache
        echo "✅ Maintenance ACTIVÉE pour $WP_SITE_NAME"
        ;;
    off)
        disable_maintenance
        echo "✅ Maintenance DÉSACTIVÉE pour $WP_SITE_NAME"
        ;;
    *)
        echo "Usage: $0 [on|off] [site_name]"
        exit 1
        ;;
esac