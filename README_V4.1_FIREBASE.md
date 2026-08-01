# AdminFacile V4.1 — Comptes et sauvegarde cloud

## Ce qui est ajouté

- Bouton **Se connecter** en haut à droite de l’accueil.
- Création de compte par nom, e-mail et mot de passe.
- Connexion, déconnexion et mot de passe oublié.
- Synchronisation des métadonnées dans Cloud Firestore.
- Sauvegarde des PDF dans Firebase Storage.
- Récupération des documents après connexion sur un autre appareil.
- Fonctionnement local conservé lorsque l’utilisateur n’est pas connecté.

## Configuration Firebase obligatoire une seule fois

La V4.1 utilise Firebase. Le code ne peut pas connaître à l’avance l’identifiant de votre projet Firebase. Il faut donc relier l’application à votre propre projet.

### 1. Installer les outils

Dans PowerShell :

```powershell
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
```

Si la commande `flutterfire` n’est pas reconnue, ajoutez ce dossier au PATH Windows :

```text
%LOCALAPPDATA%\Pub\Cache\bin
```

### 2. Créer et relier le projet

Depuis le dossier du projet Flutter :

```powershell
flutter pub get
flutterfire configure
```

Sélectionnez au minimum **Android**. Vous pouvez aussi sélectionner **Windows** et **Web** si vous souhaitez les utiliser plus tard.

### 3. Activer les services dans la console Firebase

Dans **Authentication > Sign-in method**, activez **E-mail/Mot de passe**.

Créez ensuite :

- une base **Cloud Firestore** ;
- un espace **Firebase Storage**.

### 4. Installer les règles de sécurité

Copiez le contenu de `firestore.rules` dans les règles Firestore, puis publiez-les.

Copiez le contenu de `storage.rules` dans les règles Storage, puis publiez-les.

Ces règles empêchent un utilisateur d’accéder aux documents d’un autre compte.

### 5. Tester

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d RFCW611W5BE
```

## Test sur deux appareils

1. Créez un compte sur le premier téléphone.
2. Scannez un document et ajoutez-le à **Mes documents**.
3. Déconnectez-vous.
4. Sur un second appareil, installez la même application configurée avec le même projet Firebase.
5. Connectez-vous avec le même e-mail et le même mot de passe.
6. Le document doit apparaître dans **Mes documents**.

## Confidentialité

Les documents sont protégés par les règles du compte Firebase et stockés dans le cloud. Cette version n’ajoute pas encore de chiffrement de bout en bout avec une clé détenue uniquement par l’utilisateur. N’utilisez pas encore cette version de test pour des documents extrêmement sensibles sans politique de confidentialité, gestion des consentements et audit de sécurité.
