#!/bin/bash


MAINTENANCE_MODE="$1" # ex. on|off
WP_SITE_NAME="$2" # ex. site1_skyscaledev_com

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 [on|off] [site_name]"
    exit 1
fi

# Configuration
WEB_ROOT="/var/www/$WP_SITE_NAME"  # Chemin vers la racine WordPress
ACTIVE_THEME_NAME=$(wp option get stylesheet --path=${WEB_ROOT} --allow-root) # Thème actif
echo "ACTIVE_THEME_NAME=$ACTIVE_THEME_NAME"

THEME_DIR="$WEB_ROOT/wp-content/themes/$ACTIVE_THEME_NAME"
echo "THEME_DIR=$THEME_DIR"

MAINTENANCE_HTML="$THEME_DIR/maintenance-page.php"
echo "MAINTENANCE_HTML=$MAINTENANCE_HTML"

LSCACHE_EXCLUSION="/usr/local/lsws/conf/vhosts/$WP_SITE_NAME.d/maintenance-exclude.conf"  # Chemin de configuration OpenLiteSpeed

# Préparation du folder de config du vhost
mkdir -p "/usr/local/lsws/conf/vhosts/$WP_SITE_NAME.d/"

# Vérification des dépendances
if [ ! -f "/usr/local/lsws/bin/lswsctrl" ]; then
    echo "Erreur : OpenLiteSpeed n'est pas installé ou le chemin est incorrect."
    exit 1
fi

# Fonction pour créer la page de maintenance
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
    echo "→ Page de maintenance créée dans : ${MAINTENANCE_HTML}"
}

# Fonction pour ajouter le hook WordPress
add_wp_hook() {
    HOOK_FILE="${THEME_DIR}/functions.php"
    if grep -q "custom_maintenance_mode" "$HOOK_FILE"; then
        echo "→ Le hook est déjà présent dans functions.php."
    else
        cat << 'EOF' >> "$HOOK_FILE"

// Activation manuelle du mode maintenance (script shell)
function custom_maintenance_mode() {
    if (!current_user_can('administrator') {
        header('HTTP/1.1 503 Service Temporarily Unavailable');
        header('Retry-After: 3600');
        include(get_template_directory() . '/maintenance-page.php');
        exit();
    }
}
add_action('template_redirect', 'custom_maintenance_mode', 1);
EOF
        echo "→ Hook ajouté à ${HOOK_FILE}"
    fi
}

# Fonction pour configurer l'exclusion LSCache
configure_lscache_exclusion() {
    cat << 'EOF' > "$LSCACHE_EXCLUSION"
RewriteCond %{DOCUMENT_ROOT}/wp-content/themes/*/maintenance-page.php -f
RewriteRule .* - [E=Cache-Control:no-cache]
EOF
    # Recharge la configuration OpenLiteSpeed
    /usr/local/lsws/bin/lswsctrl reload >/dev/null 2>&1
    echo "→ Exclusion LSCache configurée. Cache relancé."
}

# Fonction pour activer/désactiver
case "$MAINTENANCE_MODE" in
    on)
        create_maintenance_page
        add_wp_hook
        configure_lscache_exclusion
        echo "✅ Mode maintenance ACTIVÉ. Testez depuis une navigation privée."
        ;;
    off)
        rm -f "$MAINTENANCE_HTML"
        sed -i '/custom_maintenance_mode/,/add_action/d' "${THEME_DIR}/functions.php"
        rm -f "$LSCACHE_EXCLUSION"
        /usr/local/lsws/bin/lswsctrl reload >/dev/null 2>&1
        echo "✅ Mode maintenance DÉSACTIVÉ."
        ;;
    *)
        echo "Usage: $0 [on|off] [site_name]"
        exit 1
        ;;
esac