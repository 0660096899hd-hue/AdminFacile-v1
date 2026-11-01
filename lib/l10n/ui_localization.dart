import 'package:flutter/material.dart' as material;

import 'app_localizations.dart';
import 'ui_text_catalog_data.dart';

String uiText(material.BuildContext context, String source) {
  final language = material.Localizations.localeOf(context).languageCode;
  final direct = uiTextCatalogByLanguage[language]?[source];
  if (direct != null) return direct;
  if (language != 'es') return source;

  final l10n = AppLocalizations.of(context);
  final countPatterns = <RegExp, String Function(int)>{
    RegExp(r'^Modèles de lettres \((\d+)\)$'): l10n.modelsCount,
    RegExp(r'^Mes démarches \((\d+)\)$'): l10n.proceduresCount,
    RegExp(r'^Mes documents \((\d+)\)$'): l10n.documentsCount,
    RegExp(r'^Favoris \((\d+)\)$'): l10n.favoritesCount,
    RegExp(r'^Récents \((\d+)\)$'): l10n.recentCount,
  };
  for (final entry in countPatterns.entries) {
    final match = entry.key.firstMatch(source);
    if (match != null) return entry.value(int.parse(match.group(1)!));
  }

  final pageMatch = RegExp(r'^Page (\d+)$').firstMatch(source);
  if (pageMatch != null) return l10n.pageNumber(int.parse(pageMatch.group(1)!));

  final dynamicPatterns = <RegExp, String Function(RegExpMatch)>{
    RegExp(r'^Créée le (.+)$'): (match) => l10n.createdOn(match.group(1)!),
    RegExp(r'^Relance le\n(.+)$'): (match) => l10n.reminderOn(match.group(1)!),
    RegExp(r'^Échéance : (.+)$'): (match) =>
        l10n.deadlineValue(match.group(1)!),
    RegExp(r'^Fournisseur : (.+)$'): (match) =>
        l10n.supplierValue(match.group(1)!),
    RegExp(r'^Organisme : (.+)\n?$'): (match) =>
        l10n.organizationValue(match.group(1)!),
    RegExp(r'^Période : (.+)$'): (match) => l10n.periodValue(match.group(1)!),
    RegExp(r'^Priorité : (.+)$'): (match) =>
        l10n.priorityValue(match.group(1)!),
    RegExp(r'^Préparation du dossier : (\d+) %$'): (match) =>
        l10n.folderCompletion(int.parse(match.group(1)!)),
    RegExp(r'^Rappel prévu le (.+)$'): (match) =>
        l10n.reminderScheduled(match.group(1)!),
    RegExp(r'^Plus de (\d+) modèles de lettres administratives$'): (match) =>
        l10n.moreAdministrativeModels(int.parse(match.group(1)!)),
    RegExp(r'^PDF prêt • (\d+) page(?:\(s\)|s)?$'): (match) =>
        l10n.pdfReadyPages(int.parse(match.group(1)!)),
    RegExp(r'^(\d+) courriers?$'): (match) =>
        l10n.lettersCount(int.parse(match.group(1)!)),
    RegExp(r'^« (.+) » sera supprimé(?:e)? définitivement\.$'): (match) =>
        l10n.deleteNamedItem(match.group(1)!),
    RegExp(r'^« (.+) » est sauvegardée dans votre espace sécurisé\.$'):
        (match) => l10n.savedSecurely(match.group(1)!),
    RegExp(r'^Synchronisation terminée : (.+)\.$'): (match) =>
        l10n.syncCompleted(match.group(1)!),
    RegExp(r'^La synchronisation de (.+) a échoué\.$'): (match) =>
        l10n.syncFailed(match.group(1)!),
    RegExp(r'^Rappel important : (.+)\.$'): (match) =>
        l10n.importantReminder(match.group(1)!),
    RegExp(r'^(\d+) document\(s\) avec échéance$'): (match) =>
        l10n.documentsWithDeadline(int.parse(match.group(1)!)),
    RegExp(r'^(\d+) relance\(s\) dans les 7 jours$'): (match) =>
        l10n.remindersNextSevenDays(int.parse(match.group(1)!)),
    RegExp(r'^(\d+) relance\(s\) aujourd’hui$'): (match) =>
        l10n.remindersToday(int.parse(match.group(1)!)),
    RegExp(r'^(\d+) démarche\(s\) en attente de réponse$'): (match) =>
        l10n.waitingProcedures(int.parse(match.group(1)!)),
    RegExp(r'^Microphone : (.+)$'): (match) =>
        l10n.microphoneError(match.group(1)!),
    RegExp(r'^Impossible de charger la bibliothèque : (.+)$'): (match) =>
        l10n.libraryLoadError(match.group(1)!),
    RegExp(r'^Signature non enregistrée : (.+)$'): (match) =>
        l10n.signatureNotSavedError(uiText(context, match.group(1)!)),
    RegExp(r'^Signature enregistrée sur ce téléphone\. (.+)$', dotAll: true):
        (match) => l10n.signatureSavedWithWarning(match.group(1)!),
    RegExp(r'^Téléchargement du modèle (.+)…$'): (match) =>
        l10n.downloadingLanguageModel(match.group(1)!),
    RegExp(r'^Modèle indisponible : (.+)$'): (match) =>
        l10n.modelUnavailable(match.group(1)!),
    RegExp(r'^Rechercher parmi (\d+) modèles$'): (match) =>
        l10n.searchAmongModels(int.parse(match.group(1)!)),
    RegExp(r'^Erreur micro : (.+)$'): (match) =>
        l10n.microphoneShortError(match.group(1)!),
    RegExp(r'^Impossible d’initialiser le microphone : (.+)$'): (match) =>
        l10n.microphoneInitializationError(match.group(1)!),
    RegExp(r'^Je vous écoute en (.+)…$'): (match) =>
        l10n.listeningInLanguage(uiText(context, match.group(1)!)),
    RegExp(r'^Erreur de traduction : (.+)$', dotAll: true): (match) =>
        l10n.translationError(uiText(context, match.group(1)!)),
    RegExp(r'^(?:Exception: )?Le modèle (.+) n’a pas pu être téléchargé\.$'):
        (match) => l10n.languageModelDownloadFailed(match.group(1)!),
    RegExp(r'^Erreur : (.+)$'): (match) => l10n.genericError(match.group(1)!),
    RegExp(r'^Profil conservé sur cet appareil\. (.+)$', dotAll: true):
        (match) => l10n.profileKeptOnDevice(uiText(context, match.group(1)!)),
    RegExp(r'^Votre démarche (.+) est à compléter\.$'): (match) =>
        l10n.procedureNeedsCompletion(match.group(1)!),
    RegExp(r'^Votre document (.+) a été ajouté\.$'): (match) =>
        l10n.documentWasAdded(match.group(1)!),
    RegExp(r'^(\d+) courriers? sur (\d+)$'): (match) => l10n.letterResultsCount(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
        ),
    RegExp(
      r'^(?:FileSystemException: )?La signature dépasse la taille maximale de 5 Mo\.?$',
    ): (_) => l10n.signatureTooLarge,
  };
  for (final entry in dynamicPatterns.entries) {
    final match = entry.key.firstMatch(source);
    if (match != null) return entry.value(match);
  }

  final searchMatch =
      RegExp(r'^Chercher « (.*) » dans les modèles$').firstMatch(source);
  if (searchMatch != null) return l10n.searchModelsFor(searchMatch.group(1)!);

  final failureMatch =
      RegExp(r'^(.+) impossible : (.+)$', dotAll: true).firstMatch(source);
  if (failureMatch != null) {
    return l10n.operationFailed(
      uiText(context, failureMatch.group(1)!),
      failureMatch.group(2)!,
    );
  }

  if (source == 'Bienvenue') return l10n.welcome;
  if (source.startsWith('Bonjour ')) {
    return l10n.helloName(source.substring('Bonjour '.length));
  }

  var withLocalizedStatuses = source;
  final catalog = uiTextCatalogByLanguage[language]!;
  for (final status in const [
    'Assistant IA momentanément indisponible.',
    'Une lettre locale a été préparée.',
    'La lettre reste modifiable manuellement.',
    'Relance prévue',
    'En attente',
    'Terminée',
    'Envoyée',
    'Créée',
  ]) {
    final localized = catalog[status];
    if (localized != null) {
      withLocalizedStatuses =
          withLocalizedStatuses.replaceAll(status, localized);
    }
  }
  return withLocalizedStatuses;
}

class LocalizedText extends material.StatelessWidget {
  const LocalizedText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final material.TextStyle? style;
  final material.StrutStyle? strutStyle;
  final material.TextAlign? textAlign;
  final material.TextDirection? textDirection;
  final material.Locale? locale;
  final bool? softWrap;
  final material.TextOverflow? overflow;
  final material.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final material.TextWidthBasis? textWidthBasis;
  final material.TextHeightBehavior? textHeightBehavior;
  final material.Color? selectionColor;

  @override
  material.Widget build(material.BuildContext context) => material.Text(
        uiText(context, data),
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel:
            semanticsLabel == null ? null : uiText(context, semanticsLabel!),
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
}
