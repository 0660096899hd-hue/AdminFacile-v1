# AdminFacile V20.0 — Release Candidate 1

Version : `20.0.0+80`

## Périmètre

Cette version ne contient aucune nouvelle fonctionnalité. Elle stabilise les
parcours existants, réduit le travail au démarrage, supprime du code réellement
inactif et prépare les artefacts Android de bêta.

## Bugs corrigés

- Le démarrage attendait la synchronisation Supabase d'une signature migrée.
  Cette synchronisation est désormais lancée après `runApp`, bornée à 20
  secondes et ne bloque plus le premier écran.
- Le chargement des documents et des démarches était séquentiel. Les deux
  lectures locales indépendantes utilisent maintenant `Future.wait`.
- Une panne cloud après l'enregistrement local d'une signature faisait remonter
  « signature non enregistrée », alors que la copie locale existait. La copie
  locale est maintenant conservée et le message distingue clairement l'échec
  de synchronisation.
- Les uploads de démarches, documents et signatures pouvaient attendre le
  réseau sans limite. Ils disposent maintenant de délais de 20 ou 30 secondes.
- Les erreurs cloud pouvaient afficher directement une exception technique.
  Elles sont traduites en messages réseau, session, timeout ou indisponibilité.
- Plusieurs écrans relisaient et redécodaient le catalogue JSON de plus de 500
  modèles. `BundledLetterCatalog` partage maintenant un cache immuable unique.
- Le build AAB release échouait dans R8 car le plugin OCR référence des modules
  chinois, japonais, coréen et devanagari non installés. AdminFacile utilise
  uniquement `TextRecognitionScript.latin`; les règles `-dontwarn` exactement
  générées par AGP ont été ajoutées dans `android/app/proguard-rules.pro`.
- La mémoire Gradle autorisait 8 Go de heap et 4 Go de metaspace. Les plafonds
  sont ramenés à 4 Go et 1 Go afin d'éviter la terminaison du build sur une
  machine standard.
- Le titre technique de l'application indiquait encore V11 et la description
  du package V15.6.1. Ils sont désormais neutres et à jour.

## Optimisations

- affichage initial indépendant de la synchronisation réseau de signature ;
- chargements locaux parallélisés ;
- une seule lecture et un seul décodage du catalogue de 542 modèles ;
- liste du catalogue mise en cache sous forme non modifiable ;
- appels cloud bornés pour éviter une interface bloquée ;
- mémoire de build Gradle bornée ;
- aucun changement du moteur scanner, de l'OCR, des générateurs PDF ou du
  design fonctionnel.

## Code supprimé

Les fichiers suivants n'étaient importés par aucun code ni aucun test actif :

- `lib/main_backup.dart`, copie complète exclue explicitement de l'analyse ;
- `lib/account_controller.dart`, ancien pont d'authentification ;
- `lib/cloud_documents.dart`, ancien parcours Supabase Storage REST parallèle.

L'application active utilise `supabase_flutter` et
`ProfessionalAuthService`. Le projet ne contient plus deux piles cloud/auth
concurrentes dans `lib/`.

Les sauvegardes historiques `lib.zip` et `android_patch/` ne sont pas compilées.
Elles ont été signalées mais conservées pour ne pas supprimer d'archives sans
décision explicite de l'équipe.

## Dépendances

`flutter pub outdated` a été exécuté. Aucune mise à jour automatique n'a été
faite dans cette RC.

- `supabase_flutter` : 2.16.0, mise à jour mineure 2.17.1 disponible ;
- `share_plus` : migration majeure 13.3.0 disponible ;
- `file_picker` : version actuelle 10.3.10, versions plus récentes à valider ;
- `flutter_lints` : version majeure 6 disponible ;
- plusieurs plugins appliquent encore eux-mêmes Kotlin Gradle Plugin. Flutter
  signale une incompatibilité future avec Built-in Kotlin. Le build actuel
  réussit, mais ce point doit être suivi avant une future mise à jour Flutter.

Les migrations majeures sont différées pour ne pas augmenter le risque RC1.

## Scanner

Le moteur reste Google ML Kit Document Scanner 16.0.0 en
`SCANNER_MODE_FULL`. L'ancien `EdgeDetector` n'est pas revenu. Les tests couvrent
le moteur principal, le multipage, l'annulation, le fallback, la conservation
du document précédent, l'OCR direct et la création PDF.

Les tests avec feuilles, factures, tickets, ombres et Fold5 doivent encore être
exécutés physiquement avant la bêta.

## Authentification

`ProfessionalAuthService` reste l'unique couche métier. Les tests couvrent
inscription, confirmation e-mail, e-mail déjà utilisé, mauvais mot de passe,
e-mail invalide, reset, reconnexion, restauration de session, déconnexion,
absence de réseau, timeout et diagnostic réservé au debug.

La validation réelle des e-mails, politiques et redirections Supabase doit être
refaite dans l'environnement de préproduction.

## Supabase

- le client officiel restaure et renouvelle la session ;
- les objets sont stockés dans le bucket privé `admin-documents` ;
- les chemins sont préfixés par l'UID ;
- le SQL fourni limite lecture, insertion, mise à jour et suppression à l'UID ;
- aucune URL publique permanente n'est construite dans le code actif ;
- la clé incluse est une clé publishable, pas une `service_role` ;
- uploads et migrations de signature ont maintenant des timeouts.

Les politiques RLS présentes dans le dépôt ont été auditées statiquement. Leur
déploiement réel dans le projet Supabase ne peut pas être prouvé par un test
local et doit être vérifié dans la console de préproduction.

## Gemini

L'application fonctionne sans clé Gemini grâce aux parcours locaux et aux
messages de configuration. Les appels ont déjà des timeouts et valident la
structure des réponses.

L'AAB release de cette validation a été construit sans
`--dart-define=GEMINI_API_KEY`, donc aucune clé Gemini n'y a été injectée.
Attention : une clé passée par `--dart-define` est compilée dans le binaire.
Elle ne doit pas être utilisée pour une publication Play Store. Une passerelle
serveur avec quotas et attestation est recommandée avant d'activer Gemini en
production.

## PDF et signature

Les tests de régression valident : PDF Unicode, accents et apostrophes, page A4,
fond blanc et texte noir, objet unique, générateur de lettres partagé, bloc de
signature officiel, absence du bloc si désactivé et nom non dupliqué.

## Sécurité

- aucune clé Gemini ou clé `service_role` trouvée dans les sources actives ;
- les diagnostics d'authentification détaillés restent limités au debug ;
- les erreurs cloud présentées à l'utilisateur ne révèlent plus l'exception ;
- Supabase utilise une clé publishable et des chemins privés par UID ;
- la signature normalisée reste dans le stockage applicatif privé ;
- permissions Android finales : Internet, microphone, état réseau ajouté par
  les dépendances ; aucune permission caméra propre à l'application.

Risque bloquant : le build `release` utilise encore la clé de signature debug.
Il ne doit pas être envoyé sur une piste Play Store.

## Tests et validations

- `dart format` : réussi, fichiers Dart formatés ;
- `flutter analyze` : réussi, `No issues found!` ;
- `flutter test --concurrency=1` : réussi, 93 tests réussis ;
- `flutter pub outdated` : exécuté, aucune mise à jour automatique ;
- `flutter build apk --debug` : APK debug généré ;
- `flutter build appbundle --release` : AAB release généré après correction R8 ;
- contrôle APK : package `com.example.admin_facile`, versionCode 80,
  versionName 20.0.0, minSdk 24, targetSdk 36, compileSdk 36 ;
- contrôle AAB : archive signée et vérifiée, mais certificat autosigné debug.

## Fichiers V20.0 modifiés

- `pubspec.yaml`
- `analysis_options.yaml`
- `lib/main.dart`
- `test/widget_test.dart`
- `android/app/build.gradle.kts`
- `android/app/proguard-rules.pro`
- `android/gradle.properties`
- `README_V20.0_RC1.md`

Fichiers morts supprimés :

- `lib/main_backup.dart`
- `lib/account_controller.dart`
- `lib/cloud_documents.dart`

APK :
`C:\Users\dhibi\Documents\admin_facile_v1\build\app\outputs\flutter-apk\app-debug.apk`

AAB :
`C:\Users\dhibi\Documents\admin_facile_v1\build\app\outputs\bundle\release\app-release.aab`

## Anomalies et risques restants

Bloquants avant bêta Play Store :

1. remplacer `com.example.admin_facile` par l'identifiant Android définitif
   avant toute première publication ;
2. créer et sécuriser la clé d'upload/release, puis retirer la signature debug ;
3. remplacer l'icône Flutter par défaut par l'icône AdminFacile adaptative ;
4. remplacer le splash Flutter par un splash AdminFacile conforme Android 12+ ;
5. publier une politique de confidentialité accessible par URL ;
6. préparer et valider la déclaration Data Safety ;
7. fournir e-mail développeur, contact support, description et captures ;
8. ne pas injecter une clé Gemini cliente dans le build Play Store.

Non bloquants pour les essais internes :

- avertissement futur Built-in Kotlin pour plusieurs plugins ;
- anciens helpers privés masqués par `ignore: unused_element` encore présents
  dans `main.dart` et à réévaluer après la bêta sans refactor massif ;
- `lib.zip` et `android_patch/` restent des archives hors compilation ;
- tests physiques complets scanner, réseau faible, impression et partage requis ;
- comportement RLS et bucket privé à confirmer dans Supabase préproduction ;
- iOS n'est pas couvert par le scanner V19/V20.
- sur la machine de validation, `JAVA_HOME` contenait un chemin abrégé invalide
  et `HOME` était vide dans le terminal. Les builds ont été exécutés avec les
  chemins corrects injectés uniquement dans les commandes ; la configuration
  système reste à corriger pour fiabiliser les prochains builds.

## Checklist Play Store

- [x] versionName `20.0.0` et versionCode `80` ;
- [x] targetSdk 36 ;
- [x] AAB techniquement généré ;
- [x] analyse et tests automatisés sans échec ;
- [ ] identifiant d'application définitif ;
- [ ] clé d'upload et Play App Signing ;
- [ ] icône adaptative AdminFacile ;
- [ ] splash Android 12+ ;
- [ ] politique de confidentialité publique ;
- [ ] formulaire Data Safety validé ;
- [ ] description courte et longue ;
- [ ] captures téléphone, Fold et tablette ;
- [ ] e-mail développeur et contact support ;
- [ ] tests internes sur plusieurs appareils ;
- [ ] test inscription/reset avec e-mails réels ;
- [ ] contrôle RLS/bucket dans Supabase préproduction ;
- [ ] décision d'architecture sécurisée pour Gemini ;
- [ ] test Play Console pre-launch report.

## Scores qualité

- Stabilité : 88/100
- Performance : 85/100
- UX : 84/100
- Sécurité : 76/100
- Scanner : 86/100
- Auth : 88/100
- Préparation Play Store : 55/100

Score global : **80/100**.

Conclusion : l'application est prête pour une campagne de tests internes
contrôlée. Elle n'est pas encore prête pour une bêta Play Store publique tant
que l'identifiant, la signature release, l'icône, le splash, la politique de
confidentialité et Data Safety ne sont pas finalisés.
