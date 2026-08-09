# Politique de confidentialité — brouillon

Dernière mise à jour : [À COMPLÉTER]

Ce document est un brouillon préparatoire. Il doit être relu, complété et
publié à une adresse web accessible avant la mise à disposition publique
d’AdminFacile.

## Qui est responsable de l’application ?

AdminFacile est éditée par : [NOM OU RAISON SOCIALE À COMPLÉTER].

Contact pour la confidentialité et les demandes relatives aux données :
[ADRESSE E-MAIL À COMPLÉTER].

Adresse postale, si applicable : [À COMPLÉTER].

## À quoi sert AdminFacile ?

AdminFacile aide à numériser et classer des documents, reconnaître leur texte,
préparer des courriers administratifs, suivre des démarches et conserver une
signature. Certaines fonctions peuvent utiliser un compte et une
synchronisation cloud. Les fonctions Gemini sont facultatives.

AdminFacile ne fournit pas de conseil juridique, médical ou financier. Les
documents générés doivent être relus avant utilisation.

## Données conservées uniquement sur l’appareil

Par défaut, l’application peut enregistrer dans l’espace privé de l’application
sur votre appareil :

- les informations de profil saisies pour remplir les lettres, comme le nom,
  l’adresse, le téléphone et l’adresse e-mail ;
- les démarches, favoris, historiques et préférences ;
- les documents importés ou numérisés et leur texte OCR ;
- les PDF générés ;
- l’image normalisée de votre signature.

Ces données ne quittent pas l’appareil du seul fait de leur enregistrement
local. Elles peuvent toutefois être incluses dans une sauvegarde système Android
selon les réglages de l’appareil et la configuration finale de l’application
[À VÉRIFIER].

## Compte utilisateur et Supabase

Si vous créez un compte, Supabase traite votre adresse e-mail, les éléments
nécessaires à l’authentification et les métadonnées de profil que l’application
lui transmet. La session est conservée par le SDK Supabase afin de permettre la
reconnexion.

Lorsque vous choisissez une action de synchronisation, les documents, images ou
PDF concernés sont envoyés dans le bucket privé `admin-documents`, sous un
chemin associé à votre identifiant utilisateur. Lorsque vous êtes connecté et
enregistrez une signature, sa version normalisée est également synchronisée.

Les règles RLS fournies avec le projet visent à limiter l’accès de chaque
utilisateur à ses propres fichiers. Leur déploiement effectif et la localisation
du projet Supabase doivent être confirmés avant publication [À VÉRIFIER].

Sous-traitant pressenti : Supabase [ENTITÉ, RÉGION ET LIEN CONTRACTUEL À
COMPLÉTER].

## Scanner, photos, fichiers et OCR

Le scanner professionnel Google ML Kit détecte et recadre les documents sur
l’appareil. Vous pouvez également sélectionner une photo ou importer un fichier
à la demande. L’OCR latin est réalisé localement par ML Kit. Le module scanner
peut être fourni ou mis à jour par Google Play Services.

AdminFacile n’envoie pas automatiquement la photo originale à Gemini. Une image
ou un PDF peut être envoyé à Supabase uniquement lors d’une synchronisation
prévue par l’application.

## Gemini

Gemini est facultatif. Lorsque vous déclenchez une analyse, une question, une
rédaction ou une amélioration avec Gemini, le texte nécessaire à la demande est
envoyé au service Google Gemini. Il peut comprendre du texte OCR et le contenu
administratif saisi. La photo ou le PDF source ne sont pas transmis par le code
actuel, mais leur texte peut contenir des données personnelles ou sensibles.

Le traitement, la conservation et la localisation chez Google dépendent du
compte, de l’API et des conditions qui seront retenus pour la production [À
VÉRIFIER]. Gemini doit rester désactivé dans la version publique tant qu’une
architecture de clé sécurisée et les informations contractuelles ne sont pas
finalisées.

## Microphone et dictée

La permission microphone est demandée uniquement lorsque vous utilisez la
dictée. L’application utilise le service de reconnaissance vocale disponible
sur l’appareil Android. Selon le moteur choisi par l’utilisateur ou le
fabricant, l’audio peut être traité localement ou transmis à son fournisseur.
Ce comportement doit être vérifié sur les appareils ciblés [À VÉRIFIER].
AdminFacile ne conserve pas volontairement un enregistrement audio ; elle
conserve seulement le texte dicté lorsqu’il est intégré à un document.

## Traduction

La traduction utilise les modèles ML Kit installés sur l’appareil. Le
téléchargement initial des modèles nécessite Internet. Le texte traduit est
traité localement par le code actuel.

## Signature

La signature est convertie en PNG puis enregistrée dans l’espace privé de
l’application. Si vous êtes connecté, elle est synchronisée dans votre espace
Supabase privé. Vous pouvez la supprimer depuis le profil ; l’application tente
alors de supprimer également la copie cloud de la signature.

## Partage, impression et export

Lorsque vous choisissez Partager, Imprimer, Exporter ou Transmettre, les données
sont remises au service ou à l’application que vous sélectionnez. Cette action
est déclenchée par vous et les règles de confidentialité du destinataire
s’appliquent ensuite.

## Finalités

Les données sont utilisées pour fournir les fonctions demandées : créer un
compte, restaurer une session, personnaliser une lettre, numériser et analyser
un document, générer un PDF, synchroniser un fichier, répondre à une demande
Gemini, permettre la dictée et assurer l’assistance technique.

Aucune utilisation publicitaire ni vente de données n’a été identifiée dans le
code audité.

## Sécurité

Les échanges réseau utilisent HTTPS. Les fichiers cloud sont destinés à rester
dans un bucket privé protégé par authentification et RLS. Les données locales
sont placées dans l’espace applicatif Android, mais ne disposent pas d’un
chiffrement applicatif supplémentaire identifié. Aucun système ne peut garantir
une sécurité absolue.

## Durée de conservation

- données locales : jusqu’à leur suppression dans l’application, la suppression
  des données Android ou la désinstallation ;
- compte et données Supabase : jusqu’à leur suppression par l’utilisateur ou le
  responsable du traitement, selon une durée à définir [À COMPLÉTER] ;
- données Gemini et journaux techniques des fournisseurs : selon les conditions
  de production de Google et Supabase [À VÉRIFIER].

## Suppression des données et du compte

Vous pouvez supprimer localement une signature, des documents et des démarches
depuis les écrans qui proposent cette action. La couverture de suppression des
copies cloud doit être testée pour chaque type de document [À VÉRIFIER].

L’application permet actuellement la création d’un compte, mais aucun parcours
complet de suppression du compte et de toutes les données associées n’a été
confirmé lors de l’audit. Avant publication, il faudra fournir :

- une demande de suppression accessible dans l’application ;
- une page web publique permettant de demander la suppression ;
- une procédure vérifiée supprimant le compte et les données associées.

URL de suppression : [À COMPLÉTER].

## Vos droits

Selon la réglementation applicable, vous pouvez demander l’accès, la
rectification, l’effacement, la limitation ou la portabilité de vos données, et
vous opposer à certains traitements. Contact : [À COMPLÉTER]. Les modalités et
le délai de réponse doivent être adaptés au statut réel de l’éditeur et aux
territoires de diffusion.

## Enfants

Le public cible et l’âge minimal ne sont pas encore définis [À COMPLÉTER].
L’application n’est pas conçue pour collecter sciemment les données d’enfants.
La déclaration Families devra être cohérente avec le ciblage Play Store final.

## Modifications

Cette politique pourra évoluer. La version publiée indiquera sa date de mise à
jour et présentera les changements importants lorsque la loi l’exige.
