# AdminFacile V18.2 — Authentification professionnelle

Version : `18.2.0+72`

## Audit et causes exactes

### Initialisation Supabase

L’application utilise le projet
`https://pmnjphgaxcmxmhurhucm.supabase.co` avec une clé publique Supabase
(`sb_publishable_…`). La clé est une clé cliente publique, pas une clé
`service_role`. Le point de santé Auth `/auth/v1/health` a répondu HTTP 200 avec
GoTrue v2.195.0 le 8 août 2026.

Avant V18.2, une exception de `Supabase.initialize()` pouvait interrompre le
démarrage. L’initialisation est désormais protégée ; l’application reste
utilisable localement et conserve la cause complète pour le diagnostic debug.
Les options PKCE, restauration d’URI et rafraîchissement automatique sont
maintenant explicites.

### Cause du problème de connexion

Deux propriétaires de session coexistaient :

- l’interface active utilisait `supabase_flutter` ;
- `AccountController` appelait directement les endpoints REST GoTrue et
  enregistrait une deuxième copie des access/refresh tokens dans
  `SharedPreferences`.

Ces sessions pouvaient diverger après rafraîchissement, expiration ou
déconnexion. De plus, l’interface affichait directement certains messages
anglais de `AuthException` et transformait toute autre exception en
« Connexion impossible », sans distinguer réseau, timeout, serveur ou réponse
invalide.

`AccountController` est maintenant seulement un pont de compatibilité vers le
client officiel. Il ne persiste plus aucun jeton et ne renouvelle plus une
session en parallèle.

### Cause du problème d’inscription

L’ancien écran considérait tout retour sans exception comme un succès, sans
examiner si Supabase avait créé une session ou demandait une confirmation
e-mail. Il ne détectait pas non plus le retour volontairement neutre que
Supabase peut produire pour une adresse déjà inscrite, et ne transmettait
aucune métadonnée de profil.

La nouvelle couche vérifie maintenant :

- la présence d’un utilisateur dans la réponse ;
- la présence ou l’absence de session ;
- une liste d’identités vide, indicatrice d’une adresse déjà inscrite ;
- la confirmation e-mail requise ;
- le format de l’e-mail et la longueur du mot de passe avant le réseau.

## Architecture V18.2

`ProfessionalAuthService` est la couche unique et testable. En production,
`SupabaseAuthGateway` délègue à `Supabase.instance.client.auth`.

Fonctions couvertes :

- `signUp()` ;
- `signIn()` ;
- `sendPasswordReset()` ;
- `updatePassword()` ;
- `updateProfile()` ;
- `signOut()`.

Chaque opération possède un timeout de 15 secondes. Les erreurs réseau,
timeout, réponse invalide, session expirée, compte non confirmé, mot de passe
incorrect, e-mail invalide, doublon et erreur serveur ont un message français
distinct.

En debug, `AuthOperationException.displayMessage` ajoute la fonction, le code
Supabase et l’exception complète. Cette branche dépend de `kDebugMode` et ne
s’affiche jamais en release.

## Session et changements d’état

`supabase_flutter` assure désormais seul :

- la persistance locale de session ;
- la restauration au démarrage ;
- le rafraîchissement automatique ;
- la reconnexion ;
- le traitement PKCE des liens entrants ;
- la suppression locale lors de la déconnexion.

`AppShell` continue d’écouter `onAuthStateChange`, annule son abonnement dans
`dispose()` et journalise toute erreur du flux sans faire planter l’interface.

## Récupération et changement de mot de passe

Le bouton « Mot de passe oublié ? » envoie un e-mail de récupération. Android
et iOS déclarent le lien `io.adminfacile://reset-password`. Après ouverture du
lien, l’utilisateur peut utiliser « Changer le mot de passe » dans son compte.

Le redirect URL doit également être autorisé dans le tableau de bord Supabase :
`Authentication > URL Configuration > Redirect URLs`. Cette configuration
distante ne peut pas être modifiée depuis le dépôt.

## Profil et RLS

AdminFacile ne réalise aucune insertion dans une table SQL `profiles`. Le profil
administratif reste stocké localement et les champs `first_name`, `last_name`
et `display_name` sont synchronisés dans `auth.users.user_metadata` via
`updateUser()` lorsqu’une session existe.

Cette méthode ne dépend pas d’une table applicative ni d’une politique RLS ;
elle élimine donc le blocage SQL/RLS qui aurait pu apparaître lors d’une
insertion de profil non configurée. Les politiques Storage existantes restent
inchangées.

## Tests automatisés

Les tests utilisent un faux backend et ne créent aucune donnée utilisateur :

- inscription avec connexion automatique ;
- inscription avec confirmation e-mail ;
- adresse déjà utilisée ;
- mauvais mot de passe ;
- e-mail invalide ;
- récupération du mot de passe ;
- reconnexion ;
- restauration d’une session ;
- déconnexion ;
- absence de réseau ;
- réponse invalide ;
- serveur indisponible ;
- diagnostic debug ;
- mise à jour du profil sans SQL.

## Fichiers modifiés

- `lib/professional_auth_service.dart`
- `lib/account_controller.dart`
- `lib/main.dart`
- `test/professional_auth_service_test.dart`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- `pubspec.yaml`
- `README_V18.2.md`

Le scanner, les générateurs PDF et Gemini n’ont pas été modifiés.

## Validations

- `dart format` : réussi ;
- `flutter analyze` : `No issues found!` ;
- tests Auth V18.2 : 13 réussis ;
- `flutter test` complet : 91 tests réussis ;
- `flutter build apk --debug` : réussi, APK debug généré.

Chemin de l’APK généré :
`C:\Users\dhibi\Documents\admin_facile_v1\build\app\outputs\flutter-apk\app-debug.apk`

## Validation manuelle Supabase restante

Les tests automatisés n’écrivent volontairement pas dans le projet Supabase.
Avant publication, utiliser deux adresses de test dédiées pour vérifier la
politique réelle de confirmation e-mail, l’autorisation du redirect URL et la
réception des e-mails. Ne pas utiliser de compte utilisateur réel pour ce test.
