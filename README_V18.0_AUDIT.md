# AdminFacile V18.0 — Audit qualité et publication

Version auditée : `18.0.0+70`  
Date : 6 août 2026  
Périmètre : gel fonctionnel, qualité, stabilité, performances, interface, accessibilité, sécurité et préparation Google Play.

## Synthèse

Le socle debug est stable : analyse statique sans anomalie, 69 tests réussis et APK debug généré. Les parcours principaux sont couverts par les tests de widgets et les générateurs PDF sont centralisés.

La publication Google Play n’est toutefois pas autorisable en l’état. Les blocages principaux sont la configuration release non sécurisée, l’identifiant d’exemple, l’absence de suppression de compte, l’absence de politique de confidentialité publique complète et l’exposition inévitable d’une clé Gemini lorsqu’elle est injectée directement dans une application cliente.

État global estimé : **73/100 — bêta avancée, non prête pour la production publique**.

## Bugs corrigés

- La suppression d’un document depuis son menu était immédiate alors que les démarches demandaient confirmation. Un dialogue « Supprimer ce document ? » protège maintenant cette action.
- Le manifeste Android demandait trois permissions Bluetooth sans qu’aucun code Bluetooth ne soit présent. `BLUETOOTH`, `BLUETOOTH_ADMIN` et `BLUETOOTH_CONNECT` ont été retirées.
- La notice de confidentialité disait seulement que les documents restaient locaux. Elle distingue maintenant le stockage local par défaut, la synchronisation volontaire vers Supabase et l’envoi du texte — sans photo/PDF — à Gemini.
- La version Android produite est confirmée comme `18.0.0` / code `70`.

## Performances et fluidité

- Les longues collections visibles utilisent déjà majoritairement `ListView.builder` ou `ListView.separated`.
- Les opérations PDF sont produites à la demande et les octets sont ensuite réutilisés par l’aperçu, le partage et l’impression.
- Une mutualisation en mémoire du décodage des 542 modèles a été évaluée. Elle passait isolément mais bloquait la suite complète lors de l’enchaînement de plusieurs écrans. Elle a été retirée : aucune optimisation instable n’est conservée dans V18.0.
- Le catalogue JSON est encore décodé indépendamment par plusieurs écrans. Une optimisation future nécessite un dépôt injecté avec un cycle de vie explicite et des mesures de démarrage/recherche sur appareil réel.
- `lib/main.dart` dépasse 480 Ko. Son découpage par domaines améliorerait la maintenabilité et limiterait les risques de rebuild, mais cette refactorisation est trop large pour une version de stabilisation.

## Interface et accessibilité

- Les tests existants couvrent le mode clair, le contraste de plusieurs actions, les écrans étroits, les overflows principaux et les destinations des actions rapides.
- Les listes principales, formulaires, dialogues, menus de documents/démarches, aperçu de lettres et signature ont été relus statiquement.
- Les actions destructives principales sont maintenant confirmées pour les documents et les démarches.
- Les contrôles matériels restent nécessaires avec facteur de police Android à 1,3× et 2×, TalkBack, tablette et appareil pliable ouvert/fermé. Ces configurations ne sont pas entièrement simulées par la suite actuelle.

## Code mort et fichiers historiques

L’analyseur ne signale aucun import ou symbole inutilisé dans le graphe compilé.

Éléments hors du graphe actif identifiés :

- `lib/main_backup.dart` ;
- `lib/account_controller.dart` et `lib/cloud_documents.dart`, référencés seulement par cette sauvegarde ou entre eux ;
- `android_patch/` ;
- `lib.zip` ;
- anciennes notes d’installation et rapports de versions.

Ils ne sont pas intégrés à l’APK et n’affectent pas les performances d’exécution. Ils ont été conservés afin de ne supprimer aucune sauvegarde ou donnée appartenant au projet sans décision d’archivage explicite. Ils devraient être déplacés hors du dépôt applicatif avant la publication.

## Audit des services et parcours

### PDF, aperçu, partage et impression

- Le générateur actif reste `LetterSignatureService.buildLetterPdf`.
- Modèles, aperçu, export, impression, partage, Mes démarches et envoi de démarches vers Supabase consomment le même PDF.
- Les tests couvrent Unicode, objet unique, signature, cadre officiel, image absente et parcours modèle → personnalisation → PDF.

### Supabase

- Connexion, création de compte, déconnexion, upload de documents/démarches et signature privée sont présents.
- Les erreurs réseau principales sont interceptées et affichées.
- Les règles/politiques Supabase doivent être validées sur un projet de préproduction avec deux comptes distincts afin de prouver l’isolation entre utilisateurs.
- Blocage Play Store : l’application permet la création de compte mais ne fournit aucun parcours de suppression de compte et des données associées.
- La récupération de mot de passe n’est pas implémentée ; elle doit être traitée avant une publication publique.

### Gemini

- La configuration est injectée par `--dart-define` et les erreurs de configuration/API sont gérées.
- Blocage sécurité : une clé injectée dans une application mobile peut être extraite de l’artefact. Une API intermédiaire avec authentification, quotas et restrictions doit remplacer l’appel direct avant production.
- Les prompts demandent de ne pas inventer les informations administratives, mais une validation humaine reste explicitement nécessaire.

### Scanner et OCR

- Les chemins scanner, import, reconnaissance OCR, relance et messages d’erreur existent.
- La permission microphone est justifiée par la dictée vocale. Les permissions Bluetooth inutiles ont été supprimées.
- La validation finale doit être faite sur plusieurs fournisseurs Android avec PDF, photo nette, photo sombre, document multipage, refus de permission et absence de service OCR.

### Stockage local, export et synchronisation

- Les stores locaux persistent les documents et démarches avec compatibilité des anciens formats testée.
- Les fichiers temporaires de partage d’aperçu sont supprimés dans un bloc `finally`.
- Les suppressions de fiches locales ne prouvent pas la suppression des éventuels fichiers ou copies cloud associés. La politique produit de conservation/suppression doit être définie avant publication.

## Préparation Google Play

### Conforme ou présent

- `targetSdkVersion=36`, compatible avec l’exigence Android 16 annoncée pour les soumissions à partir du 31 août 2026.
- `minSdkVersion=24`.
- Icônes launcher présentes pour les cinq densités Android.
- Nom d’application `AdminFacile`.
- Permission Internet et microphone seulement dans le manifeste principal après nettoyage.

### Blocages avant publication

1. Remplacer `com.example.admin_facile` par un identifiant définitif avant la toute première publication.
2. Créer une clé d’upload et configurer Play App Signing. Le build `release` utilise actuellement la signature debug, refusée pour une publication réelle.
3. Générer et vérifier un Android App Bundle release signé (`.aab`).
4. Ajouter une suppression de compte dans l’application et une ressource web de demande de suppression.
5. Ajouter la récupération de mot de passe.
6. Publier une politique de confidentialité complète et accessible par URL, puis la rendre accessible dans l’application.
7. Compléter précisément la fiche Data Safety pour Supabase, Gemini, adresse e-mail, documents, signature, microphone et SDK tiers.
8. Ne pas embarquer la clé Gemini : utiliser un service intermédiaire sécurisé.
9. Remplacer le splash blanc Flutter par un écran de lancement AdminFacile final.
10. Vérifier visuellement que les icônes existantes sont des créations AdminFacile et fournir une icône Play Store 512 × 512.
11. Préparer mentions légales, coordonnées de support, description courte/longue, catégorie, classification du contenu, captures téléphone/tablette et visuel promotionnel.
12. Tester les politiques Supabase/RLS avec comptes isolés et documenter la suppression/rétention des données.
13. Mettre à niveau les plugins appliquant encore l’ancien mécanisme Kotlin Gradle Plugin.

Références officielles :

- Exigences API cible : https://developer.android.com/google/play/requirements/target-sdk
- Signature et Play App Signing : https://developer.android.com/studio/publish/app-signing
- Data Safety : https://support.google.com/googleplay/android-developer/answer/10787469
- Suppression de compte : https://support.google.com/googleplay/android-developer/answer/13327111

## Dépendances

`flutter pub outdated` signale notamment :

- `supabase_flutter` 2.16.0, mise à niveau résoluble vers 2.17.1 ;
- `share_plus` 11.1.0, version résoluble 13.3.0 ;
- `file_picker` 10.3.10, une version stable 11.0.3 existe mais la résolution courante propose une préversion 12 ;
- `flutter_lints` 5.0.0, version 6 disponible ;
- 11 dépendances verrouillées à des versions antérieures.

Aucune mise à niveau majeure n’a été appliquée pendant le gel fonctionnel. Une branche dédiée doit mettre à niveau un paquet à la fois avec tests Android complets.

## Anomalies restantes et limites de l’audit

- Aucune exécution automatisée ne peut valider l’interface native de partage/impression ni le comportement matériel du scanner et du microphone.
- Aucun test de bout en bout n’a été exécuté contre Supabase ou Gemini afin d’éviter de muter des données externes et d’utiliser des secrets pendant l’audit.
- Les parcours création de compte, connexion et déconnexion sont présents mais la récupération et la suppression du compte manquent.
- Les actions cloud de suppression/rétention ne sont pas définies de bout en bout.
- Le splash est celui du projet Flutter par défaut.
- Le package Android et la signature release interdisent une publication immédiate.
- Plusieurs fichiers historiques et trois sources Dart hors graphe restent dans le dépôt.
- L’avertissement de migration Kotlin est non bloquant aujourd’hui mais deviendra bloquant dans une future version de Flutter.

## Fichiers modifiés pour V18.0

- `android/app/src/main/AndroidManifest.xml`
- `lib/main.dart`
- `pubspec.yaml`
- `test/widget_test.dart`
- `README_V18.0_AUDIT.md`

`pubspec.lock` apparaît déjà modifié dans l’arbre de travail et a été préservé.

## Validations exécutées

- `dart format` : réussi.
- `flutter analyze` : `No issues found!`.
- `flutter test` : 69 tests réussis.
- `flutter build apk --debug` : réussi.
- `flutter pub outdated` : audit exécuté, mises à niveau disponibles listées ci-dessus.
- Manifeste fusionné : version `18.0.0` code `70`, min SDK 24, cible SDK 36.

APK :

`C:\Users\dhibi\Documents\admin_facile_v1\build\app\outputs\flutter-apk\app-debug.apk`

## Score qualité

- Stabilité : **88/100**
- Performances : **78/100**
- Interface : **86/100**
- Expérience utilisateur : **82/100**
- Sécurité : **58/100**
- Préparation Play Store : **45/100**
- Score global pondéré : **73/100**

Conclusion : bonne base de bêta et qualité debug satisfaisante. La publication publique doit attendre la résolution des blocages sécurité, comptes, confidentialité, identité Android et signature release.
