# AdminFacile V15.3 — Comptes et espace sécurisé

Cette version ajoute une première bêta de stockage utilisateur Firebase :

- création de compte par e-mail et mot de passe ;
- connexion et déconnexion ;
- session conservée localement ;
- envoi volontaire d'un PDF vers `users/<uid>/documents/` ;
- liste, téléchargement et suppression des documents cloud ;
- aucun envoi automatique pendant les tests.

## Configuration Firebase obligatoire

1. Créez ou ouvrez un projet dans la console Firebase.
2. Dans **Authentication > Sign-in method**, activez **E-mail/Mot de passe**.
3. Dans **Storage**, créez le bucket.
4. Copiez le contenu du fichier `storage.rules` dans les règles Storage et publiez-les.
5. Récupérez :
   - la clé API Web du projet ;
   - le nom exact du bucket, par exemple `mon-projet.firebasestorage.app` ou `mon-projet.appspot.com`.

## Lancement

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d RFCW611W5BE `
  --dart-define=GEMINI_API_KEY=VOTRE_CLE_GEMINI `
  --dart-define=FIREBASE_API_KEY=VOTRE_CLE_FIREBASE `
  --dart-define=FIREBASE_STORAGE_BUCKET=VOTRE_BUCKET
```

Sans ces deux valeurs Firebase, l'application compile et affiche « Firebase à configurer », mais la création de compte et le cloud restent désactivés.

## Test conseillé

1. Profil > Créer un compte.
2. Mes documents > choisir un document PDF > icône cloud.
3. Ouvrir « Mon espace sécurisé ».
4. Vérifier la présence du document.
5. Tester le téléchargement puis la suppression.

## Sécurité

Chaque utilisateur ne peut accéder qu'au chemin correspondant à son propre UID. La limite de fichier définie dans les règles est de 20 Mo.
