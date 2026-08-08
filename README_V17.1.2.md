# AdminFacile V17.1.2

Version Flutter : `17.1.2+60`.

## Trois points horizontaux

Tous les menus d’actions actifs utilisent explicitement `Icons.more_horiz_rounded` avec le tooltip **Plus d’actions**. Les anciens `Icons.more_vert` et `Icons.more_vert_rounded` ont été retirés de l’application principale. Cela concerne la fiche intelligente et le PDF prêt du Scanner, Mes démarches, Mes documents et le coffre-fort documentaire.

## Lisibilité du mode clair

Le widget partagé par **Traduire**, **Dictée libre** et **Scanner** adapte désormais son style à la luminosité du thème. En mode clair, il utilise un fond blanc, une bordure bleu clair, un texte et une icône bleu foncé ainsi qu’une ombre légère. Le style sombre existant est conservé.

## Version Premium

Une entrée discrète **Version Premium**, avec accent doré, est placée en bas du menu latéral au-dessus du sélecteur de thème. Elle ouvre une boîte de dialogue informative annonçant la disponibilité prochaine. Aucun achat ni paiement n’est intégré.

## Fichiers modifiés

- `lib/main.dart`
- `lib/main_backup.dart`
- `pubspec.yaml`
- `test/widget_test.dart`
- `README_V17.1.2.md`

Les fichiers et fonctionnalités V17.1/V17.1.1 déjà présents sont conservés.

## Tests exécutés

- absence des icônes verticales dans l’application principale ;
- présence des quatre icônes horizontales et des quatre tooltips ;
- couleurs de fond, texte et bordure des trois actions en mode clair ;
- présence et ouverture de la boîte de dialogue Premium ;
- absence d’overflow à 320 × 568 et 344 × 700 ;
- suite complète des tests historiques.

## Points à vérifier sur téléphone

1. Contrôler les points horizontaux dans Scanner, PDF prêt, fiche intelligente, Mes documents et Mes démarches.
2. Vérifier le tooltip **Plus d’actions** avec un appui long ou les outils d’accessibilité.
3. En mode clair, contrôler Traduire, Dictée libre et Scanner sur l’accueil.
4. Refaire le contrôle en mode sombre et confort.
5. Ouvrir le menu latéral, toucher Version Premium puis fermer la boîte de dialogue.
6. Vérifier l’absence de débordement sur Galaxy Z Fold5 fermé et ouvert.

## APK

`build/app/outputs/flutter-apk/app-debug.apk`
