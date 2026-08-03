import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Source unique de vérité pour la signature et les PDF de lettres.
class LetterSignatureService {
  const LetterSignatureService._();

  static bool defaultForLetter({
    required bool autoInsert,
    required bool hasSignature,
  }) =>
      autoInsert && hasSignature;

  static Future<Uint8List?> loadSignature({
    required bool enabled,
    required String signaturePath,
  }) async {
    if (!enabled || signaturePath.trim().isEmpty) return null;
    final file = File(signaturePath);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static Future<Uint8List> buildLetterPdf({
    required String text,
    required String subject,
    required bool signed,
    String signaturePath = '',
    Uint8List? signatureBytes,
    String senderName = '',
    String? heading,
    String notes = '',
  }) async {
    final signature = signed
        ? signatureBytes ??
            await loadSignature(
              enabled: true,
              signaturePath: signaturePath,
            )
        : null;
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(56, 52, 56, 58),
      build: (_) => [
        if (heading != null && heading.trim().isNotEmpty) ...[
          pw.Text(heading.trim(),
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
        ],
        if (subject.trim().isNotEmpty) ...[
          pw.Text('Objet : ${subject.trim()}',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 18),
        ],
        pw.Text(text.trim(),
            style: const pw.TextStyle(fontSize: 11.5, lineSpacing: 3.5)),
        if (signature != null) ...[
          pw.SizedBox(height: 16),
          pw.Image(pw.MemoryImage(signature),
              width: 130, height: 55, fit: pw.BoxFit.contain),
          if (senderName.trim().isNotEmpty)
            pw.Text(senderName.trim(), style: const pw.TextStyle(fontSize: 10)),
        ],
        if (notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.Text('Notes personnelles',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(notes.trim()),
        ],
      ],
    ));
    return pdf.save();
  }
}
