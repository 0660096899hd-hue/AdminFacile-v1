# AdminFacile V17.0

Version : `17.0.0+56`

## Nouveautés

- Nouvel accueil chaleureux et responsive, inspiré de l'ergonomie historique d'AdminFacile.
- En-tête compact avec identité AdminFacile, notifications utiles et accès direct au Profil.
- Grande carte d'accueil avec les actions « Créer une lettre » et « Scanner un document ».
- Cinq raccourcis principaux : assistant administratif, bibliothèque de modèles, démarches, favoris et historique.
- Affichage de trois démarches récentes au maximum et de compteurs « À ne pas manquer ».
- Gestion complète d'une signature personnelle : dessin tactile, import PNG/JPG/JPEG, aperçu, suppression et insertion automatique facultative.
- Insertion de la signature dans la rédaction, l'aperçu A4, les PDF et les démarches enregistrées.
- Sauvegarde locale et synchronisation privée Supabase sous `{userId}/profile/signature.png` lorsque l'utilisateur est connecté.

## Tableau de bord

Le tableau de bord conserve la navigation et toutes les fonctions existantes. Sa mise en page s'adapte aux téléphones étroits, au Galaxy Z Fold5 fermé, aux tablettes et au mode paysage. Les raccourcis utilisent une rangée de cinq cartes lorsque la largeur le permet et une grille compacte sur écran étroit.

## Signature

La section « Ma signature » se trouve dans Profil. L'insertion automatique est désactivée par défaut. La signature n'est jamais publique et n'est pas écrite dans les logs. Une lettre peut aussi activer ou désactiver la signature individuellement dans l'écran de rédaction.

Formats d'import acceptés : PNG, JPG et JPEG, avec une limite de 5 Mo et un aperçu avant conservation. Le PDF reste au format A4, sur fond blanc et avec texte noir.

## Fichiers modifiés

- `lib/main.dart`
- `lib/signature_pad.dart` (nouveau)
- `pubspec.yaml`
- `test/widget_test.dart`
- `README_V17.0.md` (nouveau)

## Widgets et composants V17

- `LegacyHomeScreen` adapté comme tableau de bord V17.
- `_DarkHeader`, `_DarkHeroCard`, `_ShortcutGrid`, `_DarkShortcut` et `_DarkProcedurePreview` adaptés.
- `SignaturePadScreen` et `SignaturePainter` créés.
- Section « Ma signature » ajoutée au Profil.
- `buildSignedLetterPdf` ajouté pour partager la génération A4 signée entre les aperçus et les démarches.

## Tests effectués

- `dart format lib/main.dart lib/signature_pad.dart test/widget_test.dart`
  - Résultat : `Formatted 3 files (1 changed) in 0.14 seconds.`
- `flutter analyze`
  - Résultat : `No issues found! (ran in 7.3s)`
- `flutter test`
  - Résultat : `00:04 +28: All tests passed!`
- `flutter build apk --debug`
  - Résultat : `√ Built build\app\outputs\flutter-apk\app-debug.apk`
  - Avertissement non bloquant : certains plugins utilisent encore l'ancien mécanisme Kotlin Gradle Plugin et devront être mis à jour avant une future version de Flutter.

## APK

`C:\Users\dhibi\Documents\admin_facile_v1\build\app\outputs\flutter-apk\app-debug.apk`

## Points à vérifier sur téléphone

- Rendu du tableau de bord en mode clair et sombre sur Galaxy Z Fold5 fermé et ouvert.
- Absence de débordement en portrait, paysage, avec grande taille de police et sur tablette.
- Accès direct au Profil depuis l'icône supérieure.
- Ouverture correcte des deux boutons de la carte principale et des cinq raccourcis.
- Affichage des trois démarches les plus récentes, des statuts, dates et relances.
- Tracé au doigt, effacement, annulation et enregistrement de la signature.
- Import réel de fichiers PNG, JPG et JPEG, contrôle de la limite de 5 Mo et suppression.
- Persistance locale de la signature après redémarrage.
- Activation globale et activation par lettre de l'insertion de signature.
- Position, proportions et netteté de la signature dans l'aperçu A4 et le PDF exporté.
- Synchronisation privée Supabase avec un compte connecté, puis comportement hors connexion.
- Conservation du scanner/OCR, Gemini, lettres, démarches, documents, partage, micro, traduction et recherche.

Aucun commit et aucun push n'ont été effectués.
