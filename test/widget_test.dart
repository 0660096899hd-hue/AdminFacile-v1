import 'dart:io';
import 'dart:typed_data';

import 'package:admin_facile/main.dart';
import 'package:admin_facile/letter_signature_service.dart';
import 'package:admin_facile/signature_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AdminFacile V17 affiche le nouveau tableau de bord',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettings();
    final documentStore = DocumentStore();
    final procedureStore = ProcedureStore();
    await settings.load();
    await documentStore.load();
    await procedureStore.load();
    await tester.pumpWidget(AdminFacileApp(
      settings: settings,
      documentStore: documentStore,
      procedureStore: procedureStore,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-v17')), findsOneWidget);
    expect(find.text('Simplifiez vos démarches au quotidien'), findsOneWidget);
    expect(find.byKey(const Key('create-letter-v17')), findsOneWidget);
    for (final label in [
      'Assistant\nadministratif',
      'Bibliothèque\nde modèles',
      'Mes\ndémarches',
      'Favoris',
      'Historique'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('Le tableau de bord salue avec le prénom', (tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'firstName': 'hafid'});
    final settings = AppSettings();
    final documents = DocumentStore();
    final procedures = ProcedureStore();
    await settings.load();
    await documents.load();
    await procedures.load();
    expect(settings.greeting, 'Bonjour Hafid');
  });

  testWidgets('Le bouton Profil ouvre directement le profil', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettings();
    final documents = DocumentStore();
    final procedures = ProcedureStore();
    await settings.load();
    await documents.load();
    await procedures.load();
    await tester.pumpWidget(AdminFacileApp(
        settings: settings,
        documentStore: documents,
        procedureStore: procedures));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dashboard-profile-button')));
    await tester.pumpAndSettle();
    expect(find.text('Mon profil'), findsOneWidget);
  });

  test('Les compteurs V16 calculent les démarches et relances proches', () {
    final now = DateTime(2026, 8, 3);
    final metrics = DashboardMetrics(procedures: [
      AdministrativeProcedure(
          id: '1',
          title: 'CAF',
          organisation: 'CAF',
          category: 'Aides',
          letter: '',
          createdAt: now,
          updatedAt: now,
          status: ProcedureStatus.waiting),
      AdministrativeProcedure(
          id: '2',
          title: 'Impôts',
          organisation: 'DGFIP',
          category: 'Impôts',
          letter: '',
          createdAt: now,
          updatedAt: now,
          status: ProcedureStatus.reminder,
          reminderDate: now.add(const Duration(days: 4))),
      AdministrativeProcedure(
          id: '3',
          title: 'Terminée',
          organisation: 'CPAM',
          category: 'Santé',
          letter: '',
          createdAt: now,
          updatedAt: now,
          status: ProcedureStatus.completed),
    ], documents: const [], now: now);
    expect(metrics.activeProcedures, 2);
    expect(metrics.remindersNextSevenDays, 1);
    expect(metrics.waitingProcedures, 1);
  });

  testWidgets('Les trois compteurs À ne pas manquer sont affichés',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettings();
    final documents = DocumentStore();
    final procedures = ProcedureStore();
    await settings.load();
    await documents.load();
    await procedures.load();
    await tester.pumpWidget(AdminFacileApp(
        settings: settings,
        documentStore: documents,
        procedureStore: procedures));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('À ne pas manquer'), 500,
        scrollable: find.byType(Scrollable).first);
    for (final fragment in ['Relances', 'terminées', 'En attente']) {
      expect(find.textContaining(fragment), findsWidgets);
    }
  });

  testWidgets('L’activité récente affiche démarches et documents',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final procedures = ProcedureStore();
    final documents = DocumentStore();
    final now = DateTime(2026, 8, 3);
    await procedures.load();
    await documents.load();
    await procedures.add(AdministrativeProcedure(
        id: 'recent-p',
        title: 'Démarche récente',
        organisation: 'CAF',
        category: 'Aides',
        letter: '',
        createdAt: now,
        updatedAt: now));
    await documents.add(SavedDocument(
        id: 'recent-d',
        title: 'Document récent',
        category: 'Facture',
        organisation: 'EDF',
        createdAt: now));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HomeScreen(
                settings: AppSettings(),
                documentStore: documents,
                procedureStore: procedures,
                openScanner: () {},
                openLetters: () {},
                openSearch: () {},
                openProblem: () {},
                openAiWriter: () {},
                openTranslator: () {},
                openDictation: () {},
                openProcedures: () {},
                openDocuments: () {},
                openSecureSpace: () {},
                openMenu: () {},
                openGlobalSearch: () {},
                openProfile: () {}))));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Activité récente'), 500,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('recent-activity')), findsOneWidget);
    expect(find.text('Démarche récente'), findsOneWidget);
    expect(find.text('Document récent'), findsOneWidget);
  });

  testWidgets('Les cinq raccourcis principaux sont présents', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettings();
    final documents = DocumentStore();
    final procedures = ProcedureStore();
    await settings.load();
    await documents.load();
    await procedures.load();
    await tester.pumpWidget(AdminFacileApp(
        settings: settings,
        documentStore: documents,
        procedureStore: procedures));
    await tester.pumpAndSettle();
    for (final label in [
      'Assistant\nadministratif',
      'Bibliothèque\nde modèles',
      'Mes\ndémarches',
      'Favoris',
      'Historique'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('Les huit actions rapides ouvrent la bonne destination',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HomeScreen(
                settings: AppSettings(),
                documentStore: DocumentStore(),
                procedureStore: ProcedureStore(),
                openScanner: () => calls.add('Scanner'),
                openLetters: () => calls.add('Lettre'),
                openSearch: () {},
                openProblem: () {},
                openAiWriter: () => calls.add('Rédiger avec Gemini'),
                openTranslator: () => calls.add('Traduire'),
                openDictation: () {},
                openProcedures: () => calls.add('Démarches'),
                openDocuments: () => calls.add('Documents'),
                openSecureSpace: () => calls.add('Cloud'),
                openMenu: () {},
                openGlobalSearch: () => calls.add('Rechercher'),
                openProfile: () {}))));
    await tester.pump();
    for (final label in [
      'Scanner',
      'Rédiger avec Gemini',
      'Lettre',
      'Démarches',
      'Documents',
      'Cloud',
      'Traduire',
      'Rechercher'
    ]) {
      final action = find.byKey(ValueKey('quick-action-$label'));
      await tester.scrollUntilVisible(action, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(action);
      await tester.pump();
    }
    expect(calls, [
      'Scanner',
      'Rédiger avec Gemini',
      'Lettre',
      'Démarches',
      'Documents',
      'Cloud',
      'Traduire',
      'Rechercher'
    ]);
  });

  testWidgets('La section Ma signature est présente dans Profil',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettings();
    final documents = DocumentStore();
    final procedures = ProcedureStore();
    await settings.load();
    await documents.load();
    await procedures.load();
    await tester.pumpWidget(AdminFacileApp(
        settings: settings,
        documentStore: documents,
        procedureStore: procedures));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dashboard-profile-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ma signature'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('profile-signature-section')), findsOneWidget);
  });

  testWidgets('Le tableau de bord ne déborde pas aux tailles principales',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in [
      const Size(320, 568),
      const Size(344, 700),
      const Size(800, 400),
      const Size(1024, 768),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: LegacyHomeScreen(
                  settings: AppSettings(),
                  documentStore: DocumentStore(),
                  procedureStore: ProcedureStore(),
                  openScanner: () {},
                  openLetters: () {},
                  openSearch: () {},
                  openProblem: () {},
                  openAiWriter: () {},
                  openTranslator: () {},
                  openDictation: () {},
                  openProcedures: () {},
                  openDocuments: () {},
                  openSecureSpace: () {},
                  openMenu: () {},
                  openGlobalSearch: () {},
                  openProfile: () {}))));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Taille $size');
    }
  });

  testWidgets('Le tableau de bord limite les démarches récentes à trois',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettings();
    final documents = DocumentStore();
    final procedures = ProcedureStore();
    await settings.load();
    await documents.load();
    await procedures.load();
    final now = DateTime(2026, 8, 3);
    for (var index = 0; index < 4; index++) {
      await procedures.add(AdministrativeProcedure(
        id: 'procedure-$index',
        title: 'Démarche $index',
        organisation: 'Organisme $index',
        category: 'Test',
        letter: 'Courrier',
        createdAt: now,
        updatedAt: now.add(Duration(minutes: index)),
      ));
    }
    await tester.pumpWidget(AdminFacileApp(
        settings: settings,
        documentStore: documents,
        procedureStore: procedures));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Mes démarches en cours'), 500,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Démarche '), findsNWidgets(3));
  });

  testWidgets('L’écran de dessin de signature accepte un tracé',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignaturePadScreen()));
    final area = find.byKey(const Key('signature-drawing-area'));
    expect(area, findsOneWidget);
    await tester.drag(area, const Offset(100, 20));
    await tester.pump();
    expect(find.byKey(const Key('save-signature-drawing')), findsOneWidget);
  });

  test('La signature est sauvegardée localement et le réglage persiste',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory = await Directory.systemTemp.createTemp('adminfacile_v17_');
    addTearDown(() => directory.delete(recursive: true));
    final settings = AppSettings();
    await settings.load();
    final png = await File('assets/adminfacile_mark.png').readAsBytes();
    await settings.saveSignatureBytes(png, directory: directory);
    expect(settings.hasSignature, isTrue);
    await settings.setAutoInsertSignature(true);
    expect(settings.autoInsertSignature, isTrue);
    await settings.setAutoInsertSignature(false);
    expect(settings.autoInsertSignature, isFalse);
  });

  test('La signature est activée pour l’aperçu de lettre', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory =
        await Directory.systemTemp.createTemp('adminfacile_preview_');
    final settings = AppSettings();
    await settings.load();
    await settings.saveSignatureBytes(
        await File('assets/adminfacile_mark.png').readAsBytes(),
        directory: directory);
    await settings.setAutoInsertSignature(true);
    expect(shouldInsertSignature(settings), isTrue);
  });

  test('Le PDF A4 peut intégrer la signature', () async {
    final bytes = await buildSignedLetterPdf(
      text: 'Courrier administratif',
      subject: 'Test',
      signatureBytes: await File('assets/adminfacile_mark.png').readAsBytes(),
      senderName: 'Hafid Test',
    );
    expect(bytes.take(4), [37, 80, 68, 70]);
    expect(bytes.length, greaterThan(500));
  });

  test('Le PDF d\'une démarche utilise le chemin privé attendu', () {
    expect(
      procedureCloudPath('user-123', 'procedure-456'),
      'user-123/procedures/procedure-456.pdf',
    );
  });

  test('Assistant local comprend résilier Orange', () {
    final match =
        LocalIntentEngine.best('Je veux résilier mon abonnement Orange');
    expect(match.template, LetterTemplate.telecom);
    expect(match.model.title.toLowerCase(), contains('résiliation'));
  });

  test('Assistant local comprend facture EDF', () {
    final match =
        LocalIntentEngine.best('Je souhaite contester une facture EDF');
    expect(match.template, LetterTemplate.energy);
    expect(match.model.title.toLowerCase(), contains('contestation'));
  });

  test('Analyse locale détecte montant et organisme', () {
    final insight = LocalDocumentAnalyzer.analyze(
      'CAF - Dossier AB1234. Merci de régler 125,50 € avant le 15/08/2026.',
    );
    expect(insight.organisation, 'CAF');
    expect(insight.amounts, contains('125,50 €'));
    expect(insight.dates, contains('15/08/2026'));
  });

  test('Facture Gemini conserve les libellés des montants', () {
    const insight = DocumentInsight(
      category: 'Facture de gaz',
      summary: 'Facture de gaz mensuelle.',
      organisation: 'ENGIE',
      dates: ['15/08/2026'],
      amounts: ['45,66 €'],
      references: [],
      actions: ['Vérifier puis payer la facture.'],
      priority: 'Important',
      documentsToPrepare: [],
      warnings: [],
      documentType: 'facture',
      amountDetails: [
        DocumentAmountItem(label: 'Consommation de gaz', amount: '9,53 €'),
        DocumentAmountItem(label: 'Total TTC', amount: '45,66 €'),
      ],
    );
    expect(insight.isInvoice, isTrue);
    expect(insight.amountDetails.first.label, 'Consommation de gaz');
  });

  test('La sélection du ton propose les quatre tons V15.6', () {
    expect(
      GeminiLetterToneV156.values.map((value) => value.label),
      ['Courtois', 'Professionnel', 'Ferme', 'Très simple'],
    );
  });

  test('La sélection du type propose les sept courriers V15.6', () {
    expect(
      GeminiLetterTypeV156.values.map((value) => value.label),
      [
        'Réclamation',
        'Résiliation',
        'Contestation',
        'Demande de document',
        'Réponse à un organisme',
        'Relance',
        'Lettre libre',
      ],
    );
  });

  test('Courrier officiel est le format V15.6.1 par défaut', () {
    expect(LetterFormatV1561.values.first, LetterFormatV1561.official);
    expect(LetterFormatV1561.values.first.label, 'Courrier officiel');
  });

  test('Les quatre formats V15.6.1 sont proposés', () {
    expect(
      LetterFormatV1561.values.map((value) => value.label),
      [
        'Courrier officiel',
        'E-mail',
        'Lettre recommandée',
        'Mise en demeure',
      ],
    );
  });

  test('Le courrier officiel absent de données utilise des repères explicites',
      () {
    final letter = buildFormattedLetterV1561(
      format: LetterFormatV1561.official,
      recipient: '',
      subject: '',
      body: '',
      settings: AppSettings(),
    );

    expect(letter, contains('[ADRESSE À COMPLÉTER]'));
    expect(letter, contains('[VILLE ET DATE À COMPLÉTER]'));
    expect(letter, contains('[NOM ET SIGNATURE À COMPLÉTER]'));
    expect(letter, isNot(contains(RegExp(r'\d{2}/\d{2}/\d{4}'))));
    expect(letter, isNot(contains(RegExp(r'\b\d{5}\b'))));
  });

  testWidgets('La feuille de lettre est blanche avec un texte noir',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(),
        home: const Scaffold(
          body: OfficialLetterSheet(
            child: TextField(
              key: Key('test-letter-field'),
              style: TextStyle(color: Colors.black),
            ),
          ),
        ),
      ),
    );

    final sheet = tester.widget<Container>(
      find.byKey(const Key('official-letter-sheet')),
    );
    final decoration = sheet.decoration! as BoxDecoration;
    final field = tester.widget<TextField>(
      find.byKey(const Key('test-letter-field')),
    );
    expect(decoration.color, Colors.white);
    expect(field.style?.color, Colors.black);
  });

  test('Le mode local n’invente pas les informations manquantes', () {
    final letter = buildLocalGeminiLetter(
      recipient: '',
      subject: '',
      situation: 'Je souhaite mettre fin à mon abonnement.',
      desiredResult: 'Recevoir une confirmation.',
      importantInformation: '',
      type: GeminiLetterTypeV156.cancellation,
      tone: GeminiLetterToneV156.professional,
    );

    expect(letter.title, contains('[DESTINATAIRE À COMPLÉTER]'));
    expect(letter.subject, contains('[OBJET À COMPLÉTER]'));
    expect(letter.body, contains('[INFORMATIONS IMPORTANTES À COMPLÉTER]'));
    expect(letter.body, isNot(contains(RegExp(r'\d{2}/\d{2}/\d{4}'))));
  });

  testWidgets('Une lettre est enregistrée dans Mes démarches', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(MaterialApp(
      home: GeminiLetterWriterV156Screen(settings: AppSettings()),
    ));

    final situationField =
        find.widgetWithText(TextField, 'Situation de l’utilisateur');
    await tester.scrollUntilVisible(
      situationField,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      situationField,
      'Mon dossier est sans réponse.',
    );
    final resultField = find.widgetWithText(TextField, 'Résultat souhaité');
    await tester.scrollUntilVisible(
      resultField,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      resultField,
      'Obtenir une réponse.',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('generate-letter-v156')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('generate-letter-v156')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-procedure')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('save-procedure')));
    await tester.pumpAndSettle();

    expect(appProcedureStore.items, isNotEmpty);
    expect(appProcedureStore.items.first.letter, contains('Mon dossier'));
    expect(find.text('Enregistrée dans Mes démarches'), findsOneWidget);
  });
  test('V17.0.1 conserve les démarches anciennes sans champ signed', () {
    final procedure = AdministrativeProcedure.fromJson({
      'id': 'legacy',
      'title': 'Ancienne démarche',
      'organisation': 'CAF',
      'category': 'CAF',
      'letter': 'Texte historique',
      'createdAt': '2025-01-01T00:00:00.000',
      'updatedAt': '2025-01-01T00:00:00.000',
    });
    expect(procedure.signed, isFalse);
  });

  test('La préférence automatique pilote la signature par défaut', () {
    expect(
      LetterSignatureService.defaultForLetter(
          autoInsert: true, hasSignature: true),
      isTrue,
    );
    expect(
      LetterSignatureService.defaultForLetter(
          autoInsert: false, hasSignature: true),
      isFalse,
    );
  });

  test('L’aperçu interne distingue les images sans lancer l’impression', () {
    final preview = InternalDocumentPreviewScreen(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      title: 'Image',
      isImage: true,
    );
    expect(preview.isImage, isTrue);
    expect(preview.title, 'Image');
  });

  test('Les quatre états cloud V17.0.1 sont disponibles', () {
    expect(ProcedureCloudState.values, hasLength(4));
    expect(ProcedureCloudState.values, contains(ProcedureCloudState.failed));
  });
}
