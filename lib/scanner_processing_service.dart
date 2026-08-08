import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum ProfessionalScanFilter {
  original,
  document,
  blackAndWhite,
  enhancedColor,
}

extension ProfessionalScanFilterLabel on ProfessionalScanFilter {
  String get label => switch (this) {
        ProfessionalScanFilter.original => 'Original',
        ProfessionalScanFilter.document => 'Document',
        ProfessionalScanFilter.blackAndWhite => 'Noir et blanc',
        ProfessionalScanFilter.enhancedColor => 'Couleur améliorée',
      };
}

class ScannerProcessingService {
  const ScannerProcessingService._();

  static const double pdfMargin = 18;
  static const int maximumProcessingWidth = 2400;

  static Uint8List processPage(
    Uint8List source,
    ProfessionalScanFilter filter, {
    int quarterTurns = 0,
  }) {
    if (filter == ProfessionalScanFilter.original && quarterTurns % 4 == 0) {
      return source;
    }
    var image = img.decodeImage(source);
    if (image == null) {
      throw const FormatException('Page scannée illisible.');
    }
    image = img.bakeOrientation(image);
    if (image.width > maximumProcessingWidth) {
      image = img.copyResize(
        image,
        width: maximumProcessingWidth,
        interpolation: img.Interpolation.cubic,
      );
    }

    image = switch (filter) {
      ProfessionalScanFilter.original => image,
      ProfessionalScanFilter.enhancedColor => img.adjustColor(
          img.normalize(image, min: 0, max: 255),
          contrast: 1.06,
          saturation: 1.04,
          brightness: 1.01,
        ),
      ProfessionalScanFilter.blackAndWhite => img.luminanceThreshold(
          img.normalize(img.grayscale(image), min: 0, max: 255),
          threshold: .60,
        ),
      ProfessionalScanFilter.document => img.adjustColor(
          img.normalize(img.grayscale(image), min: 0, max: 255),
          contrast: 1.10,
          brightness: 1.01,
        ),
    };

    final turns = quarterTurns % 4;
    if (turns != 0) {
      image = img.copyRotate(image, angle: turns * 90);
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }

  static Future<Uint8List> buildA4Pdf(List<Uint8List> pages) async {
    final document = pw.Document();
    for (final page in pages) {
      document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(pdfMargin),
        build: (_) => pw.Center(
          child: pw.Image(
            pw.MemoryImage(page),
            fit: pw.BoxFit.contain,
          ),
        ),
      ));
    }
    return document.save();
  }
}
