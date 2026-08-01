# AdminFacile V13.1 — Gemini Flash-Lite

## Lancement de test

Ne mettez jamais la clé dans `main.dart`. Lancez :

```powershell
flutter run -d RFCW611W5BE --dart-define=GEMINI_API_KEY=VOTRE_CLE
```

Modèle par défaut : `gemini-3.5-flash-lite`.

## Test

1. Scanner ou coller un courrier.
2. Appuyer sur **Que dois-je faire ?**.
3. Appuyer sur **Expliquer simplement avec Gemini**.
4. Vérifier le résumé, les dates, montants, références et actions.

Si la clé ou Internet manque, l’analyse locale reste affichée.

## Sécurité

`--dart-define` convient uniquement aux essais personnels. Avant publication, utilisez un serveur intermédiaire ou Firebase AI Logic/App Check afin de ne pas exposer la clé dans l’application mobile.
