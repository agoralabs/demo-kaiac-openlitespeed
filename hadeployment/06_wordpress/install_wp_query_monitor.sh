#!/bin/bash
# Installe Query Monitor + active

# Vérifie que le chemin du vhost WordPress est fourni en argument
if [ -z "$1" ]; then
    echo "Usage: $0 <web_root>"
    exit 1
fi

WEB_ROOT="$1"

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

# Installation et activation de Query Monitor
echo "🔄 Installation de Query Monitor..."
wp --path="$WEB_ROOT" plugin install query-monitor --activate --allow-root

# Vérification de l'installation
if wp --path="$WEB_ROOT" plugin is-active query-monitor --allow-root; then
    echo "✅ Query Monitor a été installé et activé avec succès."
else
    echo "❌ Une erreur s'est produite lors de l'installation."
    exit 1
fi

# Configure les permissions pour OpenLiteSpeed (si nécessaire)
echo "🔧 Ajustement des permissions pour OpenLiteSpeed..."
chown -R nobody:nogroup "$WEB_ROOT/wp-content/plugins/query-monitor"
find "$WEB_ROOT/wp-content/plugins/query-monitor" -type d -exec chmod 755 {} \;
find "$WEB_ROOT/wp-content/plugins/query-monitor" -type f -exec chmod 644 {} \;

echo "✔️ Opération terminée. Query Monitor est prêt à l'emploi."