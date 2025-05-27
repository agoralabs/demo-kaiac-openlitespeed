Pour installer Node.js version 16 sur Ubuntu, vous pouvez suivre ces étapes :

### Méthode 1 : Utiliser les dépôts NodeSource (recommandé)
1. **Ajoutez le dépôt NodeSource** pour Node.js 16 :
   ```bash
   curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
   ```

2. **Installez Node.js et npm** :
   ```bash
   sudo apt-get install -y nodejs
   ```

3. **Vérifiez l'installation** :
   ```bash
   node --version  # Doit afficher v16.x.x
   npm --version   # Vérifie aussi npm
   ```

---

### Méthode 2 : Utiliser `nvm` (pour gérer plusieurs versions)
1. **Installez `nvm`** (Node Version Manager) :
   ```bash
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
   ```
   Fermez et rouvrez votre terminal ou exécutez :
   ```bash
   source ~/.bashrc  # Ou ~/.zshrc selon votre shell
   ```

2. **Installez Node.js 16** :
   ```bash
   nvm install 16
   ```

3. **Vérifiez la version** :
   ```bash
   node --version
   ```

---

### Méthode 3 : Via `apt` (version souvent plus ancienne)
Si vous préférez utiliser les dépôts par défaut d'Ubuntu (peut ne pas fournir la dernière version 16) :
```bash
sudo apt update
sudo apt install nodejs npm
node --version  # Peut afficher une version inférieure à 16
```

---

### Notes :
- **NodeSource** est recommandé pour obtenir la dernière version stable de Node.js 16.
- **`nvm`** est idéal si vous avez besoin de basculer entre plusieurs versions de Node.js.
- Pour **les dépendances build**, installez éventuellement :
  ```bash
  sudo apt install build-essential
  ```

Si vous rencontrez des problèmes, vérifiez les erreurs spécifiques ou les conflits de versions existantes.



Pour installer Redis sur Ubuntu, suivez ces étapes :

### 1. **Mettez à jour les paquets**
   ```bash
   sudo apt update
   sudo apt upgrade -y
   ```

### 2. **Installez Redis**
   ```bash
   sudo apt install redis-server -y
   ```

### 3. **Vérifiez que Redis est actif**
   ```bash
   sudo systemctl status redis-server
   ```
   - Si Redis n'est pas actif, démarrez-le avec :
     ```bash
     sudo systemctl start redis-server
     ```
   - Pour l'activer au démarrage :
     ```bash
     sudo systemctl enable redis-server
     ```

### 4. **Testez Redis**
   - Connectez-vous à Redis via la CLI :
     ```bash
     redis-cli
     ```
   - Testez avec une commande simple :
     ```redis
     ping
     ```
     (Réponse attendue : `"PONG"`)

### 5. **Configuration (optionnel)**
   - Modifiez le fichier de configuration si nécessaire :
     ```bash
     sudo nano /etc/redis/redis.conf
     ```
   - Par exemple, pour accepter les connexions distantes, remplacez :
     ```
     bind 127.0.0.1
     ```
     par :
     ```
     bind 0.0.0.0
     ```
     *(Attention : cela expose Redis sur le réseau, protégez-le avec un mot de passe dans `requirepass` et un pare-feu)*.

   - Redémarrez Redis après les modifications :
     ```bash
     sudo systemctl restart redis-server
     ```

### 6. **Sécurisation (recommandé)**
   - Ajoutez un mot de passe dans `/etc/redis/redis.conf` :
     ```
     requirepass votre_mot_de_passe
     ```
   - Protégez le port avec un pare-feu (UFW) :
     ```bash
     sudo ufw allow from votre_ip to any port 6379
     sudo ufw enable
     ```

### 7. **Désinstallation (si besoin)**
   ```bash
   sudo apt remove redis-server -y
   sudo apt autoremove -y
   ```

Redis est maintenant installé et fonctionnel sur votre Ubuntu ! 🚀