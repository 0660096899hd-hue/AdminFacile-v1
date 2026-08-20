# AdminFacile V20.4.0+85 — Google Auth et proxy Gemini

Date de validation : 11 août 2026. Aucun commit, push, déploiement Supabase ou envoi Google Play n'a été effectué.

## 1. Architecture Google Sign-In retenue

L'application utilise `google_sign_in` 7.2.0. Son implémentation Android 7.x repose sur **Sign in with Google via Android Credential Manager** et n'utilise plus l'ancien SDK Google Sign-In Android déprécié.

Flux : bouton `Continuer avec Google` → Credential Manager → ID token Google → `Supabase.auth.signInWithIdToken(OAuthProvider.google)` → session Supabase réelle → événement Auth → `AuthGate` → dashboard.

Le Client ID Web est injecté avec `--dart-define=GOOGLE_WEB_CLIENT_ID=...`. Il s'agit d'un identifiant public, jamais d'un client secret. En son absence, le bouton reste immédiatement visible mais désactivé et l'authentification e-mail reste disponible.

Supabase Flutter conserve et rafraîchit déjà la session localement (`autoRefreshToken: true`). Au redémarrage, `AuthGate` reconnaît la session restaurée. La déconnexion supprime la session Supabase locale, nettoie l'état Google si possible et le dashboard n'existe plus dans la pile de navigation.

## 2. Dépendances ajoutées ou modifiées

- Ajout direct : `google_sign_in: ^7.2.0`.
- Dépendances transitives Android : `google_sign_in_android` et Credential Manager fournis par le plugin officiel Flutter.
- Aucun ancien plugin Google Sign-In ni dépendance Android OAuth manuelle ajouté.
- `supabase_flutter` reste en 2.16.0 afin de ne pas provoquer de migration hors périmètre.
- L'icône `assets/google_g_logo.png` vient de l'actif officiel Google et conserve ses couleurs/proportions.

## 3. Intégration Supabase

Le token Google n'est jamais affiché, journalisé ni stocké par le code applicatif. Il est transmis directement au SDK Supabase. Une réponse sans `user` ou sans `session` est refusée. Les erreurs UI sont normalisées et ne reprennent jamais le texte brut susceptible de contenir un token.

Supabase demeure l'unique autorité de session. L'AuthGate existant traite donc Google comme e-mail/mot de passe, sans branche dashboard parallèle.

Dans Supabase Dashboard :

1. Ouvrir **Authentication > Providers > Google**.
2. Activer Google.
3. Renseigner le **Client ID Web** Google OAuth.
4. Renseigner son **Client secret Web** uniquement dans Supabase Dashboard ; ne jamais le mettre dans Flutter ou Git.
5. Vérifier dans un projet de recette que l'identity linking automatique par e-mail vérifié est actif/comporte le comportement décrit ci-dessous.

## 4. Configuration Google Cloud nécessaire

Dans le même projet Google Cloud / Google Auth Platform :

1. Configurer Branding : nom AdminFacile, logo, e-mail de support, domaine et politique de confidentialité.
2. Dans Data Access, conserver seulement `openid`, `userinfo.email` et `userinfo.profile`.
3. Créer un **OAuth Client ID Web**. Ce Client ID est utilisé dans Supabase et dans `GOOGLE_WEB_CLIENT_ID`. Son secret reste exclusivement dans Supabase.
4. Créer des **OAuth Client IDs Android** pour le package exact `fr.adminfacile.app`, un par certificat nécessaire : debug éventuel, clé d'upload locale et clé Play App Signing réelle.
5. Ne pas utiliser le Client ID Android comme `GOOGLE_WEB_CLIENT_ID` : Credential Manager attend le Client ID Web comme `serverClientId`/audience.

Commande de build configurée attendue :

```powershell
flutter build appbundle --release `
  --dart-define=GOOGLE_WEB_CLIENT_ID=<CLIENT_ID_WEB> `
  --dart-define=GEMINI_PROXY_URL=https://pmnjphgaxcmxmhurhucm.supabase.co/functions/v1/gemini-proxy
```

## 5. SHA-1 et SHA-256 : valeurs à ajouter et récupération

Aucune empreinte n'a été inventée ni copiée dans le dépôt.

- Clé d'upload locale : exécuter `cd android` puis `.\gradlew.bat signingReport`. Relever SHA-1 et SHA-256 de la variante `release`. Cette commande lit la configuration locale ; ne jamais publier `android/key.properties`.
- Alternative contrôlée : `keytool -list -v -keystore <chemin-du-keystore> -alias <alias>`, saisie du mot de passe de façon interactive.
- Clé Play App Signing réelle : Google Play Console → **Tester et publier > Configuration > Intégrité de l'application > Signature d'application**. Copier SHA-1 et SHA-256 dans un OAuth Client ID Android distinct.
- Ajouter chaque paire package + SHA dans Google Cloud Console → **Google Auth Platform > Clients > Create client > Android**.

## 6. Play App Signing

La clé d'upload locale signe l'AAB envoyé, mais Google Play re-signe l'APK distribué avec la clé **Play App Signing**. Les deux certificats doivent donc avoir leur propre Client ID Android pour `fr.adminfacile.app`. Tester obligatoirement une installation issue d'une piste de test Play ; un APK installé localement ne valide que le certificat local.

En cas de rotation future de clé Play, ajouter le nouveau SHA avant diffusion et conserver l'ancien client tant que d'anciennes installations doivent encore se connecter.

## 7. Redirect URI

Pour le provider Google Supabase, ajouter dans le Client OAuth Web Google l'URI autorisée :

`https://pmnjphgaxcmxmhurhucm.supabase.co/auth/v1/callback`

Le flux Android natif de cette version échange directement un ID token et ne dépend pas d'un deep link OAuth. Le deep link `io.adminfacile://reset-password` existant reste réservé à la récupération de mot de passe et n'a pas été modifié.

## 8. Comportement des comptes existants

- **Nouveau compte Google** : Supabase crée un utilisateur et une identité Google, puis fournit une session.
- **Compte Google existant** : Supabase retrouve la même identité Google et restaure le même utilisateur.
- **Adresse déjà utilisée par e-mail/mot de passe** : Supabase relie automatiquement une identité Google portant le même e-mail **vérifié** au même utilisateur ; le même UUID doit être conservé. Vérifier ce point dans la recette Supabase avant production. Si le projet a désactivé ce comportement ou rencontre un conflit, l'application affiche une erreur générique et n'invente pas un second compte côté client. Ne pas tenter une recherche d'utilisateur depuis le téléphone et ne jamais utiliser de clé `service_role` dans l'application.
- **Annulation** : retour sur l'accueil avec `Connexion Google annulée.` sans session.
- **Erreur réseau** : message `Vérifiez votre connexion Internet.` sans détail technique.
- **Compte Google indisponible** : message indiquant qu'aucun compte Google n'est disponible.
- **Configuration OAuth invalide** : service temporairement indisponible. À noter : Credential Manager peut parfois remonter une erreur de configuration sous forme d'annulation ; contrôler en priorité package, SHA et Client ID Web.

Avant production, exécuter en recette trois tests avec contrôle du UUID dans Authentication > Users : création Google, reconnexion Google, puis connexion Google sur un compte e-mail confirmé existant.

## 9. Tests Google Auth

Tests ajoutés/adaptés : bouton Google visible, succès Google vers AuthGate/dashboard, annulation, erreur réseau, restauration de session, logout et impossibilité de retour Android, compte e-mail existant, verrou anti-double-lancement, et erreur brute sans fuite de token. Les tests historiques couvrent toujours création de compte Supabase, e-mail/mot de passe, affichage/masquage du mot de passe et scanner ML Kit release.

Résultat après la correction Notifications : **125 tests réussis, 0 échec**, avec `flutter test --concurrency=1`.

## 10. État Gemini actuel

`GeminiTransport` est conservé, mais le mode direct `GEMINI_API_KEY` côté Flutter a été supprimé. Le seul mode actif est un `GEMINI_PROXY_URL` HTTPS. Sans proxy, l'interface affiche discrètement `ASSISTANT IA INDISPONIBLE`; le reste de l'application et la génération locale continuent de fonctionner.

Le build de validation a volontairement été produit sans URL de production validée : Gemini y reste indisponible. Aucune clé Gemini n'est présente dans l'APK/AAB par ce mécanisme.

## 11. Architecture du proxy Gemini

La fonction Supabase Edge préparée dans `supabase/functions/gemini-proxy/index.ts` :

- accepte uniquement POST HTTPS ;
- exige le bearer token Supabase et vérifie l'utilisateur avec `auth.getUser()` côté serveur ;
- limite la requête à 64 Kio et le prompt à 40 000 caractères ;
- impose une liste de modèles autorisés ;
- applique un timeout amont de 35 secondes ;
- appelle Gemini côté serveur ;
- garde `GEMINI_API_KEY` dans les secrets Deno ;
- ne journalise ni prompt, ni document, ni token ;
- renvoie seulement des codes d'erreur génériques et jamais la clé ;
- utilise la fonction SQL atomique `consume_gemini_quota` pour 6 requêtes/minute et 50/jour/utilisateur.

La table de quota est protégée par RLS, sans accès direct `anon`/`authenticated`. Seule la fonction SQL `security definer`, fondée sur `auth.uid()`, est exécutable par un utilisateur authentifié.

## 12. Éléments manuels pour activer Gemini

Aucun déploiement n'a été effectué.

1. Installer/ouvrir la CLI Supabase et lier explicitement le bon projet : `supabase link --project-ref pmnjphgaxcmxmhurhucm`.
2. Relire les limites dans la migration, puis appliquer la migration : `supabase db push`.
3. Stocker la clé hors Git : `supabase secrets set GEMINI_API_KEY=<valeur>` (ne pas mettre la valeur dans l'historique du shell partagé).
4. Déployer après validation : `supabase functions deploy gemini-proxy --no-verify-jwt`. Le code vérifie lui-même chaque session via `auth.getUser()`.
5. URL finale attendue : `https://pmnjphgaxcmxmhurhucm.supabase.co/functions/v1/gemini-proxy`.
6. Faire un appel de recette avec utilisateur valide, puis vérifier 401 sans token, 413 au-delà de la taille, 429 au quota et 504 au timeout.
7. Construire l'AAB public avec uniquement `GEMINI_PROXY_URL` ; ne jamais passer `GEMINI_API_KEY` à Flutter.

Secrets serveur nécessaires : `GEMINI_API_KEY`. `SUPABASE_URL` et `SUPABASE_ANON_KEY` sont fournis automatiquement par l'environnement Edge Supabase. Aucun `service_role` n'est nécessaire.

## 13. Résultat flutter analyze

`flutter analyze` : **succès, No issues found**.

`dart format .` a été exécuté ; un fichier historique sous `android_patch/` a uniquement été reformaté. La passe finale ciblée `dart format lib test` n'a produit aucun changement supplémentaire.

## 14. Nombre total de tests

**125 tests**, tous réussis avec concurrence 1.

## 15. Résultat APK

`flutter build apk --release` : **succès**.

- Fichier : `build/app/outputs/flutter-apk/app-release.apk`
- Taille : 141 609 519 octets (affichage Flutter : 135,0 Mo)

## 16. Résultat AAB

`flutter build appbundle --release` : **succès**.

- Fichier : `build/app/outputs/bundle/release/app-release.aab`
- Taille : 117 562 925 octets (affichage Flutter : 112,1 Mo)

Gradle signale un avertissement futur sur des plugins appliquant encore KGP (`file_picker`, ML Kit, `share_plus`, `speech_to_text`), sans erreur de build actuelle. Aucune mise à niveau risquée n'a été imposée dans cette version.

Métadonnées contrôlées dans `output-metadata.json` :

- `applicationId` : `fr.adminfacile.app`
- `versionName` : `20.4.0`
- `versionCode` : `85`

## 17. Fichiers modifiés

- `pubspec.yaml`, `pubspec.lock`
- `lib/main.dart`
- `lib/google_auth_service.dart` (nouveau)
- `lib/notification_store.dart` (nouveau)
- `assets/google_g_logo.png` (nouveau)
- `test/widget_test.dart`
- `test/scanner_android_release_config_test.dart`
- `supabase/config.toml` (nouveau)
- `supabase/functions/gemini-proxy/index.ts` (nouveau)
- `supabase/migrations/202608110001_gemini_quota.sql` (nouveau)
- `macos/Flutter/GeneratedPluginRegistrant.swift` (généré par Flutter pour le nouveau plugin)
- `android_patch/lib/main.dart` (formatage Dart uniquement)
- `README_V20.4_GOOGLE_AUTH_GEMINI.md` (nouveau)

Les artefacts de build se trouvent sous `build/` et ne sont pas destinés à être commités. Aucun fichier de clé, mot de passe, token ou secret OAuth n'a été ouvert ou affiché pendant cette validation.

## 18. Correction du bouton et centre de notifications

La cloche du dashboard possède désormais sa propre destination `Notifications`. La loupe reste exclusivement reliée à `Recherche globale`; les deux callbacks et les deux pages sont distincts.

Le centre repose sur `NotificationStore`, un store local persistant dans `SharedPreferences`. Il conserve le type, le message, la date, l'état lu/non lu et une cible document/démarche. Aucun contenu fictif n'est créé au chargement. Les notifications automatiques proviennent seulement d'événements constatés par l'application : ajout réel d'un document, création réelle d'une démarche, rappel réellement attaché à une démarche, synchronisation réussie ou synchronisation échouée.

L'écran fournit :

- l'état vide `Aucune notification pour le moment` ;
- une date et heure locales lisibles ;
- un indicateur bleu pour chaque notification non lue ;
- `Tout marquer comme lu` dès qu'il existe plusieurs notifications dont au moins une non lue ;
- un badge `1` à `9+` sur la cloche, absent à zéro ;
- l'ouverture directe d'une fiche correspondant au document ou à la démarche ciblée.

Les tests vérifient séparément Recherche, Notifications, l'état vide, la distinction des routes, le non-lu, le badge, la lecture globale et l'ouverture des deux types de cibles.

Validation après cette correction : `dart format lib test` réussi, `flutter analyze` sans problème, **125/125 tests réussis**. Une régénération combinée APK/AAB a été relancée, mais le processus Gradle silencieux a atteint le timeout de 20 minutes avant de produire un résultat. Les artefacts mentionnés aux sections 15 et 16 sont donc ceux de la validation V20.4 précédente et ne contiennent pas encore cette correction Notifications ; ils ne doivent pas être publiés. Aucun déploiement ni publication n'a été tenté.
