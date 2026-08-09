# AdminFacile V20.2 — Migration du package Android

Version : `20.2.0+82`

## Identité définitive

- Ancien package Android : `com.example.admin_facile`
- Nouveau package Android définitif : `fr.adminfacile.app`

Le `namespace` et l'`applicationId` utilisent désormais tous deux `fr.adminfacile.app`. Le contrôle du manifeste fusionné de l'APK confirme le package `fr.adminfacile.app`, le `versionCode` 82 et le `versionName` 20.2.0.

## Fichier déplacé

- Ancien emplacement supprimé : `android/app/src/main/kotlin/com/example/admin_facile/MainActivity.kt`
- Nouvel emplacement : `android/app/src/main/kotlin/fr/adminfacile/app/MainActivity.kt`

La déclaration Kotlin est maintenant `package fr.adminfacile.app`. Les anciens répertoires Kotlin devenus vides ont été supprimés.

## Fichiers modifiés pour V20.2

- `android/app/build.gradle.kts` : nouveau `namespace` et nouvel `applicationId` ;
- `android/app/src/main/kotlin/fr/adminfacile/app/MainActivity.kt` : nouvel emplacement et package Kotlin ;
- `pubspec.yaml` : version `20.2.0+82` ;
- `test/widget_test.dart` : chemins Kotlin adaptés et test V20.2 ajouté ;
- `README_V20.2_PACKAGE_MIGRATION.md` : présent rapport.

Les changements V20.1 non commités restent également présents dans le répertoire de travail. Aucune fonctionnalité métier n'a été modifiée.

## Manifest et MethodChannel

Le manifeste principal déclare `android:name=".MainActivity"`. Cette référence relative se résout correctement sous le nouveau namespace et ne nécessitait aucun changement textuel.

Le canal natif reste exactement :

```text
adminfacile/mlkit_document_scanner
```

Il est identique dans `MainActivity.kt` et `lib/document_scanner_service.dart`.

## Supabase, authentification et deep links

Le parcours de récupération du mot de passe utilise toujours :

```text
io.adminfacile://reset-password
```

Ce schéma métier ne dépend pas de l'`applicationId`; le modifier aurait cassé les redirections existantes. Aucun autre App Link, Firebase configuration ou fichier OAuth Android n'a été trouvé dans le projet actif.

Actions manuelles Supabase :

1. conserver ou ajouter `io.adminfacile://reset-password` dans la liste des Redirect URLs autorisées de Supabase Auth ;
2. exécuter une récupération de mot de passe réelle sur une installation portant `fr.adminfacile.app` ;
3. contrôler les modèles d'e-mail afin qu'ils utilisent bien la redirection autorisée ;
4. si un fournisseur OAuth mobile est ajouté ou déjà configuré uniquement dans le tableau de bord, l'associer explicitement au package `fr.adminfacile.app` et aux certificats réels ;
5. ne pas modifier les politiques RLS ou le bucket privé uniquement à cause du package : ils sont liés à l'utilisateur Supabase, pas à l'identifiant Android.

La clé publishable et les URL Supabase ne nécessitent pas de changement de code pour cette migration.

## Certificats et OAuth

Aucune empreinte SHA n'a été inventée. Avant Play Store :

- créer/configurer l'upload key réelle ;
- relever ses empreintes SHA-1/SHA-256 ;
- après activation de Play App Signing, relever également les empreintes du certificat de signature d'application fourni par Play ;
- associer `fr.adminfacile.app` et les empreintes appropriées à tout fournisseur OAuth Android réellement utilisé ;
- mettre à jour les configurations externes éventuelles qui référencent encore l'ancien package.

L'AAB de validation est généré mais reste volontairement non signé, car aucun `android/key.properties` réel n'est présent et la configuration interdit le fallback vers la clé debug.

## Tests automatisés

Le test V20.2 vérifie :

- `namespace = "fr.adminfacile.app"` ;
- `applicationId = "fr.adminfacile.app"` ;
- présence de `MainActivity` au nouvel emplacement ;
- absence de l'ancien fichier et de l'ancien package dans le code Android actif ;
- résolution relative `.MainActivity` dans le manifeste ;
- conservation exacte du MethodChannel côté Kotlin et Dart.

## Validations

- `dart format test/widget_test.dart` : fichier formaté ; le lanceur a ensuite signalé une écriture de télémétrie interdite hors workspace, sans affecter le formatage ;
- `flutter analyze` : **No issues found!** ;
- `flutter test --concurrency=1` : **97 tests réussis — All tests passed!** ;
- `flutter build apk --debug` : succès, `Built build\app\outputs\flutter-apk\app-debug.apk` ;
- `flutter build appbundle --release` : succès, `Built build\app\outputs\bundle\release\app-release.aab (111.5MB)` ;
- contrôle `aapt` : `fr.adminfacile.app`, version 20.2.0+82, minSdk 24, targetSdk 36 ;
- recherche ciblée : aucune occurrence de `com.example.admin_facile` dans `android/app` ou `lib` ;
- contrôle `jarsigner` : `jar is unsigned`, attendu tant que l'upload key n'est pas configurée.

Avertissement non bloquant : Flutter signale que plusieurs plugins appliquent encore explicitement Kotlin Gradle Plugin et devront migrer vers Built-in Kotlin dans une future version de Flutter.

## Artefacts

- APK debug : `build/app/outputs/flutter-apk/app-debug.apk` — 242 989 397 octets
- AAB release : `build/app/outputs/bundle/release/app-release.aab` — 116 934 796 octets, non signé

## Étapes manuelles avant Play Store

1. Réserver/créer l'application Play Console avec `fr.adminfacile.app`. Après création, ce package ne pourra plus être changé pour cette application.
2. Créer et sauvegarder l'upload key, compléter localement `android/key.properties`, puis reconstruire et vérifier un AAB signé.
3. Activer Play App Signing et archiver séparément les certificats/empreintes.
4. Vérifier la Redirect URL Supabase et tester le reset de mot de passe réel.
5. Associer le nouveau package et les SHA aux fournisseurs OAuth effectivement utilisés.
6. Finaliser la politique de confidentialité, Data Safety, suppression de compte, contact support et visuels Play Store déjà identifiés en V20.1.

L'assistant n'a exécuté aucune commande de commit, push ou publication Play
Store. Pendant les validations, le `HEAD` a toutefois changé de façon externe
de `1dd9f60` vers `9909b6c` (`Correction Flutter analyze + formatage`) et ce
commit apparaît également sur `origin/feature/v16-dashboard`. Il contient les
changements V20.1/V20.2 ainsi que des fichiers de télémétrie `.dart-tool` qui
n'ont pas été ajoutés volontairement par cette tâche. Cette modification Git
concurrente doit être auditée par le propriétaire avant toute bêta.
