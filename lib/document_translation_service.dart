import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class DocumentTranslationLanguage {
  const DocumentTranslationLanguage(this.label, this.language);

  final String label;
  final TranslateLanguage language;

  String get code => language.bcpCode;
}

const supportedDocumentTranslationLanguages = <DocumentTranslationLanguage>[
  DocumentTranslationLanguage('Français', TranslateLanguage.french),
  DocumentTranslationLanguage('Anglais', TranslateLanguage.english),
  DocumentTranslationLanguage('Espagnol', TranslateLanguage.spanish),
  DocumentTranslationLanguage('Allemand', TranslateLanguage.german),
  DocumentTranslationLanguage('Italien', TranslateLanguage.italian),
  DocumentTranslationLanguage('Portugais', TranslateLanguage.portuguese),
  DocumentTranslationLanguage('Arabe', TranslateLanguage.arabic),
];

DocumentTranslationLanguage documentTranslationLanguageForCode(
  String? code, {
  required DocumentTranslationLanguage fallback,
}) {
  return supportedDocumentTranslationLanguages.firstWhere(
    (language) => language.code == code,
    orElse: () => fallback,
  );
}

class DocumentTranslationModelException implements Exception {
  const DocumentTranslationModelException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class DocumentTranslationException implements Exception {
  const DocumentTranslationException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

typedef TranslationStatusCallback = void Function(String status);

abstract interface class DocumentTranslationEngine {
  Future<void> ensureModels(
    TranslateLanguage source,
    TranslateLanguage target, {
    TranslationStatusCallback? onStatus,
  });

  Future<List<String>> translateBlocks(
    List<String> blocks,
    TranslateLanguage source,
    TranslateLanguage target,
  );
}

class MlKitDocumentTranslationEngine implements DocumentTranslationEngine {
  MlKitDocumentTranslationEngine({
    OnDeviceTranslatorModelManager? modelManager,
  }) : _modelManager = modelManager ?? OnDeviceTranslatorModelManager();

  final OnDeviceTranslatorModelManager _modelManager;

  @override
  Future<void> ensureModels(
    TranslateLanguage source,
    TranslateLanguage target, {
    TranslationStatusCallback? onStatus,
  }) async {
    for (final language in {source, target}) {
      final code = language.bcpCode;
      try {
        if (await _modelManager.isModelDownloaded(code)) continue;
        onStatus?.call('Téléchargement du modèle $code…');
        final downloaded = await _modelManager.downloadModel(code);
        if (!downloaded) {
          throw DocumentTranslationModelException(
            'Le modèle de langue $code n’a pas pu être téléchargé.',
          );
        }
      } on DocumentTranslationModelException {
        rethrow;
      } catch (error) {
        throw DocumentTranslationModelException(
          'Le modèle de langue $code n’a pas pu être préparé.',
          error,
        );
      }
    }
  }

  @override
  Future<List<String>> translateBlocks(
    List<String> blocks,
    TranslateLanguage source,
    TranslateLanguage target,
  ) async {
    final translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );
    try {
      final translated = <String>[];
      for (final block in blocks) {
        translated.add(await translator.translateText(block));
      }
      return translated;
    } catch (error) {
      throw DocumentTranslationException(
        'La traduction locale du document a échoué.',
        error,
      );
    } finally {
      await translator.close();
    }
  }
}

class DocumentTranslationResult {
  const DocumentTranslationResult({
    required this.pageTexts,
    required this.fullText,
  });

  final List<String> pageTexts;
  final String fullText;
}

class DocumentTranslationService {
  DocumentTranslationService({
    DocumentTranslationEngine? engine,
    this.maxBlockCharacters = 1200,
  })  : assert(maxBlockCharacters > 0),
        engine = engine ?? MlKitDocumentTranslationEngine();

  final DocumentTranslationEngine engine;
  final int maxBlockCharacters;

  Future<DocumentTranslationResult> translatePages({
    required List<String> pageTexts,
    required TranslateLanguage source,
    required TranslateLanguage target,
    TranslationStatusCallback? onStatus,
  }) async {
    final immutableInput = List<String>.unmodifiable(pageTexts);
    if (immutableInput.isEmpty ||
        immutableInput.every((page) => page.trim().isEmpty) ||
        source == target) {
      return _resultFor(immutableInput);
    }

    onStatus?.call('Préparation des modèles de langue…');
    await engine.ensureModels(source, target, onStatus: onStatus);

    final plans = immutableInput.map(_planPage).toList(growable: false);
    final blocks = <String>[
      for (final plan in plans)
        for (final line in plan.lines) ...line.blocks,
    ];
    if (blocks.isEmpty) return _resultFor(immutableInput);

    onStatus?.call('Traduction locale en cours…');
    final translated = await engine.translateBlocks(blocks, source, target);
    if (translated.length != blocks.length) {
      throw const DocumentTranslationException(
        'La traduction locale a renvoyé un résultat incomplet.',
      );
    }

    var translatedIndex = 0;
    final translatedPages = <String>[];
    for (final plan in plans) {
      final buffer = StringBuffer();
      for (final line in plan.lines) {
        if (line.blocks.isEmpty) {
          buffer.write(line.original);
        } else {
          buffer.write(line.leadingWhitespace);
          for (var index = 0; index < line.blocks.length; index++) {
            if (index > 0) buffer.write(' ');
            buffer.write(translated[translatedIndex++]);
          }
          buffer.write(line.trailingWhitespace);
        }
        buffer.write(line.lineBreak);
      }
      translatedPages.add(buffer.toString());
    }
    return _resultFor(List<String>.unmodifiable(translatedPages));
  }

  _PageTranslationPlan _planPage(String page) {
    final lines = <_LineTranslationPlan>[];
    var start = 0;
    for (final match in RegExp(r'\r\n|\n|\r').allMatches(page)) {
      lines.add(_planLine(page.substring(start, match.start), match.group(0)!));
      start = match.end;
    }
    lines.add(_planLine(page.substring(start), ''));
    return _PageTranslationPlan(lines);
  }

  _LineTranslationPlan _planLine(String line, String lineBreak) {
    final core = line.trim();
    if (core.isEmpty) {
      return _LineTranslationPlan(
        original: line,
        lineBreak: lineBreak,
        blocks: const [],
      );
    }
    final coreStart = line.indexOf(core);
    return _LineTranslationPlan(
      original: line,
      lineBreak: lineBreak,
      leadingWhitespace: line.substring(0, coreStart),
      trailingWhitespace: line.substring(coreStart + core.length),
      blocks: _splitWithoutCuttingWords(core),
    );
  }

  List<String> _splitWithoutCuttingWords(String text) {
    if (text.length <= maxBlockCharacters) return [text];
    final blocks = <String>[];
    var remaining = text;
    while (remaining.length > maxBlockCharacters) {
      var splitAt = remaining.lastIndexOf(' ', maxBlockCharacters);
      if (splitAt <= 0) {
        final nextSpace = remaining.indexOf(' ', maxBlockCharacters);
        if (nextSpace < 0) break;
        splitAt = nextSpace;
      }
      final block = remaining.substring(0, splitAt).trim();
      if (block.isNotEmpty) blocks.add(block);
      remaining = remaining.substring(splitAt).trimLeft();
    }
    if (remaining.isNotEmpty) blocks.add(remaining);
    return blocks;
  }

  static DocumentTranslationResult _resultFor(List<String> pages) {
    final pageTexts = List<String>.unmodifiable(pages);
    final fullText = pageTexts.length <= 1
        ? (pageTexts.isEmpty ? '' : pageTexts.single)
        : [
            for (var index = 0; index < pageTexts.length; index++)
              if (index == 0)
                pageTexts[index]
              else
                '\n\n--- Page ${index + 1} ---\n\n${pageTexts[index]}',
          ].join();
    return DocumentTranslationResult(pageTexts: pageTexts, fullText: fullText);
  }
}

class _PageTranslationPlan {
  const _PageTranslationPlan(this.lines);

  final List<_LineTranslationPlan> lines;
}

class _LineTranslationPlan {
  const _LineTranslationPlan({
    required this.original,
    required this.lineBreak,
    required this.blocks,
    this.leadingWhitespace = '',
    this.trailingWhitespace = '',
  });

  final String original;
  final String lineBreak;
  final List<String> blocks;
  final String leadingWhitespace;
  final String trailingWhitespace;
}
