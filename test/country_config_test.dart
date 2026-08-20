import 'dart:io';

import 'package:admin_facile/app_config.dart';
import 'package:admin_facile/countries/country_config.dart';
import 'package:admin_facile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectedCountries = <String, Map<String, String>>{
    'france': {
      'code': 'FR',
      'name': 'AdminFacile',
      'locale': 'fr',
      'applicationId': 'fr.adminfacile.app',
    },
    'spain': {
      'code': 'ES',
      'name': 'AdminFácil',
      'locale': 'es',
      'applicationId': 'es.adminfacile.app',
    },
    'italy': {
      'code': 'IT',
      'name': 'Amministrazione Facile',
      'locale': 'it',
      'applicationId': 'it.adminfacile.app',
    },
    'morocco': {
      'code': 'MA',
      'name': 'AdminFacile Maroc',
      'locale': 'fr',
      'applicationId': 'ma.adminfacile.app',
    },
  };

  test('chaque flavor charge la configuration pays attendue', () {
    for (final entry in expectedCountries.entries) {
      final country = AppConfig.forFlavor(entry.key).country;
      expect(country.flavor, entry.key);
      expect(country.countryCode, entry.value['code']);
      expect(country.applicationName, entry.value['name']);
      expect(country.primaryLocale.languageCode, entry.value['locale']);
      expect(country.androidApplicationId, entry.value['applicationId']);
      expect(country.content.administrativeOrganizations, isNotEmpty);
      expect(country.content.modelPackId, isNotEmpty);
    }
  });

  test('le flavor par défaut reste la France compatible Google Play', () {
    expect(appConfig.country.flavor, 'france');
    expect(appConfig.country.countryCode, 'FR');
    expect(appConfig.country.applicationName, 'AdminFacile');
    expect(appConfig.country.androidApplicationId, 'fr.adminfacile.app');
    expect(appConfig.country.content.status, CountryContentStatus.active);
    expect(
      appConfig.country.content.modelAssetPath,
      'assets/letters/library.json',
    );

    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(pubspec, contains('default-flavor: france'));
    expect(gradle, contains('applicationId = "fr.adminfacile.app"'));
    expect(gradle, contains('create("france")'));
  });

  test('les quatre productFlavors Android gardent leurs applicationId', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    for (final entry in expectedCountries.entries) {
      expect(gradle, contains('create("${entry.key}")'));
      expect(
        gradle,
        contains('applicationId = "${entry.value['applicationId']}"'),
      );
    }
  });

  test('les contenus hors France restent explicitement placeholders', () {
    for (final flavor in ['spain', 'italy', 'morocco']) {
      expect(
        AppConfig.forFlavor(flavor).country.content.status,
        CountryContentStatus.placeholder,
      );
    }
  });

  test('le Maroc expose français, arabe et le nom arabe prévu', () {
    final morocco = AppConfig.forFlavor('morocco').country;
    expect(
      morocco.supportedLocales.map((locale) => locale.languageCode),
      ['fr', 'ar'],
    );
    expect(morocco.supportsRightToLeft, isTrue);
    expect(
        morocco.resolveLocale(const [Locale('ar', 'MA')]), const Locale('ar'));
    expect(morocco.usesRightToLeft(const Locale('ar')), isTrue);
    expect(morocco.applicationNameFor(const Locale('ar')), 'إدارة سهلة');
  });

  testWidgets('la locale arabe active réellement une direction RTL',
      (tester) async {
    final morocco = AppConfig.forFlavor('morocco').country;
    TextDirection? direction;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: morocco.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        direction = Directionality.of(context);
        return Text(AppLocalizations.of(context).appName);
      }),
    ));
    await tester.pumpAndSettle();

    expect(direction, TextDirection.rtl);
    expect(find.text('إدارة سهلة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
