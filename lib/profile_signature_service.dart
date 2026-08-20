import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'signature_image_service.dart';

typedef SignatureDirectoryProvider = Future<Directory> Function();

abstract interface class SignatureRemoteStore {
  bool get isAvailable;

  Future<Uint8List?> download(String userId);

  Future<void> upload(String userId, Uint8List bytes);

  Future<void> delete(String userId);
}

class UnavailableSignatureRemoteStore implements SignatureRemoteStore {
  const UnavailableSignatureRemoteStore();

  @override
  bool get isAvailable => false;

  @override
  Future<Uint8List?> download(String userId) async => null;

  @override
  Future<void> upload(String userId, Uint8List bytes) async {}

  @override
  Future<void> delete(String userId) async {}
}

class SupabaseSignatureRemoteStore implements SignatureRemoteStore {
  SupabaseSignatureRemoteStore(
    this.client, {
    this.bucket = 'admin-documents',
  });

  final SupabaseClient client;
  final String bucket;

  @override
  bool get isAvailable => true;

  String pathFor(String userId) => '$userId/profile/signature.png';

  @override
  Future<Uint8List?> download(String userId) async {
    try {
      return await client.storage
          .from(bucket)
          .download(pathFor(userId))
          .timeout(const Duration(seconds: 20));
    } on StorageException catch (error) {
      if (error.statusCode == '404') return null;
      rethrow;
    }
  }

  @override
  Future<void> upload(String userId, Uint8List bytes) async {
    await client.storage
        .from(bucket)
        .uploadBinary(
          pathFor(userId),
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/png',
          ),
        )
        .timeout(const Duration(seconds: 20));
  }

  @override
  Future<void> delete(String userId) async {
    await client.storage
        .from(bucket)
        .remove([pathFor(userId)]).timeout(const Duration(seconds: 20));
  }
}

class SignatureActivationResult {
  const SignatureActivationResult({
    this.path,
    this.restoredFromRemote = false,
    this.migratedLegacy = false,
    this.remoteError,
  });

  final String? path;
  final bool restoredFromRemote;
  final bool migratedLegacy;
  final Object? remoteError;
}

class SignatureSaveResult {
  const SignatureSaveResult({
    required this.path,
    required this.remoteSaved,
    this.remoteError,
  });

  final String path;
  final bool remoteSaved;
  final Object? remoteError;
}

class SignatureDeleteResult {
  const SignatureDeleteResult({
    required this.remoteDeleted,
    this.remoteError,
  });

  final bool remoteDeleted;
  final Object? remoteError;
}

class ProfileSignatureService {
  ProfileSignatureService({
    required this.preferences,
    this.remoteStore = const UnavailableSignatureRemoteStore(),
    SignatureDirectoryProvider? directoryProvider,
  }) : directoryProvider =
            directoryProvider ?? getApplicationDocumentsDirectory;

  static const legacyPathKey = 'signaturePathV17';
  static const legacyOwnerKey = 'signatureMigrationV205UserId';
  static const legacyAutoInsertKey = 'autoInsertSignatureV17';
  static const legacyTransparentKey = 'signatureTransparentPngV1735';

  final SharedPreferences preferences;
  final SignatureRemoteStore remoteStore;
  final SignatureDirectoryProvider directoryProvider;

  String? _activeUserId;
  String _activePath = '';

  String? get activeUserId => _activeUserId;
  String get activePath => _activePath;

  static String pathPreferenceKey(String userId) => 'signature.$userId.path';

  static String autoInsertPreferenceKey(String userId) =>
      'signature.$userId.autoInsert';

  static String transparentPreferenceKey(String userId) =>
      'signature.$userId.transparentPng';

  static String pendingUploadPreferenceKey(String userId) =>
      'signature.$userId.pendingUpload';

  static String pendingDeletionPreferenceKey(String userId) =>
      'signature.$userId.pendingDeletion';

  Future<SignatureActivationResult> activateUser(String userId) async {
    _activeUserId = userId;
    _activePath = '';
    final scopedPath = preferences.getString(pathPreferenceKey(userId));
    if (preferences.getBool(pendingDeletionPreferenceKey(userId)) ?? false) {
      final expectedFile = await _fileForUser(userId);
      Object? remoteError;
      if (remoteStore.isAvailable) {
        try {
          await remoteStore.delete(userId);
          await preferences.remove(pendingDeletionPreferenceKey(userId));
        } catch (error) {
          remoteError = error;
        }
      }
      if (await expectedFile.exists()) await expectedFile.delete();
      await preferences.remove(pathPreferenceKey(userId));
      return SignatureActivationResult(remoteError: remoteError);
    }
    if (scopedPath != null) {
      final expectedFile = await _fileForUser(userId);
      if (_samePath(scopedPath, expectedFile.path) &&
          await _isValidPngFile(expectedFile)) {
        _activePath = expectedFile.path;
        Object? remoteError;
        if ((preferences.getBool(pendingUploadPreferenceKey(userId)) ??
                false) &&
            remoteStore.isAvailable) {
          try {
            await remoteStore.upload(userId, await expectedFile.readAsBytes());
            await preferences.remove(pendingUploadPreferenceKey(userId));
          } catch (error) {
            remoteError = error;
          }
        }
        return SignatureActivationResult(
          path: _activePath,
          remoteError: remoteError,
        );
      }
      await preferences.remove(pathPreferenceKey(userId));
      if (await expectedFile.exists() && !await _isValidPngFile(expectedFile)) {
        await expectedFile.delete();
      }
    }

    Object? remoteError;
    if (remoteStore.isAvailable) {
      try {
        final remoteBytes = await remoteStore.download(userId);
        if (remoteBytes != null) {
          final path = await _saveLocalPng(userId, remoteBytes);
          await preferences.remove(pendingUploadPreferenceKey(userId));
          if (preferences.getString(legacyPathKey) != null &&
              preferences.getString(legacyOwnerKey) == null) {
            await preferences.setString(legacyOwnerKey, userId);
          }
          _activePath = path;
          return SignatureActivationResult(
            path: path,
            restoredFromRemote: true,
          );
        }
      } catch (error) {
        remoteError = error;
      }
    }

    final legacyPath = preferences.getString(legacyPathKey);
    final legacyOwner = preferences.getString(legacyOwnerKey);
    final canClaimLegacy =
        legacyPath != null && (legacyOwner == null || legacyOwner == userId);
    if (canClaimLegacy) {
      final legacyFile = File(legacyPath);
      if (await legacyFile.exists()) {
        try {
          final path = await _saveLocalPng(
            userId,
            await legacyFile.readAsBytes(),
          );
          await preferences.setString(legacyOwnerKey, userId);
          final legacyAutoInsert =
              preferences.getBool(legacyAutoInsertKey) ?? false;
          await setAutoInsert(userId, legacyAutoInsert);
          _activePath = path;
          if (remoteStore.isAvailable) {
            try {
              await remoteStore.upload(userId, await File(path).readAsBytes());
              await preferences.remove(pendingUploadPreferenceKey(userId));
            } catch (error) {
              remoteError ??= error;
              await preferences.setBool(
                pendingUploadPreferenceKey(userId),
                true,
              );
            }
          } else {
            await preferences.setBool(
              pendingUploadPreferenceKey(userId),
              true,
            );
          }
          return SignatureActivationResult(
            path: path,
            migratedLegacy: true,
            remoteError: remoteError,
          );
        } catch (_) {
          // Une ancienne référence illisible n’est jamais attribuée au compte.
        }
      }
    }
    return SignatureActivationResult(remoteError: remoteError);
  }

  void deactivateUser() {
    _activeUserId = null;
    _activePath = '';
  }

  Future<SignatureSaveResult> saveForUser(
    String userId,
    Uint8List source,
  ) async {
    final path = await _saveLocalPng(userId, source);
    await preferences.remove(pendingDeletionPreferenceKey(userId));
    _activeUserId = userId;
    _activePath = path;
    Object? remoteError;
    var remoteSaved = false;
    if (remoteStore.isAvailable) {
      try {
        await remoteStore.upload(userId, await File(path).readAsBytes());
        remoteSaved = true;
        await preferences.remove(pendingUploadPreferenceKey(userId));
      } catch (error) {
        remoteError = error;
        await preferences.setBool(pendingUploadPreferenceKey(userId), true);
      }
    } else {
      await preferences.setBool(pendingUploadPreferenceKey(userId), true);
    }
    return SignatureSaveResult(
      path: path,
      remoteSaved: remoteSaved,
      remoteError: remoteError,
    );
  }

  Future<SignatureDeleteResult> deleteForUser(String userId) async {
    await preferences.setBool(pendingDeletionPreferenceKey(userId), true);
    await preferences.remove(pendingUploadPreferenceKey(userId));
    final file = await _fileForUser(userId);
    if (await file.exists()) await file.delete();
    await preferences.remove(pathPreferenceKey(userId));
    await preferences.remove(transparentPreferenceKey(userId));
    await preferences.remove(autoInsertPreferenceKey(userId));

    final legacyOwner = preferences.getString(legacyOwnerKey);
    if (legacyOwner == userId) {
      final legacyPath = preferences.getString(legacyPathKey);
      if (legacyPath != null) {
        final legacyFile = File(legacyPath);
        if (await legacyFile.exists() &&
            !_samePath(legacyFile.path, file.path)) {
          await legacyFile.delete();
        }
      }
      await preferences.remove(legacyPathKey);
      await preferences.remove(legacyOwnerKey);
      await preferences.remove(legacyTransparentKey);
      await preferences.remove(legacyAutoInsertKey);
    }

    if (_activeUserId == userId) _activePath = '';
    Object? remoteError;
    var remoteDeleted = false;
    if (remoteStore.isAvailable) {
      try {
        await remoteStore.delete(userId);
        remoteDeleted = true;
        await preferences.remove(pendingDeletionPreferenceKey(userId));
      } catch (error) {
        remoteError = error;
      }
    }
    return SignatureDeleteResult(
      remoteDeleted: remoteDeleted,
      remoteError: remoteError,
    );
  }

  bool autoInsertFor(String userId) =>
      preferences.getBool(autoInsertPreferenceKey(userId)) ?? false;

  Future<void> setAutoInsert(String userId, bool value) =>
      preferences.setBool(autoInsertPreferenceKey(userId), value);

  Future<String> _saveLocalPng(String userId, Uint8List source) async {
    final normalized =
        await SignatureImageService.normalizeSignatureToTransparentPng(source);
    final file = await _fileForUser(userId);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(normalized, flush: true);
    await preferences.setString(pathPreferenceKey(userId), file.path);
    await preferences.setBool(transparentPreferenceKey(userId), true);
    return file.path;
  }

  Future<File> _fileForUser(String userId) async {
    final base = await directoryProvider();
    final safeUserId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File(
      '${base.path}${Platform.pathSeparator}signatures'
      '${Platform.pathSeparator}$safeUserId'
      '${Platform.pathSeparator}signature.png',
    );
  }

  static bool _samePath(String first, String second) =>
      File(first).absolute.path.toLowerCase() ==
      File(second).absolute.path.toLowerCase();

  static Future<bool> _isValidPngFile(File file) async {
    try {
      if (!await file.exists() || await file.length() == 0) return false;
      final decoded = img.decodePng(await file.readAsBytes());
      return decoded != null && decoded.width > 0 && decoded.height > 0;
    } catch (_) {
      return false;
    }
  }
}
