import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _prefsKey = 'adminfacileSupabaseSessionV153';

  String? _email;
  String? _uid;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  bool _busy = false;
  String? _error;

  bool get isConfigured =>
      _supabaseUrl.trim().isNotEmpty && _publishableKey.trim().isNotEmpty;
  bool get isSignedIn => _accessToken != null && _uid != null;
  bool get busy => _busy;
  String? get email => _email;
  String? get uid => _uid;
  String? get error => _error;

  String get _authBase =>
      '${_supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/auth/v1';

  Map<String, String> get _baseHeaders => {
        'apikey': _publishableKey,
        'Authorization': 'Bearer $_publishableKey',
        'Content-Type': 'application/json',
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _email = data['email'] as String?;
      _uid = data['uid'] as String?;
      _accessToken = data['accessToken'] as String?;
      _refreshToken = data['refreshToken'] as String?;
      _expiresAt = DateTime.tryParse(data['expiresAt'] as String? ?? '');
      if (_accessToken != null && _refreshToken != null) {
        await validAccessToken();
      }
    } catch (_) {
      await signOut();
    }
    notifyListeners();
  }

  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) {
      throw StateError('Supabase n’est pas configuré dans cette version.');
    }
    _setBusy(true);
    _error = null;
    try {
      final response = await http.post(
        Uri.parse('$_authBase/signup'),
        headers: _baseHeaders,
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      );
      final payload = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_friendlyAuthError(payload, response.statusCode));
      }
      await _saveSession(payload, fallbackEmail: email.trim());
      if (!isSignedIn) {
        throw StateError(
          'Compte créé. Vérifiez votre e-mail, puis revenez vous connecter.',
        );
      }
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) {
      throw StateError('Supabase n’est pas configuré dans cette version.');
    }
    _setBusy(true);
    _error = null;
    try {
      final response = await http.post(
        Uri.parse('$_authBase/token?grant_type=password'),
        headers: _baseHeaders,
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      );
      final payload = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_friendlyAuthError(payload, response.statusCode));
      }
      await _saveSession(payload, fallbackEmail: email.trim());
      if (!isSignedIn) {
        throw StateError('Connexion incomplète. Réessayez.');
      }
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<String> validAccessToken() async {
    if (!isSignedIn) throw StateError('Vous devez vous connecter.');
    if (_expiresAt != null && DateTime.now().isBefore(_expiresAt!)) {
      return _accessToken!;
    }
    if (_refreshToken == null || _refreshToken!.isEmpty) {
      await signOut();
      throw StateError('Votre session a expiré. Reconnectez-vous.');
    }

    final response = await http.post(
      Uri.parse('$_authBase/token?grant_type=refresh_token'),
      headers: _baseHeaders,
      body: jsonEncode({'refresh_token': _refreshToken}),
    );
    final payload = _decodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await signOut();
      throw StateError('Votre session a expiré. Reconnectez-vous.');
    }
    await _saveSession(payload, fallbackEmail: _email ?? '');
    return _accessToken!;
  }

  Future<void> signOut() async {
    final token = _accessToken;
    if (token != null && isConfigured) {
      try {
        await http.post(
          Uri.parse('$_authBase/logout'),
          headers: {
            ..._baseHeaders,
            'Authorization': 'Bearer $token',
          },
        );
      } catch (_) {}
    }
    _email = null;
    _uid = null;
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _error = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }

  Future<void> _saveSession(
    Map<String, dynamic> payload, {
    required String fallbackEmail,
  }) async {
    final user = payload['user'] is Map
        ? Map<String, dynamic>.from(payload['user'] as Map)
        : <String, dynamic>{};
    _email = user['email'] as String? ?? fallbackEmail;
    _uid = user['id'] as String?;
    _accessToken = payload['access_token'] as String?;
    _refreshToken = payload['refresh_token'] as String?;
    final expiresIn = int.tryParse('${payload['expires_in'] ?? 3600}') ?? 3600;
    _expiresAt = _accessToken == null
        ? null
        : DateTime.now().add(Duration(seconds: expiresIn - 60));
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'email': _email,
        'uid': _uid,
        'accessToken': _accessToken,
        'refreshToken': _refreshToken,
        'expiresAt': _expiresAt?.toIso8601String(),
      }),
    );
  }

  Map<String, dynamic> _decodeMap(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  String _friendlyAuthError(Map<String, dynamic> payload, int statusCode) {
    final message =
        '${payload['msg'] ?? payload['message'] ?? payload['error_description'] ?? ''}'
            .trim();
    final lower = message.toLowerCase();
    if (lower.contains('already registered') ||
        lower.contains('already been registered')) {
      return 'Un compte existe déjà avec cette adresse e-mail.';
    }
    if (lower.contains('invalid login credentials')) {
      return 'Adresse e-mail ou mot de passe incorrect.';
    }
    if (lower.contains('password') && lower.contains('6')) {
      return 'Le mot de passe doit contenir au moins 6 caractères.';
    }
    if (lower.contains('email') && lower.contains('invalid')) {
      return 'L’adresse e-mail n’est pas valide.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Confirmez votre adresse e-mail avant de vous connecter.';
    }
    if (statusCode == 429) {
      return 'Trop de tentatives. Réessayez un peu plus tard.';
    }
    return message.isEmpty
        ? 'Connexion impossible ($statusCode).'
        : 'Connexion impossible : $message';
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}
