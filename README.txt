AdminFacile V15.4.2 - Correction main.dart

1. Sauvegarder votre ancien lib/main.dart.
2. Remplacer lib/main.dart par le fichier fourni.
3. Exécuter:
   dart format lib/main.dart
   flutter analyze
   flutter test
   flutter run -d RFCW611W5BE

Corrections:
- Icône cloud visible dans Mes démarches.
- Statut Synchronisée / Non synchronisée.
- Upload PDF vers admin-documents/{uid}/procedures.
- Initialisation Supabase.
- Connexion/création de compte Supabase dans Profil.
- Bouton profil de l'accueil actif.
- Correction de la structure cassée autour de ProceduresScreen.
