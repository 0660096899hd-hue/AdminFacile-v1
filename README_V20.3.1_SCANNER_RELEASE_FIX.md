# AdminFacile V20.3.1+84 — correction scanner ML Kit release

## Résumé

Le crash avant ouverture de la caméra était causé par R8. En release, les noms
des classes implémentant `ComponentRegistrar` étaient conservés par les règles
consumer de Firebase, mais pas leurs constructeurs publics sans argument. La
découverte Firebase/ML Kit charge ces classes par réflexion et appelle ce
constructeur. Cela produisait les `NoSuchMethodException` observées, empêchait
l'initialisation du contexte ML Kit, puis provoquait une `NullPointerException`
synchrone lors de `GmsDocumentScanning.getClient(options)`.

La règle ajoutée conserve uniquement les constructeurs requis par cette
réflexion :

```proguard
-keepclassmembers class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
```

Elle évite volontairement un `-keep class com.google.mlkit.** { *; }` global,
beaucoup trop large.

## Instruction qui échouait

Dans `MainActivity.launchMlKitScanner`, l'échec s'échappait depuis :

```kotlin
GmsDocumentScanning.getClient(options)
```

Le dernier ancien log était donc `event=request pages=10`; aucun listener de la
`Task` ne pouvait intercepter cette exception synchrone. Les erreurs similaires
au démarrage de `google_mlkit_translation`, du text recognizer et de
`vision-common` provenaient de la même suppression de constructeur.

## Audit R8 / release

- La configuration `release` référence
  `proguard-android-optimize.txt` et `proguard-rules.pro`.
- La release effective passe bien par R8 : `mapping.txt`, `usage.txt`,
  `seeds.txt`, `configuration.txt` et `resources.txt` sont produits.
- Le mapping antérieur conservait les quatre noms de Registrars mais ne
  contenait aucun `void <init>()` pour eux.
- Après correction, le mapping contient `void <init>():0:0 -> <init>` pour
  `CommonComponentRegistrar`, `NaturalLanguageTranslateRegistrar`,
  `VisionCommonRegistrar` et `TextRegistrar`.
- L'obfuscation et le shrinking release restent actifs. La configuration debug
  ne produit pas de mapping R8 équivalent, ce qui explique la différence de
  comportement.

R8 est donc la cause racine confirmée, et non un simple identifiant présent
fortuitement dans les traces.

## Audit des dépendances résolues

Versions Flutter :

- `google_mlkit_commons` : `0.12.0` ;
- `google_mlkit_text_recognition` : `0.16.0` ;
- `google_mlkit_translation` : `0.14.0`.

Versions Android/ML Kit résolues sur `releaseRuntimeClasspath` :

- scanner natif AdminFacile : MethodChannel Kotlin intégré à `MainActivity` ;
- `play-services-mlkit-document-scanner` : `16.0.0` ;
- `com.google.mlkit:common` : `18.11.0` ;
- `com.google.mlkit:vision-common` : `17.3.0` ;
- `com.google.mlkit:vision-interfaces` : `16.3.0` ;
- `com.google.mlkit:text-recognition` : `16.0.1` ;
- `text-recognition-bundled-common` : `17.0.0` ;
- `play-services-mlkit-text-recognition` : `19.0.1` ;
- `play-services-mlkit-text-recognition-common` : `19.1.0` ;
- `com.google.mlkit:translate` : `17.0.3` ;
- `play-services-base` : `18.5.0` (résolution de conflit depuis `18.1.0`) ;
- `play-services-basement` : `18.4.0` (depuis `18.1.0`) ;
- `play-services-tasks` : `18.2.0` (depuis `18.0.2`).

Gradle ne signale ni doublon de classes, ni exclusion ML Kit, ni conflit
incompatible. Les montées de versions transitives ci-dessus sont des
résolutions normales vers la version la plus récente demandée. Aucune version
n'a donc été forcée ou exclue : modifier arbitrairement cet ensemble aurait
ajouté un risque sans corriger les constructeurs supprimés démontrés dans le
mapping.

AGP 9.0.1 avertit toutefois que plusieurs plugins Flutter appliquent encore
eux-mêmes l'ancien plugin Kotlin. C'est une dette de migration future, pas la
cause de cette NPE : la compilation release réussit et le défaut observé est
directement visible dans le mapping R8.

## Correction native et comportement de repli

Chaque étape critique est désormais journalisée sans donnée personnelle :

- `SCANNER_NATIVE step=options_create/options_ready` ;
- `SCANNER_NATIVE step=client_create/client_ready` ;
- `SCANNER_NATIVE step=intent_sender_create/intent_sender_ready` ;
- `SCANNER_NATIVE step=activity_launched` ;
- `SCANNER_NATIVE step=activity_result` ;
- `SCANNER_NATIVE failure=... code=... type=...` en cas d'échec.

La création des options, du client, de l'IntentSender et le lancement de
l'Activity sont chacun protégés, y compris contre une erreur synchrone ou de
liaison. Flutter reçoit alors un code `MLKIT_*` géré au lieu d'une NPE. Le flux
existant affiche le message clair indiquant que le scanner professionnel est
indisponible et propose `Photo simple` et `Importer`, sans effacer le document
précédent.

Le succès conserve le flux attendu : interface ML Kit, recadrage, multipage,
JPEG/PDF puis copie des pages vers Flutter.

## Fichiers modifiés pour cette correction

- `android/app/proguard-rules.pro` ;
- `android/app/src/main/kotlin/fr/adminfacile/app/MainActivity.kt` ;
- `pubspec.yaml` (`20.3.1+84`) ;
- `test/document_scanner_service_test.dart` ;
- `test/scanner_android_release_config_test.dart` ;
- ce rapport.

L'authentification, Gemini et l'UX globale n'ont pas été modifiés dans cette
intervention.

## Validation locale

- `dart format lib test` : 12 fichiers vérifiés, aucun changement requis ;
- `flutter analyze` : aucune anomalie ;
- `flutter test --concurrency=1` : **117 tests réussis** ;
- `flutter build apk --release` : succès, APK de 134,7 Mo ;
- `flutter build appbundle --release` : succès, AAB de 111,7 Mo ;
- package APK : `fr.adminfacile.app` ;
- `versionName` : `20.3.1` ;
- `versionCode` : `84` ;
- signature APK : valide, schéma v2, un signataire release ;
- mapping post-build : constructeurs des quatre Registrars présents.

Les tests couvrent le MethodChannel, le multipage et sa borne, l'annulation,
les résultats vides, la conversion des erreurs natives en exception contrôlée,
la conservation du code natif, le fallback Photo/Import, la configuration R8
et les étapes de diagnostic Kotlin.

## Test physique restant

Aucun appareil Android n'est connecté à cet environnement (`flutter devices`
ne liste que Windows et les navigateurs). L'installation et le parcours caméra
doivent donc être validés sur un téléphone compatible Google Play Services :

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
adb logcat -s AdminFacileScanner
```

À vérifier : ouverture de l'interface ML Kit, capture, recadrage, ajout de
plusieurs pages, validation, retour des images/PDF, puis test du fallback avec
ML Kit indisponible. Aucun commit, push ou envoi Google Play n'a été effectué.
