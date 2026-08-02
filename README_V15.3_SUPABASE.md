# AdminFacile V15.3.1 — Espace sécurisé Supabase

Cette version remplace Firebase Storage par Supabase Auth + Supabase Storage.

## Important

Pour que les politiques privées fonctionnent réellement, le compte utilisateur de l’application est maintenant géré par Supabase Auth. Firebase Authentication peut rester activé dans votre ancien projet, mais il n’est pas utilisé par cette version.

## Configuration Supabase

1. Dans Authentication > Providers, activez Email.
2. Pour un test immédiat, vous pouvez désactiver temporairement la confirmation d’e-mail dans Authentication > Settings. Sinon, confirmez l’e-mail reçu avant de vous connecter.
3. Conservez le bucket `admin-documents` en privé.
4. Ouvrez SQL Editor, puis exécutez le contenu de `supabase_storage_policies.sql`.

## Lancement

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d RFCW611W5BE `
  --dart-define=GEMINI_API_KEY=TA_CLE_GEMINI `
  --dart-define=SUPABASE_URL=https://pmnjphgaxcmxmhurhucm.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=TA_CLE_PUBLIABLE
```

## Test

1. Ouvrez Profil.
2. Créez un compte ou connectez-vous.
3. Dans Mes documents, appuyez sur l’icône cloud d’un PDF.
4. Ouvrez Mon espace sécurisé.
5. Testez Actualiser, Télécharger et Supprimer.

## Sécurité

N’utilisez jamais une clé `sb_secret_...` dans Flutter. La clé `sb_publishable_...` est prévue pour les applications clientes et reste protégée par les politiques RLS.
