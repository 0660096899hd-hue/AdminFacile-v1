# AdminFacile V19.0 — Nouveau Scanner Professionnel

Version : `19.0.0+73`

## Ancien moteur

La V18.1.1 utilisait une activité CameraX propre à AdminFacile. Son
`EdgeDetector.detect()` sélectionnait quatre extrêmes parmi les gradients de la
frame. `DocumentOverlay` dessinait le cadre et `PerspectiveCropper` appliquait
une matrice à partir des coordonnées d’aperçu.

Ce moteur ne recherchait pas un contour documentaire fermé et ne redétectait
pas les bords sur une image haute résolution. Il pouvait sélectionner le bord
d’une table, du texte ou un objet en arrière-plan. Il a été entièrement retiré,
ainsi que ses dépendances CameraX directes et ses tests géométriques parallèles.

## Nouveau moteur Android

Android utilise directement Google ML Kit Document Scanner
`play-services-mlkit-document-scanner:16.0.0`, en mode
`SCANNER_MODE_FULL`.

ML Kit prend en charge localement :

- l’aperçu caméra ;
- la détection des bords et des quatre coins ;
- la capture automatique ;
- le recadrage et la perspective ;
- la validation et le recadrage manuels ;
- les filtres natifs ;
- le multipage jusqu’à dix pages.

AdminFacile demande des résultats JPEG et copie immédiatement chaque image
validée dans son cache privé. Si une copie échoue après plusieurs pages, les
pages déjà copiées sont retournées comme résultat partiel au lieu d’être
perdues.

## Architecture

L’écran Flutter dépend uniquement de l’interface `DocumentScannerService`.
L’implémentation actuelle est `AndroidMlKitDocumentScannerService`, connectée au
canal `adminfacile/mlkit_document_scanner`.

Une future implémentation `IosVisionKitDocumentScannerService` pourra respecter
la même interface sans modifier `ScannerScreen`. iOS n’est pas implémenté dans
cette version.

## Pipeline avant/après

Avant :

`JPEG → PDF → raster PNG → JPEG → second PDF → raster OCR`

V19.0 :

`ML Kit → JPEG corrigé → OCR direct sur JPEG → PDF final direct`

Le scan ML Kit ne passe plus par `Printing.raster`. Les octets JPEG validés sont
placés directement dans `ScannerProcessingService.buildA4Pdf()`. Le PDF importé
conserve son parcours OCR historique, qui reste distinct du nouveau scanner.

## Qualité d’image

ML Kit `SCANNER_MODE_FULL` expose ses corrections et filtres dans l’interface
native. Les quatre rendus simples conservés côté AdminFacile sont Original,
Document, Noir et blanc et Couleur améliorée.

Le résultat ML Kit est utilisé en mode Original par défaut, sans réencodage.
Les réglages Dart secondaires ont été adoucis afin de limiter les blancs brûlés
et la perte des petits caractères.

## Interface

Avant le scan, l’écran conserve uniquement Scanner, Photo et Importer.

Après le scan :

- `PDF prêt • X pages` ;
- bouton Ouvrir ;
- menu contenant Ajouter à Mes documents, Transmettre et Imprimer.

Les puces de filtre, Réinitialiser, Rotation et Valider de l’ancien moteur ont
été retirées : ces opérations sont déjà proposées dans l’interface native ML
Kit avant le retour vers AdminFacile.

## Gestion des erreurs

Une indisponibilité, une réponse vide ou une erreur ML Kit affiche uniquement :

« Le scanner professionnel est momentanément indisponible. Vous pouvez utiliser
Photo simple ou Importer. »

L’ancien PDF affiché n’est pas effacé avant qu’un nouveau scan ait réussi.
L’annulation est traitée sans erreur.

## Composants retirés

- `ProfessionalScannerActivity.kt` ;
- `EdgeDetector` ;
- `PerspectiveCropper` ;
- `DocumentOverlay` ;
- `lib/document_edge_geometry.dart` ;
- canal `adminfacile/professional_scanner` ;
- dépendances CameraX et ExifInterface directes ;
- permission caméra déclarée par l’application pour cet ancien moteur.

Il n’existe plus deux moteurs scanner actifs en parallèle.

## Fichiers modifiés

- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/example/admin_facile/MainActivity.kt`
- `lib/document_scanner_service.dart`
- `lib/main.dart`
- `lib/scanner_processing_service.dart`
- `pubspec.yaml`
- `test/document_scanner_service_test.dart`
- `test/widget_test.dart`
- `README_V19.0.md`

Fichiers supprimés :

- `android/app/src/main/kotlin/com/example/admin_facile/ProfessionalScannerActivity.kt`
- `lib/document_edge_geometry.dart`

Les clés API, les données utilisateur, l’authentification, Gemini et les
générateurs de lettres PDF n’ont pas été modifiés.

## Tests automatisés

- ML Kit est le moteur Android principal ;
- l’ancien moteur et son canal sont absents ;
- retour JPEG multipage ;
- annulation sans erreur ;
- fallback avec message non technique ;
- rejet d’un résultat vide ;
- conservation du document précédent en cas d’échec ;
- OCR direct sur les images finales ;
- génération PDF directe ;
- quatre rendus simples ;
- écran scanner compact sans overflow ;
- régression complète de l’application.

## Validations

- `dart format` : réussi, tous les fichiers Dart concernés sont formatés ;
- `flutter analyze` : réussi, `No issues found!` ;
- `flutter test` : réussi, 90 tests réussis ;
- `flutter build apk --debug` : réussi, APK debug généré ;
- installation ADB sur le Galaxy Z Fold5 `RFCW611W5BE` : réussie ;
- lancement de l’application sur le Galaxy Z Fold5 : réussi.

Chemin APK généré :
`C:\Users\dhibi\Documents\admin_facile_v1\build\app\outputs\flutter-apk\app-debug.apk`

## Limitations connues et tests manuels

ML Kit Document Scanner dépend des composants Google Play Services disponibles
sur l’appareil. Le premier lancement peut télécharger le module scanner. Les
appareils Android sans Google Play Services doivent utiliser Photo simple ou
Importer.

Tester sur Galaxy Z Fold5 fermé et téléphone Android classique, en portrait et
paysage : feuille blanche, facture, courrier, reçu, ombre, fond clair et fond
sombre. Vérifier aussi 1 à 10 pages, annulation, recadrage manuel, chaque filtre
natif, OCR, PDF, Mes documents, partage, impression et synchronisation Supabase.
