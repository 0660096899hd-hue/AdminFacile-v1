import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('es'),
    Locale('fr'),
    Locale('it')
  ];

  /// No description provided for @appName.
  ///
  /// In fr, this message translates to:
  /// **'AdminFacile'**
  String get appName;

  /// No description provided for @languageDisplayName.
  ///
  /// In fr, this message translates to:
  /// **'Français'**
  String get languageDisplayName;

  /// No description provided for @countryContentStatus.
  ///
  /// In fr, this message translates to:
  /// **'Contenu France actif'**
  String get countryContentStatus;

  /// No description provided for @continueWithGoogle.
  ///
  /// In fr, this message translates to:
  /// **'Continuer avec Google'**
  String get continueWithGoogle;

  /// No description provided for @or.
  ///
  /// In fr, this message translates to:
  /// **'ou'**
  String get or;

  /// No description provided for @createMyAccount.
  ///
  /// In fr, this message translates to:
  /// **'Créer mon compte'**
  String get createMyAccount;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In fr, this message translates to:
  /// **'J’ai déjà un compte'**
  String get alreadyHaveAccount;

  /// No description provided for @serviceTemporarilyUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Service temporairement indisponible.'**
  String get serviceTemporarilyUnavailable;

  /// No description provided for @createAccount.
  ///
  /// In fr, this message translates to:
  /// **'Créer un compte'**
  String get createAccount;

  /// No description provided for @signIn.
  ///
  /// In fr, this message translates to:
  /// **'Connexion'**
  String get signIn;

  /// No description provided for @signInAction.
  ///
  /// In fr, this message translates to:
  /// **'Se connecter'**
  String get signInAction;

  /// No description provided for @emailAddress.
  ///
  /// In fr, this message translates to:
  /// **'Adresse e-mail'**
  String get emailAddress;

  /// No description provided for @email.
  ///
  /// In fr, this message translates to:
  /// **'E-mail'**
  String get email;

  /// No description provided for @password.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe'**
  String get password;

  /// No description provided for @showPassword.
  ///
  /// In fr, this message translates to:
  /// **'Afficher le mot de passe'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In fr, this message translates to:
  /// **'Masquer le mot de passe'**
  String get hidePassword;

  /// No description provided for @forgotPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe oublié ?'**
  String get forgotPassword;

  /// No description provided for @back.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get back;

  /// No description provided for @googleTemporarilyUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'La connexion Google est temporairement indisponible.'**
  String get googleTemporarilyUnavailable;

  /// No description provided for @googleSignInFailed.
  ///
  /// In fr, this message translates to:
  /// **'La connexion Google a échoué. Réessayez.'**
  String get googleSignInFailed;

  /// No description provided for @accountCreatedCheckEmail.
  ///
  /// In fr, this message translates to:
  /// **'Compte créé. Vérifiez votre e-mail pour le confirmer.'**
  String get accountCreatedCheckEmail;

  /// No description provided for @recoveryEmailSent.
  ///
  /// In fr, this message translates to:
  /// **'E-mail de récupération envoyé. Vérifiez aussi vos courriers indésirables.'**
  String get recoveryEmailSent;

  /// No description provided for @administrativeAssistant.
  ///
  /// In fr, this message translates to:
  /// **'Assistant administratif'**
  String get administrativeAssistant;

  /// No description provided for @yourAdministrativeAssistant.
  ///
  /// In fr, this message translates to:
  /// **'Votre assistant administratif'**
  String get yourAdministrativeAssistant;

  /// No description provided for @yourAdministrativeSpace.
  ///
  /// In fr, this message translates to:
  /// **'Votre espace administratif'**
  String get yourAdministrativeSpace;

  /// No description provided for @home.
  ///
  /// In fr, this message translates to:
  /// **'Accueil'**
  String get home;

  /// No description provided for @scanner.
  ///
  /// In fr, this message translates to:
  /// **'Scanner'**
  String get scanner;

  /// No description provided for @letters.
  ///
  /// In fr, this message translates to:
  /// **'Lettres'**
  String get letters;

  /// No description provided for @documents.
  ///
  /// In fr, this message translates to:
  /// **'Documents'**
  String get documents;

  /// No description provided for @profile.
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get profile;

  /// No description provided for @writeWithGemini.
  ///
  /// In fr, this message translates to:
  /// **'Rédiger avec Gemini'**
  String get writeWithGemini;

  /// No description provided for @generateLetter.
  ///
  /// In fr, this message translates to:
  /// **'Générer une lettre'**
  String get generateLetter;

  /// No description provided for @scanDocument.
  ///
  /// In fr, this message translates to:
  /// **'Scanner un document'**
  String get scanDocument;

  /// No description provided for @myProcedures.
  ///
  /// In fr, this message translates to:
  /// **'Mes démarches'**
  String get myProcedures;

  /// No description provided for @myDocuments.
  ///
  /// In fr, this message translates to:
  /// **'Mes documents'**
  String get myDocuments;

  /// No description provided for @templateLibrary.
  ///
  /// In fr, this message translates to:
  /// **'Bibliothèque de modèles'**
  String get templateLibrary;

  /// No description provided for @translation.
  ///
  /// In fr, this message translates to:
  /// **'Traduction'**
  String get translation;

  /// No description provided for @globalSearch.
  ///
  /// In fr, this message translates to:
  /// **'Recherche globale'**
  String get globalSearch;

  /// No description provided for @settingsAndProfile.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres et profil'**
  String get settingsAndProfile;

  /// No description provided for @premiumVersion.
  ///
  /// In fr, this message translates to:
  /// **'Version Premium'**
  String get premiumVersion;

  /// No description provided for @unlockAllFeatures.
  ///
  /// In fr, this message translates to:
  /// **'Débloquer toutes les fonctionnalités'**
  String get unlockAllFeatures;

  /// No description provided for @premiumComingSoon.
  ///
  /// In fr, this message translates to:
  /// **'La version Premium sera bientôt disponible.'**
  String get premiumComingSoon;

  /// No description provided for @close.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get close;

  /// No description provided for @darkMode.
  ///
  /// In fr, this message translates to:
  /// **'Mode sombre'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In fr, this message translates to:
  /// **'Mode clair'**
  String get lightMode;

  /// No description provided for @menu.
  ///
  /// In fr, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @search.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher'**
  String get search;

  /// No description provided for @notifications.
  ///
  /// In fr, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @markAllRead.
  ///
  /// In fr, this message translates to:
  /// **'Tout marquer comme lu'**
  String get markAllRead;

  /// No description provided for @noNotifications.
  ///
  /// In fr, this message translates to:
  /// **'Aucune notification pour le moment'**
  String get noNotifications;

  /// No description provided for @notificationsHelp.
  ///
  /// In fr, this message translates to:
  /// **'Les rappels et informations importantes apparaîtront ici.'**
  String get notificationsHelp;

  /// No description provided for @searchEverywhere.
  ///
  /// In fr, this message translates to:
  /// **'Recherchez partout'**
  String get searchEverywhere;

  /// No description provided for @noResults.
  ///
  /// In fr, this message translates to:
  /// **'Aucun résultat'**
  String get noResults;

  /// No description provided for @viewAll.
  ///
  /// In fr, this message translates to:
  /// **'Voir tout'**
  String get viewAll;

  /// No description provided for @noUrgentAction.
  ///
  /// In fr, this message translates to:
  /// **'Aucune action urgente'**
  String get noUrgentAction;

  /// No description provided for @noRecentActivity.
  ///
  /// In fr, this message translates to:
  /// **'Aucune activité récente'**
  String get noRecentActivity;

  /// No description provided for @simplifyDaily.
  ///
  /// In fr, this message translates to:
  /// **'Simplifiez vos démarches au quotidien'**
  String get simplifyDaily;

  /// No description provided for @homeTagline.
  ///
  /// In fr, this message translates to:
  /// **'Vos démarches administratives, simplifiées par l’IA'**
  String get homeTagline;

  /// No description provided for @createLetter.
  ///
  /// In fr, this message translates to:
  /// **'Créer une lettre'**
  String get createLetter;

  /// No description provided for @chooseMethod.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez une méthode'**
  String get chooseMethod;

  /// No description provided for @generateWithGemini.
  ///
  /// In fr, this message translates to:
  /// **'Générer avec Gemini'**
  String get generateWithGemini;

  /// No description provided for @useTemplate.
  ///
  /// In fr, this message translates to:
  /// **'Utiliser un modèle'**
  String get useTemplate;

  /// No description provided for @currentProcedures.
  ///
  /// In fr, this message translates to:
  /// **'Mes démarches en cours'**
  String get currentProcedures;

  /// No description provided for @important.
  ///
  /// In fr, this message translates to:
  /// **'À ne pas manquer'**
  String get important;

  /// No description provided for @privacy.
  ///
  /// In fr, this message translates to:
  /// **'Confidentialité'**
  String get privacy;

  /// No description provided for @localStorageHelp.
  ///
  /// In fr, this message translates to:
  /// **'Stockage local • Touchez pour en savoir plus'**
  String get localStorageHelp;

  /// No description provided for @noCurrentProcedure.
  ///
  /// In fr, this message translates to:
  /// **'Aucune démarche en cours. Créez votre première lettre pour commencer le suivi.'**
  String get noCurrentProcedure;

  /// No description provided for @documentsTab.
  ///
  /// In fr, this message translates to:
  /// **'Documents'**
  String get documentsTab;

  /// No description provided for @proceduresTab.
  ///
  /// In fr, this message translates to:
  /// **'Démarches'**
  String get proceduresTab;

  /// No description provided for @ready.
  ///
  /// In fr, this message translates to:
  /// **'Prêt'**
  String get ready;

  /// No description provided for @scanningDocument.
  ///
  /// In fr, this message translates to:
  /// **'Scan du document…'**
  String get scanningDocument;

  /// No description provided for @recognizingText.
  ///
  /// In fr, this message translates to:
  /// **'Reconnaissance du texte (OCR)…'**
  String get recognizingText;

  /// No description provided for @geminiAnalysisInProgress.
  ///
  /// In fr, this message translates to:
  /// **'Analyse Gemini…'**
  String get geminiAnalysisInProgress;

  /// No description provided for @processingCompleted.
  ///
  /// In fr, this message translates to:
  /// **'Traitement terminé'**
  String get processingCompleted;

  /// No description provided for @scanFailed.
  ///
  /// In fr, this message translates to:
  /// **'Le scan a échoué'**
  String get scanFailed;

  /// No description provided for @takePhoto.
  ///
  /// In fr, this message translates to:
  /// **'Prendre une photo'**
  String get takePhoto;

  /// No description provided for @importDocument.
  ///
  /// In fr, this message translates to:
  /// **'Importer un document'**
  String get importDocument;

  /// No description provided for @photo.
  ///
  /// In fr, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @importAction.
  ///
  /// In fr, this message translates to:
  /// **'Importer'**
  String get importAction;

  /// No description provided for @scanA4.
  ///
  /// In fr, this message translates to:
  /// **'Scanner un document A4'**
  String get scanA4;

  /// No description provided for @scanA4Instructions.
  ///
  /// In fr, this message translates to:
  /// **'Placez la feuille dans le cadre. L’application détecte les bords, recadre le document et corrige la perspective.'**
  String get scanA4Instructions;

  /// No description provided for @scanFramingInstructions.
  ///
  /// In fr, this message translates to:
  /// **'Cadrez toute la feuille. Après la capture, ajustez les quatre poignées si nécessaire, choisissez le filtre puis validez dans le scanner.'**
  String get scanFramingInstructions;

  /// No description provided for @processingStatus.
  ///
  /// In fr, this message translates to:
  /// **'État du traitement'**
  String get processingStatus;

  /// No description provided for @recognizedText.
  ///
  /// In fr, this message translates to:
  /// **'Texte reconnu'**
  String get recognizedText;

  /// No description provided for @ocrText.
  ///
  /// In fr, this message translates to:
  /// **'Texte OCR'**
  String get ocrText;

  /// No description provided for @viewOcrText.
  ///
  /// In fr, this message translates to:
  /// **'Voir le texte OCR'**
  String get viewOcrText;

  /// No description provided for @retryOcr.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer l’OCR'**
  String get retryOcr;

  /// No description provided for @geminiAnalysis.
  ///
  /// In fr, this message translates to:
  /// **'Analyse Gemini'**
  String get geminiAnalysis;

  /// No description provided for @correctInformation.
  ///
  /// In fr, this message translates to:
  /// **'Corriger les informations'**
  String get correctInformation;

  /// No description provided for @addToDocuments.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter à Mes documents'**
  String get addToDocuments;

  /// No description provided for @send.
  ///
  /// In fr, this message translates to:
  /// **'Transmettre'**
  String get send;

  /// No description provided for @print.
  ///
  /// In fr, this message translates to:
  /// **'Imprimer'**
  String get print;

  /// No description provided for @translate.
  ///
  /// In fr, this message translates to:
  /// **'Traduire'**
  String get translate;

  /// No description provided for @translateDocument.
  ///
  /// In fr, this message translates to:
  /// **'Traduire le document'**
  String get translateDocument;

  /// No description provided for @addSignature.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter ma signature'**
  String get addSignature;

  /// No description provided for @placeSignature.
  ///
  /// In fr, this message translates to:
  /// **'Placer ma signature'**
  String get placeSignature;

  /// No description provided for @addOnThisPage.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter sur cette page'**
  String get addOnThisPage;

  /// No description provided for @signatureToApply.
  ///
  /// In fr, this message translates to:
  /// **'Signature à apposer'**
  String get signatureToApply;

  /// No description provided for @senderSignature.
  ///
  /// In fr, this message translates to:
  /// **'Signature de l’expéditeur'**
  String get senderSignature;

  /// No description provided for @documentAdded.
  ///
  /// In fr, this message translates to:
  /// **'Document ajouté à Mes documents.'**
  String get documentAdded;

  /// No description provided for @signedCopyCreated.
  ///
  /// In fr, this message translates to:
  /// **'Une copie signée du document a été créée.'**
  String get signedCopyCreated;

  /// No description provided for @pdfReady.
  ///
  /// In fr, this message translates to:
  /// **'PDF prêt'**
  String get pdfReady;

  /// No description provided for @open.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir'**
  String get open;

  /// No description provided for @download.
  ///
  /// In fr, this message translates to:
  /// **'Télécharger'**
  String get download;

  /// No description provided for @share.
  ///
  /// In fr, this message translates to:
  /// **'Partager'**
  String get share;

  /// No description provided for @edit.
  ///
  /// In fr, this message translates to:
  /// **'Modifier'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get save;

  /// No description provided for @validate.
  ///
  /// In fr, this message translates to:
  /// **'Valider'**
  String get validate;

  /// No description provided for @retry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get retry;

  /// No description provided for @copy.
  ///
  /// In fr, this message translates to:
  /// **'Copier'**
  String get copy;

  /// No description provided for @copiedText.
  ///
  /// In fr, this message translates to:
  /// **'Texte copié'**
  String get copiedText;

  /// No description provided for @analysisCopied.
  ///
  /// In fr, this message translates to:
  /// **'Analyse copiée'**
  String get analysisCopied;

  /// No description provided for @translationCopied.
  ///
  /// In fr, this message translates to:
  /// **'Traduction copiée'**
  String get translationCopied;

  /// No description provided for @responseCopied.
  ///
  /// In fr, this message translates to:
  /// **'Réponse copiée'**
  String get responseCopied;

  /// No description provided for @documentLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Langue du document'**
  String get documentLanguage;

  /// No description provided for @translateTo.
  ///
  /// In fr, this message translates to:
  /// **'Traduire vers'**
  String get translateTo;

  /// No description provided for @originalText.
  ///
  /// In fr, this message translates to:
  /// **'Texte original'**
  String get originalText;

  /// No description provided for @translatedText.
  ///
  /// In fr, this message translates to:
  /// **'Traduction'**
  String get translatedText;

  /// No description provided for @copyTranslation.
  ///
  /// In fr, this message translates to:
  /// **'Copier la traduction'**
  String get copyTranslation;

  /// No description provided for @fullDocument.
  ///
  /// In fr, this message translates to:
  /// **'Document complet'**
  String get fullDocument;

  /// No description provided for @translationCompletedOnDevice.
  ///
  /// In fr, this message translates to:
  /// **'Traduction terminée sur l’appareil.'**
  String get translationCompletedOnDevice;

  /// No description provided for @enterOrPasteText.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez ou collez un texte.'**
  String get enterOrPasteText;

  /// No description provided for @dictation.
  ///
  /// In fr, this message translates to:
  /// **'Dictée vocale'**
  String get dictation;

  /// No description provided for @speechUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'La reconnaissance vocale n’est pas disponible.'**
  String get speechUnavailable;

  /// No description provided for @microphone.
  ///
  /// In fr, this message translates to:
  /// **'Microphone'**
  String get microphone;

  /// No description provided for @assistantWriter.
  ///
  /// In fr, this message translates to:
  /// **'Assistant de rédaction IA'**
  String get assistantWriter;

  /// No description provided for @describeNeed.
  ///
  /// In fr, this message translates to:
  /// **'Expliquez naturellement votre besoin'**
  String get describeNeed;

  /// No description provided for @yourRequest.
  ///
  /// In fr, this message translates to:
  /// **'Votre demande'**
  String get yourRequest;

  /// No description provided for @recipientAndRequest.
  ///
  /// In fr, this message translates to:
  /// **'Destinataire et demande'**
  String get recipientAndRequest;

  /// No description provided for @generateTheLetter.
  ///
  /// In fr, this message translates to:
  /// **'Générer la lettre'**
  String get generateTheLetter;

  /// No description provided for @regenerate.
  ///
  /// In fr, this message translates to:
  /// **'Régénérer'**
  String get regenerate;

  /// No description provided for @generatedLetter.
  ///
  /// In fr, this message translates to:
  /// **'Lettre générée'**
  String get generatedLetter;

  /// No description provided for @generatedLetterEditable.
  ///
  /// In fr, this message translates to:
  /// **'Lettre générée (modifiable)'**
  String get generatedLetterEditable;

  /// No description provided for @improve.
  ///
  /// In fr, this message translates to:
  /// **'Améliorer'**
  String get improve;

  /// No description provided for @improveWithGemini.
  ///
  /// In fr, this message translates to:
  /// **'Améliorer avec Gemini'**
  String get improveWithGemini;

  /// No description provided for @geminiImprovedReview.
  ///
  /// In fr, this message translates to:
  /// **'Lettre améliorée avec Gemini. Relisez-la avant l’envoi.'**
  String get geminiImprovedReview;

  /// No description provided for @verifyBeforeSending.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez toujours le contenu avant l’envoi. Le texte saisi est transmis à Gemini pour générer la lettre.'**
  String get verifyBeforeSending;

  /// No description provided for @letterSaved.
  ///
  /// In fr, this message translates to:
  /// **'Lettre enregistrée dans Mes démarches.'**
  String get letterSaved;

  /// No description provided for @procedureAdded.
  ///
  /// In fr, this message translates to:
  /// **'Démarche ajoutée à Mes démarches.'**
  String get procedureAdded;

  /// No description provided for @openLetter.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir la lettre'**
  String get openLetter;

  /// No description provided for @preview.
  ///
  /// In fr, this message translates to:
  /// **'Aperçu'**
  String get preview;

  /// No description provided for @modelPreview.
  ///
  /// In fr, this message translates to:
  /// **'Aperçu du modèle'**
  String get modelPreview;

  /// No description provided for @useThisTemplate.
  ///
  /// In fr, this message translates to:
  /// **'Utiliser ce modèle'**
  String get useThisTemplate;

  /// No description provided for @letterModels.
  ///
  /// In fr, this message translates to:
  /// **'Modèles de lettres'**
  String get letterModels;

  /// No description provided for @allModels.
  ///
  /// In fr, this message translates to:
  /// **'Tous les modèles'**
  String get allModels;

  /// No description provided for @recommendedLetters.
  ///
  /// In fr, this message translates to:
  /// **'Lettres recommandées'**
  String get recommendedLetters;

  /// No description provided for @bestLetters.
  ///
  /// In fr, this message translates to:
  /// **'Afficher les meilleures lettres'**
  String get bestLetters;

  /// No description provided for @professionalLibrary.
  ///
  /// In fr, this message translates to:
  /// **'Bibliothèque professionnelle V6.7'**
  String get professionalLibrary;

  /// No description provided for @searchLetters.
  ///
  /// In fr, this message translates to:
  /// **'Recherche de courriers'**
  String get searchLetters;

  /// No description provided for @noModelFound.
  ///
  /// In fr, this message translates to:
  /// **'Aucun modèle trouvé. Essayez avec un mot plus simple, par exemple « résiliation », « facture » ou « logement ».'**
  String get noModelFound;

  /// No description provided for @noLetterForFilters.
  ///
  /// In fr, this message translates to:
  /// **'Aucun courrier ne correspond à ces filtres.'**
  String get noLetterForFilters;

  /// No description provided for @noRelevantLetter.
  ///
  /// In fr, this message translates to:
  /// **'Aucun courrier suffisamment pertinent n’a été trouvé.'**
  String get noRelevantLetter;

  /// No description provided for @availableOffline.
  ///
  /// In fr, this message translates to:
  /// **'Disponible hors connexion'**
  String get availableOffline;

  /// No description provided for @favorites.
  ///
  /// In fr, this message translates to:
  /// **'Favoris'**
  String get favorites;

  /// No description provided for @recent.
  ///
  /// In fr, this message translates to:
  /// **'Récents'**
  String get recent;

  /// No description provided for @all.
  ///
  /// In fr, this message translates to:
  /// **'Tous'**
  String get all;

  /// No description provided for @allCategories.
  ///
  /// In fr, this message translates to:
  /// **'Toutes catégories'**
  String get allCategories;

  /// No description provided for @allRequests.
  ///
  /// In fr, this message translates to:
  /// **'Toutes les demandes'**
  String get allRequests;

  /// No description provided for @fieldsToComplete.
  ///
  /// In fr, this message translates to:
  /// **'Champs à compléter'**
  String get fieldsToComplete;

  /// No description provided for @yourContactDetails.
  ///
  /// In fr, this message translates to:
  /// **'Vos coordonnées'**
  String get yourContactDetails;

  /// No description provided for @subject.
  ///
  /// In fr, this message translates to:
  /// **'Objet'**
  String get subject;

  /// No description provided for @notes.
  ///
  /// In fr, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @sendOrKeep.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer ou conserver'**
  String get sendOrKeep;

  /// No description provided for @prepareEmail.
  ///
  /// In fr, this message translates to:
  /// **'Préparer l’e-mail'**
  String get prepareEmail;

  /// No description provided for @chooseGmailOutlook.
  ///
  /// In fr, this message translates to:
  /// **'Choisir Gmail ou Outlook'**
  String get chooseGmailOutlook;

  /// No description provided for @emailPdfHelp.
  ///
  /// In fr, this message translates to:
  /// **'AdminFacile préparera le message et le PDF. Vous choisirez ensuite Gmail, Outlook ou une autre application pour vérifier et envoyer.'**
  String get emailPdfHelp;

  /// No description provided for @checkRecipientEmail.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez l’adresse e-mail du destinataire.'**
  String get checkRecipientEmail;

  /// No description provided for @sendByPost.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer par La Poste'**
  String get sendByPost;

  /// No description provided for @exportPdf.
  ///
  /// In fr, this message translates to:
  /// **'Exporter en PDF'**
  String get exportPdf;

  /// No description provided for @letterExportedPdf.
  ///
  /// In fr, this message translates to:
  /// **'Lettre exportée en PDF.'**
  String get letterExportedPdf;

  /// No description provided for @documentSavedPdf.
  ///
  /// In fr, this message translates to:
  /// **'Document enregistré en PDF.'**
  String get documentSavedPdf;

  /// No description provided for @myProfile.
  ///
  /// In fr, this message translates to:
  /// **'Mon profil'**
  String get myProfile;

  /// No description provided for @appearance.
  ///
  /// In fr, this message translates to:
  /// **'Apparence'**
  String get appearance;

  /// No description provided for @chooseTheme.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez le thème de l’application.'**
  String get chooseTheme;

  /// No description provided for @automatic.
  ///
  /// In fr, this message translates to:
  /// **'Automatique'**
  String get automatic;

  /// No description provided for @light.
  ///
  /// In fr, this message translates to:
  /// **'Clair'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In fr, this message translates to:
  /// **'Sombre'**
  String get dark;

  /// No description provided for @comfortMode.
  ///
  /// In fr, this message translates to:
  /// **'Mode confort'**
  String get comfortMode;

  /// No description provided for @comfortModeHelp.
  ///
  /// In fr, this message translates to:
  /// **'Texte plus grand et navigation plus lisible'**
  String get comfortModeHelp;

  /// No description provided for @saveProfile.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer mon profil'**
  String get saveProfile;

  /// No description provided for @update.
  ///
  /// In fr, this message translates to:
  /// **'Mettre à jour'**
  String get update;

  /// No description provided for @signOut.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get signOut;

  /// No description provided for @signedOut.
  ///
  /// In fr, this message translates to:
  /// **'Vous êtes déconnecté.'**
  String get signedOut;

  /// No description provided for @changePassword.
  ///
  /// In fr, this message translates to:
  /// **'Changer le mot de passe'**
  String get changePassword;

  /// No description provided for @mySignature.
  ///
  /// In fr, this message translates to:
  /// **'Ma signature'**
  String get mySignature;

  /// No description provided for @drawSignature.
  ///
  /// In fr, this message translates to:
  /// **'Dessiner ma signature'**
  String get drawSignature;

  /// No description provided for @importImage.
  ///
  /// In fr, this message translates to:
  /// **'Importer une image'**
  String get importImage;

  /// No description provided for @noSavedSignature.
  ///
  /// In fr, this message translates to:
  /// **'Aucune signature enregistrée.'**
  String get noSavedSignature;

  /// No description provided for @drawBeforeSave.
  ///
  /// In fr, this message translates to:
  /// **'Dessinez votre signature avant de l’enregistrer.'**
  String get drawBeforeSave;

  /// No description provided for @signWithFinger.
  ///
  /// In fr, this message translates to:
  /// **'Signez avec votre doigt dans la zone blanche.'**
  String get signWithFinger;

  /// No description provided for @clear.
  ///
  /// In fr, this message translates to:
  /// **'Effacer'**
  String get clear;

  /// No description provided for @transparentBackground.
  ///
  /// In fr, this message translates to:
  /// **'Fond transparent'**
  String get transparentBackground;

  /// No description provided for @insertSignatureAutomatically.
  ///
  /// In fr, this message translates to:
  /// **'Insérer automatiquement ma signature dans les lettres'**
  String get insertSignatureAutomatically;

  /// No description provided for @addSignatureToLetter.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter ma signature à cette lettre'**
  String get addSignatureToLetter;

  /// No description provided for @saveSignatureFirst.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrez d’abord votre signature dans votre profil.'**
  String get saveSignatureFirst;

  /// No description provided for @profileDataHelp.
  ///
  /// In fr, this message translates to:
  /// **'Ces informations seront automatiquement reprises dans vos lettres.'**
  String get profileDataHelp;

  /// No description provided for @localPrivacyStatement.
  ///
  /// In fr, this message translates to:
  /// **'Vos documents restent enregistrés localement par défaut. Si vous choisissez la synchronisation, le document PDF ou l’image et votre signature sont envoyés dans votre espace privé Supabase ; votre adresse e-mail y sert à gérer le compte.'**
  String get localPrivacyStatement;

  /// No description provided for @cloud.
  ///
  /// In fr, this message translates to:
  /// **'Cloud'**
  String get cloud;

  /// No description provided for @cloudSync.
  ///
  /// In fr, this message translates to:
  /// **'Cloud / Synchroniser'**
  String get cloudSync;

  /// No description provided for @documentVault.
  ///
  /// In fr, this message translates to:
  /// **'Coffre-fort documentaire'**
  String get documentVault;

  /// No description provided for @connectProfileCloud.
  ///
  /// In fr, this message translates to:
  /// **'Connectez-vous dans Profil pour utiliser le cloud.'**
  String get connectProfileCloud;

  /// No description provided for @connectProfileSaveProcedure.
  ///
  /// In fr, this message translates to:
  /// **'Connectez-vous dans Profil avant de sauvegarder cette démarche.'**
  String get connectProfileSaveProcedure;

  /// No description provided for @supabaseNotConfigured.
  ///
  /// In fr, this message translates to:
  /// **'Supabase n’est pas configuré dans cette version.'**
  String get supabaseNotConfigured;

  /// No description provided for @procedureCreated.
  ///
  /// In fr, this message translates to:
  /// **'Créée'**
  String get procedureCreated;

  /// No description provided for @procedureSent.
  ///
  /// In fr, this message translates to:
  /// **'Envoyée'**
  String get procedureSent;

  /// No description provided for @procedureWaiting.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get procedureWaiting;

  /// No description provided for @procedureReminder.
  ///
  /// In fr, this message translates to:
  /// **'Relance prévue'**
  String get procedureReminder;

  /// No description provided for @procedureCompleted.
  ///
  /// In fr, this message translates to:
  /// **'Terminée'**
  String get procedureCompleted;

  /// No description provided for @inProgress.
  ///
  /// In fr, this message translates to:
  /// **'En cours'**
  String get inProgress;

  /// No description provided for @toProcess.
  ///
  /// In fr, this message translates to:
  /// **'À traiter'**
  String get toProcess;

  /// No description provided for @urgent.
  ///
  /// In fr, this message translates to:
  /// **'Urgents'**
  String get urgent;

  /// No description provided for @archivedMasculine.
  ///
  /// In fr, this message translates to:
  /// **'Archivés'**
  String get archivedMasculine;

  /// No description provided for @archivedFeminine.
  ///
  /// In fr, this message translates to:
  /// **'Archivées'**
  String get archivedFeminine;

  /// No description provided for @noProcedureSection.
  ///
  /// In fr, this message translates to:
  /// **'Aucune démarche dans cette section.'**
  String get noProcedureSection;

  /// No description provided for @editProcedure.
  ///
  /// In fr, this message translates to:
  /// **'Modifier la démarche'**
  String get editProcedure;

  /// No description provided for @deleteProcedureQuestion.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer cette démarche ?'**
  String get deleteProcedureQuestion;

  /// No description provided for @deleteDocumentQuestion.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce document ?'**
  String get deleteDocumentQuestion;

  /// No description provided for @editDocument.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le document'**
  String get editDocument;

  /// No description provided for @noDocumentFilters.
  ///
  /// In fr, this message translates to:
  /// **'Aucun document ne correspond aux filtres sélectionnés.'**
  String get noDocumentFilters;

  /// No description provided for @classifyDocumentsHelp.
  ///
  /// In fr, this message translates to:
  /// **'Classez, retrouvez et suivez tous vos documents administratifs au même endroit.'**
  String get classifyDocumentsHelp;

  /// No description provided for @documentFileUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Le fichier PDF n’est plus disponible, mais le texte archivé reste accessible.'**
  String get documentFileUnavailable;

  /// No description provided for @advancedAnalysis.
  ///
  /// In fr, this message translates to:
  /// **'Analyse avancée'**
  String get advancedAnalysis;

  /// No description provided for @plainLanguageExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Explication en langage simple'**
  String get plainLanguageExplanation;

  /// No description provided for @hideExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Masquer l’explication'**
  String get hideExplanation;

  /// No description provided for @documentQuestions.
  ///
  /// In fr, this message translates to:
  /// **'Questions sur le document'**
  String get documentQuestions;

  /// No description provided for @askDocumentQuestion.
  ///
  /// In fr, this message translates to:
  /// **'Poser une question sur ce document'**
  String get askDocumentQuestion;

  /// No description provided for @desiredReply.
  ///
  /// In fr, this message translates to:
  /// **'Quelle réponse souhaitez-vous envoyer ?'**
  String get desiredReply;

  /// No description provided for @generateReply.
  ///
  /// In fr, this message translates to:
  /// **'Générer la réponse'**
  String get generateReply;

  /// No description provided for @generateSuitableReply.
  ///
  /// In fr, this message translates to:
  /// **'Générer une réponse adaptée'**
  String get generateSuitableReply;

  /// No description provided for @noTextToAnalyze.
  ///
  /// In fr, this message translates to:
  /// **'Ajoutez d’abord le texte du courrier pour l’analyser.'**
  String get noTextToAnalyze;

  /// No description provided for @noDocumentFirst.
  ///
  /// In fr, this message translates to:
  /// **'Scannez ou ajoutez d’abord un document.'**
  String get noDocumentFirst;

  /// No description provided for @describeProblemFirst.
  ///
  /// In fr, this message translates to:
  /// **'Décrivez d’abord votre problème.'**
  String get describeProblemFirst;

  /// No description provided for @checkImportantInformation.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez les informations importantes dans le document original.'**
  String get checkImportantInformation;

  /// No description provided for @generalModelWarning.
  ///
  /// In fr, this message translates to:
  /// **'Modèle général : vérifiez toujours les dates, montants, références et obligations du courrier original.'**
  String get generalModelWarning;

  /// No description provided for @mandatoryField.
  ///
  /// In fr, this message translates to:
  /// **'Champ obligatoire'**
  String get mandatoryField;

  /// No description provided for @notProvided.
  ///
  /// In fr, this message translates to:
  /// **'Non renseigné'**
  String get notProvided;

  /// No description provided for @other.
  ///
  /// In fr, this message translates to:
  /// **'Autre'**
  String get other;

  /// No description provided for @yes.
  ///
  /// In fr, this message translates to:
  /// **'Oui'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In fr, this message translates to:
  /// **'Non'**
  String get no;

  /// No description provided for @pageNumber.
  ///
  /// In fr, this message translates to:
  /// **'Page {number}'**
  String pageNumber(int number);

  /// No description provided for @modelsCount.
  ///
  /// In fr, this message translates to:
  /// **'Modèles de lettres ({count})'**
  String modelsCount(int count);

  /// No description provided for @proceduresCount.
  ///
  /// In fr, this message translates to:
  /// **'Mes démarches ({count})'**
  String proceduresCount(int count);

  /// No description provided for @documentsCount.
  ///
  /// In fr, this message translates to:
  /// **'Mes documents ({count})'**
  String documentsCount(int count);

  /// No description provided for @favoritesCount.
  ///
  /// In fr, this message translates to:
  /// **'Favoris ({count})'**
  String favoritesCount(int count);

  /// No description provided for @recentCount.
  ///
  /// In fr, this message translates to:
  /// **'Récents ({count})'**
  String recentCount(int count);

  /// No description provided for @searchModelsFor.
  ///
  /// In fr, this message translates to:
  /// **'Chercher « {query} » dans les modèles'**
  String searchModelsFor(String query);

  /// No description provided for @operationFailed.
  ///
  /// In fr, this message translates to:
  /// **'{operation} impossible : {error}'**
  String operationFailed(String operation, String error);

  /// No description provided for @brandNameUpper.
  ///
  /// In fr, this message translates to:
  /// **'ADMIN FACILE'**
  String get brandNameUpper;

  /// No description provided for @tenProfessionalModels.
  ///
  /// In fr, this message translates to:
  /// **'10 modèles professionnels'**
  String get tenProfessionalModels;

  /// No description provided for @assistantAdministrativeVersion.
  ///
  /// In fr, this message translates to:
  /// **'Assistant administratif • V7.0'**
  String get assistantAdministrativeVersion;

  /// No description provided for @assistantPremium.
  ///
  /// In fr, this message translates to:
  /// **'Assistant IA Premium'**
  String get assistantPremium;

  /// No description provided for @translationAdministrativeVersion.
  ///
  /// In fr, this message translates to:
  /// **'Traduction administrative • V7.0'**
  String get translationAdministrativeVersion;

  /// No description provided for @assistedReplyVersion.
  ///
  /// In fr, this message translates to:
  /// **'Réponse assistée • V3.1'**
  String get assistedReplyVersion;

  /// No description provided for @autoShort.
  ///
  /// In fr, this message translates to:
  /// **'Auto'**
  String get autoShort;

  /// No description provided for @correct.
  ///
  /// In fr, this message translates to:
  /// **'Corriger'**
  String get correct;

  /// No description provided for @sendAction.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get sendAction;

  /// No description provided for @reminderDate.
  ///
  /// In fr, this message translates to:
  /// **'Date de relance'**
  String get reminderDate;

  /// No description provided for @chooseImageFormat.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez une image PNG, JPG ou JPEG.'**
  String get chooseImageFormat;

  /// No description provided for @pdfMustBeSavedToOpen.
  ///
  /// In fr, this message translates to:
  /// **'Ce PDF doit d’abord être enregistré localement pour être ouvert.'**
  String get pdfMustBeSavedToOpen;

  /// No description provided for @pdfMustBeStored.
  ///
  /// In fr, this message translates to:
  /// **'Le PDF doit d’abord être enregistré dans le stockage de l’application.'**
  String get pdfMustBeStored;

  /// No description provided for @postWebsiteUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d’ouvrir le site de La Poste.'**
  String get postWebsiteUnavailable;

  /// No description provided for @letterStaysLocal.
  ///
  /// In fr, this message translates to:
  /// **'La lettre reste locale et n’est jamais envoyée automatiquement vers Supabase.'**
  String get letterStaysLocal;

  /// No description provided for @documentWillBeAttached.
  ///
  /// In fr, this message translates to:
  /// **'Le document sera ajouté en pièce jointe.'**
  String get documentWillBeAttached;

  /// No description provided for @fiveBestLetters.
  ///
  /// In fr, this message translates to:
  /// **'Les 5 courriers les plus adaptés'**
  String get fiveBestLetters;

  /// No description provided for @letterPdfFileName.
  ///
  /// In fr, this message translates to:
  /// **'Lettre AdminFacile.pdf'**
  String get letterPdfFileName;

  /// No description provided for @editInformation.
  ///
  /// In fr, this message translates to:
  /// **'Modifier les informations'**
  String get editInformation;

  /// No description provided for @procedureCreatedAutomatically.
  ///
  /// In fr, this message translates to:
  /// **'Une démarche est créée automatiquement lorsque vous générez une lettre.'**
  String get procedureCreatedAutomatically;

  /// No description provided for @printSharePdfHelp.
  ///
  /// In fr, this message translates to:
  /// **'Utilisez “Imprimer / partager le PDF” pour ce document.'**
  String get printSharePdfHelp;

  /// No description provided for @verifyTitleSubject.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez le titre et l’objet avant de personnaliser la lettre.'**
  String get verifyTitleSubject;

  /// No description provided for @describeSituationGemini.
  ///
  /// In fr, this message translates to:
  /// **'Décrivez votre situation. Gemini prépare un modèle professionnel que vous pourrez vérifier, compléter et modifier.'**
  String get describeSituationGemini;

  /// No description provided for @generateSendTrackLetters.
  ///
  /// In fr, this message translates to:
  /// **'Générez, envoyez et suivez vos courriers administratifs simplement.'**
  String get generateSendTrackLetters;

  /// No description provided for @needExamples.
  ///
  /// In fr, this message translates to:
  /// **'Exemples : « résilier Orange », « contester une facture EDF », « préavis logement » ou « remboursement CPAM ».'**
  String get needExamples;

  /// No description provided for @speechSilenceHelp.
  ///
  /// In fr, this message translates to:
  /// **'Android peut arrêter la reconnaissance après quelques secondes de silence. Appuyez de nouveau sur le microphone pour continuer votre texte.'**
  String get speechSilenceHelp;

  /// No description provided for @localAnalysisWarning.
  ///
  /// In fr, this message translates to:
  /// **'Analyse locale indicative : vérifiez toujours les dates, montants, références et obligations avant d’envoyer une réponse.'**
  String get localAnalysisWarning;

  /// No description provided for @noLetterForFiltersHelp.
  ///
  /// In fr, this message translates to:
  /// **'Aucun courrier ne correspond à ces filtres. Essayez un mot plus simple ou affichez tous les modèles.'**
  String get noLetterForFiltersHelp;

  /// No description provided for @privacyFullStatement.
  ///
  /// In fr, this message translates to:
  /// **'Vos documents restent enregistrés localement par défaut. Si vous choisissez la synchronisation, le document PDF ou l’image et votre signature sont envoyés dans votre espace privé Supabase ; votre adresse e-mail y sert à gérer le compte. Lorsque vous utilisez Gemini, seul le texte nécessaire à l’analyse est envoyé : le PDF ou la photo ne sont pas transmis à Gemini.\n\nVérifiez toujours les informations importantes avant tout partage ou envoi.'**
  String get privacyFullStatement;

  /// No description provided for @documentType.
  ///
  /// In fr, this message translates to:
  /// **'Type du document'**
  String get documentType;

  /// No description provided for @supplierOrOrganization.
  ///
  /// In fr, this message translates to:
  /// **'Fournisseur ou organisme'**
  String get supplierOrOrganization;

  /// No description provided for @totalAmount.
  ///
  /// In fr, this message translates to:
  /// **'Montant total'**
  String get totalAmount;

  /// No description provided for @dueDate.
  ///
  /// In fr, this message translates to:
  /// **'Date limite'**
  String get dueDate;

  /// No description provided for @reference.
  ///
  /// In fr, this message translates to:
  /// **'Référence'**
  String get reference;

  /// No description provided for @category.
  ///
  /// In fr, this message translates to:
  /// **'Catégorie'**
  String get category;

  /// No description provided for @priority.
  ///
  /// In fr, this message translates to:
  /// **'Priorité'**
  String get priority;

  /// No description provided for @moreActions.
  ///
  /// In fr, this message translates to:
  /// **'Plus d’actions'**
  String get moreActions;

  /// No description provided for @resetZoom.
  ///
  /// In fr, this message translates to:
  /// **'Réinitialiser le zoom'**
  String get resetZoom;

  /// No description provided for @dictatedEditableText.
  ///
  /// In fr, this message translates to:
  /// **'Texte dicté et modifiable'**
  String get dictatedEditableText;

  /// No description provided for @speechInputHint.
  ///
  /// In fr, this message translates to:
  /// **'Appuyez sur le microphone, puis commencez à parler.'**
  String get speechInputHint;

  /// No description provided for @fromLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Depuis'**
  String get fromLanguage;

  /// No description provided for @toLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Vers'**
  String get toLanguage;

  /// No description provided for @swapLanguages.
  ///
  /// In fr, this message translates to:
  /// **'Inverser les langues'**
  String get swapLanguages;

  /// No description provided for @textToTranslate.
  ///
  /// In fr, this message translates to:
  /// **'Texte à traduire'**
  String get textToTranslate;

  /// No description provided for @translationInputHint.
  ///
  /// In fr, this message translates to:
  /// **'Écrivez, collez ou dictez le texte à traduire.'**
  String get translationInputHint;

  /// No description provided for @askDocumentHint.
  ///
  /// In fr, this message translates to:
  /// **'Posez une question sur le document…'**
  String get askDocumentHint;

  /// No description provided for @administrativeDomain.
  ///
  /// In fr, this message translates to:
  /// **'Domaine administratif'**
  String get administrativeDomain;

  /// No description provided for @organizationOrRecipient.
  ///
  /// In fr, this message translates to:
  /// **'Organisme ou destinataire'**
  String get organizationOrRecipient;

  /// No description provided for @requestQuestion.
  ///
  /// In fr, this message translates to:
  /// **'Que souhaitez-vous demander ?'**
  String get requestQuestion;

  /// No description provided for @usefulInformation.
  ///
  /// In fr, this message translates to:
  /// **'Informations utiles'**
  String get usefulInformation;

  /// No description provided for @letterTone.
  ///
  /// In fr, this message translates to:
  /// **'Ton de la lettre'**
  String get letterTone;

  /// No description provided for @letterType.
  ///
  /// In fr, this message translates to:
  /// **'Type de courrier'**
  String get letterType;

  /// No description provided for @format.
  ///
  /// In fr, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @tone.
  ///
  /// In fr, this message translates to:
  /// **'Ton'**
  String get tone;

  /// No description provided for @yourLetter.
  ///
  /// In fr, this message translates to:
  /// **'Votre courrier'**
  String get yourLetter;

  /// No description provided for @shareAnalysis.
  ///
  /// In fr, this message translates to:
  /// **'Partager l’analyse'**
  String get shareAnalysis;

  /// No description provided for @optionalDetails.
  ///
  /// In fr, this message translates to:
  /// **'Précisions facultatives'**
  String get optionalDetails;

  /// No description provided for @yourReply.
  ///
  /// In fr, this message translates to:
  /// **'Votre réponse'**
  String get yourReply;

  /// No description provided for @replyInputHint.
  ///
  /// In fr, this message translates to:
  /// **'Écrivez votre réponse ou utilisez le microphone.'**
  String get replyInputHint;

  /// No description provided for @yourProblem.
  ///
  /// In fr, this message translates to:
  /// **'Votre problème'**
  String get yourProblem;

  /// No description provided for @needOrOrganization.
  ///
  /// In fr, this message translates to:
  /// **'Votre besoin ou un organisme'**
  String get needOrOrganization;

  /// No description provided for @needSearchHint.
  ///
  /// In fr, this message translates to:
  /// **'Ex. résiliation mobile, CAF, facture EDF…'**
  String get needSearchHint;

  /// No description provided for @firstName.
  ///
  /// In fr, this message translates to:
  /// **'Prénom'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In fr, this message translates to:
  /// **'Nom'**
  String get lastName;

  /// No description provided for @address.
  ///
  /// In fr, this message translates to:
  /// **'Adresse'**
  String get address;

  /// No description provided for @postalCode.
  ///
  /// In fr, this message translates to:
  /// **'Code postal'**
  String get postalCode;

  /// No description provided for @city.
  ///
  /// In fr, this message translates to:
  /// **'Ville'**
  String get city;

  /// No description provided for @organizationCompanyEmployer.
  ///
  /// In fr, this message translates to:
  /// **'Organisme, entreprise ou employeur'**
  String get organizationCompanyEmployer;

  /// No description provided for @recipientAddressOptional.
  ///
  /// In fr, this message translates to:
  /// **'Adresse du destinataire (facultatif)'**
  String get recipientAddressOptional;

  /// No description provided for @contractReference.
  ///
  /// In fr, this message translates to:
  /// **'Référence ou numéro de contrat'**
  String get contractReference;

  /// No description provided for @detailRequest.
  ///
  /// In fr, this message translates to:
  /// **'Précisez votre demande'**
  String get detailRequest;

  /// No description provided for @requestDetailsHint.
  ///
  /// In fr, this message translates to:
  /// **'Écrivez ou dictez les détails de votre demande.'**
  String get requestDetailsHint;

  /// No description provided for @recipientOptional.
  ///
  /// In fr, this message translates to:
  /// **'Destinataire (facultatif)'**
  String get recipientOptional;

  /// No description provided for @message.
  ///
  /// In fr, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @desiredTone.
  ///
  /// In fr, this message translates to:
  /// **'Ton souhaité'**
  String get desiredTone;

  /// No description provided for @saveAsPdf.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer en PDF'**
  String get saveAsPdf;

  /// No description provided for @editableDocument.
  ///
  /// In fr, this message translates to:
  /// **'Document modifiable'**
  String get editableDocument;

  /// No description provided for @status.
  ///
  /// In fr, this message translates to:
  /// **'Statut'**
  String get status;

  /// No description provided for @personalNotes.
  ///
  /// In fr, this message translates to:
  /// **'Notes personnelles'**
  String get personalNotes;

  /// No description provided for @removeDate.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer la date'**
  String get removeDate;

  /// No description provided for @refreshCloud.
  ///
  /// In fr, this message translates to:
  /// **'Actualiser le cloud'**
  String get refreshCloud;

  /// No description provided for @searchProcedure.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher une démarche'**
  String get searchProcedure;

  /// No description provided for @title.
  ///
  /// In fr, this message translates to:
  /// **'Titre'**
  String get title;

  /// No description provided for @detectedType.
  ///
  /// In fr, this message translates to:
  /// **'Type détecté'**
  String get detectedType;

  /// No description provided for @detectedPriority.
  ///
  /// In fr, this message translates to:
  /// **'Priorité détectée'**
  String get detectedPriority;

  /// No description provided for @organization.
  ///
  /// In fr, this message translates to:
  /// **'Organisme'**
  String get organization;

  /// No description provided for @searchDocumentHint.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher dans le titre, l’OCR ou les notes'**
  String get searchDocumentHint;

  /// No description provided for @sortBy.
  ///
  /// In fr, this message translates to:
  /// **'Trier par'**
  String get sortBy;

  /// No description provided for @newPassword.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau mot de passe'**
  String get newPassword;

  /// No description provided for @sixCharactersMinimum.
  ///
  /// In fr, this message translates to:
  /// **'6 caractères minimum'**
  String get sixCharactersMinimum;

  /// No description provided for @accountEmailAddress.
  ///
  /// In fr, this message translates to:
  /// **'Adresse e-mail du compte'**
  String get accountEmailAddress;

  /// No description provided for @phone.
  ///
  /// In fr, this message translates to:
  /// **'Téléphone'**
  String get phone;

  /// No description provided for @translationPart.
  ///
  /// In fr, this message translates to:
  /// **'Partie à traduire'**
  String get translationPart;

  /// No description provided for @createdOn.
  ///
  /// In fr, this message translates to:
  /// **'Créée le {date}'**
  String createdOn(String date);

  /// No description provided for @reminderOn.
  ///
  /// In fr, this message translates to:
  /// **'Relance le\n{date}'**
  String reminderOn(String date);

  /// No description provided for @deadlineValue.
  ///
  /// In fr, this message translates to:
  /// **'Échéance : {value}'**
  String deadlineValue(String value);

  /// No description provided for @supplierValue.
  ///
  /// In fr, this message translates to:
  /// **'Fournisseur : {value}'**
  String supplierValue(String value);

  /// No description provided for @organizationValue.
  ///
  /// In fr, this message translates to:
  /// **'Organisme : {value}'**
  String organizationValue(String value);

  /// No description provided for @periodValue.
  ///
  /// In fr, this message translates to:
  /// **'Période : {value}'**
  String periodValue(String value);

  /// No description provided for @priorityValue.
  ///
  /// In fr, this message translates to:
  /// **'Priorité : {value}'**
  String priorityValue(String value);

  /// No description provided for @folderCompletion.
  ///
  /// In fr, this message translates to:
  /// **'Préparation du dossier : {percent} %'**
  String folderCompletion(int percent);

  /// No description provided for @reminderScheduled.
  ///
  /// In fr, this message translates to:
  /// **'Rappel prévu le {date}'**
  String reminderScheduled(String date);

  /// No description provided for @moreAdministrativeModels.
  ///
  /// In fr, this message translates to:
  /// **'Plus de {count} modèles de lettres administratives'**
  String moreAdministrativeModels(int count);

  /// No description provided for @deleteNamedItem.
  ///
  /// In fr, this message translates to:
  /// **'« {title} » sera supprimé définitivement.'**
  String deleteNamedItem(String title);

  /// No description provided for @savedSecurely.
  ///
  /// In fr, this message translates to:
  /// **'« {title} » est sauvegardée dans votre espace sécurisé.'**
  String savedSecurely(String title);

  /// No description provided for @invalidEmail.
  ///
  /// In fr, this message translates to:
  /// **'Adresse e-mail invalide.'**
  String get invalidEmail;

  /// No description provided for @enterPassword.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre mot de passe.'**
  String get enterPassword;

  /// No description provided for @passwordMinimum.
  ///
  /// In fr, this message translates to:
  /// **'Le mot de passe doit contenir au moins 6 caractères.'**
  String get passwordMinimum;

  /// No description provided for @serviceTimeout.
  ///
  /// In fr, this message translates to:
  /// **'Le service met trop de temps à répondre. Réessayez.'**
  String get serviceTimeout;

  /// No description provided for @checkInternet.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez votre connexion Internet.'**
  String get checkInternet;

  /// No description provided for @invalidServiceResponse.
  ///
  /// In fr, this message translates to:
  /// **'Le service a renvoyé une réponse invalide. Réessayez.'**
  String get invalidServiceResponse;

  /// No description provided for @emailAlreadyUsed.
  ///
  /// In fr, this message translates to:
  /// **'Adresse e-mail déjà utilisée.'**
  String get emailAlreadyUsed;

  /// No description provided for @incorrectPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe incorrect.'**
  String get incorrectPassword;

  /// No description provided for @accountNotConfirmed.
  ///
  /// In fr, this message translates to:
  /// **'Compte non confirmé. Vérifiez votre e-mail.'**
  String get accountNotConfirmed;

  /// No description provided for @tooManyAttempts.
  ///
  /// In fr, this message translates to:
  /// **'Trop de tentatives. Réessayez dans quelques minutes.'**
  String get tooManyAttempts;

  /// No description provided for @sessionExpired.
  ///
  /// In fr, this message translates to:
  /// **'Votre session a expiré. Reconnectez-vous.'**
  String get sessionExpired;

  /// No description provided for @googleUnavailableDevice.
  ///
  /// In fr, this message translates to:
  /// **'La connexion Google n’est pas disponible sur cet appareil.'**
  String get googleUnavailableDevice;

  /// No description provided for @googleValidationFailed.
  ///
  /// In fr, this message translates to:
  /// **'La connexion Google n’a pas pu être validée.'**
  String get googleValidationFailed;

  /// No description provided for @googleNoValidSession.
  ///
  /// In fr, this message translates to:
  /// **'La connexion Google n’a pas créé de session valide.'**
  String get googleNoValidSession;

  /// No description provided for @googleCancelled.
  ///
  /// In fr, this message translates to:
  /// **'Connexion Google annulée.'**
  String get googleCancelled;

  /// No description provided for @googleNoAccount.
  ///
  /// In fr, this message translates to:
  /// **'Aucun compte Google n’est disponible sur cet appareil.'**
  String get googleNoAccount;

  /// No description provided for @ocrNoTextPhoto.
  ///
  /// In fr, this message translates to:
  /// **'Aucun texte reconnu. Reprenez la photo avec une meilleure lumière.'**
  String get ocrNoTextPhoto;

  /// No description provided for @ocrRecognitionFailed.
  ///
  /// In fr, this message translates to:
  /// **'Le texte du document n’a pas pu être reconnu. Vérifiez la netteté et la lumière, puis réessayez.'**
  String get ocrRecognitionFailed;

  /// No description provided for @ocrNoTextScan.
  ///
  /// In fr, this message translates to:
  /// **'Aucun texte n’a été détecté. Essayez avec davantage de lumière ou utilisez « Photo simple ».'**
  String get ocrNoTextScan;

  /// No description provided for @capturedRenderFailed.
  ///
  /// In fr, this message translates to:
  /// **'Le document capturé est conservé, mais son rendu n’a pas pu être préparé.'**
  String get capturedRenderFailed;

  /// No description provided for @signatureSavedLocal.
  ///
  /// In fr, this message translates to:
  /// **'Signature enregistrée sur ce téléphone.'**
  String get signatureSavedLocal;

  /// No description provided for @signatureDeletedLocal.
  ///
  /// In fr, this message translates to:
  /// **'Signature supprimée de ce téléphone.'**
  String get signatureDeletedLocal;

  /// No description provided for @pdfReadyPages.
  ///
  /// In fr, this message translates to:
  /// **'PDF prêt • {count} page(s)'**
  String pdfReadyPages(int count);

  /// No description provided for @lettersCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0 {Aucun courrier} =1 {1 courrier} other {{count} courriers}}'**
  String lettersCount(int count);

  /// No description provided for @syncCompleted.
  ///
  /// In fr, this message translates to:
  /// **'Synchronisation terminée : {title}.'**
  String syncCompleted(String title);

  /// No description provided for @syncFailed.
  ///
  /// In fr, this message translates to:
  /// **'La synchronisation de {title} a échoué.'**
  String syncFailed(String title);

  /// No description provided for @importantReminder.
  ///
  /// In fr, this message translates to:
  /// **'Rappel important : {title}.'**
  String importantReminder(String title);

  /// No description provided for @welcome.
  ///
  /// In fr, this message translates to:
  /// **'Bienvenue'**
  String get welcome;

  /// No description provided for @helloName.
  ///
  /// In fr, this message translates to:
  /// **'Bonjour {name}'**
  String helloName(String name);

  /// No description provided for @documentsWithDeadline.
  ///
  /// In fr, this message translates to:
  /// **'{count} document(s) avec échéance'**
  String documentsWithDeadline(int count);

  /// No description provided for @remindersNextSevenDays.
  ///
  /// In fr, this message translates to:
  /// **'{count} relance(s) dans les 7 jours'**
  String remindersNextSevenDays(int count);

  /// No description provided for @remindersToday.
  ///
  /// In fr, this message translates to:
  /// **'{count} relance(s) aujourd’hui'**
  String remindersToday(int count);

  /// No description provided for @waitingProcedures.
  ///
  /// In fr, this message translates to:
  /// **'{count} démarche(s) en attente de réponse'**
  String waitingProcedures(int count);

  /// No description provided for @operationImport.
  ///
  /// In fr, this message translates to:
  /// **'Import'**
  String get operationImport;

  /// No description provided for @operationRead.
  ///
  /// In fr, this message translates to:
  /// **'Lecture'**
  String get operationRead;

  /// No description provided for @operationOpen.
  ///
  /// In fr, this message translates to:
  /// **'Ouverture'**
  String get operationOpen;

  /// No description provided for @operationSearch.
  ///
  /// In fr, this message translates to:
  /// **'Recherche'**
  String get operationSearch;

  /// No description provided for @operationArchive.
  ///
  /// In fr, this message translates to:
  /// **'Archivage'**
  String get operationArchive;

  /// No description provided for @operationSignature.
  ///
  /// In fr, this message translates to:
  /// **'Signature'**
  String get operationSignature;

  /// No description provided for @operationTranslation.
  ///
  /// In fr, this message translates to:
  /// **'Traduction'**
  String get operationTranslation;

  /// No description provided for @noRelevantLetterHelp.
  ///
  /// In fr, this message translates to:
  /// **'Aucun courrier suffisamment pertinent n’a été trouvé. Précisez l’organisme et l’action, par exemple : « résilier box Orange ».'**
  String get noRelevantLetterHelp;

  /// No description provided for @signatureDeletedCloudRetry.
  ///
  /// In fr, this message translates to:
  /// **'Signature supprimée de ce téléphone. La suppression cloud sera à réessayer avec une connexion active.'**
  String get signatureDeletedCloudRetry;

  /// No description provided for @microphoneError.
  ///
  /// In fr, this message translates to:
  /// **'Microphone : {error}'**
  String microphoneError(String error);

  /// No description provided for @libraryLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de charger la bibliothèque : {error}'**
  String libraryLoadError(String error);

  /// No description provided for @signatureNotSavedError.
  ///
  /// In fr, this message translates to:
  /// **'Signature non enregistrée : {error}'**
  String signatureNotSavedError(String error);

  /// No description provided for @signatureSavedWithWarning.
  ///
  /// In fr, this message translates to:
  /// **'Signature enregistrée sur ce téléphone. {warning}'**
  String signatureSavedWithWarning(String warning);

  /// No description provided for @frenchLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Français'**
  String get frenchLanguage;

  /// No description provided for @englishLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Anglais'**
  String get englishLanguage;

  /// No description provided for @spanishLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Espagnol'**
  String get spanishLanguage;

  /// No description provided for @germanLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Allemand'**
  String get germanLanguage;

  /// No description provided for @italianLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Italien'**
  String get italianLanguage;

  /// No description provided for @portugueseLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Portugais'**
  String get portugueseLanguage;

  /// No description provided for @arabicLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Arabe'**
  String get arabicLanguage;

  /// No description provided for @modelsDownloadedFirstUse.
  ///
  /// In fr, this message translates to:
  /// **'Les modèles nécessaires seront téléchargés au premier usage.'**
  String get modelsDownloadedFirstUse;

  /// No description provided for @preparingLocalTranslation.
  ///
  /// In fr, this message translates to:
  /// **'Préparation de la traduction locale…'**
  String get preparingLocalTranslation;

  /// No description provided for @sameTranslationLanguage.
  ///
  /// In fr, this message translates to:
  /// **'La langue du document et la langue cible sont identiques.'**
  String get sameTranslationLanguage;

  /// No description provided for @translationInProgress.
  ///
  /// In fr, this message translates to:
  /// **'Traduction en cours…'**
  String get translationInProgress;

  /// No description provided for @translationResultPlaceholder.
  ///
  /// In fr, this message translates to:
  /// **'La traduction apparaîtra ici.'**
  String get translationResultPlaceholder;

  /// No description provided for @preparingLanguageModels.
  ///
  /// In fr, this message translates to:
  /// **'Préparation des modèles de langue…'**
  String get preparingLanguageModels;

  /// No description provided for @localTranslationInProgress.
  ///
  /// In fr, this message translates to:
  /// **'Traduction locale en cours…'**
  String get localTranslationInProgress;

  /// No description provided for @downloadingLanguageModel.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement du modèle {code}…'**
  String downloadingLanguageModel(String code);

  /// No description provided for @modelUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Modèle indisponible : {error}'**
  String modelUnavailable(String error);

  /// No description provided for @brandSemanticLabel.
  ///
  /// In fr, this message translates to:
  /// **'ADMIN FACILE. Vos démarches administratives, simplifiées par l’IA'**
  String get brandSemanticLabel;

  /// No description provided for @brandSymbolSemanticLabel.
  ///
  /// In fr, this message translates to:
  /// **'Symbole Admin Facile'**
  String get brandSymbolSemanticLabel;

  /// No description provided for @globalSearchHint.
  ///
  /// In fr, this message translates to:
  /// **'CAF, Orange, facture, résiliation…'**
  String get globalSearchHint;

  /// No description provided for @contextDetailsHint.
  ///
  /// In fr, this message translates to:
  /// **'Dates, démarches déjà effectuées, problème rencontré…'**
  String get contextDetailsHint;

  /// No description provided for @problemExampleHint.
  ///
  /// In fr, this message translates to:
  /// **'Ex. résiliation Orange, facture EDF, préavis…'**
  String get problemExampleHint;

  /// No description provided for @requestExampleHint.
  ///
  /// In fr, this message translates to:
  /// **'Exemple : résilier mon abonnement Internet à la suite de mon déménagement.'**
  String get requestExampleHint;

  /// No description provided for @searchAmongModels.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher parmi {count} modèles'**
  String searchAmongModels(int count);

  /// No description provided for @turkishLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Turc'**
  String get turkishLanguage;

  /// No description provided for @initializingMicrophone.
  ///
  /// In fr, this message translates to:
  /// **'Initialisation du microphone…'**
  String get initializingMicrophone;

  /// No description provided for @listening.
  ///
  /// In fr, this message translates to:
  /// **'Je vous écoute…'**
  String get listening;

  /// No description provided for @microphoneReady.
  ///
  /// In fr, this message translates to:
  /// **'Microphone prêt'**
  String get microphoneReady;

  /// No description provided for @speechUnavailablePermission.
  ///
  /// In fr, this message translates to:
  /// **'Reconnaissance vocale indisponible ou permission refusée'**
  String get speechUnavailablePermission;

  /// No description provided for @listenPhoneLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Je vous écoute avec la langue du téléphone…'**
  String get listenPhoneLanguage;

  /// No description provided for @stopDictation.
  ///
  /// In fr, this message translates to:
  /// **'Arrêter la dictée'**
  String get stopDictation;

  /// No description provided for @dictateTranslationText.
  ///
  /// In fr, this message translates to:
  /// **'Dicter le texte à traduire'**
  String get dictateTranslationText;

  /// No description provided for @languageModelsFirstUse.
  ///
  /// In fr, this message translates to:
  /// **'Les modèles de langue seront téléchargés au premier usage.'**
  String get languageModelsFirstUse;

  /// No description provided for @sameSourceTargetLanguage.
  ///
  /// In fr, this message translates to:
  /// **'La langue source et la langue cible sont identiques.'**
  String get sameSourceTargetLanguage;

  /// No description provided for @preparingTranslation.
  ///
  /// In fr, this message translates to:
  /// **'Préparation de la traduction…'**
  String get preparingTranslation;

  /// No description provided for @translationReviewWarning.
  ///
  /// In fr, this message translates to:
  /// **'Traduction terminée. Relisez les noms, références et formulations administratives avant l’envoi.'**
  String get translationReviewWarning;

  /// No description provided for @microphoneInitializationError.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d’initialiser le microphone : {error}'**
  String microphoneInitializationError(String error);

  /// No description provided for @microphoneShortError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur micro : {error}'**
  String microphoneShortError(String error);

  /// No description provided for @listeningInLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Je vous écoute en {language}…'**
  String listeningInLanguage(String language);

  /// No description provided for @translationError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de traduction : {error}'**
  String translationError(String error);

  /// No description provided for @languageModelDownloadFailed.
  ///
  /// In fr, this message translates to:
  /// **'Le modèle {code} n’a pas pu être téléchargé.'**
  String languageModelDownloadFailed(String code);

  /// No description provided for @listeningClearly.
  ///
  /// In fr, this message translates to:
  /// **'Je vous écoute… Parlez clairement.'**
  String get listeningClearly;

  /// No description provided for @startDictation.
  ///
  /// In fr, this message translates to:
  /// **'Commencer la dictée'**
  String get startDictation;

  /// No description provided for @microphoneReadyFrench.
  ///
  /// In fr, this message translates to:
  /// **'Microphone prêt – français détecté'**
  String get microphoneReadyFrench;

  /// No description provided for @genericError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur : {error}'**
  String genericError(String error);

  /// No description provided for @aiAvailableUpper.
  ///
  /// In fr, this message translates to:
  /// **'ASSISTANT IA DISPONIBLE'**
  String get aiAvailableUpper;

  /// No description provided for @aiUnavailableUpper.
  ///
  /// In fr, this message translates to:
  /// **'ASSISTANT IA INDISPONIBLE'**
  String get aiUnavailableUpper;

  /// No description provided for @aiTemporarilyUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Assistant IA momentanément indisponible.'**
  String get aiTemporarilyUnavailable;

  /// No description provided for @geminiAvailable.
  ///
  /// In fr, this message translates to:
  /// **'Gemini disponible'**
  String get geminiAvailable;

  /// No description provided for @geminiUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Gemini indisponible'**
  String get geminiUnavailable;

  /// No description provided for @describeLetter.
  ///
  /// In fr, this message translates to:
  /// **'Décrivez la lettre que vous souhaitez rédiger.'**
  String get describeLetter;

  /// No description provided for @describeSituationOrResult.
  ///
  /// In fr, this message translates to:
  /// **'Décrivez votre situation ou le résultat souhaité.'**
  String get describeSituationOrResult;

  /// No description provided for @writingWithGemini.
  ///
  /// In fr, this message translates to:
  /// **'Rédaction avec Gemini'**
  String get writingWithGemini;

  /// No description provided for @letterReady.
  ///
  /// In fr, this message translates to:
  /// **'Lettre prête'**
  String get letterReady;

  /// No description provided for @connectionError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de connexion'**
  String get connectionError;

  /// No description provided for @localLetterPrepared.
  ///
  /// In fr, this message translates to:
  /// **'Une lettre locale a été préparée.'**
  String get localLetterPrepared;

  /// No description provided for @letterManuallyEditable.
  ///
  /// In fr, this message translates to:
  /// **'La lettre reste modifiable manuellement.'**
  String get letterManuallyEditable;

  /// No description provided for @cloudTimeout.
  ///
  /// In fr, this message translates to:
  /// **'Le service cloud met trop de temps à répondre. Réessayez.'**
  String get cloudTimeout;

  /// No description provided for @cloudSessionInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Votre session cloud n’est plus valide. Reconnectez-vous.'**
  String get cloudSessionInvalid;

  /// No description provided for @cloudUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Le service cloud est momentanément indisponible.'**
  String get cloudUnavailable;

  /// No description provided for @today.
  ///
  /// In fr, this message translates to:
  /// **'Aujourd’hui'**
  String get today;

  /// No description provided for @reminders.
  ///
  /// In fr, this message translates to:
  /// **'Relances'**
  String get reminders;

  /// No description provided for @completedPlural.
  ///
  /// In fr, this message translates to:
  /// **'Terminées'**
  String get completedPlural;

  /// No description provided for @quickActions.
  ///
  /// In fr, this message translates to:
  /// **'Actions rapides'**
  String get quickActions;

  /// No description provided for @letterSingular.
  ///
  /// In fr, this message translates to:
  /// **'Lettre'**
  String get letterSingular;

  /// No description provided for @recentActivity.
  ///
  /// In fr, this message translates to:
  /// **'Activité récente'**
  String get recentActivity;

  /// No description provided for @freeDictation.
  ///
  /// In fr, this message translates to:
  /// **'Dictée libre'**
  String get freeDictation;

  /// No description provided for @history.
  ///
  /// In fr, this message translates to:
  /// **'Historique'**
  String get history;

  /// No description provided for @administrativeAssistantTwoLines.
  ///
  /// In fr, this message translates to:
  /// **'Assistant\nadministratif'**
  String get administrativeAssistantTwoLines;

  /// No description provided for @myProceduresTwoLines.
  ///
  /// In fr, this message translates to:
  /// **'Mes\ndémarches'**
  String get myProceduresTwoLines;

  /// No description provided for @upcomingRemindersTwoLines.
  ///
  /// In fr, this message translates to:
  /// **'Relances\nà venir'**
  String get upcomingRemindersTwoLines;

  /// No description provided for @completedProceduresTwoLines.
  ///
  /// In fr, this message translates to:
  /// **'Démarches\nterminées'**
  String get completedProceduresTwoLines;

  /// No description provided for @waitingReplyTwoLines.
  ///
  /// In fr, this message translates to:
  /// **'En attente\nde réponse'**
  String get waitingReplyTwoLines;

  /// No description provided for @totalAmountToPay.
  ///
  /// In fr, this message translates to:
  /// **'Montant total à payer'**
  String get totalAmountToPay;

  /// No description provided for @openProfile.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le Profil'**
  String get openProfile;

  /// No description provided for @syncedMasculine.
  ///
  /// In fr, this message translates to:
  /// **'Synchronisé'**
  String get syncedMasculine;

  /// No description provided for @syncedFeminine.
  ///
  /// In fr, this message translates to:
  /// **'Synchronisée'**
  String get syncedFeminine;

  /// No description provided for @courteous.
  ///
  /// In fr, this message translates to:
  /// **'Courtois'**
  String get courteous;

  /// No description provided for @professional.
  ///
  /// In fr, this message translates to:
  /// **'Professionnel'**
  String get professional;

  /// No description provided for @firm.
  ///
  /// In fr, this message translates to:
  /// **'Ferme'**
  String get firm;

  /// No description provided for @verySimple.
  ///
  /// In fr, this message translates to:
  /// **'Très simple'**
  String get verySimple;

  /// No description provided for @complaint.
  ///
  /// In fr, this message translates to:
  /// **'Réclamation'**
  String get complaint;

  /// No description provided for @cancellation.
  ///
  /// In fr, this message translates to:
  /// **'Résiliation'**
  String get cancellation;

  /// No description provided for @dispute.
  ///
  /// In fr, this message translates to:
  /// **'Contestation'**
  String get dispute;

  /// No description provided for @documentRequest.
  ///
  /// In fr, this message translates to:
  /// **'Demande de document'**
  String get documentRequest;

  /// No description provided for @organizationReply.
  ///
  /// In fr, this message translates to:
  /// **'Réponse à un organisme'**
  String get organizationReply;

  /// No description provided for @reminder.
  ///
  /// In fr, this message translates to:
  /// **'Relance'**
  String get reminder;

  /// No description provided for @freeLetter.
  ///
  /// In fr, this message translates to:
  /// **'Lettre libre'**
  String get freeLetter;

  /// No description provided for @officialLetter.
  ///
  /// In fr, this message translates to:
  /// **'Courrier officiel'**
  String get officialLetter;

  /// No description provided for @registeredLetter.
  ///
  /// In fr, this message translates to:
  /// **'Lettre recommandée'**
  String get registeredLetter;

  /// No description provided for @formalNotice.
  ///
  /// In fr, this message translates to:
  /// **'Mise en demeure'**
  String get formalNotice;

  /// No description provided for @geminiWritingLetter.
  ///
  /// In fr, this message translates to:
  /// **'Gemini rédige la lettre…'**
  String get geminiWritingLetter;

  /// No description provided for @generateLetterWithGemini.
  ///
  /// In fr, this message translates to:
  /// **'Générer la lettre avec Gemini'**
  String get generateLetterWithGemini;

  /// No description provided for @localModeAvailable.
  ///
  /// In fr, this message translates to:
  /// **'Mode local disponible'**
  String get localModeAvailable;

  /// No description provided for @noUrgentActionDetected.
  ///
  /// In fr, this message translates to:
  /// **'Aucune action urgente détectée'**
  String get noUrgentActionDetected;

  /// No description provided for @toCheck.
  ///
  /// In fr, this message translates to:
  /// **'À vérifier'**
  String get toCheck;

  /// No description provided for @deadlineOrReplySoon.
  ///
  /// In fr, this message translates to:
  /// **'Échéance ou réponse proche'**
  String get deadlineOrReplySoon;

  /// No description provided for @completedMasculine.
  ///
  /// In fr, this message translates to:
  /// **'Terminé'**
  String get completedMasculine;

  /// No description provided for @archivedSingular.
  ///
  /// In fr, this message translates to:
  /// **'Archivé'**
  String get archivedSingular;

  /// No description provided for @importantPriority.
  ///
  /// In fr, this message translates to:
  /// **'Important'**
  String get importantPriority;

  /// No description provided for @informationPriority.
  ///
  /// In fr, this message translates to:
  /// **'Information'**
  String get informationPriority;

  /// No description provided for @mostRecent.
  ///
  /// In fr, this message translates to:
  /// **'Plus récents'**
  String get mostRecent;

  /// No description provided for @oldest.
  ///
  /// In fr, this message translates to:
  /// **'Plus anciens'**
  String get oldest;

  /// No description provided for @noSavedOcrText.
  ///
  /// In fr, this message translates to:
  /// **'Aucun texte OCR enregistré.'**
  String get noSavedOcrText;

  /// No description provided for @dictateReply.
  ///
  /// In fr, this message translates to:
  /// **'Dicter la réponse'**
  String get dictateReply;

  /// No description provided for @dictateMyReply.
  ///
  /// In fr, this message translates to:
  /// **'Dicter ma réponse'**
  String get dictateMyReply;

  /// No description provided for @removeFavorite.
  ///
  /// In fr, this message translates to:
  /// **'Retirer des favoris'**
  String get removeFavorite;

  /// No description provided for @addFavorite.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter aux favoris'**
  String get addFavorite;

  /// No description provided for @connectedAccount.
  ///
  /// In fr, this message translates to:
  /// **'Compte connecté'**
  String get connectedAccount;

  /// No description provided for @profileSaved.
  ///
  /// In fr, this message translates to:
  /// **'Profil enregistré'**
  String get profileSaved;

  /// No description provided for @profileKeptOnDevice.
  ///
  /// In fr, this message translates to:
  /// **'Profil conservé sur cet appareil. {warning}'**
  String profileKeptOnDevice(String warning);

  /// No description provided for @accountServiceNotConfigured.
  ///
  /// In fr, this message translates to:
  /// **'Le service de compte n’est pas configuré.'**
  String get accountServiceNotConfigured;

  /// No description provided for @accountCreatedConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Compte créé. Vérifiez votre e-mail pour confirmer votre compte.'**
  String get accountCreatedConfirm;

  /// No description provided for @accountCreatedSignedIn.
  ///
  /// In fr, this message translates to:
  /// **'Compte créé et connexion réussie.'**
  String get accountCreatedSignedIn;

  /// No description provided for @signInSucceeded.
  ///
  /// In fr, this message translates to:
  /// **'Connexion réussie.'**
  String get signInSucceeded;

  /// No description provided for @passwordUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe mis à jour.'**
  String get passwordUpdated;

  /// No description provided for @signatureTooLarge.
  ///
  /// In fr, this message translates to:
  /// **'La signature dépasse la taille maximale de 5 Mo.'**
  String get signatureTooLarge;

  /// No description provided for @detectedAmount.
  ///
  /// In fr, this message translates to:
  /// **'Montant repéré'**
  String get detectedAmount;

  /// No description provided for @scannedDocument.
  ///
  /// In fr, this message translates to:
  /// **'Document scanné'**
  String get scannedDocument;

  /// No description provided for @globalSearchEmptyHelp.
  ///
  /// In fr, this message translates to:
  /// **'Retrouvez vos démarches et vos documents depuis un seul écran.'**
  String get globalSearchEmptyHelp;

  /// No description provided for @globalSearchNoResultHelp.
  ///
  /// In fr, this message translates to:
  /// **'Essayez un organisme, un sujet ou un mot présent dans le document.'**
  String get globalSearchNoResultHelp;

  /// No description provided for @offlineModelsHelp.
  ///
  /// In fr, this message translates to:
  /// **'Les modèles sont disponibles même sans connexion Internet.'**
  String get offlineModelsHelp;

  /// No description provided for @procedureNeedsCompletion.
  ///
  /// In fr, this message translates to:
  /// **'Votre démarche {name} est à compléter.'**
  String procedureNeedsCompletion(String name);

  /// No description provided for @documentWasAdded.
  ///
  /// In fr, this message translates to:
  /// **'Votre document {name} a été ajouté.'**
  String documentWasAdded(String name);

  /// No description provided for @letterResultsCount.
  ///
  /// In fr, this message translates to:
  /// **'{visible} courrier(s) sur {total}'**
  String letterResultsCount(int visible, int total);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'es', 'fr', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
