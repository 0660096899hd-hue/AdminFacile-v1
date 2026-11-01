import 'dart:convert';
import 'dart:io';

void main() {
  final source = _readArb('lib/l10n/app_fr.arb');
  final catalogs = <String, Map<String, String>>{};

  for (final language in const ['ar', 'es', 'it']) {
    final translated = _readArb('lib/l10n/app_$language.arb');
    final catalog = <String, String>{};
    for (final entry in source.entries) {
      if (entry.key.startsWith('@') ||
          entry.value is! String ||
          (entry.value as String).contains('{')) {
        continue;
      }
      final localized = translated[entry.key];
      if (localized is String && localized != entry.value) {
        catalog[entry.value as String] = localized;
      }
    }
    catalogs[language] = catalog;
  }

  final output = StringBuffer()
    ..writeln('// Generated from lib/l10n/app_*.arb. Do not edit by hand.')
    ..writeln('const uiTextCatalogByLanguage = <String, Map<String, String>>{');
  for (final locale in catalogs.keys) {
    output.writeln('  ${jsonEncode(locale)}: <String, String>{');
    for (final entry in catalogs[locale]!.entries) {
      output.writeln(
        '    ${jsonEncode(entry.key)}: ${jsonEncode(entry.value)},',
      );
    }
    output.writeln('  },');
  }
  output.writeln('};');

  File('lib/l10n/ui_text_catalog_data.dart')
      .writeAsStringSync(output.toString());
}

Map<String, dynamic> _readArb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
