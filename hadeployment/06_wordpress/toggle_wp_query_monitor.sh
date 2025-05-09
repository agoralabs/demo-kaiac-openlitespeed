#!/bin/bash

# Vérifie que le chemin du vhost WordPress et l'action sont fournis
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 [on|off] /chemin/vers/le/vhost/wordpress"
    exit 1
fi

ACTION="$1"
WEB_ROOT="$2"

# Vérifie si wp-cli est disponible
if ! command -v wp &> /dev/null; then
    echo "❌ wp-cli n'est pas installé ou n'est pas dans le PATH."
    exit 1
fi

# Vérifie si le répertoire WordPress existe
if [ ! -d "$WEB_ROOT" ] || [ ! -f "$WEB_ROOT/wp-config.php" ]; then
    echo "❌ Le répertoire spécifié ne contient pas une installation WordPress valide."
    exit 1
fi

case "$ACTION" in
    on|ON|On)
        # Active Query Monitor et ajuste les permissions
        echo "🔄 Activation de Query Monitor..."
        wp --path="$WEB_ROOT" plugin activate query-monitor --allow-root
        chown -R nobody:nogroup "$WEB_ROOT/wp-content/plugins/query-monitor"
        find "$WEB_ROOT/wp-content/plugins/query-monitor" -type d -exec chmod 755 {} \;
        find "$WEB_ROOT/wp-content/plugins/query-monitor" -type f -exec chmod 644 {} \;
        echo "✅ Query Monitor est activé et configuré pour OpenLiteSpeed."
        ;;
    off|OFF|Off)
        # Désactive Query Monitor
        echo "🔄 Désactivation de Query Monitor..."
        wp --path="$WEB_ROOT" plugin deactivate query-monitor --allow-root
        echo "✅ Query Monitor est désactivé (mais toujours installé)."
        ;;
    *)
        echo "❌ Action non reconnue. Utilisez 'on' ou 'off'."
        exit 1
        ;;
esac
