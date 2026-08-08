import 'dart:io';

import 'package:admin_facile/professional_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAuthGateway implements AuthGateway {
  bool signedIn = false;
  bool confirmationRequired = false;
  Object? nextError;
  bool resetRequested = false;
  bool profileUpdated = false;
  String? email;

  @override
  bool get hasSession => signedIn;
  @override
  String? get currentEmail => email;
  @override
  String? get currentUserId => signedIn ? 'user-18-2' : null;

  void _throwIfNeeded() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    _throwIfNeeded();
    this.email = email;
    signedIn = !confirmationRequired;
    return confirmationRequired;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _throwIfNeeded();
    this.email = email;
    signedIn = true;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _throwIfNeeded();
    resetRequested = true;
  }

  @override
  Future<void> signOut() async {
    _throwIfNeeded();
    signedIn = false;
  }

  @override
  Future<void> updatePassword(String password) async => _throwIfNeeded();

  @override
  Future<void> updateProfile(Map<String, dynamic> metadata) async {
    _throwIfNeeded();
    profileUpdated = true;
  }
}

void main() {
  group('V18.2 authentification professionnelle', () {
    test('inscription réussie avec connexion automatique', () async {
      final gateway = FakeAuthGateway();
      final service = ProfessionalAuthService(gateway);

      final result = await service.signUp(
        email: ' Test@Example.fr ',
        password: 'secret12',
      );

      expect(result.emailConfirmationRequired, isFalse);
      expect(service.hasSession, isTrue);
      expect(gateway.email, 'test@example.fr');
    });

    test('inscription peut attendre la confirmation e-mail', () async {
      final gateway = FakeAuthGateway()..confirmationRequired = true;
      final result = await ProfessionalAuthService(gateway).signUp(
        email: 'test@example.fr',
        password: 'secret12',
      );
      expect(result.emailConfirmationRequired, isTrue);
      expect(gateway.signedIn, isFalse);
    });

    test('e-mail déjà utilisé reçoit le bon message', () async {
      final gateway = FakeAuthGateway()
        ..nextError = const AuthException(
          'User already registered',
          statusCode: '422',
          code: 'user_already_exists',
        );
      await expectLater(
        ProfessionalAuthService(gateway).signUp(
          email: 'test@example.fr',
          password: 'secret12',
        ),
        throwsA(isA<AuthOperationException>().having(
          (error) => error.userMessage,
          'message',
          'Adresse e-mail déjà utilisée.',
        )),
      );
    });

    test('mauvais mot de passe reçoit le bon message', () async {
      final gateway = FakeAuthGateway()
        ..nextError = const AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        );
      await expectLater(
        ProfessionalAuthService(gateway).signIn(
          email: 'test@example.fr',
          password: 'incorrect',
        ),
        throwsA(isA<AuthOperationException>().having(
          (error) => error.userMessage,
          'message',
          'Mot de passe incorrect.',
        )),
      );
    });

    test('e-mail invalide est rejeté avant le réseau', () async {
      await expectLater(
        ProfessionalAuthService(FakeAuthGateway()).signIn(
          email: 'adresse-invalide',
          password: 'secret12',
        ),
        throwsA(isA<AuthOperationException>().having(
          (error) => error.userMessage,
          'message',
          'Adresse e-mail invalide.',
        )),
      );
    });

    test('récupération du mot de passe est transmise au service', () async {
      final gateway = FakeAuthGateway();
      await ProfessionalAuthService(gateway)
          .sendPasswordReset('test@example.fr');
      expect(gateway.resetRequested, isTrue);
    });

    test('reconnexion recrée une session', () async {
      final gateway = FakeAuthGateway();
      await ProfessionalAuthService(gateway).signIn(
        email: 'test@example.fr',
        password: 'secret12',
      );
      expect(gateway.signedIn, isTrue);
    });

    test('session persistante restaurée est immédiatement reconnue', () {
      final gateway = FakeAuthGateway()
        ..signedIn = true
        ..email = 'test@example.fr';
      final service = ProfessionalAuthService(gateway);
      expect(service.hasSession, isTrue);
      expect(service.currentEmail, 'test@example.fr');
    });

    test('déconnexion supprime proprement la session locale', () async {
      final gateway = FakeAuthGateway()..signedIn = true;
      await ProfessionalAuthService(gateway).signOut();
      expect(gateway.signedIn, isFalse);
    });

    test('absence de réseau affiche un message compréhensible', () async {
      final gateway = FakeAuthGateway()
        ..nextError = const SocketException('Network unreachable');
      await expectLater(
        ProfessionalAuthService(gateway).signIn(
          email: 'test@example.fr',
          password: 'secret12',
        ),
        throwsA(isA<AuthOperationException>().having(
          (error) => error.userMessage,
          'message',
          'Vérifiez votre connexion Internet.',
        )),
      );
    });

    test('réponse invalide et serveur indisponible sont distingués', () {
      expect(
        ProfessionalAuthService.mapError(
          const FormatException('invalid json'),
          operation: 'signIn',
        ).userMessage,
        'Le service a renvoyé une réponse invalide. Réessayez.',
      );
      expect(
        ProfessionalAuthService.mapError(
          const AuthException('server', statusCode: '503'),
          operation: 'signIn',
        ).userMessage,
        'Service temporairement indisponible.',
      );
    });

    test('le diagnostic contient fonction et code uniquement en debug', () {
      final error = ProfessionalAuthService.mapError(
        const AuthException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        ),
        operation: 'signIn',
      );
      expect(error.userMessage, 'Compte non confirmé. Vérifiez votre e-mail.');
      expect(error.displayMessage, contains('fonction=signIn'));
      expect(error.displayMessage, contains('code=email_not_confirmed'));
    });

    test('la mise à jour du profil utilise les métadonnées Auth sans SQL',
        () async {
      final gateway = FakeAuthGateway()..signedIn = true;
      await ProfessionalAuthService(gateway)
          .updateProfile({'display_name': 'Hafid Dhibi'});
      expect(gateway.profileUpdated, isTrue);
    });
  });
}
