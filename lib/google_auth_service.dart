import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
);

void validateGoogleAuthReleaseConfiguration() {
  if (kReleaseMode && googleWebClientId.trim().isEmpty) {
    throw StateError(
      'GOOGLE_WEB_CLIENT_ID doit être fourni pour les builds release.',
    );
  }
}

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.userMessage, {this.code = 'google_error'});

  final String userMessage;
  final String code;
}

abstract interface class GoogleAuthService {
  bool get isConfigured;
  Future<void> signIn();
  Future<void> signOutProvider();
}

class SupabaseGoogleAuthService implements GoogleAuthService {
  SupabaseGoogleAuthService(this.client, {GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final SupabaseClient client;
  final GoogleSignIn _googleSignIn;
  Future<void>? _initialization;

  @override
  bool get isConfigured => googleWebClientId.trim().isNotEmpty;

  Future<void> _initialize() {
    if (!isConfigured) {
      throw const GoogleAuthException(
        'La connexion Google est temporairement indisponible.',
        code: 'not_configured',
      );
    }
    return _initialization ??= _googleSignIn.initialize(
      serverClientId: googleWebClientId.trim(),
    );
  }

  @override
  Future<void> signIn() async {
    try {
      await _initialize();
      if (!_googleSignIn.supportsAuthenticate()) {
        throw const GoogleAuthException(
          'La connexion Google n’est pas disponible sur cet appareil.',
          code: 'provider_unavailable',
        );
      }
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const GoogleAuthException(
          'La connexion Google n’a pas pu être validée.',
          code: 'missing_id_token',
        );
      }
      final response = await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      if (response.session == null || response.user == null) {
        throw const GoogleAuthException(
          'La connexion Google n’a pas créé de session valide.',
          code: 'missing_supabase_session',
        );
      }
    } on GoogleAuthException {
      rethrow;
    } on GoogleSignInException catch (error) {
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
          throw const GoogleAuthException(
            'Connexion Google annulée.',
            code: 'canceled',
          );
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          throw const GoogleAuthException(
            'La connexion Google est temporairement indisponible.',
            code: 'configuration_error',
          );
        case GoogleSignInExceptionCode.uiUnavailable:
          throw const GoogleAuthException(
            'Aucun compte Google n’est disponible sur cet appareil.',
            code: 'account_unavailable',
          );
        default:
          throw const GoogleAuthException(
            'La connexion Google a échoué. Réessayez.',
          );
      }
    } on SocketException {
      throw const GoogleAuthException(
        'Vérifiez votre connexion Internet.',
        code: 'network_unavailable',
      );
    } on TimeoutException {
      throw const GoogleAuthException(
        'Le service met trop de temps à répondre. Réessayez.',
        code: 'timeout',
      );
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (error is AuthRetryableFetchException ||
          message.contains('network') ||
          message.contains('connection')) {
        throw const GoogleAuthException(
          'Vérifiez votre connexion Internet.',
          code: 'network_unavailable',
        );
      }
      throw const GoogleAuthException(
        'La connexion Google a échoué. Réessayez.',
        code: 'supabase_error',
      );
    } catch (_) {
      throw const GoogleAuthException(
        'La connexion Google a échoué. Réessayez.',
      );
    }
  }

  @override
  Future<void> signOutProvider() async {
    try {
      await _initialize();
      await _googleSignIn.signOut();
    } catch (_) {
      // Supabase reste l'autorité de session. Une erreur de nettoyage Google
      // ne doit jamais empêcher la déconnexion locale Supabase.
    }
  }
}
