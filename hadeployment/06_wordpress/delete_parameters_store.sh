#!/bin/bash
# Script pour activer ou désactiver LiteSpeed Cache pour un site WordPress
# Usage: ./toggle_lscache.sh [on|off] [site_name]
# Exemple: ./toggle_lscache.sh on site1_skyscaledev_com

# Vérifier les paramètres
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [DOMAIN_FOLDER]"
    echo "Exemple: $0 site1_skyscaledev_com"
    exit 1
fi

DOMAIN_FOLDER="$1"
PARAMETER_NAME="/wordpress/${domain_folder}/redirects"

AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
# Supprimer le paramètre
aws ssm delete-parameter --name "$PARAMETER_NAME" --region "$AWS_REGION"