# AdminFacile V2.2.1 — correction speech_to_text

Correction des deux appels à `SpeechToText.listen()` :

- `options:` remplacé par `listenOptions:`
- `listenFor` et `pauseFor` déplacés dans `SpeechListenOptions`
- compatibilité avec `speech_to_text 7.4.0`

## Installation

Remplacer principalement `lib/main.dart`, puis lancer :

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d RFCW611W5BE
```
