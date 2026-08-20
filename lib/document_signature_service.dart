import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class NormalizedSignaturePlacement {
  const NormalizedSignaturePlacement({
    required this.pageIndex,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int pageIndex;
  final double x;
  final double y;
  final double width;
  final double height;

  NormalizedSignaturePlacement constrained() {
    final safeWidth = width.clamp(.08, 1.0).toDouble();
    final safeHeight = height.clamp(.03, 1.0).toDouble();
    return NormalizedSignaturePlacement(
      pageIndex: pageIndex,
      x: x.clamp(0, 1 - safeWidth).toDouble(),
      y: y.clamp(0, 1 - safeHeight).toDouble(),
      width: safeWidth,
      height: safeHeight,
    );
  }

  NormalizedSignaturePlacement transform({
    required double deltaX,
    required double deltaY,
    required double scale,
    required double pageAspectRatio,
    required double signatureAspectRatio,
  }) {
    final nextWidth = (width * scale).clamp(.08, .8).toDouble();
    final nextHeight = (nextWidth * pageAspectRatio / signatureAspectRatio)
        .clamp(.03, .8)
        .toDouble();
    final centerX = x + width / 2 + deltaX;
    final centerY = y + height / 2 + deltaY;
    return NormalizedSignaturePlacement(
      pageIndex: pageIndex,
      x: centerX - nextWidth / 2,
      y: centerY - nextHeight / 2,
      width: nextWidth,
      height: nextHeight,
    ).constrained();
  }

  NormalizedSignaturePlacement resizeFromBottomRight({
    required double deltaWidth,
    required double pageAspectRatio,
    required double signatureAspectRatio,
  }) {
    final heightPerWidth = pageAspectRatio / signatureAspectRatio;
    final maximumWidthFromHeight = (1 - y) / heightPerWidth;
    final maximumWidth = <double>[.8, 1 - x, maximumWidthFromHeight]
        .reduce((left, right) => left < right ? left : right);
    final safeMaximum = maximumWidth.clamp(.08, .8).toDouble();
    final nextWidth = (width + deltaWidth).clamp(.08, safeMaximum).toDouble();
    return NormalizedSignaturePlacement(
      pageIndex: pageIndex,
      x: x,
      y: y,
      width: nextWidth,
      height: nextWidth * heightPerWidth,
    ).constrained();
  }
}

class SignaturePageRect {
  const SignaturePageRect(this.left, this.top, this.width, this.height);
  final double left;
  final double top;
  final double width;
  final double height;
}

class SignatureViewportTransform {
  const SignatureViewportTransform._();

  static const double minimumZoom = 1;
  static const double maximumZoom = 4;

  static double clampZoom(double zoom) =>
      zoom.clamp(minimumZoom, maximumZoom).toDouble();

  static double screenDeltaToNormalized(
    double screenDelta, {
    required double unscaledPageExtent,
    required double zoom,
  }) {
    if (unscaledPageExtent <= 0) return 0;
    return screenDelta / (unscaledPageExtent * clampZoom(zoom));
  }
}

class DocumentSignatureService {
  const DocumentSignatureService._();

  static List<NormalizedSignaturePlacement> placementsForPage(
    List<NormalizedSignaturePlacement> placements,
    int pageIndex,
  ) =>
      placements
          .where((placement) => placement.pageIndex == pageIndex)
          .map((placement) => placement.constrained())
          .toList(growable: false);

  static SignaturePageRect pdfRectForPlacement(
    NormalizedSignaturePlacement placement, {
    required double pageWidth,
    required double pageHeight,
  }) {
    final safe = placement.constrained();
    return SignaturePageRect(
      safe.x * pageWidth,
      safe.y * pageHeight,
      safe.width * pageWidth,
      safe.height * pageHeight,
    );
  }

  static Future<String> createSignedCopy({
    required List<Uint8List> pageImages,
    required Uint8List signaturePng,
    required List<NormalizedSignaturePlacement> placements,
    required Directory outputDirectory,
  }) async {
    if (pageImages.isEmpty) {
      throw const FormatException('Le document ne contient aucune page.');
    }
    final signature = pw.MemoryImage(signaturePng);
    final document = pw.Document();
    for (var pageIndex = 0; pageIndex < pageImages.length; pageIndex++) {
      final bytes = pageImages[pageIndex];
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw FormatException('La page ${pageIndex + 1} est illisible.');
      }
      const pdfWidth = 595.28;
      final pdfHeight = pdfWidth * decoded.height / decoded.width;
      final format = PdfPageFormat(pdfWidth, pdfHeight, marginAll: 0);
      final pagePlacements = placementsForPage(placements, pageIndex);
      document.addPage(pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(children: [
          pw.Positioned.fill(
            child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
          ),
          for (final placement in pagePlacements)
            pw.Positioned(
              left: pdfRectForPlacement(placement,
                      pageWidth: pdfWidth, pageHeight: pdfHeight)
                  .left,
              top: pdfRectForPlacement(placement,
                      pageWidth: pdfWidth, pageHeight: pdfHeight)
                  .top,
              child: pw.SizedBox(
                width: pdfRectForPlacement(placement,
                        pageWidth: pdfWidth, pageHeight: pdfHeight)
                    .width,
                height: pdfRectForPlacement(placement,
                        pageWidth: pdfWidth, pageHeight: pdfHeight)
                    .height,
                child: pw.Image(signature, fit: pw.BoxFit.contain),
              ),
            ),
        ]),
      ));
    }
    await outputDirectory.create(recursive: true);
    final output = File(
      '${outputDirectory.path}/document_signe_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await output.writeAsBytes(await document.save(), flush: true);
    return output.path;
  }
}
