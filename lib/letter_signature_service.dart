import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'signature_image_service.dart';

/// Normalise les caractères français sans perdre les accents.
///
/// Les corrections d'apostrophes absentes sont volontairement limitées aux
/// locutions sûres rencontrées dans les anciens modèles.
String normalizeFrenchTypography(String value) {
  var result = value
      .replaceAll('\u00a0', ' ')
      .replaceAll('\u202f', ' ')
      .replaceAll('\u2007', ' ')
      .replaceAll("'", '’');
  const corrections = <String, String>{
    'd information': 'd’information',
    'l expression': 'l’expression',
    'l examen': 'l’examen',
    'l électricité': 'l’électricité',
    'j ai': 'j’ai',
    'n est': 'n’est',
    'qu il': 'qu’il',
    's il': 's’il',
    'aujourd hui': 'aujourd’hui',
    'D information': 'D’information',
    'L expression': 'L’expression',
    'L examen': 'L’examen',
    'L électricité': 'L’électricité',
    'J ai': 'J’ai',
    'N est': 'N’est',
    'Qu il': 'Qu’il',
    'S il': 'S’il',
    'Aujourd hui': 'Aujourd’hui',
  };
  for (final correction in corrections.entries) {
    result = result.replaceAll(correction.key, correction.value);
  }
  return result;
}

/// Capitalise uniquement un nom de profil, y compris ses éléments composés.
String capitalizeProfileName(String value) {
  final normalized = normalizeFrenchTypography(value).trim().toLowerCase();
  if (normalized.isEmpty) return '';
  return normalized.splitMapJoin(
    RegExp(r"[\s\-’]+"),
    onMatch: (match) => match.group(0)!,
    onNonMatch: (part) => part.isEmpty
        ? part
        : '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
  );
}

/// Thème Unicode partagé par tous les PDF de lettres.
class FrenchPdfTheme {
  const FrenchPdfTheme._();

  static pw.ThemeData? _cachedTheme;

  static Future<pw.ThemeData> load() async {
    final cached = _cachedTheme;
    if (cached != null) return cached;
    final loaded = await _load();
    _cachedTheme = loaded;
    return loaded;
  }

  static Future<pw.ThemeData> _load() async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }
}

/// Source unique de vérité pour la signature et les PDF de lettres.
class LetterSignatureService {
  const LetterSignatureService._();

  static const double signatureWidth = 95;
  static const double signatureHeight = 45;
  static const double signatureFrameWidth = 145;
  static const double signatureFrameHeight = 75;

  static ({String text, bool containsSubject}) prepareContent({
    required String text,
    required bool signed,
    String senderName = '',
  }) {
    var prepared = normalizeFrenchTypography(text).trim();
    final subjectLine =
        RegExp(r'^\s*Objet\s*:\s*.+$', caseSensitive: false, multiLine: true);
    final containsSubject = subjectLine.hasMatch(prepared);
    final normalizedSenderName = capitalizeProfileName(senderName);
    if (signed && normalizedSenderName.isNotEmpty) {
      final escapedName = RegExp.escape(normalizedSenderName);
      prepared = prepared
          .replaceFirst(
            RegExp('(?:\\r?\\n)+\\s*$escapedName\\s*\$', caseSensitive: false),
            '',
          )
          .trimRight();
    }
    return (text: prepared, containsSubject: containsSubject);
  }

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
    final normalizedSubject = normalizeFrenchTypography(subject).trim();
    final normalizedNotes = normalizeFrenchTypography(notes).trim();
    final normalizedSenderName = capitalizeProfileName(senderName);
    final rawSignature = signed
        ? signatureBytes ??
            await loadSignature(
              enabled: true,
              signaturePath: signaturePath,
            )
        : null;
    Uint8List? signature;
    if (rawSignature != null) {
      try {
        signature =
            await SignatureImageService.normalizeSignatureToTransparentPng(
          rawSignature,
        );
      } catch (_) {
        signature = null;
      }
    }
    final content = prepareContent(
      text: text,
      signed: signature != null,
      senderName: normalizedSenderName,
    );
    final pdf = pw.Document(theme: await FrenchPdfTheme.load());
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(56, 52, 56, 58),
      build: (_) => [
        if (!content.containsSubject && normalizedSubject.isNotEmpty) ...[
          pw.Text('Objet : $normalizedSubject',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 18),
        ],
        pw.Text(content.text,
            style: const pw.TextStyle(fontSize: 11.5, lineSpacing: 3.5)),
        if (signed) ...[
          pw.SizedBox(height: 16),
          pw.Text('Signature de l’expéditeur',
              style:
                  const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
          pw.SizedBox(height: 5),
          pw.Container(
            width: signatureFrameWidth,
            height: signatureFrameHeight,
            padding: const pw.EdgeInsets.all(8),
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: PdfColors.grey400, width: .6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: signature != null
                ? pw.Image(pw.MemoryImage(signature),
                    width: signatureWidth,
                    height: signatureHeight,
                    fit: pw.BoxFit.contain)
                : pw.Text('Signature à apposer',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600)),
          ),
          pw.SizedBox(height: 4),
          if (normalizedSenderName.isNotEmpty)
            pw.Text(normalizedSenderName,
                style: const pw.TextStyle(fontSize: 10)),
        ],
        if (normalizedNotes.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.Text('Notes personnelles',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(normalizedNotes),
        ],
      ],
    ));
    return pdf.save();
  }
}
