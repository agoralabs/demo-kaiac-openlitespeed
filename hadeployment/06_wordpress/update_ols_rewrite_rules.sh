#!/bin/bash

# Paramètres d'entrée
VHOST_NAME="$1"      # Nom du Virtual Host (ex: "site1_skyscaledev_com")

# Chemins importants
PARAMETER_PATH="/wordpress/${VHOST_NAME}/redirects" # Chemin du paramètre dans Parameter Store
OLS_CONF_DIR="/usr/local/lsws/conf/vhosts"
VHOST_CONF_FILE="${OLS_CONF_DIR}/${VHOST_NAME}/vhconf.conf"

TMP_RULES_FILE=$(mktemp)

AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# 1. Récupérer les règles depuis AWS Parameter Store
echo "🔍 Récupération des règles depuis AWS Parameter Store (${PARAMETER_PATH})..."
RULES_JSON=$(aws ssm get-parameter --name "${PARAMETER_PATH}" --query "Parameter.Value" --output text --region "${AWS_REGION}")

# Vérifier si la récupération a réussi
if [ -z "$RULES_JSON" ]; then
  echo "❌ Erreur: Impossible de récupérer les règles depuis Parameter Store !"
  exit 1
fi

# 2. Parser le JSON et générer les règles triées par priorité
echo "🔨 Génération des règles de réécriture..."
cat > "${TMP_RULES_FILE}" <<EOL
rewrite {
  enable 1
  autoLoadHtaccess 0
  rules <<<END_rules
EOL

# Extraire les règles, les trier par priorité et les formater
echo "$RULES_JSON" | jq -r '.rules | sort_by(.priority)[] | select(.is_active == true) | 
  (if .condition and (.condition != "") then "  \(.condition)\n" else "" end) + 
  "  \(.rewrite_rule)"' >> "${TMP_RULES_FILE}"

cat >> "${TMP_RULES_FILE}" <<EOL
END_rules
}
EOL

# 3. Mettre à jour le fichier de configuration du VHost
echo "📝 Mise à jour de ${VHOST_CONF_FILE}..."

# Supprimer l'ancienne section rewrite si elle existe
sed -i '/rewrite {/,/}/d' "${VHOST_CONF_FILE}"

# Ajouter les nouvelles règles
cat "${TMP_RULES_FILE}" >> "${VHOST_CONF_FILE}"

# Nettoyage
rm -rf "${TMP_RULES_FILE}"

echo "✅ Terminé ! Les règles ont été appliquées pour le vHost ${VHOST_NAME}."