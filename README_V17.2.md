# AdminFacile V17.2

Version Flutter : `17.2.0+61`.

## Interface simplifiée

- L’accueil conserve les deux actions essentielles : **Créer une lettre** et **Scanner un document**.
- Créer une lettre ouvre un choix simple entre **Générer avec Gemini** et **Utiliser un modèle**.
- Le raccourci Bibliothèque de modèles n’est plus dupliqué sur l’accueil ; les modèles restent accessibles par le choix précédent et le menu latéral.
- Scanner affiche trois commandes : **Scanner**, **Photo** et **Importer**.
- Après création, le PDF affiche uniquement son état, **Ouvrir** et un menu pour l’ajout aux documents, la transmission et l’impression.
- La fiche automatique et le texte OCR ne sont plus affichés par défaut. Ils restent accessibles dans le menu **Analyse avancée** avec la correction manuelle.
- Les cartes Mes documents affichent le nom, la date, Ouvrir/Aperçu et le menu Cloud, Partager, Imprimer, Supprimer.
- Les cartes Mes démarches affichent le titre, le statut, Ouvrir la lettre et le menu Modifier, Cloud, Partager, Télécharger, Supprimer.

## Scan automatique

Le parcours **Scanner** continue d’utiliser `flutter_doc_scanner`, qui assure la détection des bords, le recadrage, le redressement et la correction de perspective avant la création du PDF. L’OCR reste automatique et local. Les couleurs du document sont conservées ; aucun filtre noir et blanc destructif n’est appliqué.

## Fonctionnalités conservées

Les services OCR, analyse locale, correction structurée, génération PDF, partage, impression, stockage local, cloud, Gemini, signature et historique restent présents. Gemini n’est jamais lancé automatiquement après un scan ; l’accès à l’analyse est volontaire et masqué dans Analyse avancée.

## Fichiers modifiés

- `lib/main.dart`
- `pubspec.yaml`
- `test/widget_test.dart`
- `README_V17.2.md`

Les fichiers V17.1, V17.1.1 et V17.1.2 déjà présents sont conservés.

## Tests

- accueil sans doublon Bibliothèque de modèles ;
- choix Gemini/modèle depuis Créer une lettre ;
- Scanner/Photo/Importer ;
- absence de fiche intelligente et de texte OCR visibles par défaut ;
- présence des trois commandes d’Analyse avancée ;
- menus simplifiés des documents et démarches ;
- absence d’overflow sur téléphone étroit ;
- suite complète des tests historiques.

## Tests sur téléphone

1. Sur l’accueil, vérifier Créer une lettre et Scanner un document.
2. Toucher Créer une lettre et tester les deux méthodes.
3. Vérifier l’absence du raccourci Bibliothèque de modèles sur l’accueil.
4. Tester Scanner, Photo et Importer.
5. Après scan, vérifier PDF prêt, Ouvrir et les trois actions du menu.
6. Vérifier que l’OCR et la fiche intelligente ne s’affichent pas automatiquement.
7. Ouvrir Analyse avancée puis tester OCR, analyse et correction.
8. Contrôler les cartes Mes documents et Mes démarches.
9. Refaire les contrôles sur Galaxy Z Fold5 fermé, ouvert, en modes clair, sombre et confort.

## APK

`build/app/outputs/flutter-apk/app-debug.apk`
