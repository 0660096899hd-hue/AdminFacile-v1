import 'package:admin_facile/document_translation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class FakeDocumentTranslationEngine implements DocumentTranslationEngine {
  final List<List<String>> blockCalls = [];
  final List<(TranslateLanguage, TranslateLanguage)> modelCalls = [];
  Object? modelError;
  Object? translationError;
  String Function(String block) translate = (block) => '[$block]';

  @override
  Future<void> ensureModels(
    TranslateLanguage source,
    TranslateLanguage target, {
    TranslationStatusCallback? onStatus,
  }) async {
    modelCalls.add((source, target));
    if (modelError != null) throw modelError!;
  }

  @override
  Future<List<String>> translateBlocks(
    List<String> blocks,
    TranslateLanguage source,
    TranslateLanguage target,
  ) async {
    blockCalls.add(List<String>.from(blocks));
    if (translationError != null) throw translationError!;
    return blocks.map(translate).toList(growable: false);
  }
}

void main() {
  late FakeDocumentTranslationEngine engine;
  late DocumentTranslationService service;

  setUp(() {
    engine = FakeDocumentTranslationEngine();
    service = DocumentTranslationService(engine: engine);
  });

  test('expose les sept langues ML Kit demandées', () {
    expect(
      supportedDocumentTranslationLanguages.map((item) => item.language),
      [
        TranslateLanguage.french,
        TranslateLanguage.english,
        TranslateLanguage.spanish,
        TranslateLanguage.german,
        TranslateLanguage.italian,
        TranslateLanguage.portuguese,
        TranslateLanguage.arabic,
      ],
    );
  });

  test('source identique à cible conserve le texte sans modèle', () async {
    final result = await service.translatePages(
      pageTexts: const ['Texte original'],
      source: TranslateLanguage.french,
      target: TranslateLanguage.french,
    );

    expect(result.fullText, 'Texte original');
    expect(engine.modelCalls, isEmpty);
    expect(engine.blockCalls, isEmpty);
  });

  test('texte vide ne télécharge ni ne traduit', () async {
    final result = await service.translatePages(
      pageTexts: const ['', '  '],
      source: TranslateLanguage.french,
      target: TranslateLanguage.english,
    );

    expect(result.pageTexts, ['', '  ']);
    expect(engine.modelCalls, isEmpty);
    expect(engine.blockCalls, isEmpty);
  });

  test('traduit un texte simple après préparation des modèles', () async {
    engine.translate = (block) => block == 'Bonjour' ? 'Hello' : block;
    final statuses = <String>[];

    final result = await service.translatePages(
      pageTexts: const ['Bonjour'],
      source: TranslateLanguage.french,
      target: TranslateLanguage.english,
      onStatus: statuses.add,
    );

    expect(result.fullText, 'Hello');
    expect(
      engine.modelCalls,
      [(TranslateLanguage.french, TranslateLanguage.english)],
    );
    expect(statuses, contains('Traduction locale en cours…'));
  });

  test('conserve paragraphes et retours à la ligne', () async {
    final result = await service.translatePages(
      pageTexts: const ['Premier paragraphe\n\nSecond paragraphe\nTroisième'],
      source: TranslateLanguage.french,
      target: TranslateLanguage.english,
    );

    expect(
      result.fullText,
      '[Premier paragraphe]\n\n[Second paragraphe]\n[Troisième]',
    );
  });

  test('découpe un long document sans couper les mots', () async {
    service = DocumentTranslationService(
      engine: engine,
      maxBlockCharacters: 12,
    );
    const input = 'alpha bravo charlie delta echo foxtrot golf';

    await service.translatePages(
      pageTexts: const [input],
      source: TranslateLanguage.french,
      target: TranslateLanguage.english,
    );

    final blocks = engine.blockCalls.single;
    expect(blocks.length, greaterThan(1));
    expect(blocks.every((block) => !block.startsWith(' ')), isTrue);
    expect(blocks.every((block) => !block.endsWith(' ')), isTrue);
    expect(blocks.join(' '), input);
  });

  test('recompose les blocs traduits dans leur ordre', () async {
    service = DocumentTranslationService(
      engine: engine,
      maxBlockCharacters: 10,
    );
    var sequence = 0;
    engine.translate = (_) => '${++sequence}';

    final result = await service.translatePages(
      pageTexts: const ['un deux trois quatre cinq six sept'],
      source: TranslateLanguage.french,
      target: TranslateLanguage.english,
    );

    expect(result.fullText, '1 2 3 4 5');
  });

  test('conserve les pages et construit une vue document multipage', () async {
    final result = await service.translatePages(
      pageTexts: const ['Page une', 'Page deux', 'Page trois'],
      source: TranslateLanguage.french,
      target: TranslateLanguage.english,
    );

    expect(result.pageTexts, ['[Page une]', '[Page deux]', '[Page trois]']);
    expect(
      result.fullText,
      '[Page une]\n\n--- Page 2 ---\n\n[Page deux]'
      '\n\n--- Page 3 ---\n\n[Page trois]',
    );
  });

  test('propage une erreur de modèle sans annoncer de traduction', () async {
    engine.modelError = const DocumentTranslationModelException(
      'Modèle indisponible',
    );

    await expectLater(
      service.translatePages(
        pageTexts: const ['Bonjour'],
        source: TranslateLanguage.french,
        target: TranslateLanguage.english,
      ),
      throwsA(isA<DocumentTranslationModelException>()),
    );
    expect(engine.blockCalls, isEmpty);
  });

  test('propage une erreur de traduction', () async {
    engine.translationError = const DocumentTranslationException(
      'Traduction impossible',
    );

    await expectLater(
      service.translatePages(
        pageTexts: const ['Bonjour'],
        source: TranslateLanguage.french,
        target: TranslateLanguage.english,
      ),
      throwsA(isA<DocumentTranslationException>()),
    );
  });
}
