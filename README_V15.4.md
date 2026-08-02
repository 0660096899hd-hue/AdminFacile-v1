# AdminFacile V15.4

## Objectif
Rendre l’espace sécurisé Supabase testable sans retaper les paramètres à chaque lancement.

## Modifications
- URL Supabase et clé publiable configurées par défaut dans l’application.
- Les valeurs `--dart-define` restent prioritaires pour remplacer la configuration lors d’une future rotation de clé.
- Aucun secret Supabase n’est inclus.
- La clé Gemini n’est pas incluse.
- Correction de l’utilisation dépréciée de `localeId` dans le bouton micro principal.
- Version : `15.4.0+47`.

## Lancement
Sans Gemini :
```powershell
flutter run -d RFCW611W5BE
```

Avec Gemini :
```powershell
flutter run -d RFCW611W5BE --dart-define=GEMINI_API_KEY=TA_CLE_GEMINI
```

## Test du stockage
1. Ouvrir Profil.
2. Créer un compte Supabase ou se connecter.
3. Ouvrir Mes documents.
4. Appuyer sur l’icône cloud d’un PDF.
5. Ouvrir Mon espace sécurisé.
6. Tester actualisation, téléchargement et suppression.

## Sécurité
Le bucket `admin-documents` doit rester privé et les politiques RLS du fichier `supabase_storage_policies.sql` doivent avoir été exécutées dans Supabase.
