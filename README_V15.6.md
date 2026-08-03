# AdminFacile V15.6 — Assistant de rédaction Gemini

## Nouveautés

- Écran « Rédiger avec Gemini » enrichi avec sept types de courrier et quatre tons.
- Champs dédiés au destinataire, à l’objet, à la situation, au résultat souhaité et aux informations importantes.
- Dictée vocale disponible dans chaque zone de saisie, y compris la lettre générée.
- Consignes Gemini renforcées : réponses courtes, sans explications et sans invention de dates, montants, numéros de contrat ou faits absents.
- Repères explicites entre crochets lorsque des informations sont manquantes.
- Mode local automatique quand Gemini n’est pas configuré ou indisponible.
- États visibles : Prêt, Rédaction avec Gemini, Lettre prête et Erreur de connexion.
- Lettre modifiable manuellement après génération.
- Actions Corriger, Raccourcir, Rendre plus ferme, Rendre plus courtois, Simplifier et Régénérer.
- Enregistrement local dans « Mes démarches », sans envoi automatique vers Supabase.
- Export PDF et transmission avec la feuille de partage Android.
- Version du projet portée à `15.6.0+50`.

## Fichiers modifiés

- `lib/main.dart` : modèles V15.6, génération Gemini et locale, nouvel écran, sauvegarde, PDF et partage.
- `test/widget_test.dart` : tests V15.6 et mise à jour du test de démarrage.
- `pubspec.yaml` : version et description du projet.
- `README_V15.6.md` : présent récapitulatif.

## Tests exécutés

- `dart format lib/main.dart test/widget_test.dart`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`

## Points à tester sur téléphone

- Autorisation du microphone, démarrage/arrêt de la dictée et insertion du texte dans chaque champ.
- Génération réelle avec une clé Gemini, puis comportement hors ligne ou sans clé.
- Lisibilité et défilement du formulaire sur petits écrans Android.
- Modification manuelle de la lettre et chacune des six actions après génération.
- Présence de la lettre dans « Mes démarches » après redémarrage de l’application.
- Export du PDF dans un emplacement choisi et ouverture du fichier obtenu.
- Bouton « Transmettre » et sélection d’une application dans la feuille de partage Android.
- Vérification qu’aucun transfert Supabase n’est déclenché automatiquement.
