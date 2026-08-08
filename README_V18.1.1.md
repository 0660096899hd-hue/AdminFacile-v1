# AdminFacile V18.1.1 — Détection professionnelle des bords

Version : `18.1.1+71`

## Audit et cause du cadre instable

Avant cette version, `ScannerScreen.scanA4()` appelait
`FlutterDocScanner.getScannedDocumentAsPdf()`. Sur Android, le plugin ouvrait
`GmsDocumentScanning.getClient()` avec `SCANNER_MODE_FULL`. La caméra, le cadre
bleu, les coins, la capture, le recadrage et la perspective appartenaient tous à
l'activité fermée de Google ML Kit.

ML Kit ne transmettait à Flutter que le PDF terminé : aucune frame, aucun coin,
aucun score de confiance et aucun seuil n'étaient accessibles. L'instabilité ne
pouvait donc pas être corrigée dans AdminFacile et dépendait entièrement des
heuristiques internes du service Google sur l'appareil.

## Nouveau moteur et chemin d'exécution

Le scanner utilise maintenant une activité Android propre à AdminFacile :

`ScannerScreen.scanA4()` → canal `adminfacile/professional_scanner` →
`ProfessionalScannerActivity` → CameraX Preview/ImageAnalysis →
`EdgeDetector.detect()` → `updateDetection()` → `DocumentOverlay` →
ImageCapture haute résolution → `PerspectiveCropper.crop()` → écran manuel →
`ScannerProcessingService.buildA4Pdf()` → OCR/aperçu/partage/impression.

Le plugin `flutter_doc_scanner` a été retiré. Il n'existe plus de scanner caméra
parallèle.

## Détection et seuils

- analyse du plan de luminance YUV, sans copie RGB pour l'aperçu ;
- fréquence limitée à 8 analyses par seconde (intervalle 125 ms) ;
- gradients horizontaux et verticaux échantillonnés tous les 8 pixels ;
- seuil de bord : gradient supérieur à 42 ;
- sélection des extrêmes puis remise en ordre haut-gauche, haut-droite,
  bas-droite, bas-gauche ;
- surface minimale normalisée : 12 % de l'image ;
- coins obligatoirement entre 1 et 99 % de l'image ;
- rejet des quadrilatères concaves ou croisés ;
- rapport largeur/hauteur accepté : 0,18 à 5,5, couvrant A4, A5 et tickets ;
- rejet des côtés opposés dont la proportion est inférieure à 35 %.

## Stabilisation et capture automatique

Les coins sont lissés selon `ancien × 0,75 + nouveau × 0,25`. Les variations
inférieures à 1,2 % entrent dans une zone morte. La stabilité exige des
déplacements inférieurs à 0,8 %, maintenus pendant 500 ms.

Le cadre est orange pendant la recherche et bleu quand le document est stable.
Les messages courts sont : Cherchez le document, Rapprochez-vous, Améliorez
l'éclairage, Ne bougez plus et Document détecté.

La capture automatique est activée par défaut, mémorisée localement et peut être
désactivée avec l'interrupteur « Capture automatique ». La capture manuelle reste
toujours disponible.

## Haute résolution, perspective et repli manuel

Après capture, les coordonnées normalisées sont appliquées à l'image JPEG haute
résolution, et non à une frame d'aperçu. `Matrix.setPolyToPoly()` réalise la
correction de perspective. La marge de sécurité est limitée à 1,5 %.

L'original est toujours conservé dans le cache. Chaque capture ouvre l'écran de
contrôle avec quatre poignées tactiles, Réinitialiser, Rotation 90° et Valider.
Si aucune détection n'est fiable, des coins sûrs à 5 % sont proposés avec le
message « Le document a été capturé. Ajustez les coins si nécessaire. » : la
création du PDF n'est jamais bloquée.

Le multipage est conservé avec « Ajouter une page » ou « Terminer », jusqu'à dix
pages dans le pipeline Flutter existant.

## Traitement de l'image

Le filtre initial est Couleur afin de préserver un rendu naturel et d'éviter la
suraccentuation. Les filtres professionnels V18.1 restent disponibles après la
capture. Les traitements lourds et la perspective sont exécutés hors du thread
UI ; CameraX conserve uniquement la dernière frame d'analyse.

## Fichiers modifiés pour V18.1.1

- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/example/admin_facile/MainActivity.kt`
- `android/app/src/main/kotlin/com/example/admin_facile/ProfessionalScannerActivity.kt`
- `lib/main.dart`
- `lib/document_edge_geometry.dart`
- `pubspec.yaml`
- `pubspec.lock`
- `test/widget_test.dart`
- `linux/flutter/generated_plugin_registrant.cc`
- `linux/flutter/generated_plugins.cmake`
- `macos/Flutter/GeneratedPluginRegistrant.swift`
- `windows/flutter/generated_plugin_registrant.cc`
- `windows/flutter/generated_plugins.cmake`
- `README_V18.1.1.md`

Les autres changements déjà présents dans le dépôt ont été conservés.

## Tests automatisés

- quadrilatère valide ;
- rejet des coins croisés ;
- rejet d'une surface trop petite ;
- lissage temporel 75/25 ;
- stabilité après plusieurs frames proches ;
- prise en compte d'un déplacement réel ;
- marge finale limitée à 1,5 % ;
- repli manuel et absence de blocage ;
- conservation des tests scanner/PDF V18.1 et de toute la suite historique.

## Validations

- `dart format` : réussi ;
- `flutter analyze` : `No issues found!` ;
- `flutter test` : 78 tests réussis ;
- `flutter build apk --debug` : réussi.

APK :
`C:\Users\dhibi\Documents\admin_facile_v1\build\app\outputs\flutter-apk\app-debug.apk`

La compilation affiche uniquement l'avertissement non bloquant déjà connu sur
la future migration Built-in Kotlin de plusieurs plugins tiers.

## Tests manuels requis

Sur Galaxy Z Fold5 fermé puis sur un Android milieu de gamme, vérifier en portrait
et paysage : table claire, table sombre, faible lumière, ombre latérale, feuille
A4/A5 inclinée ou légèrement froissée, ticket, arrière-plan chargé, capture
automatique activée/désactivée, déplacement des quatre poignées, rotation,
multipage, PDF, OCR, partage et impression.
