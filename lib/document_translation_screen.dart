import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'document_translation_service.dart';

class DocumentTranslationScreen extends StatefulWidget {
  const DocumentTranslationScreen({
    super.key,
    required this.pageTexts,
    this.service,
  });

  final List<String> pageTexts;
  final DocumentTranslationService? service;

  @override
  State<DocumentTranslationScreen> createState() =>
      _DocumentTranslationScreenState();
}

class _DocumentTranslationScreenState extends State<DocumentTranslationScreen> {
  static const _sourcePreferenceKey = 'documentTranslation.source';
  static const _targetPreferenceKey = 'documentTranslation.target';

  late final DocumentTranslationService _service;
  DocumentTranslationLanguage _source =
      supportedDocumentTranslationLanguages[0];
  DocumentTranslationLanguage _target =
      supportedDocumentTranslationLanguages[1];
  int _selectedPage = -1;
  bool _translating = false;
  String _status =
      'Les modèles nécessaires seront téléchargés au premier usage.';
  String _translation = '';

  List<String> get _pages => widget.pageTexts.isEmpty
      ? const <String>[]
      : List<String>.unmodifiable(widget.pageTexts);

  List<String> get _selectedPages =>
      _selectedPage < 0 ? _pages : [_pages[_selectedPage]];

  String get _originalText => _joinPages(_selectedPages);

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DocumentTranslationService();
    _restoreLanguages();
  }

  Future<void> _restoreLanguages() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _source = documentTranslationLanguageForCode(
        preferences.getString(_sourcePreferenceKey),
        fallback: supportedDocumentTranslationLanguages[0],
      );
      _target = documentTranslationLanguageForCode(
        preferences.getString(_targetPreferenceKey),
        fallback: supportedDocumentTranslationLanguages[1],
      );
    });
  }

  Future<void> _selectSource(DocumentTranslationLanguage? language) async {
    if (language == null) return;
    setState(() => _source = language);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_sourcePreferenceKey, language.code);
  }

  Future<void> _selectTarget(DocumentTranslationLanguage? language) async {
    if (language == null) return;
    setState(() => _target = language);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_targetPreferenceKey, language.code);
  }

  Future<void> _translate() async {
    if (_originalText.trim().isEmpty) return;
    setState(() {
      _translating = true;
      _translation = '';
      _status = 'Préparation de la traduction locale…';
    });
    try {
      final result = await _service.translatePages(
        pageTexts: _selectedPages,
        source: _source.language,
        target: _target.language,
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _translation = result.fullText;
        _status = _source.language == _target.language
            ? 'La langue du document et la langue cible sont identiques.'
            : 'Traduction terminée sur l’appareil.';
      });
    } on DocumentTranslationModelException catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Modèle indisponible : ${error.message}');
    } on DocumentTranslationException catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Traduction impossible : ${error.message}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Traduction impossible : $error');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _copyTranslation() async {
    if (_translation.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _translation));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Traduction copiée')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Traduire le document')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_pages.length > 1) ...[
              DropdownButtonFormField<int>(
                key: const Key('document-translation-page'),
                initialValue: _selectedPage,
                decoration: const InputDecoration(
                  labelText: 'Partie à traduire',
                ),
                items: [
                  const DropdownMenuItem(
                    value: -1,
                    child: Text('Document complet'),
                  ),
                  for (var index = 0; index < _pages.length; index++)
                    DropdownMenuItem(
                      value: index,
                      child: Text('Page ${index + 1}'),
                    ),
                ],
                onChanged: _translating
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedPage = value;
                          _translation = '';
                        });
                      },
              ),
              const SizedBox(height: 16),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final dropdowns = [
                  DropdownButtonFormField<DocumentTranslationLanguage>(
                    key: ValueKey(
                      'document-translation-source-${_source.code}',
                    ),
                    initialValue: _source,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Langue du document',
                    ),
                    items: _languageItems(),
                    onChanged: _translating ? null : _selectSource,
                  ),
                  DropdownButtonFormField<DocumentTranslationLanguage>(
                    key: ValueKey(
                      'document-translation-target-${_target.code}',
                    ),
                    initialValue: _target,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Traduire vers',
                    ),
                    items: _languageItems(),
                    onChanged: _translating ? null : _selectTarget,
                  ),
                ];
                if (constraints.maxWidth < 560) {
                  return Column(
                    children: [
                      dropdowns[0],
                      const SizedBox(height: 12),
                      dropdowns[1],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: dropdowns[0]),
                    const SizedBox(width: 12),
                    Expanded(child: dropdowns[1]),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('document-translation-submit'),
              onPressed: _translating || _originalText.trim().isEmpty
                  ? null
                  : _translate,
              icon: _translating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate_rounded),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  _translating ? 'Traduction en cours…' : 'Traduire',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(_status, key: const Key('document-translation-status')),
            const SizedBox(height: 18),
            _TranslationTextZone(
              title: 'Texte original',
              text: _originalText,
              key: const Key('document-translation-original'),
            ),
            const SizedBox(height: 14),
            _TranslationTextZone(
              title: 'Traduction',
              text: _translation.isEmpty
                  ? 'La traduction apparaîtra ici.'
                  : _translation,
              key: const Key('document-translation-result'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('document-translation-copy'),
              onPressed: _translation.isEmpty ? null : _copyTranslation,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copier la traduction'),
            ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<DocumentTranslationLanguage>> _languageItems() =>
      supportedDocumentTranslationLanguages
          .map(
            (language) => DropdownMenuItem(
              value: language,
              child: Text(language.label),
            ),
          )
          .toList(growable: false);

  static String _joinPages(List<String> pages) {
    if (pages.isEmpty) return '';
    if (pages.length == 1) return pages.single;
    return [
      for (var index = 0; index < pages.length; index++)
        if (index == 0)
          pages[index]
        else
          '\n\n--- Page ${index + 1} ---\n\n${pages[index]}',
    ].join();
  }
}

class _TranslationTextZone extends StatelessWidget {
  const _TranslationTextZone({
    super.key,
    required this.title,
    required this.text,
  });

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            SelectableText(text),
          ],
        ),
      ),
    );
  }
}
