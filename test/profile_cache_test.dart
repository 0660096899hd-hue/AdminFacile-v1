import 'package:admin_facile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('les anciennes clés sont attribuées à un seul utilisateur', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'firstName': 'Ancien',
      'city': 'Paris',
    });
    final settings = AppSettings();
    await settings.load();

    await settings.activateProfileForUser('user-a');
    expect(settings.firstName, 'Ancien');
    expect(settings.city, 'Paris');

    settings.deactivateProfile();
    await settings.activateProfileForUser('user-b');
    expect(settings.hasProfileData, isFalse);

    settings.deactivateProfile();
    await settings.activateProfileForUser('user-a');
    expect(settings.firstName, 'Ancien');
  });

  test('un profil distant remplace le cache et devient le cache du UUID',
      () async {
    final settings = AppSettings();
    await settings.load();
    await settings.activateProfileForUser('user-a');

    await settings.applyRemoteProfile(<String, dynamic>{
      'first_name': 'Distant',
      'last_name': 'Durable',
      'address': '1 rue Cloud',
      'postal_code': '75000',
      'city': 'Paris',
      'phone': '0102030405',
      'email': 'profil@example.test',
    });

    settings.deactivateProfile();
    await settings.activateProfileForUser('user-a');
    expect(settings.firstName, 'Distant');
    expect(settings.lastName, 'Durable');
    expect(settings.address, '1 rue Cloud');
  });

  test('les modifications locales sont isolées par UUID', () async {
    final settings = AppSettings();
    await settings.load();
    await settings.activateProfileForUser('user-a');
    await settings.saveProfile(<String, String>{
      'firstName': 'Alice',
      'lastName': '',
      'address': '',
      'postalCode': '',
      'city': '',
      'phone': '',
      'email': '',
    });

    settings.deactivateProfile();
    await settings.activateProfileForUser('user-b');
    expect(settings.hasProfileData, isFalse);

    settings.deactivateProfile();
    await settings.activateProfileForUser('user-a');
    expect(settings.firstName, 'Alice');
  });

  test('un premier compte utilise le thème clair par défaut', () async {
    final settings = AppSettings();
    await settings.load();
    await settings.activateProfileForUser('new-user');

    expect(settings.themePreference, AppThemePreference.light);
  });

  test('la préférence existante est conservée et isolée par UUID', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'themePreference': 'dark',
    });
    final settings = AppSettings();
    await settings.load();
    await settings.activateProfileForUser('existing-user');
    expect(settings.themePreference, AppThemePreference.dark);

    await settings.setThemePreference(AppThemePreference.system);
    settings.deactivateProfile();
    await settings.activateProfileForUser('other-user');
    expect(settings.themePreference, AppThemePreference.light);
    await settings.setThemePreference(AppThemePreference.light);
    settings.deactivateProfile();
    await settings.activateProfileForUser('existing-user');

    expect(settings.themePreference, AppThemePreference.system);
  });
}
