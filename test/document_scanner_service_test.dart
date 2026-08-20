import 'package:admin_facile/document_scanner_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('adminfacile/mlkit_document_scanner_test');
  const service = AndroidMlKitDocumentScannerService(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('V19.0 retourne toutes les images finales du scan multipage', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'scan');
      expect(call.arguments, {'pageLimit': 10});
      return {
        'imagePaths': ['page_1.jpg', 'page_2.jpg', 'page_3.jpg'],
        'pageCount': 3,
        'pdfPath': 'native.pdf',
      };
    });

    final result = await service.scan();
    expect(result, isNotNull);
    expect(result!.pageCount, 3);
    expect(result.imagePaths.last, 'page_3.jpg');
    expect(result.pdfPath, 'native.pdf');
  });

  test('PDF natif absent conserve les JPEG multipages', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {
              'imagePaths': ['page_1.jpg', 'page_2.jpg'],
              'pdfPath': null,
            });

    final result = await service.scan();
    expect(result!.pdfPath, isNull);
    expect(result.imagePaths, ['page_1.jpg', 'page_2.jpg']);
  });

  test('V19.0 traite une annulation sans erreur', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    expect(await service.scan(), isNull);
  });

  test('V19.0 transforme une indisponibilité native en fallback lisible',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'MLKIT_UNAVAILABLE');
    });

    await expectLater(
      service.scan(),
      throwsA(isA<DocumentScannerUnavailableException>().having(
        (error) => error.toString(),
        'message',
        DocumentScannerUnavailableException.message,
      )),
    );
  });

  test('V20.3.1 conserve le code de l’erreur native gérée', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'MLKIT_CLIENT_FAILED',
        message: 'Le scanner de documents est indisponible.',
      );
    });

    await expectLater(
      service.scan(),
      throwsA(isA<DocumentScannerUnavailableException>().having(
        (error) => error.code,
        'code natif',
        'MLKIT_CLIENT_FAILED',
      )),
    );
  });

  test('V20.3.1 borne la configuration multipage envoyée au MethodChannel',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'scan');
      expect(call.arguments, {'pageLimit': 10});
      return null;
    });

    expect(await service.scan(pageLimit: 99), isNull);
  });

  test('V19.0 refuse un résultat vide sans perdre le document courant',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (_) async => {'imagePaths': <String>[]});
    await expectLater(
      service.scan(),
      throwsA(isA<DocumentScannerUnavailableException>()),
    );
  });
}
