# Acrypcom

Messagerie chiffrée de bout en bout. Serveur Python + Client Flutter.

## Structure

```
acrypcom/
├── server/          # Serveur Python (FastAPI + WebSocket)
│   ├── main.py
│   ├── database.py
│   ├── security.py
│   ├── sockets.py
│   └── requirements.txt
├── app/             # Client Flutter (Android)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── crypto/         # Chiffrement X25519 + AES-GCM
│   │   ├── data/           # API, WebSocket, DB, Notifications
│   │   └── presentation/   # UI (login, chat, profil, accueil)
│   ├── android/
│   └── pubspec.yaml
├── .gitignore
└── README.md
```

## Démarrage rapide

### 1. Serveur

```bash
cd server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Le serveur écoute sur `http://0.0.0.0:8000`.

### 2. Application mobile

```bash
cd app
flutter pub get
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### 3. Utilisation

1. Ouvrez l'app
2. Cliquez sur "Configuration Serveur Local"
3. Entrez l'IP du serveur : `IP_DU_SERVEUR:8000`
4. Créez un compte
5. Recherchez un utilisateur et démarrez une conversation

## Sécurité

- Chiffrement E2EE : X25519 + AES-GCM 256
- Clé unique par message (dérivation HKDF)
- Rotation de clés toutes les 60s
- Anti-rejeu (UUID + timestamp)
- Padding aléatoire sur les payloads
- Mots de passe hachés avec PBKDF2-SHA256 + sel
- Aucune donnée personnelle requise
