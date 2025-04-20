
---

### ✅ **Prérequis avant d’ajouter l’email**
1. **Domaine enregistré** : tu dois posséder `example.com`
2. **Accès à la gestion DNS** : chez ton registrar (Gandi, OVH, Cloudflare, etc.)
3. **Mailcow installé et fonctionnel** : accessible via une IP publique ou un nom de domaine (par exemple `mail.example.com`)
4. **Certificat SSL valide** (Mailcow le fait avec Let's Encrypt)

---

### 📦 Étapes pour créer l’adresse `contact@example.com`

#### 1. **Accède à l’interface d’administration Mailcow**
- URL : `https://<ton-serveur-mail>`
- Connecte-toi avec le compte admin créé à l’installation

#### 2. **Ajoute le domaine `example.com`**
- Va dans **"Configuration" > "Domaines de mail"**
- Clique sur **"Ajouter un domaine"**
  - Domaine : `example.com`
  - Quota : par ex. 1 Go ou illimité
  - Active DKIM (recommandé)
  - Active l’antispam et antivirus

#### 3. **Ajoute l’utilisateur (l’adresse mail)**
- Va dans **"Utilisateurs" > "Ajouter un utilisateur"**
  - Adresse email : `contact@example.com`
  - Mot de passe : crée-en un fort ou génère-le
  - Quota personnalisé (ou celui du domaine)
  - Alias, redirections si tu veux

#### 4. **Configure les enregistrements DNS pour le domaine**
Ajoute les entrées suivantes chez ton registrar :

```txt
# Pour recevoir des mails
MX  @     mail.example.com.    (priorité 10)

# Pour l’authentification (envois sûrs)
A   mail  <IP de ton serveur>
AAAA mail  <IPv6 si dispo>
TXT @     "v=spf1 mx ~all"

# DKIM (généré par Mailcow dans l'interface)
TXT  dkim._domainkey.example.com  "v=DKIM1; k=rsa; p=..."

# DMARC
TXT _dmarc.example.com  "v=DMARC1; p=quarantine; rua=mailto:postmaster@example.com"
```

#### 5. **Tester l’envoi/réception**
- Connecte-toi sur le webmail intégré (SoGo) via `https://mail.example.com/SOGo`
- Ou configure ton client (Thunderbird, Outlook, etc.) avec :
  - **IMAP** : `mail.example.com`, port 993, SSL
  - **SMTP** : `mail.example.com`, port 587, STARTTLS

---

### 🧪 Astuces et vérifications
- Teste ton setup avec [https://www.mail-tester.com](https://www.mail-tester.com)
- Vérifie que tu n’es pas en blacklist : [https://mxtoolbox.com/blacklists.aspx](https://mxtoolbox.com/blacklists.aspx)
- Regarde les logs dans Mailcow si un message n’arrive pas

---

Si tu veux, je peux t’aider à configurer les DNS ou t’envoyer un exemple concret de configuration selon ton registrar. Tu l’as chez qui, ton domaine ?