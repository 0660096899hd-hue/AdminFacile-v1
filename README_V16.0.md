# AdminFacile V16.0

## Nouveautés

- Nouveau tableau de bord adaptatif téléphone/tablette, compatible avec les thèmes clair et sombre.
- Salutation personnalisée, état du compte et état de synchronisation Supabase.
- Indicateur vert, orange ou rouge selon les relances et échéances.
- Synthèse « Aujourd’hui », alertes utiles, huit actions rapides et activité récente.
- Accès direct au Profil, aux démarches, aux documents et à l’espace sécurisé existant.
- Aucune analyse Gemini automatique et aucun texte OCR brut sur l’accueil.

## Fichiers modifiés

- `lib/main.dart`
- `test/widget_test.dart`
- `pubspec.yaml`
- `README_V16.0.md`

## Tests exécutés

- `dart format lib/main.dart test/widget_test.dart`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`

Résultats de la validation finale :

- Formatage : `Formatted 2 files (0 changed)` lors du contrôle final.
- Analyse : `No issues found! (ran in 15.6s)`.
- Tests : `+19: All tests passed!`.
- APK debug : `√ Built build\app\outputs\flutter-apk\app-debug.apk`.

## Points à vérifier sur téléphone

- Lisibilité et défilement sur petit écran en modes clair et sombre.
- Passage direct du bouton Profil vers l’onglet Profil.
- Ouverture de chaque action rapide, notamment l’espace sécurisé Supabase.
- Mise à jour des compteurs après ajout ou modification d’une démarche ou d’un document.
- Couleurs de vigilance avec une relance aujourd’hui, dans les sept jours et une échéance documentaire.
- Comportement hors connexion puis après reconnexion et synchronisation Supabase.
- Scanner/OCR, microphone, traduction, génération PDF et partage avec les autorisations Android réelles.
