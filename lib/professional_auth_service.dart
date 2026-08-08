import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthOperationException implements Exception {
  const AuthOperationException({
    required this.userMessage,
    required this.operation,
    this.code,
    this.cause,
  });

  final String userMessage;
  final String operation;
  final String? code;
  final Object? cause;

  String get displayMessage {
    if (!kDebugMode) return userMessage;
    return '$userMessage\n[DEBUG] fonction=$operation'
        '${code == null ? '' : ' • code=$code'}'
        '${cause == null ? '' : '\n$cause'}';
  }

  @override
  String toString() => displayMessage;
}

class AuthSignUpResult {
  const AuthSignUpResult({required this.emailConfirmationRequired});
  final bool emailConfirmationRequired;
}

abstract interface class AuthGateway {
  bool get hasSession;
  String? get currentUserId;
  String? get currentEmail;

  Future<bool> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  });

  Future<void> signIn({required String email, required String password});
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String password);
  Future<void> updateProfile(Map<String, dynamic> metadata);
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this.client);
  final SupabaseClient client;

  @override
  bool get hasSession => client.auth.currentSession != null;

  @override
  String? get currentUserId => client.auth.currentUser?.id;

  @override
  String? get currentEmail => client.auth.currentUser?.email;

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: metadata,
      emailRedirectTo: 'io.adminfacile://reset-password',
    );
    if (response.user == null) {
      throw const FormatException('Réponse d’inscription sans utilisateur.');
    }
    if (response.user!.identities?.isEmpty ?? false) {
      throw const AuthException(
        'User already registered',
        statusCode: '422',
        code: 'user_already_exists',
      );
    }
    return response.session == null;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (response.session == null || response.user == null) {
      throw const FormatException('Réponse de connexion sans session.');
    }
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.adminfacile://reset-password',
      );

  @override
  Future<void> updatePassword(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> updateProfile(Map<String, dynamic> metadata) async {
    await client.auth.updateUser(UserAttributes(data: metadata));
  }

  @override
  Future<void> signOut() => client.auth.signOut(scope: SignOutScope.local);
}

class ProfessionalAuthService {
  ProfessionalAuthService(
    this.gateway, {
    this.timeout = const Duration(seconds: 15),
  });

  final AuthGateway gateway;
  final Duration timeout;

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  bool get hasSession => gateway.hasSession;
  String? get currentUserId => gateway.currentUserId;
  String? get currentEmail => gateway.currentEmail;

  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    final normalized = _validateEmail(email, 'signUp');
    _validatePassword(password, 'signUp');
    try {
      final confirmationRequired = await gateway
          .signUp(
            email: normalized,
            password: password,
            metadata: metadata,
          )
          .timeout(timeout);
      return AuthSignUpResult(emailConfirmationRequired: confirmationRequired);
    } catch (error) {
      throw mapError(error, operation: 'signUp');
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final normalized = _validateEmail(email, 'signIn');
    if (password.isEmpty) {
      throw const AuthOperationException(
        userMessage: 'Saisissez votre mot de passe.',
        operation: 'signIn',
        code: 'empty_password',
      );
    }
    try {
      await gateway
          .signIn(email: normalized, password: password)
          .timeout(timeout);
    } catch (error) {
      throw mapError(error, operation: 'signIn');
    }
  }

  Future<void> sendPasswordReset(String email) async {
    final normalized = _validateEmail(email, 'sendPasswordReset');
    try {
      await gateway.sendPasswordReset(normalized).timeout(timeout);
    } catch (error) {
      throw mapError(error, operation: 'sendPasswordReset');
    }
  }

  Future<void> updatePassword(String password) async {
    _validatePassword(password, 'updatePassword');
    try {
      await gateway.updatePassword(password).timeout(timeout);
    } catch (error) {
      throw mapError(error, operation: 'updatePassword');
    }
  }

  Future<void> updateProfile(Map<String, dynamic> metadata) async {
    if (!gateway.hasSession) return;
    try {
      await gateway.updateProfile(metadata).timeout(timeout);
    } catch (error) {
      throw mapError(error, operation: 'updateProfile');
    }
  }

  Future<void> signOut() async {
    try {
      await gateway.signOut().timeout(timeout);
    } catch (error) {
      throw mapError(error, operation: 'signOut');
    }
  }

  String _validateEmail(String email, String operation) {
    final normalized = email.trim().toLowerCase();
    if (!_emailPattern.hasMatch(normalized)) {
      throw AuthOperationException(
        userMessage: 'Adresse e-mail invalide.',
        operation: operation,
        code: 'invalid_email',
      );
    }
    return normalized;
  }

  void _validatePassword(String password, String operation) {
    if (password.length < 6) {
      throw AuthOperationException(
        userMessage: 'Le mot de passe doit contenir au moins 6 caractères.',
        operation: operation,
        code: 'weak_password',
      );
    }
  }

  static AuthOperationException mapError(
    Object error, {
    required String operation,
  }) {
    if (error is AuthOperationException) return error;
    if (error is TimeoutException) {
      return AuthOperationException(
        userMessage: 'Le service met trop de temps à répondre. Réessayez.',
        operation: operation,
        code: 'timeout',
        cause: error,
      );
    }
    if (error is SocketException) {
      return AuthOperationException(
        userMessage: 'Vérifiez votre connexion Internet.',
        operation: operation,
        code: 'network_unavailable',
        cause: error,
      );
    }
    if (error is FormatException) {
      return AuthOperationException(
        userMessage: 'Le service a renvoyé une réponse invalide. Réessayez.',
        operation: operation,
        code: 'invalid_response',
        cause: error,
      );
    }
    if (error is AuthException) {
      final code = error.code?.toLowerCase();
      final message = error.message.toLowerCase();
      String friendly;
      if (code == 'user_already_exists' ||
          message.contains('already registered') ||
          message.contains('already been registered')) {
        friendly = 'Adresse e-mail déjà utilisée.';
      } else if (code == 'invalid_credentials' ||
          message.contains('invalid login credentials')) {
        friendly = 'Mot de passe incorrect.';
      } else if (code == 'email_not_confirmed' ||
          message.contains('email not confirmed')) {
        friendly = 'Compte non confirmé. Vérifiez votre e-mail.';
      } else if (code == 'email_address_invalid' ||
          message.contains('invalid email')) {
        friendly = 'Adresse e-mail invalide.';
      } else if (code == 'weak_password' ||
          message.contains('password should be')) {
        friendly = 'Le mot de passe doit contenir au moins 6 caractères.';
      } else if (error.statusCode == '429' ||
          code == 'over_request_rate_limit') {
        friendly = 'Trop de tentatives. Réessayez dans quelques minutes.';
      } else if (error is AuthRetryableFetchException ||
          message.contains('network') ||
          message.contains('socket') ||
          message.contains('connection')) {
        friendly = 'Vérifiez votre connexion Internet.';
      } else if (error.statusCode != null &&
          int.tryParse(error.statusCode!) != null &&
          int.parse(error.statusCode!) >= 500) {
        friendly = 'Service temporairement indisponible.';
      } else if (error is AuthSessionMissingException ||
          code == 'session_not_found' ||
          code == 'refresh_token_not_found' ||
          message.contains('session')) {
        friendly = 'Votre session a expiré. Reconnectez-vous.';
      } else {
        friendly = error.message.trim().isEmpty
            ? 'Service temporairement indisponible.'
            : error.message.trim();
      }
      return AuthOperationException(
        userMessage: friendly,
        operation: operation,
        code: error.code ?? error.statusCode,
        cause: error,
      );
    }
    return AuthOperationException(
      userMessage: 'Service temporairement indisponible.',
      operation: operation,
      code: 'unexpected_error',
      cause: error,
    );
  }
}
