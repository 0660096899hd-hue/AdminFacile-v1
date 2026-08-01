import 'package:admin_facile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AdminFacile démarre correctement', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final settings = AppSettings();
    await settings.load();
    await tester.pumpWidget(AdminFacileApp(settings: settings));
    await tester.pumpAndSettle();

    expect(find.text('Votre assistant administratif'), findsOneWidget);
    expect(find.text('Scanner un courrier'), findsWidgets);
  });
}
