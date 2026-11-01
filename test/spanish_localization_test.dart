import 'dart:convert';
import 'dart:io';

import 'package:admin_facile/app_config.dart';
import 'package:admin_facile/document_translation_screen.dart';
import 'package:admin_facile/google_auth_service.dart';
import 'package:admin_facile/l10n/app_localizations.dart';
import 'package:admin_facile/l10n/ui_localization.dart';
import 'package:admin_facile/main.dart';
import 'package:admin_facile/professional_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnavailableAuthSession implements AppAuthSession {
  const _UnavailableAuthSession();

  @override
  bool get isAuthenticated => false;

  @override
  bool get isServiceAvailable => false;

  @override
  ProfessionalAuthService? get service => null;

  @override
  GoogleAuthService? get googleService => null;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}

Widget _localizedApp(Locale locale, Widget home) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
    );

void main() {
  test('le flavor Espagne utilise bien la locale espagnole', () {
    final country = AppConfig.forFlavor('spain').country;
    expect(country.applicationName, 'AdminFácil');
    expect(country.primaryLocale, const Locale('es'));
    expect(country.resolveLocale(null), const Locale('es'));
  });

  test('chaque message français possède une entrée ARB espagnole', () {
    final french = jsonDecode(
      File('lib/l10n/app_fr.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final spanish = jsonDecode(
      File('lib/l10n/app_es.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final frenchKeys = french.keys.where((key) => !key.startsWith('@')).toSet();
    final spanishKeys =
        spanish.keys.where((key) => !key.startsWith('@')).toSet();

    expect(spanishKeys, frenchKeys);
    expect(
      spanishKeys.every(
        (key) => spanish[key] is String && (spanish[key] as String).isNotEmpty,
      ),
      isTrue,
    );
    expect(spanishKeys.length, greaterThan(400));
  });

  testWidgets('la couche UI conserve exactement les textes France',
      (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        const Locale('fr'),
        const Scaffold(
          body: Column(
            children: [
              LocalizedText('Accueil'),
              LocalizedText('Scanner un document'),
              LocalizedText('Créer une lettre'),
              LocalizedText('Mon profil'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Scanner un document'), findsOneWidget);
    expect(find.text('Créer une lettre'), findsOneWidget);
    expect(find.text('Mon profil'), findsOneWidget);
    expect(find.text('Inicio'), findsNothing);
  });

  testWidgets('la couche UI traduit les écrans principaux en espagnol',
      (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        const Locale('es'),
        const Scaffold(
          body: Column(
            children: [
              LocalizedText('Accueil'),
              LocalizedText('Scanner un document'),
              LocalizedText('Créer une lettre'),
              LocalizedText('Mon profil'),
              LocalizedText('Modèles de lettres (12)'),
              LocalizedText('Bonjour Ana'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Escanear un documento'), findsOneWidget);
    expect(find.text('Crear una carta'), findsOneWidget);
    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.text('Modelos de cartas (12)'), findsOneWidget);
    expect(find.text('Hola Ana'), findsOneWidget);
    expect(find.text('Accueil'), findsNothing);
  });

  testWidgets('l’écran de connexion rend réellement les actions espagnoles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(
      _localizedApp(
        const Locale('es'),
        const WelcomeAuthScreen(authSession: _UnavailableAuthSession()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Crear mi cuenta'), findsOneWidget);
    expect(find.text('Ya tengo una cuenta'), findsOneWidget);
    expect(find.text('Servicio temporalmente no disponible.'), findsOneWidget);
    expect(find.text('Créer mon compte'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('la traduction OCR rend ses commandes en espagnol',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(
      _localizedApp(
        const Locale('es'),
        const DocumentTranslationScreen(pageTexts: ['Bonjour']),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Traducir el documento'), findsOneWidget);
    expect(find.text('Idioma del documento'), findsOneWidget);
    expect(find.text('Traducir a'), findsOneWidget);
    expect(find.text('Texto original'), findsOneWidget);
    expect(find.text('Copiar la traducción'), findsOneWidget);
    expect(find.text('Langue du document'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('la navigation ouvre scanner et profil en espagnol',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(
      _localizedApp(
        const Locale('es'),
        AppShell(
          settings: AppSettings(),
          documentStore: DocumentStore(),
          procedureStore: ProcedureStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Inicio',
      'Escanear',
      'Cartas',
      'Documentos',
      'Perfil',
    ]) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('Escanear').first);
    await tester.pumpAndSettle();
    expect(find.text('Foto'), findsOneWidget);
    expect(find.text('Importar'), findsOneWidget);
    expect(find.text('Scanner'), findsNothing);

    await tester.tap(find.text('Perfil').first);
    await tester.pumpAndSettle();
    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.text('Mon profil'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });
}
