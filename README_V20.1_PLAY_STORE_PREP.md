# AdminFacile V20.1 — Préparation Google Play Store

Version préparée : `20.1.0+81`

Cette étape prépare la publication sans publier l'application, sans créer de clé secrète et sans modifier l'identifiant Android. Aucun commit ni push n'a été effectué.

## Identité Android

L'identifiant actuel `com.example.admin_facile` est conservé à la demande du propriétaire. Le nom visible est `AdminFacile`. L'APK contrôlé porte bien le `versionCode` 81 et le `versionName` 20.1.0.

Une fois l'identifiant définitif confirmé, la migration devra concerner :

- `android/app/build.gradle.kts` : `namespace` et `applicationId` ;
- `android/app/src/main/kotlin/com/example/admin_facile/MainActivity.kt` : déclaration `package`, puis déplacement dans le répertoire correspondant au nouveau package ;
- `test/widget_test.dart` : chemin Kotlin actuellement contrôlé par les tests ;
- `android/app/src/main/AndroidManifest.xml` : vérifier la résolution de `.MainActivity` après migration, même si la référence relative peut rester inchangée ;
- les configurations externes liées à l'identité de l'application : fiche Play Console, certificats SHA, OAuth/deep links et éventuelles redirections Supabase.

Le `MethodChannel` `adminfacile/mlkit_document_scanner` ne dépend pas du package Android et ne nécessite pas de renommage.

## Signature release et Play App Signing

La configuration Gradle ne réutilise plus silencieusement la clé debug en release. Elle charge `android/key.properties` uniquement s'il existe. Le fichier réel et les keystores sont exclus de Git ; seul `android/key.properties.example` est fourni avec des valeurs factices.

L'AAB de validation est donc volontairement **non signé**. Il ne peut pas être envoyé sur Google Play tant qu'une upload key n'a pas été créée et configurée.

Commandes manuelles proposées après choix du package, depuis PowerShell :

```powershell
keytool -genkeypair -v -keystore C:\CHEMIN_SECURISÉ\adminfacile-upload.jks -alias adminfacile-upload -keyalg RSA -keysize 4096 -validity 10000
Copy-Item android\key.properties.example android\key.properties
keytool -export -rfc -keystore C:\CHEMIN_SECURISÉ\adminfacile-upload.jks -alias adminfacile-upload -file upload_certificate.pem
```

Il faudra ensuite compléter localement `android/key.properties`, sauvegarder séparément le keystore et ses secrets, activer Play App Signing et reconstruire l'AAB. Aucun mot de passe ni keystore n'a été créé ou ajouté au projet.

## Icône et splash screen

L'icône Flutter générique a été remplacée par une déclinaison raster et adaptative de l'asset AdminFacile existant `assets/adminfacile_mark.png`. Aucun nouveau logo n'a été inventé. Les ressources adaptatives utilisent un foreground transparent et un fond clair cohérent.

Le splash utilise la même marque, avec des fonds clair et sombre dédiés. Android 12+ dispose de ressources `values-v31`; les versions antérieures utilisent les launch backgrounds centrés. Un contrôle visuel sur plusieurs densités reste requis avant publication, ainsi qu'un export Play Store 512 × 512 depuis le fichier source de marque.

## Permissions Android

| Permission source | Usage | Écran/fonction |
|---|---|---|
| `INTERNET` | Supabase, Gemini et téléchargements nécessaires | Authentification, cloud, assistance IA |
| `RECORD_AUDIO` | Dictée vocale via le moteur de reconnaissance Android | Saisie par dictée |

L'application ne déclare pas directement de permission caméra, stockage général, photos/vidéos ou notifications. Le scanner ML Kit et la photo simple reposent sur des activités système/plugins qui gèrent leur propre capture. L'APK fusionné ajoute `ACCESS_NETWORK_STATE` et une permission interne de receiver dynamique issue des bibliothèques Android.

La fiche Play Store devra expliquer l'accès microphone et confirmer le comportement réel du fournisseur de reconnaissance vocale choisi par l'appareil.

## Configuration release

- `minSdk` constaté : 24 ;
- `targetSdk` constaté : 36 ;
- `compileSdk` constaté : 36 ;
- Java/Kotlin JVM : 17 ;
- règles ProGuard/R8 existantes conservées ;
- pas de multidex explicite ;
- dépendance ML Kit Document Scanner inchangée ;
- aucun changement du scanner, de Supabase, de Gemini ou de l'UX métier.

Le build release est techniquement généré, mais il reste impropre à l'envoi tant que la vraie signature d'upload n'est pas configurée.

## Sécurité et Gemini

La clé Gemini est lue avec `String.fromEnvironment('GEMINI_API_KEY')`. Aucun secret Gemini n'a été ajouté. Un `--dart-define` est compilé dans le binaire et ne protège donc pas une clé destinée à la production. Avant une publication publique avec Gemini actif, un proxy/backend contrôlé, des quotas et des restrictions doivent être définis. Le build release de cette validation a été créé sans clé Gemini.

Les recherches ciblées ne montrent aucune clé `service_role` Supabase embarquée. L'application utilise une clé publishable. Les scripts SQL présents décrivent un bucket privé et des politiques RLS par utilisateur. Avant production, ces politiques doivent être vérifiées sur l'instance réelle, ainsi que l'expiration des URL signées et la suppression complète des données.

Checklist Supabase préproduction :

- confirmer RLS sur chaque table et bucket depuis le tableau de bord de production ;
- tester qu'un compte ne peut ni lire ni modifier les données d'un autre ;
- confirmer que le bucket reste privé et qu'aucune URL publique permanente n'est utilisée ;
- vérifier durée et renouvellement des URL signées ;
- tester suppression du compte et de toutes ses données associées ;
- vérifier sauvegarde, rétention, région et sous-traitants réellement applicables.

## Confidentialité, Data Safety et fiche Play Store

Les brouillons suivants ont été créés sans inventer d'identité juridique ni de contact :

- `PRIVACY_POLICY_DRAFT.md` ;
- `PLAY_STORE_DATA_SAFETY_DRAFT.md` ;
- `PLAY_STORE_LISTING_DRAFT.md` ;
- `PLAY_STORE_SCREENSHOTS.md` ;
- `PREMIUM_PLAN_DRAFT.md`.

Les réponses incertaines sont marquées `[À VÉRIFIER]` et les coordonnées manquantes `[À COMPLÉTER]`. La politique devra être relue juridiquement, publiée sur une URL publique stable et liée dans l'application/Play Console.

Comme l'application permet de créer un compte, la suppression du compte et des données doit être proposée dans l'application et via une ressource web accessible. Ce parcours complet n'est pas actuellement démontré et constitue un blocage avant publication publique.

La proposition premium est documentaire uniquement : aucune facturation n'a été intégrée. Elle recommande une version gratuite réellement utile et des abonnements mensuel/annuel pour les coûts récurrents, sous réserve de validation commerciale et juridique.

## Tests ajoutés

Les tests V20.1 contrôlent :

- l'absence de fallback vers la signature debug en release ;
- l'exclusion Git de `key.properties` et des keystores ;
- l'absence d'un vrai `key.properties` dans le projet ;
- les permissions manifest limitées ;
- la présence de l'icône adaptative et du splash Android 12+.

## Validations exécutées

- `dart format test/widget_test.dart` : succès, fichier déjà formaté ;
- `flutter analyze` : **No issues found!** ;
- `flutter test --concurrency=1` : **96 tests réussis** ;
- `flutter build apk --debug` : succès ;
- `flutter build appbundle --release` : succès, **AAB non signé** ;
- contrôle `aapt` : package actuel conservé, version 20.1.0+81, minSdk 24, target/compile SDK 36 ;
- contrôle `jarsigner -verify` : `jar is unsigned`, comportement attendu sans upload key.

Artefacts :

- APK debug : `build/app/outputs/flutter-apk/app-debug.apk` (242 989 409 octets) ;
- AAB release : `build/app/outputs/bundle/release/app-release.aab` (116 932 277 octets, non signé).

## Fichiers modifiés ou créés

- `.gitignore`
- `pubspec.yaml`
- `android/app/build.gradle.kts`
- `android/key.properties.example`
- `android/app/src/main/res/drawable/launch_background.xml`
- `android/app/src/main/res/drawable-v21/launch_background.xml`
- `android/app/src/main/res/drawable/adminfacile_mark.png`
- `android/app/src/main/res/drawable/adminfacile_splash.png`
- `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- icônes `mipmap-*dpi/ic_launcher.png`
- `android/app/src/main/res/values/colors.xml`
- `android/app/src/main/res/values-night/colors.xml`
- `android/app/src/main/res/values-v31/styles.xml`
- `android/app/src/main/res/values-night-v31/styles.xml`
- `test/widget_test.dart`
- les cinq brouillons Play Store listés plus haut
- `README_V20.1_PLAY_STORE_PREP.md`

## Blocages et décisions restantes

1. Confirmer l'identifiant Android définitif, puis appliquer la migration listée plus haut.
2. Créer et sauvegarder la vraie upload key, compléter `key.properties` hors Git, puis produire un AAB signé.
3. Implémenter et valider la suppression de compte/données, y compris la page web de demande.
4. Choisir le contact support, l'identité du responsable, l'adresse de politique de confidentialité et les mentions légales.
5. Valider Data Safety contre les services réellement activés en production, notamment Gemini, Supabase, dictée et journaux.
6. Sécuriser Gemini côté serveur ou le désactiver pour la publication publique.
7. Produire et contrôler les captures réelles, l'icône Play 512 × 512 et le feature graphic.
8. Tester visuellement icône/splash et tous les parcours release sur appareils avant bêta.

## Références officielles

- [Google Play — Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
- [Google Play — User Data et suppression de compte](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)
- [Google Play — Exigences relatives aux captures](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)

