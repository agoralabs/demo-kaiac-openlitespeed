#!/bin/bash

# Paramètres d'entrée
VHOST_NAME="$1"      # Nom du Virtual Host (ex: "site1_skyscaledev_com")

# Chemins importants
PARAMETER_PATH="/wordpress/${VHOST_NAME}/redirects" # Chemin du paramètre dans Parameter Store
OLS_CONF_DIR="/usr/local/lsws/conf/vhosts"
VHOST_CONF_FILE="${OLS_CONF_DIR}/${VHOST_NAME}/vhconf.conf"
TMP_FILE=$(mktemp)

AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# 1. Récupérer les règles depuis AWS Parameter Store
echo "🔍 Récupération des règles depuis AWS Parameter Store (${PARAMETER_PATH})..."
RULES_JSON=$(aws ssm get-parameter --name "${PARAMETER_PATH}" --query "Parameter.Value" --output text --region "${AWS_REGION}")

# Vérifier si la récupération a réussi
if [ -z "$RULES_JSON" ]; then
  echo "❌ Erreur: Impossible de récupérer les règles depuis Parameter Store !"
  exit 1
fi

# 2. Créer un fichier temporaire avec le nouveau contenu
{
  # Copier tout le contenu SAUF la section rewrite
  sed '/rewrite {/,/}/d' "${VHOST_CONF_FILE}"
  
  # Ajouter la nouvelle section rewrite
  echo "rewrite {"
  echo "  enable 1"
  echo "  autoLoadHtaccess 0"
  echo "  rules <<<END_rules"
  
  # Ajouter les règles actives triées par priorité
  echo "$RULES_JSON" | jq -r '.rules | sort_by(.priority)[] | select(.is_active == true) | 
    (if .condition and (.condition != "") then "  \(.condition)\n" else "" end) + 
    "  \(.rewrite_rule)"'
  
  echo "END_rules"
  echo "}"
} > "${TMP_FILE}"

# 3. Remplacer le fichier original
mv "${TMP_FILE}" "${VHOST_CONF_FILE}"

echo "✅ Terminé ! Les règles ont été appliquées pour le vHost ${VHOST_NAME}."