# Erreur : Your PHP installation appears to be missing the MySQL extension which is required by WordPress

### **Solution Complète (Ubuntu/Debian)**

#### 1. **Installer l'extension PHP pour MySQL/MariaDB**
```bash
# Pour PHP 8.x (remplacez par votre version de PHP)
sudo apt-get install php-mysql

# Pour PHP 7.4 (si vous utilisez une ancienne version)
sudo apt-get install php7.4-mysql
```

#### 2. **Vérifier que l'extension est activée**
```bash
php -m | grep mysqli
```
→ Doit afficher `mysqli`. Si rien ne s'affiche :
```bash
sudo phpenmod mysqli  # Active l'extension
```

#### 3. **Redémarrer OpenLiteSpeed pour appliquer les changements**
```bash
sudo systemctl restart lsws
```

---

### **Si vous utilisez un PHP personnalisé (LSAPI)**
1. Trouvez le chemin de votre PHP :
   ```bash
   which php
   ```
   (Exemple : `/usr/local/lsws/lsphp74/bin/php`)

2. Installez l'extension pour cette version spécifique :
   ```bash
   sudo /usr/local/lsws/lsphp74/bin/pecl install mysqli
   ```

3. Ajoutez `extension=mysqli.so` dans le `php.ini` correspondant :
   ```bash
   sudo nano /usr/local/lsws/lsphp74/etc/php/7.4/litespeed/php.ini
   ```

---

### **Vérification Finale**
- Créez un fichier `test.php` dans votre répertoire WordPress :
  ```php
  <?php
  phpinfo();
  ?>
  ```
- Accédez-y via un navigateur (`http://votre-site.com/test.php`) et cherchez **mysqli**.  
  → Doit apparaître dans la liste des modules chargés.

---

### **Cas Particuliers**
- **Si vous utilisez MariaDB** : L'extension `php-mysql` fonctionne aussi pour MariaDB.
- **Erreur persistante ?** Vérifiez la version de PHP utilisée par WordPress (dans `wp-admin/site-health.php` sous "Info Serveur").

---

### **Résumé des Commandes Clés**
| Problème | Solution |
|----------|----------|
| Extension manquante | `sudo apt-get install php-mysql` |
| PHP personnalisé | `sudo /chemin/vers/pecl install mysqli` |
| Redémarrage | `sudo systemctl restart lsws` |

Exécutez ces étapes, et WordPress devrait détecter correctement MySQL/MariaDB ! 🛠️

# Téléchargement des scripts sh

curl -o download_scripts.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/06_wordpress/download_scripts.sh

chmod +x download_scripts.sh
./download_scripts.sh

# Résultat activation LS Cache

```
root@ip-10-0-102-47:/home/ubuntu# ./install_wp_ls_cache.sh /var/www/site1_skyscaledev_com/

Installing LiteSpeed Cache (7.1)
Downloading installation package from https://downloads.wordpress.org/plugin/litespeed-cache.7.1.zip...
Unpacking the package...
Installing the plugin...
Plugin installed successfully.
Activating 'litespeed-cache'...
Plugin 'litespeed-cache' activated.
Success: Installed 1 of 1 plugins.
Success: Updated 'litespeed-cache-conf' option.
LSCache installé et activé !
```

```
root@ip-10-0-102-47:/home/ubuntu# curl -I https://site1.skyscaledev.com

HTTP/2 200 
date: Thu, 01 May 2025 23:52:17 GMT
content-type: text/html; charset=UTF-8
set-cookie: AWSALB=OBs4dSAtoJikQL+4b/eFEN4qGCVK2mU1emGgohz2F6yk5GXrLK+gU9xFOK1bcrCebHUTiUfUYdMpxv9nYtzRjslXeR4qxVqrCNb0FwcwWD+uh7/v1/8NuB7hySsU; Expires=Thu, 08 May 2025 23:52:17 GMT; Path=/
set-cookie: AWSALBCORS=OBs4dSAtoJikQL+4b/eFEN4qGCVK2mU1emGgohz2F6yk5GXrLK+gU9xFOK1bcrCebHUTiUfUYdMpxv9nYtzRjslXeR4qxVqrCNb0FwcwWD+uh7/v1/8NuB7hySsU; Expires=Thu, 08 May 2025 23:52:17 GMT; Path=/; SameSite=None; Secure
link: <https://site1.skyscaledev.com/index.php/wp-json/>; rel="https://api.w.org/"
x-litespeed-cache-control: public,max-age=604800
x-litespeed-tag: 00f_home,00f_URL.6666cd76f96956469e7be39d750cc7d9,00f_F,00f_
server: LiteSpeed
```


# Vérifier les prérequis
check_requirements

# Installer les dépendances
echo "Installation des dépendances..."
sudo apt-get update > /dev/null
sudo apt-get install -y python3-pymysql > /dev/null
