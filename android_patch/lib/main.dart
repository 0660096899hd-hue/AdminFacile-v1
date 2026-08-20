import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(AdminFacileApp(settings: settings));
}

class AppSettings extends ChangeNotifier {
  SharedPreferences? _prefs;
  String firstName = '';
  String lastName = '';
  String address = '';
  String postalCode = '';
  String city = '';
  String phone = '';
  String email = '';
  bool comfortMode = false;

  String get greeting => firstName.isEmpty ? 'Bienvenue' : 'Bonjour $firstName';

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    firstName = _prefs!.getString('firstName') ?? '';
    lastName = _prefs!.getString('lastName') ?? '';
    address = _prefs!.getString('address') ?? '';
    postalCode = _prefs!.getString('postalCode') ?? '';
    city = _prefs!.getString('city') ?? '';
    phone = _prefs!.getString('phone') ?? '';
    email = _prefs!.getString('email') ?? '';
    comfortMode = _prefs!.getBool('comfortMode') ?? false;
  }

  Future<void> saveProfile(Map<String, String> values) async {
    firstName = values['firstName']!.trim();
    lastName = values['lastName']!.trim();
    address = values['address']!.trim();
    postalCode = values['postalCode']!.trim();
    city = values['city']!.trim();
    phone = values['phone']!.trim();
    email = values['email']!.trim();
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    for (final entry in values.entries) {
      await prefs.setString(entry.key, entry.value.trim());
    }
    notifyListeners();
  }

  Future<void> setComfortMode(bool value) async {
    comfortMode = value;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setBool('comfortMode', value);
    notifyListeners();
  }
}

class AdminFacileApp extends StatelessWidget {
  const AdminFacileApp({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AdminFacile',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF175C8C)),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F7FA),
          cardTheme: const CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
          textTheme: settings.comfortMode
              ? const TextTheme(
                  bodyMedium: TextStyle(fontSize: 18),
                  bodyLarge: TextStyle(fontSize: 20),
                  titleMedium:
                      TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                  titleLarge:
                      TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                )
              : null,
        ),
        home: AppShell(settings: settings),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        settings: widget.settings,
        openScanner: () => setState(() => index = 1),
        openLetters: () => setState(() => index = 2),
        openTranslator: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TranslationScreen()),
        ),
        openDictation: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DictationScreen()),
        ),
      ),
      const ScannerScreen(),
      LetterLibraryScreen(settings: widget.settings),
      ProfileScreen(settings: widget.settings),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        height: widget.settings.comfortMode ? 82 : 68,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Accueil'),
          NavigationDestination(
              icon: Icon(Icons.document_scanner_outlined),
              selectedIcon: Icon(Icons.document_scanner),
              label: 'Scanner'),
          NavigationDestination(
              icon: Icon(Icons.edit_note_outlined),
              selectedIcon: Icon(Icons.edit_note),
              label: 'Lettres'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.openScanner,
    required this.openLetters,
    required this.openTranslator,
    required this.openDictation,
  });
  final AppSettings settings;
  final VoidCallback openScanner;
  final VoidCallback openLetters;
  final VoidCallback openTranslator;
  final VoidCallback openDictation;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.support_agent,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(settings.greeting,
                      style: Theme.of(context).textTheme.titleLarge),
                  const Text('Votre assistant administratif'),
                ])),
          ]),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF175C8C), Color(0xFF2E82B7)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 30),
              const SizedBox(height: 12),
              const Text('Que souhaitez-vous faire ?',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'Scannez un courrier ou créez une réponse en quelques étapes.',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF175C8C)),
                onPressed: openScanner,
                icon: const Icon(Icons.document_scanner),
                label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Scanner un courrier')),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Text('Actions rapides',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final width = (constraints.maxWidth - 14) / 2;
            return Wrap(spacing: 14, runSpacing: 14, children: [
              QuickCard(
                  width: width,
                  icon: Icons.document_scanner_outlined,
                  title: 'Scanner',
                  subtitle: 'Lire un courrier',
                  onTap: openScanner),
              QuickCard(
                  width: width,
                  icon: Icons.edit_document,
                  title: 'Créer',
                  subtitle: 'Rédiger une lettre',
                  onTap: openLetters),
              QuickCard(
                  width: width,
                  icon: Icons.translate,
                  title: 'Traduire',
                  subtitle: 'Traduction locale',
                  onTap: openTranslator),
              QuickCard(
                  width: width,
                  icon: Icons.mic_none,
                  title: 'Dicter',
                  subtitle: 'Écrire avec la voix',
                  onTap: openDictation),
            ]);
          }),
          const SizedBox(height: 24),
          const PrivacyCard(),
        ],
      ),
    );
  }
}

class QuickCard extends StatelessWidget {
  const QuickCard(
      {super.key,
      required this.width,
      required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
            child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(radius: 23, child: Icon(icon)),
                    const SizedBox(height: 14),
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(subtitle),
                  ])),
        )),
      );
}

class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key});
  @override
  Widget build(BuildContext context) => const Card(
        color: Color(0xFFE8F4EC),
        child: Padding(
            padding: EdgeInsets.all(18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.verified_user_outlined, color: Color(0xFF277A45)),
              SizedBox(width: 12),
              Expanded(
                  child: Text(
                      'Le scanner reconnaît le texte sur votre téléphone. Cette V2.2 traite les courriers et les traductions directement sur le téléphone après téléchargement des modèles de langue.')),
            ])),
      );
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final picker = ImagePicker();
  final textController = TextEditingController();
  bool processing = false;
  String? imagePath;

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  Future<void> _readImage(String path) async {
    setState(() {
      processing = true;
      imagePath = path;
      textController.clear();
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(path));
      if (!mounted) return;
      textController.text = result.text.trim().isEmpty
          ? 'Aucun texte reconnu. Reprenez la photo avec une meilleure lumière.'
          : result.text.trim();
      setState(() {});
    } finally {
      await recognizer.close();
      if (mounted) setState(() => processing = false);
    }
  }

  Future<void> pickAndRead(ImageSource source) async {
    try {
      final file = await picker.pickImage(
          source: source, imageQuality: 92, maxWidth: 2200);
      if (file == null) return;
      await _readImage(file.path);
    } catch (error) {
      if (!mounted) return;
      setState(() => processing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lecture impossible : $error')));
    }
  }

  Future<void> importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'txt'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final selected = result.files.single;
      final path = selected.path;
      if (path == null) {
        throw Exception('Le chemin du fichier est inaccessible.');
      }
      final extension = (selected.extension ?? '').toLowerCase();
      if (extension == 'txt') {
        final content = await File(path).readAsString();
        if (!mounted) return;
        setState(() {
          imagePath = null;
          textController.text = content;
        });
      } else {
        await _readImage(path);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import impossible : $error')),
      );
    }
  }

  void prepareReply() {
    if (textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ajoutez d’abord un texte ou un courrier.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReplyScreen(sourceText: textController.text)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Scanner ou importer',
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text(
          'Photographiez un courrier, importez une image ou un fichier texte déjà présent sur l’appareil.'),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
            child: FilledButton.icon(
          onPressed: processing ? null : () => pickAndRead(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Photo')),
        )),
        const SizedBox(width: 10),
        Expanded(
            child: OutlinedButton.icon(
          onPressed: processing ? null : () => pickAndRead(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Galerie')),
        )),
      ]),
      const SizedBox(height: 10),
      SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: processing ? null : importFile,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Importer depuis Mes fichiers')),
          )),
      const SizedBox(height: 20),
      if (processing)
        const Card(
            child: Padding(
                padding: EdgeInsets.all(30),
                child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Lecture du courrier en cours…'),
                ]))),
      if (!processing && imagePath != null) ...[
        ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(File(imagePath!),
                height: 220, width: double.infinity, fit: BoxFit.cover)),
        const SizedBox(height: 18),
      ],
      TextField(
        controller: textController,
        minLines: 10,
        maxLines: 18,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Texte du courrier scanné',
          alignLabelWithHint: true,
          hintText: 'Le texte reconnu apparaîtra ici.',
        ),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
            child: OutlinedButton.icon(
          onPressed: textController.text.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(
                      ClipboardData(text: textController.text));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Texte copié')));
                },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copier'),
        )),
        const SizedBox(width: 12),
        Expanded(
            child: FilledButton.icon(
                onPressed: prepareReply,
                icon: const Icon(Icons.reply),
                label: const Text('Répondre'))),
      ]),
      const SizedBox(height: 18),
      const PrivacyCard(),
    ]));
  }
}

class DictationScreen extends StatefulWidget {
  const DictationScreen({super.key});

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  final SpeechToText _speech = SpeechToText();
  final TextEditingController _controller = TextEditingController();
  bool _available = false;
  bool _listening = false;
  bool _initializing = true;
  String _prefix = '';
  String? _localeId;
  String _status = 'Initialisation du microphone…';

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize(
        debugLogging: true,
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            _listening = status == 'listening';
            _status = _listening
                ? 'Je vous écoute… Parlez clairement.'
                : 'Microphone prêt';
          });
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _status = 'Erreur : ${error.errorMsg}';
          });
        },
      );
      String? french;
      if (available) {
        final locales = await _speech.locales();
        for (final locale in locales) {
          if (locale.localeId.toLowerCase().startsWith('fr')) {
            french = locale.localeId;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _available = available;
        _localeId = french;
        _initializing = false;
        _status = available
            ? 'Microphone prêt${french == null ? '' : ' – français détecté'}'
            : 'Reconnaissance vocale indisponible ou permission refusée';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _available = false;
        _status = 'Impossible d’initialiser le microphone : $error';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_initializing) return;
    if (!_available) {
      await _initializeSpeech();
      return;
    }
    if (_speech.isListening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _prefix = _controller.text.trim();
    await _speech.listen(
      onResult: (result) {
        final spoken = result.recognizedWords.trim();
        final separator = _prefix.isEmpty || spoken.isEmpty ? '' : '\n';
        _controller.text = '$_prefix$separator$spoken';
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
        if (mounted) setState(() {});
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
    if (mounted) {
      setState(() {
        _listening = true;
        _status = 'Je vous écoute… Parlez clairement.';
      });
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dictée vocale')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              color: _listening
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      _listening ? Icons.graphic_eq : Icons.mic_none,
                      size: 34,
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Text(_status)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 12,
              maxLines: 22,
              decoration: const InputDecoration(
                labelText: 'Texte dicté et modifiable',
                alignLabelWithHint: true,
                hintText: 'Appuyez sur le microphone, puis commencez à parler.',
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _initializing ? null : _toggleListening,
              icon: Icon(_listening ? Icons.stop_circle : Icons.mic),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Text(
                    _listening ? 'Arrêter la dictée' : 'Commencer la dictée'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _controller.text.isEmpty
                        ? null
                        : () => setState(() => _controller.clear()),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Effacer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _controller.text.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: _controller.text),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Texte copié')),
                            );
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copier'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Android peut arrêter la reconnaissance après quelques secondes de silence. '
              'Appuyez de nouveau sur le microphone pour continuer votre texte.',
            ),
          ],
        ),
      ),
    );
  }
}

class TranslationLanguage {
  const TranslationLanguage(this.label, this.language);
  final String label;
  final TranslateLanguage language;
}

class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  static const languages = [
    TranslationLanguage('Français', TranslateLanguage.french),
    TranslationLanguage('Anglais', TranslateLanguage.english),
    TranslationLanguage('Arabe', TranslateLanguage.arabic),
    TranslationLanguage('Espagnol', TranslateLanguage.spanish),
    TranslationLanguage('Allemand', TranslateLanguage.german),
    TranslationLanguage('Italien', TranslateLanguage.italian),
    TranslationLanguage('Portugais', TranslateLanguage.portuguese),
    TranslationLanguage('Turc', TranslateLanguage.turkish),
  ];

  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _resultController = TextEditingController();
  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();
  TranslationLanguage _source = languages[0];
  TranslationLanguage _target = languages[1];
  bool _translating = false;
  String _status = 'Les modèles de langue seront téléchargés au premier usage.';

  @override
  void dispose() {
    _sourceController.dispose();
    _resultController.dispose();
    super.dispose();
  }

  Future<void> _ensureModel(TranslateLanguage language) async {
    final code = language.bcpCode;
    final downloaded = await _modelManager.isModelDownloaded(code);
    if (!downloaded) {
      if (mounted) {
        setState(() => _status = 'Téléchargement du modèle $code…');
      }
      final success = await _modelManager.downloadModel(code);
      if (!success) {
        throw Exception('Le modèle $code n’a pas pu être téléchargé.');
      }
    }
  }

  Future<void> _translate() async {
    final text = _sourceController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisissez ou collez un texte.')),
      );
      return;
    }
    if (_source.language == _target.language) {
      setState(() {
        _resultController.text = text;
        _status = 'La langue source et la langue cible sont identiques.';
      });
      return;
    }
    setState(() {
      _translating = true;
      _status = 'Préparation de la traduction…';
    });
    OnDeviceTranslator? translator;
    try {
      await _ensureModel(_source.language);
      await _ensureModel(_target.language);
      translator = OnDeviceTranslator(
        sourceLanguage: _source.language,
        targetLanguage: _target.language,
      );
      final translated = await translator.translateText(text);
      if (!mounted) return;
      setState(() {
        _resultController.text = translated;
        _status = 'Traduction terminée et traitée sur cet appareil.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Erreur de traduction : $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Traduction impossible : $error')),
      );
    } finally {
      translator?.close();
      if (mounted) setState(() => _translating = false);
    }
  }

  void _swapLanguages() {
    setState(() {
      final oldSource = _source;
      _source = _target;
      _target = oldSource;
      final oldText = _sourceController.text;
      _sourceController.text = _resultController.text;
      _resultController.text = oldText;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Traduire un texte')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TranslationLanguage>(
                    initialValue: _source,
                    decoration: const InputDecoration(labelText: 'Depuis'),
                    items: languages
                        .map((item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _source = value);
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Inverser les langues',
                  onPressed: _swapLanguages,
                  icon: const Icon(Icons.swap_horiz),
                ),
                Expanded(
                  child: DropdownButtonFormField<TranslationLanguage>(
                    initialValue: _target,
                    decoration: const InputDecoration(labelText: 'Vers'),
                    items: languages
                        .map((item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _target = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sourceController,
              minLines: 7,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Texte à traduire',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _translating ? null : _translate,
              icon: _translating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Text(_translating ? 'Traduction en cours…' : 'Traduire'),
              ),
            ),
            const SizedBox(height: 12),
            Text(_status),
            const SizedBox(height: 16),
            TextField(
              controller: _resultController,
              minLines: 7,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Traduction',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _resultController.text.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: _resultController.text),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Traduction copiée')),
                      );
                    },
              icon: const Icon(Icons.copy),
              label: const Text('Copier la traduction'),
            ),
            const SizedBox(height: 18),
            const PrivacyCard(),
          ],
        ),
      ),
    );
  }
}

enum ReplyIntent { understand, agree, disagree, askDelay, sendDocuments }

extension ReplyIntentInfo on ReplyIntent {
  String get label => switch (this) {
        ReplyIntent.understand => 'Mieux comprendre',
        ReplyIntent.agree => 'Je suis d’accord',
        ReplyIntent.disagree => 'Je ne suis pas d’accord',
        ReplyIntent.askDelay => 'Demander un délai',
        ReplyIntent.sendDocuments => 'Envoyer les documents',
      };
  IconData get icon => switch (this) {
        ReplyIntent.understand => Icons.lightbulb_outline,
        ReplyIntent.agree => Icons.thumb_up_alt_outlined,
        ReplyIntent.disagree => Icons.report_problem_outlined,
        ReplyIntent.askDelay => Icons.schedule_outlined,
        ReplyIntent.sendDocuments => Icons.attach_file,
      };
}

class ReplyScreen extends StatefulWidget {
  const ReplyScreen({super.key, required this.sourceText});
  final String sourceText;
  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  ReplyIntent intent = ReplyIntent.askDelay;
  final details = TextEditingController();
  final draft = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;
  bool _initializingSpeech = true;
  String? _localeId;
  String _spokenPrefix = '';

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _listening = status == 'listening');
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _listening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Microphone : ${error.errorMsg}')),
          );
        },
      );
      String? french;
      if (available) {
        final locales = await _speech.locales();
        for (final locale in locales) {
          if (locale.localeId.toLowerCase().startsWith('fr')) {
            french = locale.localeId;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _speechAvailable = available;
        _localeId = french;
        _initializingSpeech = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _initializingSpeech = false;
      });
    }
  }

  Future<void> _toggleReplyDictation() async {
    if (_initializingSpeech) return;
    if (!_speechAvailable) {
      await _initializeSpeech();
      if (!_speechAvailable && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La reconnaissance vocale n’est pas disponible.'),
          ),
        );
      }
      return;
    }
    if (_speech.isListening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _spokenPrefix = draft.text.trim();
    await _speech.listen(
      onResult: (result) {
        final spoken = result.recognizedWords.trim();
        final separator = _spokenPrefix.isEmpty || spoken.isEmpty ? '' : '\n';
        draft.text = '$_spokenPrefix$separator$spoken';
        draft.selection = TextSelection.collapsed(offset: draft.text.length);
        if (mounted) setState(() {});
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
    if (mounted) setState(() => _listening = true);
  }

  @override
  void dispose() {
    _speech.cancel();
    details.dispose();
    draft.dispose();
    super.dispose();
  }

  void generate() {
    final body = switch (intent) {
      ReplyIntent.understand =>
        'Je vous remercie de bien vouloir m’apporter des précisions complémentaires afin que je puisse comprendre les démarches attendues.',
      ReplyIntent.agree =>
        'Je vous confirme avoir pris connaissance de votre courrier et accepter la proposition ou la demande indiquée.',
      ReplyIntent.disagree =>
        'Je conteste les éléments indiqués et vous remercie de réexaminer ma situation ainsi que de me transmettre les justificatifs utiles.',
      ReplyIntent.askDelay =>
        'J’ai bien reçu votre courrier. En raison de ma situation actuelle, je sollicite un délai supplémentaire pour effectuer les démarches demandées.',
      ReplyIntent.sendDocuments =>
        'Veuillez trouver ci-joint les documents demandés. Je vous remercie de bien vouloir confirmer leur bonne réception.',
    };
    final extra = details.text.trim();
    draft.text = '''Objet : Réponse à votre courrier

Madame, Monsieur,

$body

${extra.isEmpty ? '' : 'Précisions complémentaires :\n$extra\n\n'}Je reste à votre disposition pour tout complément d’information.

Cordialement,''';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Préparer une réponse')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
            'Quelle réponse souhaitez-vous envoyer ?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ReplyIntent.values.map((item) {
              return ChoiceChip(
                selected: intent == item,
                avatar: Icon(item.icon, size: 20),
                label: Text(item.label),
                onSelected: (_) => setState(() => intent = item),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: details,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Précisions facultatives',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Générer la réponse'),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: draft,
            minLines: 10,
            maxLines: 18,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Votre réponse',
              alignLabelWithHint: true,
              hintText: 'Écrivez votre réponse ou utilisez le microphone.',
              suffixIcon: IconButton(
                tooltip: _listening ? 'Arrêter la dictée' : 'Dicter la réponse',
                onPressed: _initializingSpeech ? null : _toggleReplyDictation,
                icon: Icon(_listening ? Icons.stop_circle : Icons.mic),
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _initializingSpeech ? null : _toggleReplyDictation,
            icon: Icon(_listening ? Icons.stop_circle : Icons.mic_none),
            label: Text(
              _listening ? 'Arrêter la dictée' : 'Dicter ma réponse',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: draft.text.trim().isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: draft.text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Réponse copiée')),
                    );
                  },
            icon: const Icon(Icons.copy),
            label: const Text('Copier la réponse'),
          ),
          const SizedBox(height: 18),
          const Text(
            'Modèle général : vérifiez toujours les dates, montants, références et obligations du courrier original.',
          ),
        ]),
      );
}

enum LetterTemplate {
  internet,
  insurance,
  refund,
  paymentDelay,
  employer,
  complaint
}

extension LetterTemplateInfo on LetterTemplate {
  String get title => switch (this) {
        LetterTemplate.internet => 'Résiliation Internet / téléphone',
        LetterTemplate.insurance => 'Résiliation d’assurance',
        LetterTemplate.refund => 'Demande de remboursement',
        LetterTemplate.paymentDelay => 'Demande de délai de paiement',
        LetterTemplate.employer => 'Demande à l’employeur',
        LetterTemplate.complaint => 'Réclamation générale',
      };
  String get category => switch (this) {
        LetterTemplate.internet => 'Télécom',
        LetterTemplate.insurance => 'Assurance',
        LetterTemplate.refund || LetterTemplate.complaint => 'Consommation',
        LetterTemplate.paymentDelay => 'Finances',
        LetterTemplate.employer => 'Travail',
      };
  IconData get icon => switch (this) {
        LetterTemplate.internet => Icons.router_outlined,
        LetterTemplate.insurance => Icons.shield_outlined,
        LetterTemplate.refund => Icons.euro,
        LetterTemplate.paymentDelay => Icons.calendar_month_outlined,
        LetterTemplate.employer => Icons.badge_outlined,
        LetterTemplate.complaint => Icons.feedback_outlined,
      };
}

class LetterLibraryScreen extends StatelessWidget {
  const LetterLibraryScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) => SafeArea(
          child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Modèles de lettres',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Choisissez un modèle et personnalisez-le.'),
          const SizedBox(height: 20),
          ...LetterTemplate.values.map((template) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                    child: ListTile(
                  minVerticalPadding: 18,
                  leading: CircleAvatar(child: Icon(template.icon)),
                  title: Text(template.title),
                  subtitle: Text(template.category),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LetterFormScreen(
                          settings: settings, template: template))),
                )),
              )),
        ],
      ));
}

class LetterFormScreen extends StatefulWidget {
  const LetterFormScreen(
      {super.key, required this.settings, required this.template});
  final AppSettings settings;
  final LetterTemplate template;
  @override
  State<LetterFormScreen> createState() => _LetterFormScreenState();
}

class _LetterFormScreenState extends State<LetterFormScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController firstName;
  late final TextEditingController lastName;
  late final TextEditingController address;
  late final TextEditingController postalCode;
  late final TextEditingController city;
  final recipient = TextEditingController();
  final recipientAddress = TextEditingController();
  final reference = TextEditingController();
  final details = TextEditingController();

  @override
  void initState() {
    super.initState();
    firstName = TextEditingController(text: widget.settings.firstName);
    lastName = TextEditingController(text: widget.settings.lastName);
    address = TextEditingController(text: widget.settings.address);
    postalCode = TextEditingController(text: widget.settings.postalCode);
    city = TextEditingController(text: widget.settings.city);
  }

  @override
  void dispose() {
    for (final c in [
      firstName,
      lastName,
      address,
      postalCode,
      city,
      recipient,
      recipientAddress,
      reference,
      details
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? requiredField(String? value) =>
      value == null || value.trim().isEmpty ? 'Champ obligatoire' : null;

  void generate() {
    if (!formKey.currentState!.validate()) return;
    final letter = LetterGenerator.generate(
      template: widget.template,
      firstName: firstName.text,
      lastName: lastName.text,
      address: address.text,
      postalCode: postalCode.text,
      city: city.text,
      recipient: recipient.text,
      recipientAddress: recipientAddress.text,
      reference: reference.text,
      details: details.text,
    );
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LetterPreviewScreen(letter: letter)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.template.title)),
        body: Form(
            key: formKey,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text('Vos coordonnées',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextFormField(
                        controller: firstName,
                        validator: requiredField,
                        decoration:
                            const InputDecoration(labelText: 'Prénom'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextFormField(
                        controller: lastName,
                        validator: requiredField,
                        decoration: const InputDecoration(labelText: 'Nom'))),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                  controller: address,
                  validator: requiredField,
                  decoration: const InputDecoration(labelText: 'Adresse')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    flex: 2,
                    child: TextFormField(
                        controller: postalCode,
                        validator: requiredField,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Code postal'))),
                const SizedBox(width: 12),
                Expanded(
                    flex: 3,
                    child: TextFormField(
                        controller: city,
                        validator: requiredField,
                        decoration: const InputDecoration(labelText: 'Ville'))),
              ]),
              const SizedBox(height: 22),
              Text('Destinataire et demande',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                  controller: recipient,
                  validator: requiredField,
                  decoration: const InputDecoration(
                      labelText: 'Organisme, entreprise ou employeur')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: recipientAddress,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Adresse du destinataire (facultatif)')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: reference,
                  decoration: const InputDecoration(
                      labelText: 'Référence ou numéro de contrat')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: details,
                  maxLines: 5,
                  decoration: const InputDecoration(
                      labelText: 'Précisez votre demande',
                      alignLabelWithHint: true)),
              const SizedBox(height: 20),
              FilledButton.icon(
                  onPressed: generate,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Générer la lettre'))),
            ])),
      );
}

class LetterPreviewScreen extends StatefulWidget {
  const LetterPreviewScreen({super.key, required this.letter});
  final String letter;
  @override
  State<LetterPreviewScreen> createState() => _LetterPreviewScreenState();
}

class _LetterPreviewScreenState extends State<LetterPreviewScreen> {
  late final TextEditingController controller =
      TextEditingController(text: widget.letter);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Aperçu')),
        body: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Expanded(
                      child: TextField(
                          controller: controller,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                              labelText: 'Lettre modifiable',
                              alignLabelWithHint: true))),
                  const SizedBox(height: 14),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: controller.text));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Lettre copiée')));
                          },
                          icon: const Icon(Icons.copy),
                          label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Text('Copier la lettre')))),
                ]))),
      );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.settings});
  final AppSettings settings;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Map<String, TextEditingController> fields;

  @override
  void initState() {
    super.initState();
    fields = {
      'firstName': TextEditingController(text: widget.settings.firstName),
      'lastName': TextEditingController(text: widget.settings.lastName),
      'address': TextEditingController(text: widget.settings.address),
      'postalCode': TextEditingController(text: widget.settings.postalCode),
      'city': TextEditingController(text: widget.settings.city),
      'phone': TextEditingController(text: widget.settings.phone),
      'email': TextEditingController(text: widget.settings.email),
    };
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    await widget.settings
        .saveProfile(fields.map((key, value) => MapEntry(key, value.text)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Profil enregistré')));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Mon profil',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
            'Ces informations seront automatiquement reprises dans vos lettres.'),
        const SizedBox(height: 18),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: widget.settings.comfortMode,
          onChanged: widget.settings.setComfortMode,
          secondary: const Icon(Icons.text_increase),
          title: const Text('Mode confort'),
          subtitle: const Text('Texte plus grand et navigation plus lisible'),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: fields['firstName'],
            decoration: const InputDecoration(labelText: 'Prénom')),
        const SizedBox(height: 12),
        TextField(
            controller: fields['lastName'],
            decoration: const InputDecoration(labelText: 'Nom')),
        const SizedBox(height: 12),
        TextField(
            controller: fields['address'],
            decoration: const InputDecoration(labelText: 'Adresse')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              flex: 2,
              child: TextField(
                  controller: fields['postalCode'],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Code postal'))),
          const SizedBox(width: 12),
          Expanded(
              flex: 3,
              child: TextField(
                  controller: fields['city'],
                  decoration: const InputDecoration(labelText: 'Ville'))),
        ]),
        const SizedBox(height: 12),
        TextField(
            controller: fields['phone'],
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Téléphone')),
        const SizedBox(height: 12),
        TextField(
            controller: fields['email'],
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-mail')),
        const SizedBox(height: 18),
        FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.save_outlined),
            label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Enregistrer mon profil'))),
        const SizedBox(height: 20),
        const PrivacyCard(),
      ]));
}

class LetterGenerator {
  static String generate({
    required LetterTemplate template,
    required String firstName,
    required String lastName,
    required String address,
    required String postalCode,
    required String city,
    required String recipient,
    required String recipientAddress,
    required String reference,
    required String details,
  }) {
    final sender = '$firstName $lastName'.trim();
    final subject = switch (template) {
      LetterTemplate.internet => 'Résiliation de mon abonnement',
      LetterTemplate.insurance => 'Résiliation de mon contrat d’assurance',
      LetterTemplate.refund => 'Demande de remboursement',
      LetterTemplate.paymentDelay => 'Demande de délai de paiement',
      LetterTemplate.employer => 'Demande auprès de mon employeur',
      LetterTemplate.complaint => 'Réclamation',
    };
    final body = switch (template) {
      LetterTemplate.internet =>
        'Par la présente, je vous informe de ma volonté de résilier mon abonnement. Je vous remercie de me confirmer la date effective de résiliation et les modalités éventuelles de restitution du matériel.',
      LetterTemplate.insurance =>
        'Par la présente, je vous informe de ma volonté de mettre fin à mon contrat d’assurance. Je vous remercie de m’indiquer la date de prise d’effet et de me transmettre une confirmation écrite.',
      LetterTemplate.refund =>
        'Je sollicite le remboursement lié à la situation décrite ci-dessous. Je vous remercie d’examiner ma demande et de m’indiquer les justificatifs nécessaires.',
      LetterTemplate.paymentDelay =>
        'En raison de ma situation actuelle, je sollicite exceptionnellement un délai de paiement. Je souhaite trouver une solution amiable et reste disponible pour convenir d’un échéancier.',
      LetterTemplate.employer =>
        'Je me permets de vous adresser la demande décrite ci-dessous. Je vous remercie de bien vouloir l’étudier et de me communiquer votre réponse.',
      LetterTemplate.complaint =>
        'Je souhaite porter à votre connaissance une difficulté concernant votre service ou votre prestation. Je vous remercie de réexaminer ma situation et de me proposer une solution adaptée.',
    };
    final refLine =
        reference.trim().isEmpty ? '' : '\nRéférence : ${reference.trim()}\n';
    final precision = details.trim().isEmpty
        ? 'Je vous remercie de bien vouloir traiter ma demande dans les meilleurs délais.'
        : details.trim();
    return '''$sender
${address.trim()}
${postalCode.trim()} ${city.trim()}

${recipient.trim()}
${recipientAddress.trim()}

À ${city.trim()}, le ${formatDate(DateTime.now())}

Objet : $subject
$refLine
Madame, Monsieur,

$body

$precision

Je reste à votre disposition pour tout complément d’information.

Veuillez agréer, Madame, Monsieur, l’expression de mes salutations distinguées.

$sender''';
  }

  static String formatDate(DateTime date) {
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
