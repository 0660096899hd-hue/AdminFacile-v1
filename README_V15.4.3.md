# AdminFacile V15.4.3

## Modifications

- ajout d'un bouton cloud sur chaque carte de Mes démarches ;
- génération de la lettre en PDF pendant la synchronisation ;
- envoi dans le bucket privé Supabase `admin-documents` avec le chemin
  `{userId}/procedures/{procedureId}.pdf` ;
- animation pendant l'envoi et icône cloud verte après synchronisation ;
- bouton de connexion de l'accueil relié au Profil ;
- indicateur réactif de l'état connecté ou déconnecté ;
- politiques Supabase Storage compatibles avec les démarches et les documents
  existants.

Version : `15.4.3+49`.

Le bucket `admin-documents` doit rester privé. Exécuter
`supabase_storage_policies.sql` dans l'éditeur SQL Supabase avant de tester
l'envoi avec un compte authentifié.
