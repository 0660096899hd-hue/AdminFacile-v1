# Google Play Data Safety — brouillon

Ce document prépare le formulaire Play Console. Il ne doit pas être recopié
sans vérification de la configuration de production, des SDK et des contrats
fournisseurs. Dans le vocabulaire Google Play, une donnée est « collectée »
lorsqu’elle est transmise hors de l’appareil, même pour un traitement
éphémère.

## Résumé proposé

- L’application collecte-t-elle des données ? **Oui**, si le compte, le cloud,
  Gemini ou un service vocal réseau sont utilisés.
- Partage-t-elle des données avec des tiers ? **À VÉRIFIER** selon la
  qualification de Supabase et Google comme prestataires, et selon le caractère
  explicitement déclenché des actions Gemini/partage.
- Chiffrement en transit : **Oui** pour les endpoints HTTPS identifiés.
- Suppression des données : **Partielle actuellement** ; le parcours complet de
  suppression de compte requis par Google Play manque.
- Collecte facultative : compte, synchronisation et Gemini sont facultatifs ; la
  dictée est facultative.
- Publicité ou vente : aucune bibliothèque publicitaire et aucune vente
  identifiées.

## Tableau par type de donnée

| Type Play / donnée | Collectée hors appareil ? | Partagée ? | Finalité | Chiffrement en transit | Suppression |
|---|---|---|---|---|---|
| Adresse e-mail | Oui lors de la création/connexion Supabase | Prestataire Supabase ; qualification « partage » [À VÉRIFIER] | Gestion de compte, authentification, récupération du mot de passe | Oui, HTTPS | Suppression complète du compte à implémenter et vérifier |
| Mot de passe | Transmis directement à Supabase ; non stocké volontairement par l’application | Supabase pour authentification | Sécurité du compte | Oui, HTTPS | Géré par Supabase ; politique [À VÉRIFIER] |
| Nom, adresse, téléphone et profil | Local par défaut ; potentiellement transmis comme métadonnées de profil | Supabase [À VÉRIFIER] | Personnalisation des lettres et du compte | Oui si transmis | Local supprimable via données de l’app ; cloud [À VÉRIFIER] |
| Identifiant utilisateur/session | Oui via Supabase | Supabase [À VÉRIFIER] | Authentification, association des fichiers privés | Oui | Avec suppression du compte [À IMPLÉMENTER] |
| Documents, PDF et images | Non par défaut ; oui lors d’un upload cloud déclenché | Supabase comme stockage ; partage utilisateur vers une app tierce hors formulaire selon le cas [À VÉRIFIER] | Stockage/synchronisation, export | Oui | Localement oui selon écran ; suppression cloud complète [À VÉRIFIER] |
| Texte OCR | Local par défaut ; oui si envoyé à Gemini ou inclus dans un document cloud | Google Gemini/Supabase selon action [À VÉRIFIER] | Analyse, rédaction, synchronisation | Oui | Localement avec le document ; fournisseurs [À VÉRIFIER] |
| Texte saisi et contenu de lettres | Local par défaut ; oui si Gemini ou synchronisation est utilisé | Google Gemini/Supabase selon action [À VÉRIFIER] | Génération, amélioration, stockage | Oui | Localement selon écran ; cloud/fournisseurs [À VÉRIFIER] |
| Signature manuscrite | Oui vers Supabase lorsque l’utilisateur connecté l’enregistre | Supabase [À VÉRIFIER] | Signature de lettres, synchronisation privée | Oui | Bouton de suppression local et tentative cloud ; résultat à tester |
| Audio de dictée | Aucun fichier audio conservé par AdminFacile ; transmission possible par le service vocal Android | Fournisseur du moteur vocal [À VÉRIFIER] | Conversion parole-vers-texte | Dépend du moteur [À VÉRIFIER] | AdminFacile ne conserve pas l’audio ; fournisseur [À VÉRIFIER] |
| Fichiers de traduction | Modèles téléchargés ; texte traité localement | Pas de partage du texte identifié | Traduction locale | Téléchargement modèle via le SDK | Suppression des modèles gérée par ML Kit/appareil |
| Diagnostics et données d’appareil | Aucun SDK analytics/crash publicitaire identifié ; Supabase/Google peuvent générer des journaux techniques | [À VÉRIFIER] | Sécurité, fonctionnement, prévention des abus | Oui | Politiques fournisseurs [À VÉRIFIER] |

## Traitement local non déclaré comme collecte

S’ils restent exclusivement sur l’appareil, le scan ML Kit, l’OCR latin, la
traduction, les préférences, les favoris, l’historique, les démarches et les PDF
locaux ne constituent pas une collecte hors appareil au sens du formulaire.

## Points à vérifier avant saisie Play Console

- [ ] région, rétention, sauvegardes et sous-traitants du projet Supabase ;
- [ ] déploiement réel des RLS et caractère privé du bucket ;
- [ ] politique de rétention de l’API Gemini de production ;
- [ ] présence éventuelle de données personnelles dans les logs fournisseurs ;
- [ ] moteur de dictée réellement utilisé sur les appareils ciblés ;
- [ ] collecte technique propre à chaque SDK selon sa documentation Data Safety ;
- [ ] suppression de chaque type de fichier cloud ;
- [ ] suppression complète du compte depuis l’app et depuis une page web ;
- [ ] sauvegarde Android des préférences et fichiers ;
- [ ] âge cible et éventuelle application de la politique Families ;
- [ ] qualification exacte « collecté », « partagé », « facultatif » et
  « traitement éphémère » pour chaque donnée dans la configuration finale.

## Blocage réglementaire identifié

Google Play exige qu’une application permettant de créer un compte fournisse
un moyen clair de demander sa suppression dans l’application et via une
ressource web externe. Ce parcours n’est pas complet dans la version auditée.
