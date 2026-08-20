import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:admin_facile/main.dart';
import 'package:admin_facile/document_scanner_service.dart';
import 'package:admin_facile/professional_auth_service.dart';
import 'package:admin_facile/google_auth_service.dart';
import 'package:admin_facile/notification_store.dart';
import 'package:admin_facile/letter_signature_service.dart';
import 'package:admin_facile/signature_pad.dart';
import 'package:admin_facile/signature_image_service.dart';
import 'package:admin_facile/scanner_processing_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthenticatedTestSession implements AppAuthSession {
  const AuthenticatedTestSession();
  @override
  bool get isAuthenticated => true;
  @override
  bool get isServiceAvailable => true;
  @override
  ProfessionalAuthService? get service => null;
  @override
  GoogleAuthService? get googleService => null;
  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}

class WidgetAuthGateway implements AuthGateway {
  WidgetAuthGateway(this.onChanged, {this.confirmationRequired = false});
  final void Function(bool) onChanged;
  bool confirmationRequired;
  bool signedIn = false;
  bool resetRequested = false;
  Object? nextError;

  void _checkError() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  bool get hasSession => signedIn;
  @override
  String? get currentEmail => signedIn ? 'test@example.fr' : null;
  @override
  String? get currentUserId => signedIn ? 'test-user' : null;

  @override
  Future<bool> signUp(
      {required String email,
      required String password,
      Map<String, dynamic>? metadata}) async {
    _checkError();
    signedIn = !confirmationRequired;
    onChanged(signedIn);
    return confirmationRequired;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _checkError();
    signedIn = true;
    onChanged(true);
  }

  @override
  Future<void> signOut() async {
    _checkError();
    signedIn = false;
    onChanged(false);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _checkError();
    resetRequested = true;
  }

  @override
  Future<void> updatePassword(String password) async => _checkError();
  @override
  Future<void> updateProfile(Map<String, dynamic> metadata) async =>
      _checkError();
}

class MutableTestAuthSession implements AppAuthSession {
  MutableTestAuthSession({bool authenticated = false, bool available = true})
      : _authenticated = authenticated,
        _available = available {
    gateway = WidgetAuthGateway(_setAuthenticated);
    gateway.signedIn = authenticated;
    authService = ProfessionalAuthService(gateway);
    googleAuthService = FakeGoogleAuthService(_setAuthenticated);
  }

  final StreamController<bool> controller = StreamController<bool>.broadcast();
  late final WidgetAuthGateway gateway;
  late final ProfessionalAuthService authService;
  late final FakeGoogleAuthService googleAuthService;
  bool _authenticated;
  final bool _available;

  void _setAuthenticated(bool value) {
    _authenticated = value;
    controller.add(value);
  }

  Future<void> close() => controller.close();

  @override
  Stream<bool> get changes => controller.stream;
  @override
  bool get isAuthenticated => _authenticated;
  @override
  bool get isServiceAvailable => _available;
  @override
  ProfessionalAuthService? get service => _available ? authService : null;
  @override
  GoogleAuthService? get googleService => _available ? googleAuthService : null;
}

class FakeGoogleAuthService implements GoogleAuthService {
  FakeGoogleAuthService(this.onAuthenticated);

  final void Function(bool) onAuthenticated;
  bool configured = true;
  int launches = 0;
  Object? nextError;
  Completer<void>? pending;

  @override
  bool get isConfigured => configured;

  @override
  Future<void> signIn() async {
    launches++;
    final wait = pending;
    if (wait != null) await wait.future;
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    onAuthenticated(true);
  }

  @override
  Future<void> signOutProvider() async {}
}

class FailingDocumentScanner implements DocumentScannerService {
  const FailingDocumentScanner();
  @override
  Future<DocumentScanResult?> scan({int pageLimit = 10}) => Future.error(
      const DocumentScannerUnavailableException(null, 'MLKIT_UNAVAILABLE'));
}

void main() {
  group('V20.3 portail authentification obligatoire', () {
    Future<void> pumpApp(
        WidgetTester tester, MutableTestAuthSession session) async {
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
        procedureStore: procedures,
        authSession: session,
      ));
      await tester.pump(const Duration(milliseconds: 1300));
    }

    testWidgets('aucune session interdit le dashboard et affiche l’accueil',
        (tester) async {
      final session = MutableTestAuthSession();
      addTearDown(session.close);
      await pumpApp(tester, session);
      expect(find.byKey(const Key('auth-welcome-screen')), findsOneWidget);
      expect(find.byKey(const Key('auth-admin-facile-logo')), findsOneWidget);
      final logo = tester.widget<Image>(
        find.byKey(const Key('admin-facile-logo-image')),
      );
      expect(
        (logo.image as AssetImage).assetName,
        'assets/branding/admin_facile_logo.png',
      );
      expect(logo.fit, BoxFit.contain);
      expect(find.byKey(const Key('dashboard-v17')), findsNothing);
      expect(find.byKey(const Key('auth-google')), findsOneWidget);
      expect(find.byKey(const Key('auth-administrative-background')),
          findsOneWidget);
      expect(
        tester
            .widget<IgnorePointer>(
              find.byKey(const Key('auth-administrative-background')),
            )
            .ignoring,
        isTrue,
      );
    });

    testWidgets('succès Google traverse AuthGate vers le dashboard',
        (tester) async {
      final session = MutableTestAuthSession();
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-google')));
      await tester.pumpAndSettle();
      expect(session.googleAuthService.launches, 1);
      expect(find.byKey(const Key('dashboard-v17')), findsOneWidget);
    });

    testWidgets('annulation Google reste sur l’accueil avec message neutre',
        (tester) async {
      final session = MutableTestAuthSession();
      session.googleAuthService.nextError = const GoogleAuthException(
        'Connexion Google annulée.',
        code: 'canceled',
      );
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-google')));
      await tester.pumpAndSettle();
      expect(find.text('Connexion Google annulée.'), findsOneWidget);
      expect(find.byKey(const Key('dashboard-v17')), findsNothing);
    });

    testWidgets('erreur réseau Google est compréhensible', (tester) async {
      final session = MutableTestAuthSession();
      session.googleAuthService.nextError = const GoogleAuthException(
        'Vérifiez votre connexion Internet.',
        code: 'network_unavailable',
      );
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-google')));
      await tester.pumpAndSettle();
      expect(find.text('Vérifiez votre connexion Internet.'), findsOneWidget);
    });

    testWidgets('Google ne peut pas être lancé deux fois', (tester) async {
      final session = MutableTestAuthSession();
      session.googleAuthService.pending = Completer<void>();
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-google')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('auth-google')));
      await tester.pump();
      expect(session.googleAuthService.launches, 1);
      session.googleAuthService.pending!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('une erreur Google brute ne divulgue aucune donnée sensible',
        (tester) async {
      final session = MutableTestAuthSession();
      session.googleAuthService.nextError =
          StateError('access_token=secret-value');
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-google')));
      await tester.pumpAndSettle();
      expect(find.textContaining('secret-value'), findsNothing);
      expect(find.text('La connexion Google a échoué. Réessayez.'),
          findsOneWidget);
    });

    testWidgets('une session restaurée ouvre directement le dashboard',
        (tester) async {
      final session = MutableTestAuthSession(authenticated: true);
      addTearDown(session.close);
      await pumpApp(tester, session);
      expect(find.byKey(const Key('dashboard-v17')), findsOneWidget);
      expect(find.byKey(const Key('auth-welcome-screen')), findsNothing);
    });

    testWidgets('connexion ouvre le dashboard puis logout ferme toute la pile',
        (tester) async {
      final session = MutableTestAuthSession();
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-existing-account')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('auth-email')), 'test@example.fr');
      await tester.enterText(
          find.byKey(const Key('auth-password')), 'secret12');
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-v17')), findsOneWidget);

      await session.authService.signOut();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-welcome-screen')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-v17')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-v17')), findsNothing);
    });

    testWidgets('création avec confirmation e-mail reste hors dashboard',
        (tester) async {
      final session = MutableTestAuthSession();
      session.gateway.confirmationRequired = true;
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-create-account')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('auth-email')), 'nouveau@example.fr');
      await tester.enterText(
          find.byKey(const Key('auth-password')), 'secret12');
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Vérifiez votre e-mail'), findsOneWidget);
      expect(find.byKey(const Key('dashboard-v17')), findsNothing);
    });

    testWidgets('mot de passe oublié appelle le service', (tester) async {
      final session = MutableTestAuthSession();
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-existing-account')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('auth-email')), 'test@example.fr');
      await tester.tap(find.byKey(const Key('auth-forgot-password')));
      await tester.pumpAndSettle();
      expect(session.gateway.resetRequested, isTrue);
      expect(
          find.textContaining('E-mail de récupération envoyé'), findsOneWidget);
    });

    testWidgets(
        'connexion masque, affiche puis remasque sans perdre le contenu',
        (tester) async {
      final session = MutableTestAuthSession();
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-existing-account')));
      await tester.pump();

      final passwordFinder = find.byKey(const Key('auth-password'));
      final visibilityFinder =
          find.byKey(const Key('auth-password-visibility'));
      expect(tester.widget<TextField>(passwordFinder).obscureText, isTrue);
      expect(find.byTooltip('Afficher le mot de passe'), findsOneWidget);

      await tester.enterText(passwordFinder, 'secret12');
      await tester.tap(visibilityFinder);
      await tester.pump();
      expect(tester.widget<TextField>(passwordFinder).obscureText, isFalse);
      expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);
      expect(tester.widget<TextField>(passwordFinder).controller!.text,
          'secret12');

      await tester.tap(visibilityFinder);
      await tester.pump();
      expect(tester.widget<TextField>(passwordFinder).obscureText, isTrue);
      expect(tester.widget<TextField>(passwordFinder).controller!.text,
          'secret12');
    });

    testWidgets('création de compte possède aussi le basculement sécurisé',
        (tester) async {
      final session = MutableTestAuthSession();
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-create-account')));
      await tester.pump();

      final passwordFinder = find.byKey(const Key('auth-password'));
      expect(tester.widget<TextField>(passwordFinder).obscureText, isTrue);
      await tester.enterText(passwordFinder, 'nouveau-secret');
      await tester.tap(find.byKey(const Key('auth-password-visibility')));
      await tester.pump();
      expect(tester.widget<TextField>(passwordFinder).obscureText, isFalse);
      expect(tester.widget<TextField>(passwordFinder).controller!.text,
          'nouveau-secret');
    });

    testWidgets('erreur réseau ne donne jamais accès au dashboard',
        (tester) async {
      final session = MutableTestAuthSession();
      session.gateway.nextError = const SocketException('hors ligne');
      addTearDown(session.close);
      await pumpApp(tester, session);
      await tester.tap(find.byKey(const Key('auth-existing-account')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('auth-email')), 'test@example.fr');
      await tester.enterText(
          find.byKey(const Key('auth-password')), 'secret12');
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Vérifiez votre connexion Internet'),
          findsOneWidget);
      expect(find.byKey(const Key('dashboard-v17')), findsNothing);
    });
  });

  testWidgets('V20.3 un échec scanner propose photo et import', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScannerScreen(
          documentStore: DocumentStore(),
          procedureStore: ProcedureStore(),
          scannerService: const FailingDocumentScanner(),
        ),
      ),
    ));
    await tester.tap(find.widgetWithText(FilledButton, 'Scanner'));
    await tester.pumpAndSettle();
    expect(find.text('Le scan a échoué'), findsOneWidget);
    expect(find.byKey(const Key('scanner-fallback-camera')), findsOneWidget);
    expect(find.text('Prendre une photo'), findsOneWidget);
    expect(find.byKey(const Key('scanner-fallback-import')), findsOneWidget);
    expect(find.text('Importer un document'), findsOneWidget);
  });

  group('Configuration et transport Gemini release', () {
    tearDown(() {
      GeminiTransport.testProxyUrl = null;
      GeminiTransport.testTimeout = null;
      GeminiTransport.testPost = null;
    });

    test('absence de configuration désactive Gemini sans bloquer la lettre',
        () async {
      expect(GeminiTransport.configurationMode, 'disabled');
      final result = await GeminiLetterV156Service.generate(
        recipient: 'Mairie',
        subject: 'Demande',
        situation: 'Dossier en attente',
        desiredResult: 'Obtenir une réponse',
        importantInformation: '',
        type: GeminiLetterTypeV156.complaint,
        tone: GeminiLetterToneV156.professional,
        format: LetterFormatV1561.official,
      );
      expect(result.body, isNotEmpty);
    }, skip: GeminiTransport.usesEmbeddedKey || GeminiTransport.usesProxy);

    test('génération Gemini accepte une réponse JSON valide du proxy',
        () async {
      GeminiTransport.testProxyUrl = 'https://ia.example.test/gemini';
      GeminiTransport.testPost = (uri, {headers, body}) async {
        expect(uri.query, isEmpty);
        expect(body.toString(), isNot(contains('GEMINI_API_KEY')));
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'titre': 'Demande',
                        'objet': 'Suivi du dossier',
                        'corps': 'Je sollicite le suivi de mon dossier.'
                      })
                    }
                  ]
                }
              }
            ]
          }),
          200,
        );
      };
      final letter = await GeminiLetterWriter.generate(
        recipient: 'Mairie',
        request: 'Suivre mon dossier',
        context: '',
        tone: 'Professionnel',
      );
      expect(letter.subject, 'Suivi du dossier');
      expect(letter.body, contains('suivi'));
    });

    test('timeout Gemini est classé sans détail sensible', () async {
      GeminiTransport.testProxyUrl = 'https://ia.example.test/gemini';
      GeminiTransport.testTimeout = const Duration(milliseconds: 10);
      GeminiTransport.testPost =
          (uri, {headers, body}) => Completer<http.Response>().future;
      expect(
        () => GeminiTransport.request('test', const {}),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('erreur réseau Gemini est propagée sans clé', () async {
      GeminiTransport.testProxyUrl = 'https://ia.example.test/gemini';
      GeminiTransport.testPost = (uri, {headers, body}) =>
          Future<http.Response>.error(const SocketException('hors ligne'));
      expect(
        () => GeminiTransport.request('test', const {}),
        throwsA(isA<SocketException>()),
      );
    });

    test('réponse Gemini invalide devient une erreur générique', () async {
      GeminiTransport.testProxyUrl = 'https://ia.example.test/gemini';
      GeminiTransport.testPost =
          (uri, {headers, body}) async => http.Response('pas du json', 200);
      await expectLater(
        GeminiTransport.request('test', const {}),
        throwsA(predicate((error) =>
            error is GeminiApiException &&
            error.toString() == geminiUnavailableMessage)),
      );
    });
  });

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
      authSession: const AuthenticatedTestSession(),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-v17')), findsOneWidget);
    expect(find.text('Simplifiez vos démarches au quotidien'), findsOneWidget);
    expect(find.byKey(const Key('create-letter-v17')), findsOneWidget);
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Assistant\nadministratif',
      'Mes\ndémarches',
      'Favoris',
      'Historique'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('la carte d’accueil utilise la lettre bleue et le scan orange',
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
      procedureStore: procedures,
      authSession: const AuthenticatedTestSession(),
    ));
    await tester.pumpAndSettle();

    final scan = tester.widget<FilledButton>(
      find.byKey(const Key('home-scan-document-button')),
    );
    final background = scan.style?.backgroundColor?.resolve(<WidgetState>{});
    expect(background, const Color(0xFFFFA51F));
    expect(find.byKey(const Key('home-letter-illustration')), findsOneWidget);
    expect(find.byKey(const Key('home-large-feather')), findsOneWidget);
    final illustration = tester.widget<Image>(
      find.byKey(const Key('home-large-feather')),
    );
    expect(
      (illustration.image as AssetImage).assetName,
      'assets/images/hero_plume_document.jpg',
    );
    expect(illustration.fit, BoxFit.contain);
    expect(illustration.alignment, Alignment.center);
    expect(find.byKey(const Key('home-hero-horizontal-fade')), findsOneWidget);
    expect(find.byKey(const Key('home-hero-vertical-fade')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('home-letter-illustration'))).height,
      377,
    );
    final photoSize =
        tester.getSize(find.byKey(const Key('home-hero-photo-frame')));
    expect(photoSize.height, 377);
    expect(photoSize.width, closeTo(377 * 912 / 1156, .01));
    expect(find.byIcon(Icons.edit_rounded), findsNothing);
    expect(find.text('Créer une lettre'), findsWidgets);
    expect(find.text('Scanner un document'), findsWidgets);
    expect(tester.takeException(), isNull);
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
        procedureStore: procedures,
        authSession: const AuthenticatedTestSession()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dashboard-profile-button')));
    await tester.pumpAndSettle();
    expect(find.text('Mon profil'), findsOneWidget);
  });

  testWidgets('Le profil masque et bascule son mot de passe sans perte',
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
        procedureStore: procedures,
        authSession: const AuthenticatedTestSession()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dashboard-profile-button')));
    await tester.pumpAndSettle();

    final passwordFinder = find.byKey(const Key('profile-auth-password'));
    final visibilityFinder =
        find.byKey(const Key('profile-auth-password-visibility'));
    expect(tester.widget<TextField>(passwordFinder).obscureText, isTrue);
    await tester.enterText(passwordFinder, 'profil-secret');
    await tester.tap(visibilityFinder);
    await tester.pump();
    expect(tester.widget<TextField>(passwordFinder).obscureText, isFalse);
    expect(tester.widget<TextField>(passwordFinder).controller!.text,
        'profil-secret');
    await tester.tap(visibilityFinder);
    await tester.pump();
    expect(tester.widget<TextField>(passwordFinder).obscureText, isTrue);
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
        procedureStore: procedures,
        authSession: const AuthenticatedTestSession()));
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

  testWidgets('Les quatre raccourcis principaux sont présents', (tester) async {
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
        procedureStore: procedures,
        authSession: const AuthenticatedTestSession()));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Assistant\nadministratif',
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
        procedureStore: procedures,
        authSession: const AuthenticatedTestSession()));
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
      const Size(360, 800),
      const Size(390, 844),
      const Size(412, 915),
      const Size(800, 900),
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
      final heroRect = tester.getRect(find.byKey(const Key('home-hero-card')));
      final titleRect =
          tester.getRect(find.text('Simplifiez vos démarches au quotidien'));
      final descriptionRect = tester.getRect(find.text(
          'Générez, envoyez et suivez vos courriers administratifs simplement.'));
      final createRect =
          tester.getRect(find.byKey(const Key('create-letter-v17')));
      final scanRect =
          tester.getRect(find.byKey(const Key('home-scan-document-button')));
      final illustrationRect =
          tester.getRect(find.byKey(const Key('home-letter-illustration')));

      for (final entry in <String, Rect>{
        'titre': titleRect,
        'description': descriptionRect,
        'bouton Créer': createRect,
        'bouton Scanner': scanRect,
        'illustration': illustrationRect,
      }.entries) {
        expect(
          heroRect.contains(entry.value.topLeft) &&
              heroRect.contains(entry.value.bottomRight),
          isTrue,
          reason: '${entry.key} doit rester dans la hero card à $size',
        );
      }

      for (final contentRect in [
        titleRect,
        descriptionRect,
        createRect,
        scanRect,
      ]) {
        expect(
          contentRect.overlaps(illustrationRect),
          isFalse,
          reason: 'Le contenu ne doit pas être recouvert à $size',
        );
      }

      final createButton = tester
          .widget<FilledButton>(find.byKey(const Key('create-letter-v17')));
      final scanButton = tester.widget<FilledButton>(
          find.byKey(const Key('home-scan-document-button')));
      expect(createButton.onPressed, isNotNull);
      expect(scanButton.onPressed, isNotNull);

      final illustrationHeight = tester
          .getSize(find.byKey(const Key('home-letter-illustration')))
          .height;
      final phoneLayout = heroRect.width < 600;
      final expectedHeight = phoneLayout
          ? heroRect.width < 390
              ? 250.0
              : 270.0
          : 377.0;
      expect(
        illustrationHeight,
        expectedHeight,
        reason: 'Hauteur illustration pour $size',
      );
      final photoSize =
          tester.getSize(find.byKey(const Key('home-hero-photo-frame')));
      expect(photoSize.height, expectedHeight);
      expect(
        photoSize.width,
        closeTo(expectedHeight * 912 / 1156, .01),
        reason: 'Largeur proportionnelle de la photo pour $size',
      );
      if (phoneLayout) {
        expect(
          illustrationRect.top,
          greaterThan(scanRect.bottom),
          reason: 'L’illustration doit suivre les actions à $size',
        );
      }
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
        procedureStore: procedures,
        authSession: const AuthenticatedTestSession()));
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
    final settings = AppSettings(
      signatureDirectoryProvider: () async => directory,
    );
    await settings.load();
    await settings.activateProfileForUser('signature-test-user');
    final png = await File('assets/adminfacile_mark.png').readAsBytes();
    await settings.saveSignatureBytes(png);
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
    final settings = AppSettings(
      signatureDirectoryProvider: () async => directory,
    );
    await settings.load();
    await settings.activateProfileForUser('preview-test-user');
    await settings.saveSignatureBytes(
      await File('assets/adminfacile_mark.png').readAsBytes(),
    );
    await settings.setAutoInsertSignature(true);
    expect(shouldInsertSignature(settings), isTrue);
  });

  testWidgets('Le PDF A4 peut intégrer la signature', (tester) async {
    final bytes = await tester.runAsync(() async => buildSignedLetterPdf(
          text: 'Courrier administratif',
          subject: 'Test',
          signatureBytes:
              await File('assets/adminfacile_mark.png').readAsBytes(),
          senderName: 'Hafid Test',
        ));
    expect(bytes, isNotNull);
    expect(bytes!.take(4), [37, 80, 68, 70]);
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

  test('V17.1 détecte PRIMAGAZ comme facture de gaz', () {
    final result = SmartDocumentLocalAnalyzer.analyze(
        'PRIMAGAZ facture propane Montant total à payer : 45,66 €');
    expect(result.documentType, 'Facture de gaz');
    expect(result.organisation, 'PRIMAGAZ');
    expect(result.totalAmount, '45,66 €');
  });

  test('V17.1 détecte EDF comme facture d’électricité', () {
    expect(
        SmartDocumentLocalAnalyzer.analyze('Facture EDF 230 kWh').documentType,
        'Facture d’électricité');
  });

  test('V17.1 détecte Orange comme téléphone ou Internet', () {
    expect(
        SmartDocumentLocalAnalyzer.analyze('Orange forfait mobile')
            .documentType,
        'Facture téléphone');
    expect(
        SmartDocumentLocalAnalyzer.analyze('Orange Livebox fibre').documentType,
        'Facture Internet');
  });

  test('V17.1 détecte CAF et CPAM', () {
    expect(
        SmartDocumentLocalAnalyzer.analyze('Courrier de la CAF').documentType,
        'Courrier CAF');
    expect(
        SmartDocumentLocalAnalyzer.analyze('Assurance Maladie ameli CPAM')
            .documentType,
        'Courrier CPAM');
  });

  test('V17.1 ignore capital social et sélectionne uniquement le total dû', () {
    final result = SmartDocumentLocalAnalyzer.analyze(
      'Capital social 1 000 000,00 € TVA 8,20 € Total TTC : 45,66 €',
    );
    expect(result.totalAmount, '45,66 €');
    expect(result.amounts, isNot(contains('1 000 000,00 €')));
    expect(result.amounts, isNot(contains('8,20 €')));
  });

  test('V17.1 n’invente aucune donnée absente', () {
    final result = SmartDocumentLocalAnalyzer.analyze('Bonjour et merci.');
    expect(result.documentType, 'Document inconnu');
    expect(result.totalAmount, isEmpty);
    expect(result.dueDate, isEmpty);
    expect(result.references, isEmpty);
  });

  test('Migration SavedDocument V17.1 et correction conservée', () {
    final legacy = SavedDocument.fromJson({
      'id': 'old',
      'title': 'Ancien',
      'category': 'Autre',
      'organisation': 'Inconnu',
      'createdAt': '2025-01-01T00:00:00.000'
    });
    expect(legacy.detectedDocumentType, 'Document inconnu');
    expect(legacy.userCorrectedAnalysis, isFalse);
    final corrected = legacy.copyWith(
      detectedDocumentType: 'Facture de gaz',
      detectedAmount: '45,66 €',
      userCorrectedAnalysis: true,
    );
    expect(SavedDocument.fromJson(corrected.toJson()).userCorrectedAnalysis,
        isTrue);
    expect(
        SavedDocument.fromJson(corrected.toJson()).detectedAmount, '45,66 €');
  });

  testWidgets('Le Scanner V17.2 affiche seulement Scanner Photo et Importer',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ScannerScreen(
                documentStore: DocumentStore(),
                procedureStore: ProcedureStore()))));
    expect(find.text('Scanner'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Importer'), findsOneWidget);
    expect(find.byKey(const Key('scanner-smart-card')), findsNothing);
    expect(find.byKey(const Key('ocr-full-text-expansion')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  test('V17.2 masque l’analyse Scanner derrière Analyse avancée', () {
    final source = File('lib/main.dart').readAsStringSync() +
        File('lib/scanner_processing_service.dart').readAsStringSync();
    for (final marker in [
      "Key('scanner-pdf-open')",
      "Key('scanner-pdf-more-menu')",
      "Text('Ajouter à Mes documents')",
      "Text('Transmettre')",
      "Text('Imprimer')",
      "Key('scanner-advanced-analysis')",
      "Text('Voir le texte OCR')",
      "Text('Analyse Gemini')",
      "Text('Corriger les informations')",
    ]) {
      expect(source, contains(marker), reason: 'Action absente : $marker');
    }
  });

  testWidgets('Créer une lettre propose Gemini ou un modèle', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
          openProfile: () {},
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('create-letter-v17')));
    await tester.pumpAndSettle();
    expect(find.text('Choisissez une méthode'), findsOneWidget);
    expect(find.text('Générer avec Gemini'), findsOneWidget);
    expect(find.text('Utiliser un modèle'), findsOneWidget);
    expect(find.text('Bibliothèque\nde modèles'), findsNothing);
  });

  testWidgets('Mes documents affiche Aperçu et un menu complet sans overflow',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = DocumentStore();
    await store.add(SavedDocument(
      id: 'doc-menu',
      title: 'Facture test',
      category: 'Facture',
      organisation: 'EDF',
      createdAt: DateTime(2026, 8, 3),
      filePath: 'facture.pdf',
    ));
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DocumentsScreen(documentStore: store))));
    await tester.ensureVisible(find.byKey(const Key('document-more-doc-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Aperçu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('document-more-doc-menu')));
    await tester.pumpAndSettle();
    for (final label in [
      'Cloud / Synchroniser',
      'Partager',
      'Imprimer',
      'Supprimer'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Mes démarches affiche Ouvrir la lettre et un menu complet',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = ProcedureStore();
    await store.add(AdministrativeProcedure(
      id: 'procedure-menu',
      title: 'Courrier CAF',
      organisation: 'CAF',
      category: 'CAF',
      letter: 'Madame, Monsieur',
      createdAt: DateTime(2026, 8, 3),
      updatedAt: DateTime(2026, 8, 3),
    ));
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpWidget(MaterialApp(home: ProceduresScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('procedure-more-procedure-menu')), 350,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Ouvrir la lettre'), findsOneWidget);
    await tester.tap(find.byKey(const Key('procedure-more-procedure-menu')));
    await tester.pumpAndSettle();
    for (final label in [
      'Modifier',
      'Cloud',
      'Télécharger',
      'Partager',
      'Supprimer'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  test('V17.1.2 utilise uniquement les trois points horizontaux', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, isNot(contains('Icons.more_vert')));
    expect(RegExp(r'Icons\.more_horiz_rounded').allMatches(source).length, 5);
    expect(RegExp("tooltip: 'Plus d’actions'").allMatches(source).length, 4);
  });

  testWidgets('Les petites actions de l’accueil sont contrastées en mode clair',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
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
          openProfile: () {},
        ),
      ),
    ));
    for (final label in ['Traduire', 'Dictée libre', 'Scanner']) {
      final finder = find.byKey(Key('dashboard-small-action-$label'));
      await tester.scrollUntilVisible(finder, 300,
          scrollable: find.byType(Scrollable).first);
      final button = tester.widget<OutlinedButton>(finder);
      final background = button.style?.backgroundColor?.resolve({});
      final foreground = button.style?.foregroundColor?.resolve({});
      final border = button.style?.side?.resolve({});
      expect(background, Colors.white);
      expect(foreground, const Color(0xFF0A3A70));
      expect(border?.color, const Color(0xFF8EC5FF));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Version Premium est présente et ouvre sa boîte de dialogue',
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
      procedureStore: procedures,
      authSession: const AuthenticatedTestSession(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Version Premium'), findsOneWidget);
    expect(find.byIcon(Icons.workspace_premium_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('drawer-premium-entry')));
    await tester.pumpAndSettle();
    expect(find.text('Version Premium'), findsNWidgets(2));
    expect(find.text('La version Premium sera bientôt disponible.'),
        findsOneWidget);
    expect(find.text('Fermer'), findsOneWidget);
  });

  testWidgets('V17.1.2 ne déborde pas sur téléphone étroit', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final size in [const Size(320, 568), const Size(344, 700)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
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
            openProfile: () {},
          ),
        ),
      ));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const Key('dashboard-small-action-Scanner')), 350,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull, reason: 'Taille $size');
    }
  });

  test('V17.3 contient 542 modèles aux identifiants uniques', () {
    final data =
        jsonDecode(File('assets/letters/library.json').readAsStringSync())
            as Map<String, dynamic>;
    final base = (data['templates'] as List<dynamic>)
        .map((e) =>
            JsonLetterRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final all = [...base, ...V173LetterCatalog.additionalRecords];
    expect(all, hasLength(542));
    expect(all.map((e) => e.id).toSet(), hasLength(542));
    expect(all.map((e) => e.title).toSet().length, greaterThanOrEqualTo(500));
    expect(all.every((e) => e.description.isNotEmpty && e.fields.isNotEmpty),
        isTrue);
    expect(all.map((e) => e.category).toSet(),
        containsAll(V173LetterCatalog.categories));
  });

  test('V17.3 recherche résilier Orange et facture EDF', () {
    final orange = V173LetterCatalog.search(
        V173LetterCatalog.additionalRecords, 'résilier Orange');
    expect(orange.map((e) => e.title),
        contains('Résiliation abonnement mobile Orange'));
    expect(orange.map((e) => e.title), contains('Résiliation Internet Orange'));
    final edf = V173LetterCatalog.search(
        V173LetterCatalog.additionalRecords, 'facture EDF');
    expect(edf.map((e) => e.title), contains('Contester une facture EDF'));
    expect(edf.map((e) => e.title), contains('Demande d’échéancier EDF'));
  });

  testWidgets('La loupe ouvre la recherche globale', (tester) async {
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
      procedureStore: procedures,
      authSession: const AuthenticatedTestSession(),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.search_rounded), findsWidgets);
    await tester.tap(find.byKey(const Key('dashboard-global-search')));
    await tester.pumpAndSettle();
    expect(find.text('Recherche globale'), findsOneWidget);
  });

  testWidgets('La recherche globale trouve démarches et documents',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final documents = DocumentStore();
    final procedures = ProcedureStore();
    await documents.add(SavedDocument(
        id: 'search-document',
        title: 'Facture Orange',
        category: 'Télécoms',
        organisation: 'Orange',
        createdAt: DateTime(2026, 8, 3)));
    await procedures.add(AdministrativeProcedure(
        id: 'search-procedure',
        title: 'Réclamation Orange',
        organisation: 'Orange',
        category: 'Télécoms',
        letter: 'Texte',
        createdAt: DateTime(2026, 8, 3),
        updatedAt: DateTime(2026, 8, 3)));
    await tester.pumpWidget(MaterialApp(
        home: GlobalSearchScreen(
      documentStore: documents,
      procedureStore: procedures,
      settings: AppSettings(),
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Orange');
    await tester.pumpAndSettle();
    expect(find.textContaining('Mes démarches'), findsOneWidget);
    expect(find.textContaining('Mes documents'), findsOneWidget);
  });

  test('Les favoris et récents conservent seulement les identifiants',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'jsonLibraryFavoritesV66': <String>['v173_orange_mobile_cancel'],
      'jsonLibraryHistoryV66': <String>['v173_orange_mobile_cancel'],
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('jsonLibraryFavoritesV66'),
        const ['v173_orange_mobile_cancel']);
    expect(prefs.getStringList('jsonLibraryHistoryV66'),
        const ['v173_orange_mobile_cancel']);
  });

  testWidgets(
      'Un résultat EDF ouvre le modèle direct et Retour garde la recherche',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final edf = V173LetterCatalog.additionalRecords
        .firstWhere((e) => e.id == 'v173_edf_invoice_dispute');
    await tester.pumpWidget(MaterialApp(
      home: GlobalSearchScreen(
        documentStore: DocumentStore(),
        procedureStore: ProcedureStore(),
        settings: AppSettings(),
        initialModels: [edf],
      ),
    ));
    await tester.enterText(find.byType(TextField), 'facture EDF');
    await tester.pump();
    await tester.tap(find.text('Contester une facture EDF'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-detail-v173_edf_invoice_dispute')),
        findsOneWidget);
    expect(find.byType(JsonLibraryScreen), findsNothing);
    expect(find.text('Utiliser ce modèle'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final search = tester.widget<TextField>(find.byType(TextField));
    expect(search.controller?.text, 'facture EDF');
  });

  testWidgets('Résilier Orange ouvre directement le modèle choisi',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final orange = V173LetterCatalog.additionalRecords
        .where((e) => e.organisation == 'Orange')
        .toList();
    await tester.pumpWidget(MaterialApp(
      home: GlobalSearchScreen(
        documentStore: DocumentStore(),
        procedureStore: ProcedureStore(),
        settings: AppSettings(),
        initialModels: orange,
      ),
    ));
    await tester.enterText(find.byType(TextField), 'résilier Orange');
    await tester.pump();
    await tester.tap(find.text('Résiliation abonnement mobile Orange'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-detail-v173_orange_mobile_cancel')),
        findsOneWidget);
    expect(find.byType(JsonLibraryScreen), findsNothing);
  });

  testWidgets('Favoris et Historique ouvrent directement le modèle',
      (tester) async {
    final record = V173LetterCatalog.additionalRecords
        .firstWhere((e) => e.id == 'v173_orange_mobile_cancel');
    SharedPreferences.setMockInitialValues(<String, Object>{
      'jsonLibraryFavoritesV66': <String>[record.id],
      'jsonLibraryHistoryV66': <String>[record.id],
    });
    await tester.pumpWidget(MaterialApp(
        home: JsonLibraryScreen(
      settings: AppSettings(),
      initialRecords: [record],
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Favoris (1)'));
    await tester.pump();
    await tester.tap(find.text(record.title));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('model-detail-${record.id}')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Récents (1)'));
    await tester.pump();
    await tester.tap(find.text(record.title));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('model-detail-${record.id}')), findsOneWidget);
  });

  testWidgets('La bibliothèque indique sa disponibilité hors connexion',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(MaterialApp(
        home: JsonLibraryScreen(
      settings: AppSettings(),
      initialRecords: [V173LetterCatalog.additionalRecords.first],
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Hors ligne'), findsNothing);
    expect(find.text('Disponible hors connexion'), findsOneWidget);
    expect(find.byIcon(Icons.offline_bolt_outlined), findsOneWidget);
  });

  test('V17.3.2 normalise la typographie française sans perdre les accents',
      () {
    const legacy =
        'Je reste à votre disposition pour tout complément d information.\n'
        'Veuillez agréer, Madame, Monsieur, l expression de mes salutations distinguées.\n'
        'J ai demandé qu il soit procédé à l examen de mon dossier.\n'
        'Aujourd hui, cette situation n est toujours pas réglée.\n'
        '« Réclamation concernant l électricité »\n'
        'Morières-lès-Avignon';
    final normalized = normalizeFrenchTypography(legacy);
    expect(normalized, contains('complément d’information'));
    expect(normalized, contains('l’expression de mes salutations'));
    expect(normalized, contains('J’ai demandé qu’il soit procédé à l’examen'));
    expect(normalized, contains('Aujourd’hui, cette situation n’est'));
    expect(normalized, contains('« Réclamation concernant l’électricité »'));
    expect(normalized, contains('Morières-lès-Avignon'));
    expect(normalized, isNot(contains('□')));
    expect(normalized, isNot(contains('�')));
  });

  test('V17.3.2 capitalise sûrement les noms de profil composés', () {
    expect(capitalizeProfileName('hafid dhibi'), 'Hafid Dhibi');
    expect(capitalizeProfileName('jean-pierre d’arc'), 'Jean-Pierre D’Arc');
  });

  test('V17.3.2 garde les 542 anciens modèles lisibles', () {
    final data =
        jsonDecode(File('assets/letters/library.json').readAsStringSync())
            as Map<String, dynamic>;
    final base = (data['templates'] as List<dynamic>)
        .map((item) =>
            JsonLetterRecord.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final all = [...base, ...V173LetterCatalog.additionalRecords];
    expect(all, hasLength(542));
    final text = all
        .map((item) => '${item.title}\n${item.subject}\n${item.body}')
        .join('\n');
    expect(text, isNot(contains('□')));
    expect(text, isNot(contains('�')));
    for (final missing in const [
      'd information',
      'l expression',
      'j ai',
      'n est',
      'qu il',
      's il',
      'aujourd hui',
    ]) {
      expect(
        RegExp('(?:^|[^a-z])${RegExp.escape(missing)}(?:[^a-z]|${r'$'})')
            .hasMatch(text.toLowerCase()),
        isFalse,
      );
    }
  });

  testWidgets('V17.3.2 génère un PDF Unicode commun sans erreur',
      (tester) async {
    const text =
        'Je reste à votre disposition pour tout complément d’information.\n'
        'Veuillez agréer, Madame, Monsieur, l’expression de mes salutations distinguées.\n'
        'J’ai demandé qu’il soit procédé à l’examen de mon dossier.\n'
        'Aujourd’hui, cette situation n’est toujours pas réglée.';
    final bytes = await LetterSignatureService.buildLetterPdf(
      text: text,
      subject: '« Réclamation concernant l’électricité »',
      heading: 'Morières-lès-Avignon',
      signed: false,
      senderName: 'hafid dhibi',
    );
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final serviceSource =
        File('lib/letter_signature_service.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(serviceSource,
        contains('pw.Document(theme: await FrenchPdfTheme.load())'));
    expect(mainSource, isNot(contains('pw.Document(')));
  });

  testWidgets('V17.3.3 normalise et recadre une signature sur fond blanc',
      (tester) async {
    final source = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 400, 200),
        ui.Paint()..color = Colors.white,
      );
      canvas.drawLine(
        const Offset(120, 90),
        const Offset(280, 115),
        ui.Paint()
          ..color = const Color(0xFF102040)
          ..strokeWidth = 5
          ..strokeCap = ui.StrokeCap.round,
      );
      final image = await recorder.endRecording().toImage(400, 200);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return SignatureImageService.normalizeSignatureToTransparentPng(
          Uint8List.fromList(data!.buffer.asUint8List()));
    });
    expect(source, isNotNull);
    expect(source!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);

    final result = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(source);
      final image = (await codec.getNextFrame()).image;
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (image: image, rgba: rgba!.buffer.asUint8List());
    });
    expect(result, isNotNull);
    expect(result!.image.width, lessThan(400));
    expect(result.image.height, lessThan(200));
    expect(result.rgba[3], 0, reason: 'La marge doit être transparente.');
    expect(
      Iterable<int>.generate(result.image.width * result.image.height)
          .any((index) => result.rgba[index * 4 + 3] > 200),
      isTrue,
      reason: 'Le trait sombre doit être conservé.',
    );
  });

  testWidgets('V17.3.5 supprime aussi le rectangle gris clair et son halo',
      (tester) async {
    final source = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 360, 180),
        ui.Paint()..color = const Color.fromARGB(255, 242, 242, 242),
      );
      canvas.drawLine(
        const Offset(90, 88),
        const Offset(270, 102),
        ui.Paint()
          ..color = const Color(0xFF26384A)
          ..strokeWidth = 3
          ..strokeCap = ui.StrokeCap.round,
      );
      final image = await recorder.endRecording().toImage(360, 180);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = Uint8List.fromList(data!.buffer.asUint8List());
      expect(SignatureImageService.hasOpaqueLightBackground(bytes), isTrue);
      return SignatureImageService.normalizeSignatureToTransparentPng(bytes);
    });
    expect(source, isNotNull);

    final result = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(source!);
      final image = (await codec.getNextFrame()).image;
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (image: image, rgba: rgba!.buffer.asUint8List());
    });
    expect(result, isNotNull);
    final rgba = result!.rgba;
    final width = result.image.width;
    final height = result.image.height;
    final borderPixels = <int>[
      for (var x = 0; x < width; x++) ...[x, (height - 1) * width + x],
      for (var y = 1; y < height - 1; y++) ...[
        y * width,
        y * width + width - 1
      ],
    ];
    expect(borderPixels.every((index) => rgba[index * 4 + 3] == 0), isTrue);
    expect(borderPixels.every((index) => rgba[index * 4] == 0), isTrue,
        reason: 'Les pixels transparents ne gardent aucun RGB blanc/gris.');
    expect(SignatureImageService.hasOpaqueLightBackground(source!), isFalse);
  });

  test('V17.3.3 migre sans supprimer l’ancienne signature', () async {
    final directory = await Directory.systemTemp.createTemp('signature_old_');
    addTearDown(() => directory.delete(recursive: true));
    final legacy = File('${directory.path}/ancienne_signature.jpg');
    await legacy
        .writeAsBytes(await File('assets/adminfacile_mark.png').readAsBytes());
    SharedPreferences.setMockInitialValues(<String, Object>{
      'signaturePathV17': legacy.path,
    });
    final settings = AppSettings(
      signatureDirectoryProvider: () async => directory,
    );
    await settings.load();
    await settings.activateProfileForUser('legacy-test-user');
    expect(settings.hasSignature, isTrue);
    expect(
      settings.signaturePath,
      endsWith(
        '${Platform.pathSeparator}signatures${Platform.pathSeparator}'
        'legacy-test-user${Platform.pathSeparator}signature.png',
      ),
    );
    expect(await legacy.exists(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('signature.legacy-test-user.transparentPng'),
      isTrue,
    );
  });

  testWidgets(
      'V17.3.4 Recherche modèle → ouvrir → personnaliser → exporter utilise le générateur unique',
      (tester) async {
    final model = LetterTemplate.bank.models.firstWhere(
      (item) => item.subject == 'Demande d’opposition sur carte bancaire',
    );
    final letter = LetterGenerator.generate(
      template: LetterTemplate.bank,
      model: model,
      firstName: 'hafid',
      lastName: 'dhibi',
      address: '1 rue de la République',
      postalCode: '84000',
      city: 'Avignon',
      recipient: 'Ma banque',
      recipientAddress: '2 avenue du Centre',
      reference: 'CB-123',
      details: 'Opposition immédiate demandée.',
    );
    final prepared = LetterSignatureService.prepareContent(
      text: letter,
      signed: true,
      senderName: 'Hafid Dhibi',
    );
    expect(RegExp(r'^Objet\s*:', multiLine: true).allMatches(prepared.text),
        hasLength(1));
    expect(prepared.containsSubject, isTrue);
    expect(
      RegExp(r'^Hafid Dhibi$', multiLine: true).allMatches(prepared.text),
      hasLength(1),
      reason: 'Le nom final est réservé au bloc de signature du PDF.',
    );

    final bytes = await tester.runAsync(() async {
      return LetterSignatureService.buildLetterPdf(
        text: letter,
        subject: model.subject,
        signed: true,
        signatureBytes: await File('assets/adminfacile_mark.png').readAsBytes(),
        senderName: 'Hafid Dhibi',
      );
    });
    expect(String.fromCharCodes(bytes!.take(4)), '%PDF');
  });

  test('V17.3.6 utilise le bloc officiel dans le générateur PDF unique', () {
    final source = File('lib/letter_signature_service.dart').readAsStringSync();
    expect(LetterSignatureService.signatureWidth, lessThan(130));
    expect(LetterSignatureService.signatureHeight, inInclusiveRange(45, 60));
    expect(source, contains('pw.Image(pw.MemoryImage(signature)'));
    expect(source, contains("pw.Text('Signature de l’expéditeur'"));
    expect(source, contains('pw.Container('));
    expect(source, contains('border: pw.Border.all'));
    expect(source, contains('width: .6'));
    expect(source, contains('color: PdfColors.white'));
    expect(source, contains("pw.Text('Signature à apposer'"));
    expect(source, isNot(contains('pw.DecoratedBox')));
    expect(source, isNot(contains('boxShadow')));
    expect(LetterSignatureService.signatureWidth, lessThan(110));
    expect(
        LetterSignatureService.signatureFrameWidth, inInclusiveRange(130, 160));
    expect(
        LetterSignatureService.signatureFrameHeight, inInclusiveRange(65, 85));
  });

  testWidgets('V17.3.6 masque tout le bloc quand la signature est désactivée',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OfficialSignatureBlock(
          signed: false,
          signaturePath: '',
          senderName: 'Hafid Dhibi',
        ),
      ),
    ));
    expect(find.text('Signature de l’expéditeur'), findsNothing);
    expect(find.byKey(const Key('official-signature-frame')), findsNothing);
    expect(find.text('Hafid Dhibi'), findsNothing);
  });

  testWidgets('V17.3.6 affiche un cadre à signer si l’image manque',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OfficialSignatureBlock(
          signed: true,
          signaturePath: '',
          senderName: 'hafid dhibi',
        ),
      ),
    ));
    expect(find.text('Signature de l’expéditeur'), findsOneWidget);
    expect(find.text('Signature à apposer'), findsOneWidget);
    expect(find.byKey(const Key('official-signature-frame')), findsOneWidget);
    expect(find.text('Hafid Dhibi'), findsOneWidget);
    final frame = tester
        .widget<Container>(find.byKey(const Key('official-signature-frame')));
    final decoration = frame.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.border, isNotNull);
    expect(decoration.boxShadow, isNull);
  });

  test('V18.0 réduit les permissions et sécurise la suppression', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final source = File('lib/main.dart').readAsStringSync();
    expect(manifest, isNot(contains('android.permission.BLUETOOTH')));
    expect(manifest, contains('android.permission.RECORD_AUDIO'));
    expect(manifest, contains('android.permission.INTERNET'));
    expect(source, contains("title: const Text('Supprimer ce document ?')"));
    expect(source, contains('_confirmDeleteDocument(doc)'));
  });

  test('V19.0 conserve quatre rendus simples sans dégrader la géométrie',
      () async {
    final source = await File('assets/adminfacile_logo.png').readAsBytes();
    final original = img.decodeImage(source)!;
    expect(ProfessionalScanFilter.values.map((filter) => filter.label), [
      'Original',
      'Document',
      'Noir et blanc',
      'Couleur améliorée',
    ]);
    for (final filter in ProfessionalScanFilter.values) {
      final result = ScannerProcessingService.processPage(source, filter);
      final decoded = img.decodeImage(result);
      expect(decoded, isNotNull, reason: filter.label);
      expect(decoded!.width / decoded.height,
          closeTo(original.width / original.height, .01),
          reason: 'Le ratio doit rester stable pour ${filter.label}.');
    }
  });

  test('V18.1 tourne à 90 degrés et produit un PDF A4 lisible', () async {
    final source = await File('assets/adminfacile_logo.png').readAsBytes();
    final original = img.decodeImage(source)!;
    final rotated = ScannerProcessingService.processPage(
      source,
      ProfessionalScanFilter.document,
      quarterTurns: 1,
    );
    final decoded = img.decodeJpg(rotated)!;
    expect(decoded.width, original.height);
    expect(decoded.height, original.width);
    final pdf = await ScannerProcessingService.buildA4Pdf([rotated, rotated]);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    expect(ScannerProcessingService.pdfMargin, inInclusiveRange(12, 30));
  });

  test('V19.0 utilise ML Kit comme unique moteur Android', () {
    final source = File('lib/main.dart').readAsStringSync();
    final service =
        File('lib/document_scanner_service.dart').readAsStringSync();
    final android =
        File('android/app/src/main/kotlin/fr/adminfacile/app/MainActivity.kt')
            .readAsStringSync();
    expect(
        service, contains('abstract interface class DocumentScannerService'));
    expect(service, contains('AndroidMlKitDocumentScannerService'));
    expect(source, contains('widget.scannerService.scan(pageLimit: 10)'));
    expect(source, contains('_extractTextFromImages(renderedPaths)'));
    expect(source, contains('ScannerProcessingService.preparePdf('));
    expect(source, contains('nativePdfPath: result.pdfPath'));
    expect(android, contains('GmsDocumentScanning.getClient(options)'));
    expect(android, contains('FlutterFragmentActivity'));
    expect(android, contains('registerForActivityResult'));
    expect(android, contains('StartIntentSenderForResult'));
    expect(android, isNot(contains('startIntentSenderForResult')));
    expect(android, isNot(contains('onActivityResult')));
    expect(android, contains('SCANNER_MODE_FULL'));
    expect(android, contains('RESULT_FORMAT_JPEG'));
    expect(android, contains('RESULT_FORMAT_PDF'));
    expect(android, contains('imagePaths'));
    expect(android, isNot(contains('EdgeDetector')));
    expect(android, isNot(contains('PerspectiveCropper')));
    expect(source, isNot(contains('adminfacile/professional_scanner')));
    expect(File('lib/document_edge_geometry.dart').existsSync(), isFalse);
    expect(
        File('android/app/src/main/kotlin/fr/adminfacile/app/ProfessionalScannerActivity.kt')
            .existsSync(),
        isFalse);
  });

  test('la signature de document reste dérivée du PDF ML Kit et des JPEG OCR',
      () {
    final source = File('lib/main.dart').readAsStringSync();
    final service =
        File('lib/document_signature_service.dart').readAsStringSync();
    expect(source, contains("key: const Key('scanner-add-signature')"));
    expect(source, contains('_unsignedPdfPath ?? pdfPath'));
    expect(source, contains('_renderedScanImagePaths.isNotEmpty'));
    expect(source, contains('DocumentSignatureService.createSignedCopy'));
    expect(source, contains("'signature-resize-handle'"));
    expect(source, contains("'signature-document-interactive-viewer'"));
    expect(source, contains("key: const Key('signature-reset-zoom')"));
    expect(
        source, contains('minScale: SignatureViewportTransform.minimumZoom'));
    expect(
        source, contains('maxScale: SignatureViewportTransform.maximumZoom'));
    expect(source, contains('panEnabled: true'));
    expect(source, contains('scaleEnabled: true'));
    expect(source, contains('void _selectPage(int index)'));
    expect(source, contains('_resetPageZoom();'));
    expect(source, isNot(contains('details.pointerCount > 1')));
    expect(service, contains('document_signe_'));
    expect(service, isNot(contains('.copySync(')));
    expect(source, contains('_extractTextFromImages(renderedPaths)'));
    expect(source, contains('nativePdfPath: result.pdfPath'));
  });

  test('V19.0 garde le document précédent si ML Kit échoue', () {
    final source = File('lib/main.dart').readAsStringSync();
    final scanStart = source.indexOf('Future<void> scanA4()');
    final scanEnd = source.indexOf('Future<void> pickAndRead', scanStart);
    final scan = source.substring(scanStart, scanEnd);
    final call = scan.indexOf('widget.scannerService.scan');
    expect(call, greaterThan(0));
    expect(scan.substring(0, call), isNot(contains('pdfPath = null')));
    expect(scan, contains('DocumentScannerUnavailableException.message'));
  });

  test('V20.0 partage un cache unique pour le catalogue de modèles', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('class BundledLetterCatalog'));
    expect(source, contains('_cachedRecords ??= _loadFromAssets()'));
    expect(
      RegExp(r'BundledLetterCatalog\.load\(\)').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('V20.0 ne bloque pas le démarrage sur la synchronisation cloud', () {
    final source = File('lib/main.dart').readAsStringSync();
    final signatureSource =
        File('lib/profile_signature_service.dart').readAsStringSync();
    final runAppPosition = source.indexOf('runApp(');
    final syncPosition = source.indexOf('unawaited(_synchronizeProfileForUser');

    expect(runAppPosition, greaterThan(0));
    expect(syncPosition, greaterThan(runAppPosition));
    expect(source, contains('.timeout(const Duration(seconds: 15))'));
    expect(
      signatureSource,
      contains('.timeout(const Duration(seconds: 20))'),
    );
  });

  test('V20.0 traduit les erreurs cloud sans exposer de détail technique', () {
    expect(
      cloudOperationMessage(TimeoutException('secret technique')),
      'Le service cloud met trop de temps à répondre. Réessayez.',
    );
    expect(
      cloudOperationMessage(const SocketException('hôte privé')),
      'Vérifiez votre connexion Internet.',
    );
    expect(
      cloudOperationMessage(Exception('jeton sensible')),
      'Le service cloud est momentanément indisponible.',
    );
  });

  test('V20.1 prépare une signature release sans clé debug', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final ignore = File('.gitignore').readAsStringSync();
    final example = File('android/key.properties.example').readAsStringSync();

    expect(gradle, contains('releasePropertiesFile'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(ignore, contains('/android/key.properties'));
    expect(ignore, contains('/android/app/*.jks'));
    expect(example, contains('[À COMPLÉTER]'));
    // La configuration locale peut exister pour signer la release ; son
    // contenu ne doit jamais être lu ni exposé par les tests.
  });

  test('V20.1 conserve uniquement les permissions Android nécessaires', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android.permission.RECORD_AUDIO'));
    expect(manifest, isNot(contains('android.permission.CAMERA')));
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('READ_MEDIA_')));
    expect(manifest, isNot(contains('POST_NOTIFICATIONS')));
  });

  test('V20.4.27 utilise la nouvelle marque pour icône et splash', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    final foreground = File(
      'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
    ).readAsStringSync();
    final android12 = File(
      'android/app/src/main/res/values-v31/styles.xml',
    ).readAsStringSync();
    final colors = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();

    expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    expect(
      pubspec,
      contains('assets/branding/admin_facile_icon.png'),
    );
    expect(
      pubspec,
      contains('assets/branding/admin_facile_logo.png'),
    );
    expect(adaptive, contains('@color/adminfacile_icon_background'));
    expect(foreground, contains('@drawable/adminfacile_brand_icon'));
    expect(android12, contains('android:windowSplashScreenAnimatedIcon'));
    expect(android12, contains('@drawable/adminfacile_splash'));
    expect(colors, contains('#010E28'));
    expect(
      File('android/app/src/main/res/drawable/adminfacile_brand_icon.png')
          .existsSync(),
      isTrue,
    );
    expect(
      File('android/app/src/main/res/drawable/adminfacile_splash.png')
          .existsSync(),
      isTrue,
    );

    final expectedSizes = <String, int>{
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final entry in expectedSizes.entries) {
      final launcher = img.decodePng(
        File(
          'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
        ).readAsBytesSync(),
      );
      expect(launcher, isNotNull, reason: entry.key);
      expect(launcher!.width, entry.value, reason: entry.key);
      expect(launcher.height, entry.value, reason: entry.key);
    }

    final splash = img.decodePng(
      File('android/app/src/main/res/drawable/adminfacile_splash.png')
          .readAsBytesSync(),
    );
    expect(splash, isNotNull);
    expect(splash!.width, 288);
    expect(splash.height, 288);
  });

  testWidgets('V20.4.27 affiche le nouveau symbole dans l’interface',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AdminFacileMark(size: 96)),
      ),
    );
    await tester.pump();

    final symbol = tester.widget<Image>(
      find.byKey(const Key('admin-facile-icon-image')),
    );
    expect(
      (symbol.image as AssetImage).assetName,
      'assets/branding/admin_facile_icon.png',
    );
    expect(symbol.fit, BoxFit.contain);
    expect(tester.getSize(find.byType(AdminFacileMark)), const Size(96, 96));
  });

  test('V20.2 utilise le package Android définitif', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final mainActivityPath =
        'android/app/src/main/kotlin/fr/adminfacile/app/MainActivity.kt';
    final mainActivity = File(mainActivityPath).readAsStringSync();
    final scannerService =
        File('lib/document_scanner_service.dart').readAsStringSync();

    expect(gradle, contains('namespace = "fr.adminfacile.app"'));
    expect(gradle, contains('applicationId = "fr.adminfacile.app"'));
    expect(mainActivity, startsWith('package fr.adminfacile.app'));
    expect(manifest, contains('android:name=".MainActivity"'));
    expect(
      File(
        'android/app/src/main/kotlin/com/example/admin_facile/MainActivity.kt',
      ).existsSync(),
      isFalse,
    );
    expect(
      '$gradle\n$manifest\n$mainActivity\n$scannerService',
      isNot(contains('com.example.admin_facile')),
    );
    expect(
      mainActivity,
      contains('"adminfacile/mlkit_document_scanner"'),
    );
    expect(
      scannerService,
      contains("MethodChannel('adminfacile/mlkit_document_scanner')"),
    );
  });

  group('V20.4 centre de notifications', () {
    Future<
        ({
          AppSettings settings,
          DocumentStore documents,
          ProcedureStore procedures,
          NotificationStore notifications,
        })> fixture() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final settings = AppSettings();
      final notifications = NotificationStore();
      final documents = DocumentStore(notificationStore: notifications);
      final procedures = ProcedureStore(notificationStore: notifications);
      await Future.wait([
        settings.load(),
        notifications.load(),
        documents.load(),
        procedures.load(),
      ]);
      return (
        settings: settings,
        documents: documents,
        procedures: procedures,
        notifications: notifications,
      );
    }

    Future<void> pumpShell(
        WidgetTester tester,
        ({
          AppSettings settings,
          DocumentStore documents,
          ProcedureStore procedures,
          NotificationStore notifications,
        }) data) async {
      await tester.pumpWidget(MaterialApp(
        home: AppShell(
          settings: data.settings,
          documentStore: data.documents,
          procedureStore: data.procedures,
          notificationStore: data.notifications,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('Recherche et Notifications ouvrent deux pages distinctes',
        (tester) async {
      final data = await fixture();
      await pumpShell(tester, data);

      await tester.tap(find.byKey(const Key('dashboard-global-search')));
      await tester.pumpAndSettle();
      expect(find.text('Recherche globale'), findsOneWidget);
      expect(find.byKey(const Key('notifications-screen')), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dashboard-notifications')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notifications-screen')), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Recherche globale'), findsNothing);
      expect(find.text('Aucune notification pour le moment'), findsOneWidget);
    });

    testWidgets('notification réelle non lue affiche badge puis peut être lue',
        (tester) async {
      final data = await fixture();
      await data.documents.add(SavedDocument(
        id: 'caf-document',
        title: 'Attestation CAF',
        category: 'CAF',
        organisation: 'CAF',
        createdAt: DateTime(2026, 8, 11, 9, 30),
        extractedText: 'Attestation enregistrée',
      ));
      await pumpShell(tester, data);

      expect(find.byKey(const Key('dashboard-notification-badge')),
          findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dashboard-notifications')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification-unread-indicator')),
          findsOneWidget);

      await tester.tap(
          find.byKey(const Key('notification-document-added-caf-document')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification-document-target')),
          findsOneWidget);
      expect(find.text('Attestation CAF'), findsOneWidget);
      expect(data.notifications.unreadCount, 0);
    });

    testWidgets('tout marquer comme lu retire les indicateurs et le badge',
        (tester) async {
      final data = await fixture();
      await data.notifications.add(AppNotification(
        id: 'account-real-event',
        type: AppNotificationType.account,
        message: 'Informations de compte mises à jour.',
        createdAt: DateTime(2026, 8, 11, 10),
      ));
      await data.procedures.add(AdministrativeProcedure(
        id: 'caf-procedure',
        title: 'Dossier CAF',
        organisation: 'CAF',
        category: 'Aides',
        letter: 'Compléter le dossier.',
        createdAt: DateTime(2026, 8, 11, 10, 5),
        updatedAt: DateTime(2026, 8, 11, 10, 5),
      ));
      await pumpShell(tester, data);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dashboard-notifications')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notifications-mark-all-read')));
      await tester.pumpAndSettle();
      expect(data.notifications.unreadCount, 0);
      expect(
          find.byKey(const Key('notification-unread-indicator')), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('dashboard-notification-badge')), findsNothing);
      await tester.tap(find.byKey(const Key('dashboard-notifications')));
      await tester.pumpAndSettle();

      await tester.tap(
          find.byKey(const Key('notification-procedure-added-caf-procedure')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification-procedure-target')),
          findsOneWidget);
      expect(find.text('Dossier CAF'), findsOneWidget);
    });
  });
}
