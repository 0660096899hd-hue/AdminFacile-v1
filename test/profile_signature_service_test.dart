import 'dart:io';
import 'dart:typed_data';

import 'package:admin_facile/main.dart';
import 'package:admin_facile/profile_signature_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSignatureRemoteStore implements SignatureRemoteStore {
  final Map<String, Uint8List> files = {};
  final List<String> downloads = [];
  final List<String> uploads = [];
  final List<String> deletions = [];
  Object? downloadError;
  Object? uploadError;
  Object? deleteError;

  @override
  bool get isAvailable => true;

  @override
  Future<Uint8List?> download(String userId) async {
    downloads.add(userId);
    if (downloadError != null) throw downloadError!;
    return files[userId];
  }

  @override
  Future<void> upload(String userId, Uint8List bytes) async {
    uploads.add(userId);
    if (uploadError != null) throw uploadError!;
    files[userId] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String userId) async {
    deletions.add(userId);
    if (deleteError != null) throw deleteError!;
    files.remove(userId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late SharedPreferences preferences;
  late FakeSignatureRemoteStore remote;
  late Uint8List signatureBytes;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('profile_signature_');
    remote = FakeSignatureRemoteStore();
    signatureBytes = await File('assets/adminfacile_mark.png').readAsBytes();
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  ProfileSignatureService service() => ProfileSignatureService(
        preferences: preferences,
        remoteStore: remote,
        directoryProvider: () async => directory,
      );

  test('sauvegarde dans Documents avec une clé namespacée par UUID', () async {
    final manager = service();
    final result = await manager.saveForUser('user-a', signatureBytes);

    expect(
        result.path,
        contains(
            '${Platform.pathSeparator}signatures${Platform.pathSeparator}user-a${Platform.pathSeparator}signature.png'));
    expect(await File(result.path).exists(), isTrue);
    expect(
      preferences.getString(
        ProfileSignatureService.pathPreferenceKey('user-a'),
      ),
      result.path,
    );
    expect(remote.uploads, ['user-a']);
    expect(remote.files['user-a'], isNotEmpty);
  });

  test('logout conserve le fichier et reconnexion restaure le même utilisateur',
      () async {
    final manager = service();
    final saved = await manager.saveForUser('user-a', signatureBytes);
    manager.deactivateUser();

    expect(manager.activePath, isEmpty);
    expect(await File(saved.path).exists(), isTrue);

    final activation = await manager.activateUser('user-a');
    expect(activation.path, saved.path);
    expect(activation.restoredFromRemote, isFalse);
    expect(remote.downloads, isEmpty);
  });

  test('un second utilisateur ne voit jamais le cache du premier', () async {
    final manager = service();
    final first = await manager.saveForUser('user-a', signatureBytes);
    manager.deactivateUser();

    final second = await manager.activateUser('user-b');
    expect(second.path, isNull);
    expect(manager.activePath, isEmpty);
    expect(await File(first.path).exists(), isTrue);
    expect(
      preferences.getString(
        ProfileSignatureService.pathPreferenceKey('user-b'),
      ),
      isNull,
    );
  });

  test('fichier local absent et signature distante présente la restaure',
      () async {
    remote.files['user-a'] = signatureBytes;
    final activation = await service().activateUser('user-a');

    expect(activation.restoredFromRemote, isTrue);
    expect(activation.path, isNotNull);
    expect(await File(activation.path!).exists(), isTrue);
    expect(remote.downloads, ['user-a']);
  });

  test('fichier local invalide déclenche la restauration distante', () async {
    final expected = File(
      '${directory.path}${Platform.pathSeparator}signatures'
      '${Platform.pathSeparator}user-a${Platform.pathSeparator}signature.png',
    );
    await expected.parent.create(recursive: true);
    await expected.writeAsString('png invalide');
    await preferences.setString(
      ProfileSignatureService.pathPreferenceKey('user-a'),
      expected.path,
    );
    remote.files['user-a'] = signatureBytes;

    final activation = await service().activateUser('user-a');
    expect(activation.restoredFromRemote, isTrue);
    expect(activation.path, expected.path);
    expect(await expected.length(), greaterThan('png invalide'.length));
  });

  test('suppression explicite efface uniquement le local et distant du compte',
      () async {
    final manager = service();
    final first = await manager.saveForUser('user-a', signatureBytes);
    final second = await manager.saveForUser('user-b', signatureBytes);

    final result = await manager.deleteForUser('user-a');
    expect(result.remoteDeleted, isTrue);
    expect(await File(first.path).exists(), isFalse);
    expect(await File(second.path).exists(), isTrue);
    expect(remote.files.containsKey('user-a'), isFalse);
    expect(remote.files.containsKey('user-b'), isTrue);
    expect(remote.deletions, ['user-a']);
  });

  test('un upload en échec est retenté à la reconnexion', () async {
    remote.uploadError = StateError('hors ligne');
    final manager = service();
    final saved = await manager.saveForUser('user-a', signatureBytes);

    expect(saved.remoteSaved, isFalse);
    expect(
      preferences.getBool(
        ProfileSignatureService.pendingUploadPreferenceKey('user-a'),
      ),
      isTrue,
    );

    remote.uploadError = null;
    manager.deactivateUser();
    final activation = await manager.activateUser('user-a');
    expect(activation.path, saved.path);
    expect(remote.uploads, ['user-a', 'user-a']);
    expect(
      preferences.getBool(
        ProfileSignatureService.pendingUploadPreferenceKey('user-a'),
      ),
      isNull,
    );
  });

  test('une suppression distante en échec ne restaure pas la signature',
      () async {
    final manager = service();
    final saved = await manager.saveForUser('user-a', signatureBytes);
    remote.deleteError = StateError('hors ligne');

    final deletion = await manager.deleteForUser('user-a');
    expect(deletion.remoteDeleted, isFalse);
    expect(await File(saved.path).exists(), isFalse);

    manager.deactivateUser();
    final activation = await manager.activateUser('user-a');
    expect(activation.path, isNull);
    expect(remote.downloads, isEmpty);

    remote.deleteError = null;
    final retry = await manager.activateUser('user-a');
    expect(retry.path, isNull);
    expect(remote.files.containsKey('user-a'), isFalse);
  });

  test('migration globale préfère une signature distante existante', () async {
    final legacy = File('${directory.path}/legacy-signature.png');
    await legacy.writeAsBytes(signatureBytes);
    await preferences.setString(
      ProfileSignatureService.legacyPathKey,
      legacy.path,
    );
    remote.files['user-a'] = signatureBytes;

    final activation = await service().activateUser('user-a');
    expect(activation.restoredFromRemote, isTrue);
    expect(activation.migratedLegacy, isFalse);
    expect(
      preferences.getString(ProfileSignatureService.legacyOwnerKey),
      'user-a',
    );
    expect(await legacy.exists(), isTrue);
  });

  test('AppSettings vide seulement la session puis restaure le même UUID',
      () async {
    final settings = AppSettings(
      signatureRemoteStore: remote,
      signatureDirectoryProvider: () async => directory,
    );
    await settings.load();
    await settings.activateProfileForUser('user-a');
    await settings.saveSignatureBytes(signatureBytes);
    final path = settings.signaturePath;

    settings.deactivateProfile();
    expect(settings.signaturePath, isEmpty);
    expect(await File(path).exists(), isTrue);

    await settings.activateProfileForUser('user-a');
    expect(settings.signaturePath, path);
    expect(settings.hasSignature, isTrue);
  });
}
