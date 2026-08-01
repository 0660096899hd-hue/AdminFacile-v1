# AdminFacile V2.2

## Fonctions rendues actives

- Dictée vocale depuis l’accueil et depuis le scanner
- Détection automatique d’une langue française installée sur le téléphone
- État du microphone et messages d’erreur visibles
- Déclaration Android complète du service de reconnaissance vocale
- Traduction locale entre français, anglais, arabe, espagnol, allemand, italien et portugais
- Téléchargement automatique des modèles de traduction au premier usage
- Inversion des langues et copie du résultat

## Installation

Remplacer dans le projet :

- `lib/main.dart`
- `pubspec.yaml`
- `android/app/src/main/AndroidManifest.xml`
- `test/widget_test.dart`

Puis supprimer `pubspec.lock` et exécuter :

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d RFCW611W5BE
```

## Test du microphone

Lors du premier appui, accepter l’autorisation du microphone. Si Android indique que la reconnaissance vocale est indisponible, vérifier que l’application Google et les services de reconnaissance vocale Google sont activés et que le français est installé dans les paramètres de saisie vocale.

## Test de traduction

La première traduction nécessite une connexion Internet afin de télécharger les modèles de langue. Les traductions suivantes peuvent fonctionner localement.
