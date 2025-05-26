#!/bin/bash

# Vérification des droits root
if [ "$(id -u)" -ne 0 ]; then
    echo "⚠️ Ce script doit être exécuté en tant que root." >&2
    exit 1
fi

# Variables
CONF_FILE="/usr/local/lsws/conf/httpd_config.conf"
BACKUP_FILE="${CONF_FILE}.bak"
TMP_FILE=$(mktemp)

# Vérification des arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <enable|disable> <vhost_name>" >&2
    echo "Exemple: $0 disable site1_example_com" >&2
    exit 1
fi

ACTION="$1"
VHOST_NAME="$2"

# Sauvegarde du fichier
cp -f "$CONF_FILE" "$BACKUP_FILE" || {
    echo "❌ Erreur: Impossible de sauvegarder le fichier." >&2
    exit 1
}

# Fonction principale
manage_vhost() {
    local action="$1"
    local vhost="$2"

    # Cas "disable" : ajouter le vhost à suspendedVhosts
    if [ "$action" = "disable" ]; then
        if grep -q "suspendedVhosts" "$CONF_FILE"; then
            # Mise à jour de la ligne existante
            sed -i "/suspendedVhosts/ s/$/,${vhost}/" "$CONF_FILE"
        else
            # Ajout d'une nouvelle ligne à la fin
            echo "suspendedVhosts           ${vhost}" >> "$CONF_FILE"
        fi
        echo "✅ VHost '${vhost}' suspendu avec succès."

    # Cas "enable" : retirer le vhost de suspendedVhosts
    elif [ "$action" = "enable" ]; then
        if grep -q "suspendedVhosts" "$CONF_FILE"; then
            # Suppression du vhost de la liste
            sed -i "/suspendedVhosts/ s/${vhost}//g" "$CONF_FILE"
            # Nettoyage des virgules
            sed -i "/suspendedVhosts/ s/,,/,/g; s/, / /g; s/,$//; s/^suspendedVhosts[[:space:]]*$/d" "$CONF_FILE"
            echo "✅ VHost '${vhost}' activé avec succès."
        else
            echo "ℹ️ Aucun vHost suspendu trouvé." >&2
        fi
    fi
}

# Exécution
case "$ACTION" in
    enable|disable)
        manage_vhost "$ACTION" "$VHOST_NAME"
        systemctl restart lsws && echo "♻️ OpenLiteSpeed redémarré." || {
            echo "❌ Erreur: Redémarrage impossible." >&2
            exit 1
        }
        ;;
    *)
        echo "❌ Action invalide. Utilisez 'enable' ou 'disable'." >&2
        exit 1
        ;;
esac

# Nettoyage
rm -f "$TMP_FILE"
exit 0