import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'professional_auth_service.dart';

/// Pont de compatibilité pour les anciens contrôleurs cloud.
///
/// Depuis V18.2, cette classe ne stocke plus de jetons et ne renouvelle plus de
/// session par REST. Supabase Flutter reste l’unique propriétaire de la session.
class AccountController extends ChangeNotifier {
  AccountController._();

  static final AccountController instance = AccountController._();

  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pmnjphgaxcmxmhurhucm.supabase.co',
  );
  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_XFIAQwu98Rbgn2xFwXkKpw_DJnQrRE_',
  );

  bool _busy = false;
  String? _error;

  SupabaseClient get _client {
    try {
      return Supabase.instance.client;
    } catch (error) {
      throw AuthOperationException(
        userMessage: 'Service temporairement indisponible.',
        operation: 'Supabase.client',
        code: 'client_not_initialized',
        cause: error,
      );
    }
  }

  ProfessionalAuthService get _service =>
      ProfessionalAuthService(SupabaseAuthGateway(_client));

  bool get isConfigured =>
      _supabaseUrl.trim().isNotEmpty && _publishableKey.trim().isNotEmpty;
  bool get isSignedIn {
    try {
      return _client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  bool get busy => _busy;
  String? get email {
    try {
      return _client.auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  String? get uid {
    try {
      return _client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? get error => _error;

  Future<void> load() async {
    // La restauration et le rafraîchissement sont gérés par supabase_flutter.
    notifyListeners();
  }

  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    await _run(
      'signUp',
      () => _service.signUp(email: email, password: password),
    );
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _run(
      'signIn',
      () => _service.signIn(email: email, password: password),
    );
  }

  Future<String> validAccessToken() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw const AuthOperationException(
        userMessage: 'Votre session a expiré. Reconnectez-vous.',
        operation: 'validAccessToken',
        code: 'session_missing',
      );
    }
    return session.accessToken;
  }

  Future<void> signOut() async {
    await _run('signOut', _service.signOut);
  }

  Future<T> _run<T>(String operation, Future<T> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      return await action();
    } on AuthOperationException catch (error) {
      _error = error.userMessage;
      rethrow;
    } catch (error) {
      final mapped = ProfessionalAuthService.mapError(
        error,
        operation: operation,
      );
      _error = mapped.userMessage;
      throw mapped;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
