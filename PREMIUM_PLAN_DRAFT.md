# AdminFacile Gratuit / Premium — proposition sans intégration

Ce document décrit une architecture commerciale possible. Aucun achat, quota,
écran de paiement ni verrou fonctionnel n’est intégré dans V20.1.

## Principes

- garder gratuitement les fonctions indispensables à la gestion de documents
  et de démarches ;
- faire payer principalement les coûts récurrents réels : IA, stockage et
  synchronisation ;
- afficher les quotas avant utilisation, sans surprise ni blocage d’un document
  déjà créé ;
- permettre l’export des données même après la fin d’un abonnement ;
- éviter toute promesse juridique ou administrative ;
- proposer une expérience utile sans obligation de compte pour les fonctions
  locales.

## Version gratuite proposée

- scanner, photo et import local ;
- OCR local et création PDF ;
- bibliothèque complète des modèles ;
- rédaction et personnalisation locales ;
- suivi local des démarches et documents ;
- recherche, favoris, historique, traduction et dictée ;
- signature locale ;
- partage et impression ;
- Gemini : quota mensuel réduit, par exemple 5 à 10 requêtes, uniquement si le
  backend sécurisé et son coût sont validés ;
- cloud : petit quota de découverte, par exemple 100 à 250 Mo [À CHIFFRER].

Les valeurs exactes doivent être calculées à partir des coûts Supabase, Gemini,
du support et des taxes. Elles ne doivent pas être codées avant validation.

## Premium proposé

- quota Gemini sensiblement supérieur, avec compteur clair et limite d’abus ;
- stockage cloud étendu ;
- synchronisation sur plusieurs appareils ;
- historique cloud et restauration [SI TECHNIQUEMENT IMPLÉMENTÉS] ;
- traitement de lots ou volumes supérieurs [SI IMPLÉMENTÉ] ;
- support prioritaire réaliste, avec délai annoncé uniquement s’il peut être
  respecté ;
- conservation des fonctions locales et des exports en cas de résiliation.

Premium ne doit pas promettre de scanner plus précis, de document légalement
valide ou de réponse administrative garantie.

## Comparaison des modèles économiques

### Abonnement mensuel

Avantages :

- accessible pour tester ;
- couvre les coûts récurrents Gemini et stockage ;
- peut être résilié facilement.

Inconvénients :

- revenu moins prévisible ;
- taux de résiliation plus élevé ;
- sensibilité au prix mensuel.

### Abonnement annuel

Avantages :

- meilleure visibilité financière ;
- prix mensuel équivalent plus faible ;
- réduit les interruptions de service liées au renouvellement.

Inconvénients :

- engagement initial plus important ;
- besoin d’une politique de remboursement et d’une communication très claire.

### Paiement unique

Avantages :

- proposition simple pour les fonctions entièrement locales ;
- pas de renouvellement.

Inconvénients :

- ne finance pas durablement Gemini, le cloud et le support ;
- risque important si l’usage coûteux augmente ;
- nécessite malgré tout des limites ou des achats additionnels.

## Recommandation

Proposer, après validation du produit et sans modifier V20.1 :

1. une version gratuite réellement utile ;
2. un abonnement mensuel flexible ;
3. un abonnement annuel avec une remise transparente ;
4. éventuellement, plus tard, une licence « Local » à paiement unique qui
   n’inclut ni quota cloud permanent ni Gemini récurrent.

L’abonnement est le modèle le plus cohérent pour les services variables. Un
paiement unique ne doit pas inclure des coûts cloud illimités.

## Décisions nécessaires avant développement

- [ ] coûts Gemini par action et plafond mensuel ;
- [ ] coûts Supabase par utilisateur et par Go ;
- [ ] pays, taxes, devise et prix TTC ;
- [ ] définition exacte de l’offre gratuite ;
- [ ] politique de dépassement des quotas ;
- [ ] conservation et export après résiliation ;
- [ ] essai gratuit éventuel ;
- [ ] conditions de remboursement ;
- [ ] architecture serveur de validation des droits ;
- [ ] Google Play Billing et vérification côté serveur ;
- [ ] traitement de la suppression de compte et des achats.

## Sécurité commerciale

Les droits Premium ne devront jamais reposer uniquement sur une préférence
locale modifiable. Les reçus Play Billing devront être vérifiés par une couche
serveur, sans stocker de secret de facturation dans l’application.
