#!/bin/bash

# Vérification du nombre d'arguments
# if [ "$#" -ne 5 ]; then
#     echo "Usage: $0 <local_folder_path> <git_repo_url> <git_branch> <git_username> <git_token>"
#     exit 1
# fi

# Récupération des arguments
# LOCAL_FOLDER=$1
# GIT_REPO_URL=$2
# GIT_BRANCH=$3
# GIT_USERNAME=$4
# GIT_TOKEN=$5

# Récupération des arguments

# Construction de l'URL avec les credentials
CLEAN_URL=${GIT_REPO_URL#https://}
AUTH_URL="https://${GIT_USERNAME}:${GIT_TOKEN}@${CLEAN_URL}"

# Fonction pour vérifier si un dossier est un dépôt Git
is_git_repo() {
    [ -d "$1/.git" ]
}

# Vérification si le dossier local existe
if [ -d "$LOCAL_FOLDER" ]; then
    if is_git_repo "$LOCAL_FOLDER"; then
        echo "Dépôt Git existant détecté. Mise à jour..."
        cd "$LOCAL_FOLDER" || exit 1
        
        # Réinitialisation des changements locaux éventuels
        git reset --hard
        
        # Vérification de la branche
        CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
        if [ "$CURRENT_BRANCH" != "$GIT_BRANCH" ]; then
            git checkout "$GIT_BRANCH" || git checkout -b "$GIT_BRANCH" --track "origin/$GIT_BRANCH"
        fi
        
        # Pull des derniers changements
        git pull "$AUTH_URL" "$GIT_BRANCH"
    else
        echo "Le dossier existe mais n'est pas un dépôt Git."
        echo "Suppression du contenu existant et nouveau clonage..."
        rm -rf "${LOCAL_FOLDER:?}/"*
        git clone -b "$GIT_BRANCH" "$AUTH_URL" "$LOCAL_FOLDER"
    fi
else
    echo "Clonage du dépôt dans un nouveau dossier..."
    git clone -b "$GIT_BRANCH" "$AUTH_URL" "$LOCAL_FOLDER"
fi

# Vérification du succès de l'opération
if [ $? -eq 0 ]; then
    echo "Opération réussie."
    echo "Dépôt disponible dans: $LOCAL_FOLDER"
else
    echo "Erreur lors de l'opération."
    exit 1
fi