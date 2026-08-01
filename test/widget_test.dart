import 'package:admin_facile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AdminFacile V14 démarre correctement', (tester) async {
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

    expect(find.text('Votre assistant administratif'), findsOneWidget);
    expect(find.text('Assistant IA Gemini'), findsOneWidget);
  });

  test('Assistant local comprend résilier Orange', () {
    final match = LocalIntentEngine.best('Je veux résilier mon abonnement Orange');
    expect(match.template, LetterTemplate.telecom);
    expect(match.model.title.toLowerCase(), contains('résiliation'));
  });

  test('Assistant local comprend facture EDF', () {
    final match = LocalIntentEngine.best('Je souhaite contester une facture EDF');
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
}
