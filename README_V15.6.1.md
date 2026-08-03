# AdminFacile V15.6.1

Version : `15.6.1+51`

## Fichiers modifiés

- `lib/main.dart`
- `pubspec.yaml`
- `test/widget_test.dart`
- `README_V15.6.1.md`

## Nouveautés

- Feuille blanche de type A4, adaptative, avec marges, coins arrondis et ombre dans l'éditeur de lettre.
- Texte, curseur et sélection lisibles en mode clair comme en mode sombre.
- Même présentation blanche dans l'aperçu **Ouvrir la lettre** de **Mes démarches**.
- Quatre formats : **Courrier officiel** (par défaut), **E-mail**, **Lettre recommandée** et **Mise en demeure**.
- Mise en page administrative avec expéditeur, destinataire, ville/date, objet, appel, paragraphes, politesse et signature.
- Reprise des seules informations disponibles dans le profil ; les données absentes restent des champs explicites à compléter.
- PDF A4 blanc, texte noir, objet en gras et marges professionnelles.
- Conservation de Gemini, du microphone, de Mes démarches, de l'export PDF, du partage et de Supabase.

## Tests effectués

- `dart format`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`

Les résultats définitifs sont consignés dans le compte rendu de livraison.

## À vérifier sur téléphone

- Lisibilité et défilement de la feuille sur petit écran en modes clair et sombre.
- Saisie, curseur, poignées et surbrillance de sélection dans la lettre.
- Passage entre les quatre formats avant génération.
- Reprise correcte des coordonnées enregistrées dans le profil.
- Enregistrement puis ouverture de la lettre depuis **Mes démarches**.
- Export, ouverture, partage et impression du PDF sur Android.
- Génération et amélioration Gemini, dictée micro et synchronisation Supabase.
