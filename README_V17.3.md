# AdminFacile V17.3

Version Flutter : `17.3.0+62`.

## Bibliothèque

La bibliothèque contient **542 modèles** aux identifiants uniques : les 500 modèles locaux V17.1 sont conservés et 42 modèles structurés V17.3 complètent les catégories et les recherches courantes. Plus de 500 titres sont distincts.

Chaque modèle manipulé par l’application expose un identifiant, un titre, une catégorie, une sous-catégorie, un organisme éventuel, des mots-clés, une description courte, un objet, un corps personnalisable, les champs à compléter et un ton recommandé. Aucune référence juridique précise n’a été ajoutée.

Catégories disponibles : Administration, CAF, CPAM / Assurance Maladie, Impôts, France Travail, Retraite, Préfecture, Mairie, Éducation, Logement, Bailleur, Énergie, Eau, Télécoms, Banque, Crédit, Assurance, Santé, Travail, Employeur, Automobile, Consommation, Achats en ligne, Transport, Justice, Famille, Voisinage, Résiliation, Réclamation, Contestation, Mise en demeure, Demande de document, Relance et Divers.

## Recherche centrale

La loupe de l’accueil ouvre la recherche globale. Elle interroge en même temps les modèles, les démarches, les documents et les favoris, puis limite chaque première section à quatre résultats avec un accès **Voir tout**.

La recherche des modèles normalise les accents et utilise le titre, la catégorie, la sous-catégorie, l’organisme, la description, l’objet et les mots-clés. Des correspondances dédiées couvrent notamment « résilier Orange » et « facture EDF ».

## Favoris et historique

Les favoris et les modèles récemment utilisés restent stockés localement dans SharedPreferences. Seuls leurs identifiants sont enregistrés ; le contenu complet des modèles n’est jamais dupliqué.

## Interface

- Recherche, notifications et profil sont regroupés dans l’en-tête.
- Créer une lettre conserve les choix Générer avec Gemini et Utiliser un modèle.
- La bibliothèque affiche une recherche, des filtres compacts, des cartes courtes, une étoile discrète et le bouton Utiliser ce modèle.
- Les listes utilisent une construction paresseuse pour ne créer que les cartes visibles.

## Fichiers modifiés

- `lib/main.dart`
- `pubspec.yaml`
- `test/widget_test.dart`
- `README_V17.3.md`

Les fichiers et données des versions V17.1 à V17.2 sont conservés.

## Tests exécutés

- loupe et ouverture de la recherche globale ;
- recherche modèles, démarches et documents ;
- 542 modèles et 542 identifiants uniques ;
- au moins 500 titres distincts ;
- catégories demandées ;
- requêtes Orange et EDF ;
- stockage des favoris et récents par identifiant ;
- choix Gemini/modèle ;
- tailles de téléphone, thèmes clair et sombre ;
- suite historique complète.

## Tests sur téléphone

1. Tester la loupe en modes clair et sombre.
2. Rechercher CAF, Orange, résilier Orange, facture EDF et échéancier.
3. Vérifier les sections Modèles, Mes démarches, Mes documents et Favoris.
4. Tester Voir tout puis les filtres de catégorie, favoris et récents.
5. Ajouter et retirer plusieurs favoris, redémarrer l’application et vérifier leur persistance.
6. Utiliser des modèles puis vérifier l’ordre des récents.
7. Ouvrir Créer une lettre et tester les deux méthodes.
8. Contrôler l’absence d’overflow sur Galaxy Z Fold5 fermé et ouvert, téléphone étroit et tablette.

## APK

`build/app/outputs/flutter-apk/app-debug.apk`
