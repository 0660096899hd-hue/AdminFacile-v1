import 'package:admin_facile/document_translation_screen.dart';
import 'package:admin_facile/document_translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UiTranslationEngine implements DocumentTranslationEngine {
  @override
  Future<void> ensureModels(
    TranslateLanguage source,
    TranslateLanguage target, {
    TranslationStatusCallback? onStatus,
  }) async {}

  @override
  Future<List<String>> translateBlocks(
    List<String> blocks,
    TranslateLanguage source,
    TranslateLanguage target,
  ) async {
    return blocks
        .map((block) => block == 'Bonjour' ? 'Hello' : 'Translated: $block')
        .toList(growable: false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('affiche, traduit et copie le texte OCR', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final service = DocumentTranslationService(
      engine: _UiTranslationEngine(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentTranslationScreen(
          pageTexts: const ['Bonjour'],
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Langue du document'), findsOneWidget);
    expect(find.text('Traduire vers'), findsOneWidget);
    expect(find.text('Texte original'), findsOneWidget);
    expect(find.text('Bonjour'), findsOneWidget);

    await tester.tap(find.byKey(const Key('document-translation-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Traduction terminée sur l’appareil.'), findsOneWidget);

    final copyButton = find.byKey(const Key('document-translation-copy'));
    await tester.scrollUntilVisible(
      copyButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final copy = tester.widget<FilledButton>(copyButton);
    copy.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Traduction copiée'), findsOneWidget);
  });

  testWidgets('propose document complet et sélection de page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentTranslationScreen(
          pageTexts: const ['Première page', 'Deuxième page'],
          service: DocumentTranslationService(
            engine: _UiTranslationEngine(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Document complet'), findsOneWidget);
    expect(find.textContaining('--- Page 2 ---'), findsOneWidget);
    expect(find.text('Page 1'), findsNothing);

    await tester.tap(find.byKey(const Key('document-translation-page')));
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
  });
}
