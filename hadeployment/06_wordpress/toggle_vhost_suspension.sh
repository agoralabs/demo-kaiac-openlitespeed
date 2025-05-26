#!/bin/bash

# Vérification des droits root
if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root." >&2
    exit 1
fi

# Variables
CONF_FILE="/usr/local/lsws/conf/httpd_config.conf"
BACKUP_FILE="${CONF_FILE}.bak"

# Vérification du nombre d'arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <enable|disable> <vhost_name>" >&2
    echo "Exemple: $0 disable example_com" >&2
    exit 1
fi

ACTION="$1"
VHOST_NAME="$2"

# Sauvegarde du fichier de configuration
cp -f "$CONF_FILE" "$BACKUP_FILE" || {
    echo "Erreur: Impossible de sauvegarder le fichier de configuration." >&2
    exit 1
}

# Fonction pour gérer la suspension/activation
manage_vhost() {
    local action="$1"
    local vhost="$2"
    local has_suspended_line=$(grep -q "suspendedVhosts" "$CONF_FILE"; echo $?)

    if [ "$action" = "disable" ]; then
        if [ "$has_suspended_line" -eq 0 ]; then
            # Ajoute le vhost à la ligne existante
            sed -i "/suspendedVhosts[[:space:]]*/ s/\(suspendedVhosts[[:space:]]*\)\(.*\)/\1\2,${vhost}/" "$CONF_FILE"
        else
            # Crée une nouvelle ligne suspendedVhosts après "listen"
            sed -i "/^listen/a\ \ suspendedVhosts           ${vhost}" "$CONF_FILE"
        fi
        echo "VHost '${vhost}' suspendu avec succès."
    elif [ "$action" = "enable" ]; then
        if [ "$has_suspended_line" -eq 0 ]; then
            # Retire le vhost de la ligne existante
            sed -i "/suspendedVhosts[[:space:]]*/ s/${vhost}//g" "$CONF_FILE"
            # Nettoie les virgules résiduelles
            sed -i "/suspendedVhosts[[:space:]]*/ s/,\{2,\}/,/g; s/\(suspendedVhosts[[:space:]]*\),/\1 /; s/\(suspendedVhosts[[:space:]]*\) $//" "$CONF_FILE"
            # Supprime la ligne si elle est vide
            sed -i "/suspendedVhosts[[:space:]]*$/ d" "$CONF_FILE"
        fi
        echo "VHost '${vhost}' activé avec succès."
    fi
}

# Exécution de l'action
case "$ACTION" in
    enable|disable)
        manage_vhost "$ACTION" "$VHOST_NAME"
        # Redémarrage d'OpenLiteSpeed
        systemctl restart lsws && echo "OpenLiteSpeed redémarré avec succès." || {
            echo "Erreur: Impossible de redémarrer OpenLiteSpeed." >&2
            exit 1
        }
        ;;
    *)
        echo "Action non reconnue. Utilisez 'enable' ou 'disable'." >&2
        exit 1
        ;;
esac

exit 0