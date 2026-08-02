import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'account_controller.dart';

class CloudDocument {
  const CloudDocument({
    required this.name,
    required this.fullPath,
    required this.size,
    required this.updatedAt,
    required this.contentType,
  });

  final String name;
  final String fullPath;
  final int size;
  final DateTime? updatedAt;
  final String contentType;

  factory CloudDocument.fromSupabase(
    Map<String, dynamic> json, {
    required String prefix,
  }) {
    final metadata = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : <String, dynamic>{};
    final objectName = json['name'] as String? ?? '';
    return CloudDocument(
      name: objectName,
      fullPath: '$prefix/$objectName',
      size: int.tryParse('${metadata['size'] ?? 0}') ?? 0,
      updatedAt: DateTime.tryParse(
        '${json['updated_at'] ?? json['created_at'] ?? ''}',
      ),
      contentType: '${metadata['mimetype'] ?? 'application/octet-stream'}',
    );
  }
}

class CloudDocumentsController extends ChangeNotifier {
  CloudDocumentsController._();

  static final CloudDocumentsController instance = CloudDocumentsController._();

  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pmnjphgaxcmxmhurhucm.supabase.co',
  );
  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_XFIAQwu98Rbgn2xFwXkKpw_DJnQrRE_',
  );
  static const String _bucket = 'admin-documents';

  final List<CloudDocument> _documents = [];
  bool _busy = false;
  String? _error;

  List<CloudDocument> get documents => List.unmodifiable(_documents);
  bool get busy => _busy;
  String? get error => _error;
  bool get isConfigured =>
      _supabaseUrl.trim().isNotEmpty &&
      _publishableKey.trim().isNotEmpty &&
      AccountController.instance.isConfigured;

  String get _storageBase =>
      '${_supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/storage/v1';

  Future<Map<String, String>> _headers({String? contentType}) async {
    final token = await AccountController.instance.validAccessToken();
    return {
      'apikey': _publishableKey,
      'Authorization': 'Bearer $token',
      if (contentType != null) 'Content-Type': contentType,
    };
  }

  String get _prefix => 'users/${AccountController.instance.uid}/documents';

  Future<void> refresh() async {
    final account = AccountController.instance;
    if (!account.isSignedIn) {
      _documents.clear();
      notifyListeners();
      return;
    }
    _setBusy(true);
    _error = null;
    try {
      final response = await http.post(
        Uri.parse('$_storageBase/object/list/$_bucket'),
        headers: await _headers(contentType: 'application/json'),
        body: jsonEncode({
          'prefix': _prefix,
          'limit': 100,
          'offset': 0,
          'sortBy': {'column': 'created_at', 'order': 'desc'},
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_storageError(response));
      }
      final payload = jsonDecode(response.body);
      final items = payload is List ? payload : const <dynamic>[];
      _documents
        ..clear()
        ..addAll(
          items.map(
            (item) => CloudDocument.fromSupabase(
              Map<String, dynamic>.from(item as Map),
              prefix: _prefix,
            ),
          ),
        );
      _documents.sort(
        (a, b) => (b.updatedAt ?? DateTime(1970))
            .compareTo(a.updatedAt ?? DateTime(1970)),
      );
      notifyListeners();
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> uploadFile({
    required String localPath,
    required String displayName,
  }) async {
    final account = AccountController.instance;
    if (!account.isSignedIn) throw StateError('Vous devez vous connecter.');
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('Fichier introuvable.', localPath);
    }
    final fileSize = await file.length();
    if (fileSize > 20 * 1024 * 1024) {
      throw StateError('Le fichier dépasse la limite de 20 Mo.');
    }

    _setBusy(true);
    _error = null;
    try {
      final safeName = _safeName(displayName, localPath);
      final objectPath =
          '$_prefix/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final response = await http.post(
        Uri.parse('$_storageBase/object/$_bucket/${_encodePath(objectPath)}'),
        headers: {
          ...await _headers(contentType: _contentType(localPath)),
          'x-upsert': 'false',
        },
        body: await file.readAsBytes(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_storageError(response));
      }
      await refresh();
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<String> download(CloudDocument document) async {
    if (!AccountController.instance.isSignedIn) {
      throw StateError('Vous devez vous connecter.');
    }
    _setBusy(true);
    try {
      final response = await http.get(
        Uri.parse(
          '$_storageBase/object/authenticated/$_bucket/${_encodePath(document.fullPath)}',
        ),
        headers: await _headers(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_storageError(response));
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${document.name}');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> delete(CloudDocument document) async {
    if (!AccountController.instance.isSignedIn) {
      throw StateError('Vous devez vous connecter.');
    }
    _setBusy(true);
    try {
      final response = await http.delete(
        Uri.parse('$_storageBase/object/$_bucket'),
        headers: await _headers(contentType: 'application/json'),
        body: jsonEncode({
          'prefixes': [document.fullPath],
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_storageError(response));
      }
      _documents.removeWhere(
        (item) => item.fullPath == document.fullPath,
      );
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  String _safeName(String displayName, String localPath) {
    final extension = localPath.contains('.')
        ? '.${localPath.split('.').last.toLowerCase()}'
        : '';
    var name = displayName.trim().isEmpty ? 'document' : displayName.trim();
    name = name.replaceAll(RegExp(r'[^a-zA-Z0-9À-ÿ._-]+'), '_');
    if (extension.isNotEmpty && !name.toLowerCase().endsWith(extension)) {
      name += extension;
    }
    return name;
  }

  String _contentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.txt')) return 'text/plain; charset=utf-8';
    return 'application/octet-stream';
  }

  String _encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  String _storageError(http.Response response) {
    var details = '';
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map) {
        details = '${payload['message'] ?? payload['error'] ?? ''}'.trim();
      }
    } catch (_) {}
    if (response.statusCode == 401 || response.statusCode == 403) {
      return 'Accès refusé. Vérifiez les politiques Supabase Storage et reconnectez-vous.';
    }
    if (response.statusCode == 404) {
      return 'Document introuvable dans l’espace sécurisé.';
    }
    return details.isEmpty
        ? 'Erreur de stockage (${response.statusCode}).'
        : 'Erreur de stockage : $details';
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}
