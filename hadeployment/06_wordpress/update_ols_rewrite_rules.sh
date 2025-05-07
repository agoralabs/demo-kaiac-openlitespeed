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

# 2. Écrire dans un fichier temporaire en excluant les blocs rewrite de premier niveau
awk '
  BEGIN {
    depth = 0
    in_rewrite = 0
  }
  {
    line = $0
    open = gsub(/{/, "", line)
    close = gsub(/}/, "", line)
    brace_delta = open - close

    # Début de bloc rewrite à la racine
    if (!in_rewrite && depth == 0 && $1 == "rewrite" && $2 == "{") {
      in_rewrite = 1
      next
    }

    # Si dans un bloc rewrite, ne rien imprimer
    if (in_rewrite) {
      if (brace_delta < 0) {
        in_rewrite = 0
      }
      depth += brace_delta
      next
    }

    print $0
    depth += brace_delta
  }
' "${VHOST_CONF_FILE}" > "${TMP_FILE}"

# 3. Ajouter la nouvelle section rewrite à la fin du fichier temporaire
cat <<EOF >> "${TMP_FILE}"

rewrite {
  enable 1
  autoLoadHtaccess 0
  rules <<<END_rules
$(echo "$RULES_JSON" | jq -r '.rules | sort_by(.priority)[] | select(.is_active == true) | 
  (if .condition and (.condition != "") then "  \(.condition)\n" else "" end) + 
  "  \(.rewrite_rule)"')
END_rules
}
EOF

# 4. Remplacer le fichier original
mv "${TMP_FILE}" "${VHOST_CONF_FILE}"

echo "✅ Terminé ! Les règles ont été appliquées pour le vHost ${VHOST_NAME}."
