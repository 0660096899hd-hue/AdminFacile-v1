# AdminFacile V17.1

Version : `17.1.0+58`

## Architecture de l’analyse locale

`SmartDocumentLocalAnalyzer` traite le texte OCR sans réseau. Il normalise le texte, classe le document avec des mots-clés fiables, puis extrait uniquement les valeurs associées à des libellés explicites : total à payer, date limite et référence client/facture. Les mentions légales, capital social, SIREN/SIRET, montants HT intermédiaires et TVA isolée ne sont pas retenus.

La fiche locale reste disponible même sans clé Gemini ou sans connexion. Le texte OCR original est conservé et présenté dans « Voir le texte reconnu », replié par défaut.

## Rôle optionnel de Gemini

Gemini n’est appelé qu’après un appui volontaire sur « Améliorer avec Gemini ». Le prompt exige un JSON strict, des chaînes vides pour les données absentes, un résumé court et une confiance bornée entre 0 et 1. Le parsing valide les types et conserve l’analyse locale en cas d’erreur. Aucune clé API n’est stockée ou modifiée par cette version.

## Champs structurés ajoutés

`SavedDocument` conserve désormais, avec valeurs par défaut rétrocompatibles :

- `detectedDocumentType`
- `detectedAmount`
- `detectedDueDate`
- `detectedReference`
- `detectedOrganisation`
- `detectedPriority`
- `analysisConfidence`
- `userCorrectedAnalysis`

## Règles de prudence

- aucune donnée manquante n’est inventée ;
- rouge uniquement pour une échéance explicite située dans les quatorze jours ;
- les corrections manuelles sont marquées et persistées ;
- chaque fiche rappelle de vérifier le document original ;
- aucun bouton de paiement n’est proposé.

## Fichiers modifiés

- `lib/main.dart`
- `pubspec.yaml`
- `test/widget_test.dart`
- `README_V17.1.md`

## Tests ajoutés

- classification PRIMAGAZ, EDF, Orange, CAF et CPAM ;
- sélection du total dû et exclusion du capital social/TVA ;
- absence d’invention ;
- migration de `SavedDocument` ;
- persistance des corrections ;
- texte OCR replié et écran étroit sans overflow ;
- actions adaptées et aperçu interne sans impression automatique.

## Scénarios téléphone

1. Scanner une facture PRIMAGAZ, EDF et Orange sur Galaxy Z Fold5 fermé.
2. Comparer la fiche avec le document original, notamment total dû et échéance.
3. Déplier puis modifier le texte OCR, sans perte du texte complet.
4. Corriger chaque champ, enregistrer et rouvrir depuis Mes documents.
5. Tester « Contester cette facture » et vérifier fournisseur, montant et contexte OCR.
6. Tester Gemini configuré, non configuré, hors connexion et réponse JSON invalide.
7. Tester les actions, le cloud et l’aperçu en thèmes clair/sombre et sur tablette.

## APK

`build/app/outputs/flutter-apk/app-debug.apk`
