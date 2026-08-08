# AdminFacile V17.3.6

Version : `17.3.6+68`

## Pourquoi un bloc officiel

La transparence d’une image de signature peut être interprétée différemment selon le moteur PDF et l’appareil. V17.3.6 ne cherche donc plus à dissimuler sa zone : la signature est présentée dans un cadre officiel, volontaire, stable et immédiatement compréhensible.

Le générateur reste `LetterSignatureService.buildLetterPdf`. Les modèles, l’aperçu, l’export, l’impression, le partage, Mes démarches et Supabase utilisent toujours ce même PDF ; aucun générateur parallèle n’a été ajouté.

## Style

Le PDF utilise un `pw.Container` de 145 × 75 points : fond blanc, bordure gris clair de 0,6 point, rayon de 4 points, marge interne de 8 points et aucune ombre. La signature est centrée avec `pw.Image`, limitée à 95 × 45 points et rendue avec `pw.BoxFit.contain`.

Le bloc affiche dans l’ordre :

1. « Signature de l’expéditeur » ;
2. le cadre ;
3. le nom normalisé, une seule fois.

`OfficialSignatureBlock` reproduit la même structure et le même style dans les aperçus Flutter de lettres.

## Avec ou sans image

- Option désactivée : aucun titre, cadre ou nom de signature.
- Option activée avec image : image centrée dans le cadre.
- Option activée sans image ou avec image illisible : cadre vide contenant « Signature à apposer », afin de permettre une signature manuscrite après impression.

La fonction de normalisation existante reste utilisée pour préserver la qualité de l’image, sans chercher à masquer le cadre officiel.

## Fichiers modifiés

- `lib/letter_signature_service.dart`
- `lib/main.dart`
- `test/widget_test.dart`
- `pubspec.yaml`
- `README_V17.3.6.md`

## Tests et validations

- présence du libellé et du cadre quand l’option est active ;
- cadre fin, blanc, gris clair, arrondi et sans ombre ;
- nom affiché une seule fois ;
- bloc totalement absent si l’option est désactivée ;
- « Signature à apposer » sans image ;
- même composant officiel dans les aperçus et le générateur PDF unique ;
- parcours modèle → personnalisation → PDF conservé ;
- `dart format` : réussi ;
- `flutter analyze` : `No issues found!` ;
- `flutter test` : `68 tests passed` ;
- `flutter build apk --debug` : réussi (`Built build\app\outputs\flutter-apk\app-debug.apk`).

## APK

`C:\Users\dhibi\Documents\admin_facile_v1\build\app\outputs\flutter-apk\app-debug.apk`
