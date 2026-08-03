# AdminFacile V17.0.1

Version : `17.0.1+57`

## Causes des régressions

- Signature : plusieurs parcours construisaient leur PDF séparément et certains ne recevaient ni le choix de la lettre ni l’image enregistrée dans le Profil.
- Aperçu : l’action de Mes documents appelait directement `Printing.layoutPdf`, ce qui ouvrait l’interface d’impression Android au lieu d’une vue interne.
- Cloud : l’action dépendait de la présence d’un fichier et l’état local ne distinguait pas l’échec d’un document non synchronisé.

## Corrections

- `LetterSignatureService` centralise la valeur par défaut, le chargement non déformé de l’image et la composition PDF. Le booléen `signed` reste migrable avec `false` pour les anciennes démarches.
- Les parcours Gemini, modèles et aperçu exposent « Ajouter ma signature à cette lettre ». Une signature absente renvoie vers Profil > Ma signature.
- Les aperçus PDF/images s’ouvrent dans `InternalDocumentPreviewScreen`. Partager, Télécharger et Imprimer sont explicites ; une image est zoomable et n’est jamais imprimée automatiquement.
- Les cartes démarches et documents conservent un bouton cloud visible avec les états non synchronisé, envoi, synchronisé et échec/réessayer. Les envois utilisent `upsert`.
- Le chemin des démarches reste `{userId}/procedures/{procedureId}.pdf` dans le bucket privé `admin-documents`.

## Fichiers modifiés

- `lib/main.dart`
- `lib/letter_signature_service.dart`
- `pubspec.yaml`
- `test/widget_test.dart`
- `README_V17.0.1.md`

## Tests ajoutés/adaptés

- migration des démarches sans champ `signed` ;
- préférence automatique de signature ;
- PDF avec et sans signature ;
- aperçu interne sans impression automatique ;
- quatre états cloud et chemin privé Supabase ;
- widgets sur formats téléphone étroits.

## Test sur téléphone

1. Installer l’APK debug et tester en thème clair puis sombre sur un téléphone étroit, notamment Galaxy Z Fold5 fermé.
2. Enregistrer une signature dans Profil, activer/désactiver l’insertion automatique et vérifier chaque parcours de lettre.
3. Comparer l’éditeur, Ouvrir la lettre, le partage, le PDF local, Mes démarches et le PDF Supabase.
4. Dans Mes documents, ouvrir un PDF puis une image avec Aperçu. Vérifier qu’aucune boîte d’impression ne s’ouvre ; appuyer ensuite volontairement sur Imprimer pour le PDF.
5. Tester hors connexion, fichier supprimé et Réessayer, puis vérifier le nettoyage raisonnable des fichiers temporaires.
6. Tester les boutons cloud connecté/déconnecté et provoquer un échec réseau avant de réessayer.

## APK

`build/app/outputs/flutter-apk/app-debug.apk`
