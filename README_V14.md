# AdminFacile V14

## Nouveautés
- Microphone intégré dans les principaux champs de saisie et de modification.
- Analyse Gemini adaptative selon le type de document.
- Vue facture simplifiée avec libellés et montants associés.
- Bouton « Voir plus de détails » pour les analyses longues.
- Chat Gemini pour poser des questions sur le document.
- Rédaction Gemini et amélioration de lettres conservées.
- Scanner, OCR, PDF, confidentialité, thèmes, documents et démarches conservés.

## Lancement
```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d RFCW611W5BE --dart-define=GEMINI_API_KEY=VOTRE_CLE
```

La clé API ne doit pas être stockée dans les fichiers du projet.
