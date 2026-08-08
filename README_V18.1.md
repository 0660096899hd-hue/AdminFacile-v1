# AdminFacile V18.1 — Scanner professionnel

Version : `18.1.0+71`

## Architecture retenue

Le parcours existant reste l'unique scanner. `ScannerScreen.scanA4()` ouvre
`flutter_doc_scanner`, dont l'implémentation Android utilise Google ML Kit en
mode `SCANNER_MODE_FULL`. Ce mode fournit sur l'appareil la détection des quatre
coins, le recadrage rapproché, la correction de perspective et l'écran natif de
correction avec poignées, réinitialisation, rotation et validation. Il inclut
également les corrections documentaires natives (ombres, taches et éléments
parasites selon les capacités de l'appareil).

Aucun second moteur de capture ou générateur PDF parallèle n'a été ajouté.
AdminFacile applique ensuite son rendu professionnel dans
`ScannerProcessingService`, avant l'OCR, l'aperçu, l'archivage, le partage et
l'impression.

## Traitements et filtres

Les cinq modes sont disponibles immédiatement après la capture :

- Couleur : rendu fidèle à la capture ;
- Couleur améliorée : contraste, saturation et luminosité équilibrés ;
- Noir et blanc : normalisation puis seuillage haute lisibilité ;
- Document : niveaux normalisés, gris, contraste et luminosité renforcés ;
- Photo : correction douce respectant les couleurs.

La rotation s'effectue par quarts de tour sans étirement. Le bouton
Réinitialiser restaure le mode Document et l'orientation d'origine. Le bouton
Valider confirme le rendu courant. Le nombre de pages et la première page
traitée sont visibles dans l'aperçu.

## Qualité, PDF et performances

- Rasterisation à 170 DPI pour préserver la lisibilité du texte.
- Largeur de traitement plafonnée à 2 400 pixels pour maîtriser la mémoire sur
  les téléphones Android de milieu de gamme.
- Traitement d'image exécuté dans un isolate afin de ne pas bloquer l'interface.
- JPEG qualité 92 pour un compromis lisibilité/taille adapté aux documents.
- PDF A4 avec 18 points de marge régulière et image centrée en conservant son
  ratio.
- Maximum de 10 pages, cohérent avec le scanner et le parcours OCR existants.
- Les fichiers de travail sont placés dans le cache temporaire. Seule l'action
  d'archivage copie le PDF final dans le stockage durable de l'application.

## Compatibilité Android

Le PDF retourné par ML Kit peut être une URI Android `content://`. Le canal
`adminfacile/content_uri` la copie désormais de façon contrôlée dans le cache
privé de l'application avant traitement. La destination est validée pour rester
dans l'espace privé de l'application.

## Fichiers modifiés pour la V18.1

- `lib/main.dart`
- `lib/scanner_processing_service.dart`
- `android/app/src/main/kotlin/com/example/admin_facile/MainActivity.kt`
- `test/widget_test.dart`
- `pubspec.yaml`
- `README_V18.1.md`

Le dépôt comportait déjà d'autres modifications non commitées liées aux versions
précédentes ; elles ont été conservées.

## Tests automatisés

- géométrie conservée par les cinq filtres ;
- rotation à 90 degrés ;
- génération d'un PDF A4 multipage ;
- présence des cinq filtres et des commandes Réinitialiser, Rotation 90° et
  Valider dans le parcours réel ;
- utilisation du raster 170 DPI, du générateur A4 unique et de la copie privée
  des URI Android.

## Tests manuels à effectuer sur téléphone

Pour chaque cas, vérifier la détection des quatre coins, déplacer une poignée,
réinitialiser, tourner, valider, comparer les cinq filtres, puis archiver,
partager et imprimer le PDF :

1. feuille blanche sur table claire puis foncée ;
2. facture avec petits caractères ;
3. courrier A4 et feuille proche du format A5 ;
4. reçu étroit ;
5. document avec ombre latérale ;
6. document légèrement incliné ;
7. document couleur ou photo ;
8. scan multipage jusqu'à 10 pages ;
9. essai sur un téléphone Android de milieu de gamme.

## Validations

- `dart format lib/main.dart lib/scanner_processing_service.dart test/widget_test.dart` : réussi, 3 fichiers vérifiés, aucune modification nécessaire.
- `flutter analyze` : réussi, `No issues found!`.
- `flutter test` : réussi, 72 tests sur 72.
- `flutter build apk --debug` : réussi, APK debug généré.

La construction signale un avertissement non bloquant de compatibilité future :
plusieurs plugins tiers appliquent encore directement le Kotlin Gradle Plugin.
Une mise à jour de ces plugins sera à prévoir avant qu'une future version de
Flutter rende obligatoire le mode Built-in Kotlin.

Chemin de l'APK généré :
`C:\Users\dhibi\Documents\admin_facile_v1\build\app\outputs\flutter-apk\app-debug.apk`

## Limite de validation locale

La précision réelle des coins, la suppression des ombres et la qualité sur les
six documents physiques demandés nécessitent les essais manuels ci-dessus. Les
tests automatisés valident le traitement, l'intégration et le PDF, mais ne
remplacent pas une capture par caméra dans des conditions réelles.
