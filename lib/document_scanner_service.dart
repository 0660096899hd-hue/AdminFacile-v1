import 'package:flutter/services.dart';

class DocumentScanResult {
  const DocumentScanResult({
    required this.imagePaths,
    this.partialResult = false,
  });
  final List<String> imagePaths;
  final bool partialResult;

  int get pageCount => imagePaths.length;
}

abstract interface class DocumentScannerService {
  Future<DocumentScanResult?> scan({int pageLimit = 10});
}

class DocumentScannerUnavailableException implements Exception {
  const DocumentScannerUnavailableException([this.cause, this.code]);
  final Object? cause;
  final String? code;

  static const message =
      'Le scanner professionnel est momentanément indisponible. '
      'Vous pouvez utiliser Photo simple ou Importer.';

  @override
  String toString() => message;
}

class AndroidMlKitDocumentScannerService implements DocumentScannerService {
  const AndroidMlKitDocumentScannerService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('adminfacile/mlkit_document_scanner');

  final MethodChannel _channel;

  @override
  Future<DocumentScanResult?> scan({int pageLimit = 10}) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'scan',
        {'pageLimit': pageLimit.clamp(1, 10)},
      );
      if (response == null) return null;
      final paths = (response['imagePaths'] as List<dynamic>?)
              ?.whereType<String>()
              .where((path) => path.isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
      if (paths.isEmpty) {
        throw const FormatException('ML Kit n’a retourné aucune image.');
      }
      return DocumentScanResult(
        imagePaths: paths,
        partialResult: response['partialResult'] == true,
      );
    } on PlatformException catch (error) {
      throw DocumentScannerUnavailableException(error, error.code);
    } on MissingPluginException catch (error) {
      throw DocumentScannerUnavailableException(error);
    } on FormatException catch (error) {
      throw DocumentScannerUnavailableException(error);
    }
  }
}
