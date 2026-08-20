import 'dart:io';
import 'dart:typed_data';

import 'package:admin_facile/scanner_processing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory root;
  late Directory persistent;
  late Directory fallback;
  late List<String> jpegPaths;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('adminfacile-pdf-test-');
    persistent = Directory('${root.path}/persistent');
    fallback = Directory('${root.path}/fallback');
    jpegPaths = [];
    for (var index = 0; index < 2; index++) {
      final file = File('${root.path}/page_$index.jpg');
      await file.writeAsBytes(
        img.encodeJpg(img.Image(width: 40, height: 60)),
      );
      jpegPaths.add(file.path);
    }
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('le PDF natif accessible est copié et utilisé', () async {
    final native = File('${root.path}/native.pdf');
    await native.writeAsBytes(Uint8List.fromList('%PDF-native'.codeUnits));

    final result = await ScannerProcessingService.preparePdf(
      nativePdfPath: native.path,
      jpegPaths: jpegPaths,
      persistentDirectory: persistent,
      fallbackDirectory: fallback,
    );

    expect(result.usedNativePdf, isTrue);
    expect(result.path, startsWith(persistent.path));
    expect(await File(result.path).readAsBytes(), await native.readAsBytes());
    expect(jpegPaths.map(File.new).every((file) => file.existsSync()), isTrue);
  });

  test('PDF absent reconstruit un PDF depuis tous les JPEG', () async {
    final result = await ScannerProcessingService.preparePdf(
      nativePdfPath: null,
      jpegPaths: jpegPaths,
      persistentDirectory: persistent,
      fallbackDirectory: fallback,
    );

    expect(result.usedNativePdf, isFalse);
    expect(result.path, startsWith(fallback.path));
    expect(String.fromCharCodes((await File(result.path).readAsBytes()).take(4)),
        '%PDF');
    expect(jpegPaths.map(File.new).every((file) => file.existsSync()), isTrue);
  });

  test('PDF inaccessible retombe sur les JPEG sans crash', () async {
    final result = await ScannerProcessingService.preparePdf(
      nativePdfPath: '${root.path}/missing.pdf',
      jpegPaths: jpegPaths,
      persistentDirectory: persistent,
      fallbackDirectory: fallback,
    );

    expect(result.usedNativePdf, isFalse);
    expect(await File(result.path).length(), greaterThan(0));
  });
}
