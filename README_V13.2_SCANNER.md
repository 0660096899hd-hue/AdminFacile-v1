# AdminFacile V13.2 — Scanner stabilisé

## Corrections

- `getScannedDocumentAsPdf()` utilise désormais le résultat typé `PdfScanResult`.
- Suppression de la conversion incorrecte vers `Map<dynamic, dynamic>`.
- Lecture directe de `result.pdfUri` et `result.pageCount`.
- Messages d'erreur compréhensibles avec bouton **Réessayer**.
- Indicateur de progression pour le scan et l'OCR.
- Correction d'une déclaration `saveFile` dupliquée dans l'enregistrement PDF.
- Gemini reste configuré par `--dart-define` et l'analyse locale reste disponible en secours.

## Test

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d RFCW611W5BE --dart-define=GEMINI_API_KEY=VOTRE_CLE
```

Ne placez pas la clé API dans les fichiers du projet.
