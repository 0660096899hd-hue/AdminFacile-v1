# AdminFacile V17.1.1

Version Flutter : `17.1.1+59`.

## Écrans simplifiés

- Scanner, état PDF prêt : **Ouvrir** reste visible. Enregistrer, Ajouter à Mes documents, Transmettre et Imprimer sont dans le menu `⋮`.
- Scanner, fiche intelligente : **Corriger** et **Améliorer avec Gemini** restent visibles. Les actions adaptées au document sont dans le menu `⋮`.
- Coffre-fort documentaire / Mes documents : **Ouvrir** ou **Aperçu** reste visible. Cloud, Télécharger, Modifier les informations, Partager, Imprimer et Supprimer sont dans le menu `⋮`.
- Mes démarches : **Ouvrir la lettre** reste visible. Modifier le suivi, Synchroniser dans le cloud, Télécharger, Partager, Imprimer, Archiver/Désarchiver et Supprimer sont dans le menu `⋮`.

Les séparateurs placent les suppressions en fin de menu. Les états cloud restent visibles sous une forme discrète (progression, coche verte ou erreur). L’aperçu reste interne et ne déclenche jamais l’impression ; celle-ci ne démarre qu’après sélection volontaire de **Imprimer**.

## Accessibilité et écrans étroits

Les menus utilisent l’icône Material 3 `more_vert_rounded` et le tooltip **Plus d’actions**. Les actions principales disposent des tooltips Ouvrir, Aperçu, Corriger et Améliorer avec Gemini. Les actions Scanner utilisent `Wrap`. Les filtres du coffre-fort s’empilent sous 420 px pour éviter les débordements sur téléphone étroit et Galaxy Z Fold5 fermé.

## Fichiers modifiés

- `lib/main.dart`
- `pubspec.yaml`
- `test/widget_test.dart`
- `README_V17.1.1.md`

Les modifications V17.1 déjà présentes dans `README_V17.1.md` sont conservées.

## Tests ajoutés

- présence de toutes les actions du PDF prêt et de la fiche intelligente ;
- visibilité de Corriger, Améliorer avec Gemini et des menus Scanner ;
- carte Mes documents : Aperçu, menu complet et absence d’overflow à 320 px ;
- carte Mes démarches : Ouvrir la lettre et menu complet ;
- maintien des tests antérieurs Scanner, OCR, signature, cloud, aperçu interne et migration.

## Tests sur téléphone

1. Sur Scanner, créer un PDF puis vérifier la ligne PDF prêt, Ouvrir et les quatre entrées du menu.
2. Vérifier qu’ouvrir le menu ne lance pas l’impression ; sélectionner Imprimer volontairement.
3. Après OCR, vérifier Corriger, Améliorer avec Gemini et toutes les actions secondaires du menu.
4. Dans Mes documents, tester Aperçu interne puis Cloud, Télécharger, Modifier, Partager, Imprimer et Supprimer.
5. Vérifier les états cloud discret : en cours, synchronisé vert et erreur/réessai.
6. Dans Mes démarches, tester Ouvrir la lettre et chaque entrée du menu, dont Archiver/Désarchiver.
7. Refaire les contrôles en mode clair, sombre et confort, sur Galaxy Z Fold5 fermé puis ouvert.
8. Vérifier qu’aucun libellé, filtre, bouton ou menu ne déborde.

## APK

Après validation : `build/app/outputs/flutter-apk/app-debug.apk`.
