#!/bin/bash

# Script d'installation de WP-CLI avec vérifications
# Auteur : [Votre Nom]
# Usage : sudo ./install-wp-cli.sh

echo "=== Installation de WP-CLI ==="

# 1. Vérifier si WP-CLI est déjà installé
if command -v wp &> /dev/null; then
    echo "✅ WP-CLI est déjà installé. Version : $(wp --version)"
    exit 0
fi

# 2. Vérifier les dépendances (PHP, curl)
echo "Vérification des dépendances..."
for pkg in php curl; do
    if ! command -v $pkg &> /dev/null; then
        echo "❌ $pkg n'est pas installé. Installation en cours..."
        apt-get update && apt-get install -y $pkg || {
            echo "Échec de l'installation de $pkg. Script arrêté."
            exit 1
        }
    fi
done

# 3. Télécharger WP-CLI
echo "Téléchargement de WP-CLI..."
curl -o wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || {
    echo "❌ Échec du téléchargement. Vérifiez votre connexion internet."
    exit 1
}

# 4. Rendre le fichier exécutable
chmod +x wp-cli.phar

# 5. Installer dans /usr/local/bin (accessible globalement)
mv wp-cli.phar /usr/local/bin/wp || {
    echo "❌ Échec du déplacement. Essayez avec sudo ?"
    exit 1
}

# 6. Vérifier l'installation
if wp --allow-root --version &> /dev/null; then
    echo "✅ Installation réussie ! Version : $(wp --version)"
else
    echo "❌ Échec de l'installation. Derniers logs :"
    wp --allow-root --version
    exit 1
fi

# Optionnel : Activer la complétion bash (pour l'autocomplétion)
echo "Installation de la complétion automatique..."
curl -o /usr/share/bash-completion/completions/wp https://raw.githubusercontent.com/wp-cli/wp-cli/v2.8.1/utils/wp-completion.bash &> /dev/null && {
    echo "✅ Complétion activée. Rechargez votre terminal avec 'source ~/.bashrc'."
}

echo "=== Fin du script ==="