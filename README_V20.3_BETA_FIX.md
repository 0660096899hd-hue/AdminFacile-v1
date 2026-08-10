# V20.3 bêta — configuration IA / Gemini en release

## État de la configuration

L’application reconnaît désormais trois modes via `GeminiTransport.configurationMode` :

- `disabled` : aucune configuration ; l’application reste entièrement utilisable sans IA et affiche « Assistant IA momentanément indisponible. » ;
- `direct-beta` : `GEMINI_API_KEY` est fournie avec `--dart-define` et l’application appelle directement Google ;
- `proxy` : `GEMINI_PROXY_URL` est fournie et l’application appelle le backend HTTPS. Ce mode est prioritaire si une clé directe est également définie.

Variables acceptées :

- `GEMINI_PROXY_URL` : endpoint HTTPS du proxy de production ;
- `GEMINI_MODEL` : modèle demandé (valeur par défaut actuelle : `gemini-3.5-flash-lite`) ;
- `GEMINI_TIMEOUT_SECONDS` : délai de 5 à 120 secondes (40 secondes par défaut) ;
- `GEMINI_API_KEY` : compatibilité **bêta interne seulement**.

Android déclare déjà la permission `INTERNET`. Aucun secret Gemini n’est présent dans le manifeste, Gradle, les assets ou le code source.

## Debug, APK release et AAB Play

Une `dart-define` est une donnée de compilation. Elle doit donc être passée à **chaque** commande qui produit le binaire : sa présence lors d’un `flutter run` debug ne la transfère pas à un APK ou un AAB ultérieur.

Exemples sans valeur réelle dans l’historique Git :

```text
flutter run --dart-define=GEMINI_API_KEY=<CLE_BETA>
flutter build apk --release --dart-define=GEMINI_API_KEY=<CLE_BETA>
flutter build appbundle --release --dart-define=GEMINI_PROXY_URL=https://backend.example/ai/gemini
```

Le Play Store ne rajoute et ne retire aucune `dart-define` : l’AAB installé contient exactement la configuration compilée avant l’envoi. Le build Play public recommandé ne contient que l’URL du proxy, jamais `GEMINI_API_KEY`.

## Sécurité

`--dart-define=GEMINI_API_KEY=...` **n’est pas suffisamment sécurisé pour une publication publique**. La valeur est incorporée au binaire Flutter et peut être extraite ou utilisée abusivement, même si elle n’apparaît jamais dans les logs. Les restrictions de clé Android ne suffisent pas à transformer une clé embarquée en secret.

Le mode direct reste disponible pour une bêta interne limitée. Ne jamais committer un fichier contenant la clé, copier la clé dans un script versionné, ni publier les sorties détaillées des requêtes. L’interface ne montre désormais ni réponse d’erreur distante, ni URL, ni clé.

## Architecture de production recommandée

L’application envoie au `GEMINI_PROXY_URL` un `POST` JSON :

```json
{
  "model": "gemini-3.5-flash-lite",
  "prompt": "…",
  "generationConfig": {}
}
```

Si une session Supabase existe, son jeton est transmis dans `Authorization: Bearer …`. Le backend doit :

1. exiger et vérifier l’identité de l’utilisateur (ou une attestation d’application adaptée) ;
2. conserver la clé Gemini exclusivement dans son gestionnaire de secrets ;
3. appliquer quotas, limitation de débit, taille maximale, contrôle du modèle et délais ;
4. ne pas journaliser les documents, prompts, jetons ou secrets ;
5. appeler Gemini côté serveur et renvoyer l’enveloppe `generateContent` de Google à l’application ;
6. répondre par un statut non-2xx sans exposer de détail interne en cas d’échec.

Le client refuse une URL proxy non HTTPS en release (localhost reste autorisé en debug).

## Couverture des erreurs et tests

Le transport commun couvre la génération de lettre, l’analyse de document et les questions sur document. Il applique le même timeout et transforme statut HTTP invalide, JSON invalide et réponse vide en indisponibilité générique. La génération V15.6 conserve son modèle local de secours ; les autres écrans restent ouverts et modifiables.

Les tests automatisés couvrent : absence de configuration avec lettre locale, génération valide via proxy, timeout, erreur réseau, réponse non JSON et absence de clé dans la requête proxy.

Validation manuelle release :

1. construire et installer l’APK release configuré, puis générer une lettre ;
2. construire un AAB avec `GEMINI_PROXY_URL`, l’envoyer sur une piste de test interne Play et installer **depuis Google Play** ;
3. refaire la génération sur Wi-Fi puis réseau mobile ;
4. couper le réseau, simuler un timeout backend puis une réponse invalide et vérifier le message générique ainsi que la continuité de l’application ;
5. produire un AAB sans configuration et vérifier le mode indisponible et la lettre locale ;
6. contrôler les journaux Android et backend : aucune clé, aucun jeton et aucun contenu administratif ne doivent apparaître.

L’installation depuis Google Play et un appel réel ne sont pas reproductibles par un test unitaire local : ils restent une recette obligatoire sur la piste interne.

## Restant avant publication publique

- déployer le proxy HTTPS et son secret Gemini côté serveur ;
- définir et tester l’authentification, les quotas, la rétention et la supervision sans données sensibles ;
- vérifier que le modèle configuré est disponible pour le projet/région Gemini utilisé ;
- construire l’AAB final avec `GEMINI_PROXY_URL` et **sans** `GEMINI_API_KEY` ;
- exécuter la recette Play interne ci-dessus sur l’artefact signé et téléchargé depuis Play ;
- mettre à jour les déclarations de confidentialité/traitement des données selon le backend réellement déployé.

---

# Rapport final V20.3.0+83 — authentification et scanner

## 1. Cause exacte du problème scanner 20.2

Le canal Flutter, le package migré et la dépendance étaient corrects :

- canal identique des deux côtés : `adminfacile/mlkit_document_scanner` ;
- `namespace`, `applicationId`, package Kotlin et activité : `fr.adminfacile.app` ;
- dépendance officielle présente : `play-services-mlkit-document-scanner:16.0.0` ;
- permission `INTERNET` présente ; aucune permission caméra n’est requise par ce scanner, car sa caméra est fournie par Google Play Services ;
- R8/minification non activés dans le type release actuel. Les règles ProGuard OCR n’étaient donc pas la cause.

Le défaut était dans le cycle de retour natif : `MainActivity` lançait l’`IntentSender` avec l’ancienne paire `startIntentSenderForResult/onActivityResult` et conservait le `MethodChannel.Result` uniquement dans un champ mémoire. Ce chemin n’est pas celui recommandé pour le scanner ML Kit actuel et devient fragile lors d’un passage par l’activité caméra, où Android peut recréer l’activité. Un résultat sans attente Flutter active était alors ignoré (`scannerResult == null`), laissant l’appel Flutter sans résultat exploitable. La migration 20.2 n’a pas créé de désaccord de package, mais elle a reconduit ce pont legacy tel quel.

La compilation a également confirmé que le host `FlutterActivity` utilisé en 20.2 ne permettait pas d’enregistrer directement l’Activity Result API. Le host devait être adapté.

## 2. Correction scanner appliquée

- `MainActivity` utilise maintenant `FlutterFragmentActivity` ;
- le callback est enregistré inconditionnellement avec `registerForActivityResult(StartIntentSenderForResult())` ;
- suppression du request code manuel et de `onActivityResult` ;
- mode ML Kit `SCANNER_MODE_FULL`, jusqu’à 10 pages, import galerie désactivé ;
- résultats JPEG **et PDF** demandés au SDK ;
- toutes les pages sont copiées et validées dans `cacheDir/document_scans` avant retour à Flutter ;
- le PDF natif est également copié comme résultat de secours, tandis que Flutter continue de générer son PDF A4 contrôlé depuis les pages ;
- une page illisible produit un résultat partiel ; zéro page lisible produit une erreur ;
- l’utilisateur voit toujours une erreur claire avec `Réessayer`, `Prendre une photo` et `Importer un document` ;
- diagnostics Logcat non sensibles sous le tag `AdminFacileScanner` : identifiant court aléatoire, événement, étape, code et type d’exception uniquement. Aucun URI, chemin, image ou contenu OCR n’est journalisé.

## 3. Différences scanner debug/release

Le même code Kotlin, le même canal et la même dépendance ML Kit sont compilés en debug et release. La release actuelle n’active pas `isMinifyEnabled`; R8/ProGuard et le tree shaking Flutter ne retirent donc pas le pont scanner. Les modèles et l’interface du Document Scanner sont livrés par Google Play Services et peuvent nécessiter un premier téléchargement sur le téléphone, indépendamment du type de build.

La différence restant à valider physiquement est l’environnement : APK installé localement contre split APK généré par Google Play à partir de l’AAB, version de Google Play Services, disponibilité du module dynamique, modèle du téléphone et pression mémoire.

## 4. État de l’authentification obligatoire

Le splash est suivi par un `AuthGate` qui observe la session Supabase restaurée et tous les changements d’état :

- session et utilisateur valides : `AppShell`/dashboard ;
- aucune session, session expirée, logout ou erreur du flux auth : accueil d’authentification ;
- le dashboard n’est jamais construit sans session ;
- le portail et le dashboard sont deux branches d’un même gate, pas deux routes empilées. Après logout, Retour Android ne peut donc pas restaurer le dashboard.

`Supabase.initialize` reste exécuté avant `runApp`, avec restauration persistante et rafraîchissement automatique déjà configurés. Aucun schéma ni compte existant n’a été modifié.

## 5. Parcours création de compte

Accueil :

```text
AdminFacile
Simplifiez vos démarches administratives
[Créer mon compte]
[J’ai déjà un compte]
```

La création normalise et valide l’e-mail, impose un mot de passe d’au moins six caractères et appelle `Supabase.auth.signUp`. Si Supabase renvoie une session, le flux auth ouvre le dashboard. Si la confirmation e-mail est activée, l’utilisateur reste hors dashboard et reçoit l’instruction de confirmer son e-mail avant de se connecter. Les comptes déjà existants continuent d’utiliser le même projet Supabase et les mêmes méthodes Auth.

## 6. Parcours connexion, restauration et déconnexion

- connexion par e-mail/mot de passe avec messages dédiés pour identifiants invalides, compte non confirmé, réseau, timeout et indisponibilité serveur ;
- session Supabase restaurée au redémarrage avant décision du gate ;
- mot de passe oublié via `resetPasswordForEmail` et deep link `io.adminfacile://reset-password` conservé ;
- déconnexion locale Supabase, notification du gate, destruction de tout le sous-arbre dashboard ;
- aucun retour Android possible vers l’espace authentifié après logout.

## 7. État Gemini

Le travail Gemini réalisé au début de V20.3 est conservé sans changement d’architecture : mode désactivé, direct bêta interne et proxy HTTPS production, erreurs génériques et fonctionnement sans IA. La production publique doit utiliser `GEMINI_PROXY_URL` sans embarquer `GEMINI_API_KEY`.

## 8–11. Validation complète

- `dart format .` : terminé ; 13 fichiers inspectés par le formateur ;
- `flutter analyze` : **aucun problème** ;
- `flutter test --concurrency=1` : **109 tests réussis** ;
- APK debug : **construit**, `build/app/outputs/flutter-apk/app-debug.apk` ;
- AAB release : **construit**, `build/app/outputs/bundle/release/app-release.aab`, 111,7 Mo ;
- signature AAB : **présente et vérifiée** par `jarsigner -verify` avec code retour 0 ;
- package : `fr.adminfacile.app` ;
- `versionName` : `20.3.0` ;
- `versionCode` : `83` ;
- `minSdk` : 24 ;
- `targetSdk` : 36.

Le certificat d’upload est auto-signé, comportement normal pour une clé d’upload privée ; la vérification stricte Java ne peut pas construire une chaîne PKIX publique, mais la vérification cryptographique standard de l’AAB réussit. Aucun fichier de signature, mot de passe ou certificat n’a été affiché ou modifié.

## 12. Fichiers modifiés

- `android/app/src/main/kotlin/fr/adminfacile/app/MainActivity.kt` ;
- `lib/document_scanner_service.dart` ;
- `lib/main.dart` ;
- `pubspec.yaml` ;
- `test/widget_test.dart` ;
- `README_V20.3_BETA_FIX.md`.

## 13. Tests physiques restant obligatoires

Les tests automatisés et builds ne peuvent pas valider la caméra réelle, le téléchargement du module Google Play Services ou l’authentification réseau réelle. Avant diffusion, effectuer sur la piste Play interne :

1. installation neuve sans session : portail obligatoire, création de compte et confirmation e-mail réelle ;
2. connexion avec un compte existant, fermeture forcée, redémarrage et restauration de session ;
3. mot de passe oublié jusqu’au retour deep link et changement du mot de passe ;
4. logout depuis une page profonde, puis Retour Android : aucun dashboard ;
5. scanner sur au moins deux appareils Android avec Google Play Services à jour, dont un appareil modeste ;
6. premier lancement scanner avec Wi-Fi, puis scanner hors ligne une fois le module téléchargé ;
7. document A4 contrasté puis faible contraste : détection des quatre coins, capture automatique, correction manuelle, filtres et recadrage ;
8. scan de 2 à 10 pages, suppression/réorganisation dans ML Kit, retour de toutes les pages, OCR et ouverture du PDF ;
9. annulation, refus/indisponibilité Play Services et interruption de l’activité : message et deux fallbacks visibles ;
10. récupération Logcat filtrée sur `AdminFacileScanner` pour confirmer chaque étape sans donnée sensible ;
11. répétition complète avec l’application installée **depuis l’AAB de la piste Google Play interne**, qui reste la validation décisive de la régression 20.2.
