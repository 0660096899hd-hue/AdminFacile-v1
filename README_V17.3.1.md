# AdminFacile V17.3.1

Version : `17.3.1+63`

## Cause de la régression

Les cartes de modèles de la recherche globale et de la section Favoris ouvraient directement `JsonLibraryScreen`. Le modèle sélectionné n'était donc pas transmis à la route suivante : son identifiant et ses données étaient perdus, et l'utilisateur retrouvait la liste complète des 542 modèles. Dans la bibliothèque, l'ouverture sautait par ailleurs l'étape d'aperçu en allant directement au formulaire.

## Correction appliquée

- Ajout de `LetterModelDetailScreen`, alimenté par le `JsonLetterRecord` exact sélectionné et donc par son identifiant unique.
- Les résultats de recherche, Favoris et Historique ouvrent désormais directement cet aperçu.
- Le bouton **Utiliser ce modèle** ouvre le formulaire avec le titre, l'objet, l'organisme, la catégorie, le corps et les champs à compléter préremplis.
- Le retour ferme uniquement l'aperçu : l'écran de recherche et son contrôleur restent en mémoire, ce qui conserve la requête saisie.
- La bibliothèque reste locale et n'est pas téléchargée à chaque ouverture.
- Le libellé **Hors ligne** est remplacé par **Disponible hors connexion**, avec l'icône `offline_bolt_outlined` et l'explication : « Les modèles sont disponibles même sans connexion Internet. »
- Les états Gemini et Supabase sont présentés séparément de la disponibilité locale des modèles.

## Fichiers modifiés

- `lib/main.dart`
- `pubspec.yaml`
- `test/widget_test.dart`
- `README_V17.3.1.md`

Le répertoire de travail contient aussi des changements non validés issus des versions précédentes, notamment `lib/main_backup.dart` et les README V17.1 à V17.3. Ils ont été conservés et aucun commit ni push n'a été effectué.

## Tests ajoutés ou adaptés

- Recherche « facture EDF » : ouverture directe de `v173_edf_invoice_dispute`.
- Recherche « résilier Orange » : ouverture directe du modèle choisi.
- Vérification qu'aucun résultat ne pousse `JsonLibraryScreen` par erreur.
- Retour depuis l'aperçu avec conservation de « facture EDF ».
- Ouverture directe depuis Favoris et Historique.
- Absence du libellé « Hors ligne » et présence de « Disponible hors connexion » et de son icône.

## Validations

- `dart format lib/main.dart test/widget_test.dart` : réussi, 2 fichiers formatés.
- `flutter analyze` : `No issues found!`
- `flutter test` : `57 tests passed`.
- `flutter build apk --debug` : réussi, `Built build\app\outputs\flutter-apk\app-debug.apk`.

## Tests à effectuer sur téléphone

1. Rechercher « facture EDF », ouvrir **Contester une facture EDF**, vérifier l'aperçu puis **Utiliser ce modèle**.
2. Vérifier dans le formulaire le titre, l'objet, EDF, la catégorie, le corps et les champs à compléter, puis ouvrir l'aperçu final.
3. Revenir depuis l'aperçu du modèle et confirmer que « facture EDF » est toujours saisi et que les résultats sont conservés.
4. Rechercher « résilier Orange » et vérifier que le modèle touché est bien celui qui s'ouvre, sans passage par la bibliothèque complète.
5. Ajouter un modèle aux favoris, l'ouvrir depuis Favoris, puis répéter depuis Récents.
6. Passer le téléphone hors connexion et vérifier que la bibliothèque locale reste disponible sans message d'erreur réseau.
7. Contrôler les indicateurs Gemini et Supabase séparément, en ligne puis hors connexion.
8. Vérifier les mêmes parcours en thème clair et sombre, sur Galaxy Z Fold5 fermé.

## APK

Chemin attendu après construction :

`C:\Users\dhibi\Documents\admin_facile_v1\build\app\outputs\flutter-apk\app-debug.apk`
