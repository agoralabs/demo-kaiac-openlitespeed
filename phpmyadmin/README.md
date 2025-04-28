# Téléchargement du script shell

curl -o install_pma_manual.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/phpmyadmin/install_pma_manual.sh


# Erreur d'affichage de la page de login

Cette erreur de **Content Security Policy (CSP)** se produit parce que phpMyAdmin utilise des scripts inline, mais votre configuration OpenLiteSpeed impose une politique de sécurité stricte. Voici comment résoudre ce problème :

---

### Solution 1 (Recommandée) : Mettre à jour la CSP dans OpenLiteSpeed
1. **Modifiez la configuration du virtual host** :  
   Éditez le fichier de configuration (`/usr/local/lsws/conf/vhosts/[votre-site]/vhconf.conf`) et ajoutez :
   ```nginx
   extraHeaders          <<<END_extraHeaders
   Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob:; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; connect-src 'self'"
   END_extraHeaders
   ```

2. **Redémarrez OpenLiteSpeed** :
   ```bash
   systemctl restart lsws
   ```

---

### Solution 2 (Alternative) : Désactiver temporairement la CSP (pour débogage)
Si vous voulez vérifier que le problème vient bien de la CSP :
```nginx
extraHeaders          <<<END_extraHeaders
Content-Security-Policy ""
END_extraHeaders
```
*Redémarrez ensuite le serveur.*

---

### Explication des paramètres CSP
| Directive               | Valeur                            | Description                                                                 |
|-------------------------|-----------------------------------|-----------------------------------------------------------------------------|
| `default-src`           | `'self'`                          | Autorise uniquement les ressources du même domaine                          |
| **`'unsafe-inline'`**   | Ajouté                            | Permet les scripts/styles inline (nécessaire pour phpMyAdmin)               |
| `'unsafe-eval'`         | Ajouté                            | Permet `eval()` (utilisé par certains scripts JS)                           |
| `img-src`               | `'self' data:`                    | Autorise les images internes et en base64                                   |
| `style-src`             | `'self' 'unsafe-inline'`          | Permet les styles inline                                                   |
| `connect-src`           | `'self'`                          | Restreint les connexions AJAX/WebSocket au domaine                         |

---

### Solution 3 (Pour les utilisateurs avancés) : Utiliser des nonces
Si vous voulez garder une CSP stricte sans `unsafe-inline` :
1. **Générez un nonce** dans votre configuration PHP :
   ```php
   $nonce = base64_encode(random_bytes(16));
   $cfg['CSPNonce'] = $nonce;
   ```

2. **Modifiez la CSP** :
   ```nginx
   Content-Security-Policy "script-src 'self' 'nonce-<?php echo $nonce; ?>'"
   ```

3. **Adaptez les templates phpMyAdmin** (complexe, nécessite des modifications des fichiers sources).

---

### Vérification finale
1. **Ouvrez les outils de développement** (F12 dans Chrome/Firefox)
2. **Onglet "Console"** : L'erreur CSP devrait avoir disparu
3. **Onglet "Réseau"** : Vérifiez que les fichiers JS/CSS se chargent correctement (statut HTTP 200)

---

### Notes importantes
- La **Solution 1** est un bon équilibre entre sécurité et fonctionnalité pour phpMyAdmin.
- Si vous utilisez HTTPS, ajoutez `https:` devant `'self'` dans la CSP.
- Testez toujours après chaque modification avec une fenêtre de navigation privée pour éviter les caches.

