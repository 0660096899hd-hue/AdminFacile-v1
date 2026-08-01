# AdminFacile V2.1.1 — correction Android et tests

Corrections :
- `file_picker` fixé à la version 10.3.10 pour éviter l'erreur Android `FilePickerPlugin`.
- Retour à `FilePicker.platform.pickFiles()`.
- Stockage `SharedPreferences` rendu testable.
- Test Flutter initialisé avec `SharedPreferences.setMockInitialValues`.

Après remplacement des fichiers, exécuter :

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d RFCW611W5BE
```

Si Flutter conserve l'ancienne version du plugin, supprimer aussi `pubspec.lock` avant `flutter pub get`.
