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

# Vérifications initiales
if [ ! -d "$WEB_ROOT" ]; then
    echo "Erreur : Le dossier $WEB_ROOT n'existe pas"
    exit 1
fi

if [ ! -f "$WEB_ROOT/wp-config.php" ]; then
    echo "Erreur : wp-config.php introuvable dans $WEB_ROOT"
    exit 1
fi

# Fonction pour détecter le thème actif
get_active_theme() {
    # Essayer d'abord avec WP-CLI
    if command -v wp &> /dev/null; then
        THEME_NAME=$(wp option get stylesheet --path="$WEB_ROOT" --allow-root 2>/dev/null)
        [ -n "$THEME_NAME" ] && echo "$WEB_ROOT/wp-content/themes/$THEME_NAME" && return
    fi

    # Fallback: lecture directe de la base de données
    DB_NAME=$(grep -oP "DB_NAME',\s*'\K[^']+" "$WEB_ROOT/wp-config.php" | head -1)
    DB_USER=$(grep -oP "DB_USER',\s*'\K[^']+" "$WEB_ROOT/wp-config.php" | head -1)
    DB_PASS=$(grep -oP "DB_PASSWORD',\s*'\K[^']+" "$WEB_ROOT/wp-config.php" | head -1)
    DB_PREFIX=$(grep -oP "\$table_prefix\s*=\s*'\K[^']+" "$WEB_ROOT/wp-config.php" | head -1)

    THEME_NAME=$(mysql -N -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT option_value FROM ${DB_PREFIX}options WHERE option_name = 'stylesheet' LIMIT 1;" 2>/dev/null)
    [ -n "$THEME_NAME" ] && echo "$WEB_ROOT/wp-content/themes/$THEME_NAME" && return

    echo "ERROR" && return 1
}

# Détection du thème
THEME_DIR=$(get_active_theme)
if [ "$THEME_DIR" = "ERROR" ] || [ ! -d "$THEME_DIR" ]; then
    echo "ERREUR CRITIQUE: Impossible de déterminer le thème actif ou le dossier n'existe pas"
    echo "Thème détecté: $THEME_DIR"
    echo "Veuillez vérifier:"
    echo "1. Que WP-CLI est installé ou que vous avez accès à MySQL"
    echo "2. Que le thème est bien installé dans wp-content/themes/"
    exit 1
fi

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
        touch "$HOOK_FILE"
        chown www-data:www-data "$HOOK_FILE"
    fi

    if ! grep -q "custom_maintenance_mode" "$HOOK_FILE"; then
        cat << 'EOF' >> "$HOOK_FILE"
<?php
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

# Exécution principale
case "$MAINTENANCE_MODE" in
    on)
        echo "Activation du mode maintenance pour $WP_SITE_NAME"
        echo "Thème détecté: $THEME_DIR"
        create_maintenance_page
        add_wp_hook
        configure_lscache
        echo "✅ Maintenance ACTIVÉE avec succès"
        ;;
    off)
        echo "Désactivation du mode maintenance pour $WP_SITE_NAME"
        disable_maintenance
        echo "✅ Maintenance DÉSACTIVÉE avec succès"
        ;;
    *)
        echo "Usage: $0 [on|off] [site_name]"
        exit 1
        ;;
esac