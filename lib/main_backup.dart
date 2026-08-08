import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import 'account_controller.dart';
import 'cloud_documents.dart';

class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({super.key, required this.controller, this.localeId});
  final TextEditingController controller;
  final String? localeId;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!available || !mounted) return;
    setState(() => _listening = true);
    final initial = widget.controller.text.trim();
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: widget.localeId),
      onResult: (result) {
        final spoken = result.recognizedWords.trim();
        if (spoken.isEmpty) return;
        final separator = initial.isEmpty ? '' : ' ';
        widget.controller.text = '$initial$separator$spoken';
        widget.controller.selection = TextSelection.collapsed(
          offset: widget.controller.text.length,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: _listening ? 'Arrêter la dictée' : 'Dicter ce texte',
        onPressed: _toggle,
        icon: Icon(
          _listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
          color: _listening ? Theme.of(context).colorScheme.error : null,
        ),
      );
}

enum ProcedureStatus { created, sent, waiting, reminder, completed }

extension ProcedureStatusLabel on ProcedureStatus {
  String get label => switch (this) {
        ProcedureStatus.created => 'Créée',
        ProcedureStatus.sent => 'Envoyée',
        ProcedureStatus.waiting => 'En attente',
        ProcedureStatus.reminder => 'Relance prévue',
        ProcedureStatus.completed => 'Terminée',
      };

  IconData get icon => switch (this) {
        ProcedureStatus.created => Icons.description_outlined,
        ProcedureStatus.sent => Icons.send_outlined,
        ProcedureStatus.waiting => Icons.hourglass_top,
        ProcedureStatus.reminder => Icons.notifications_active_outlined,
        ProcedureStatus.completed => Icons.check_circle_outline,
      };
}

class AdministrativeProcedure {
  const AdministrativeProcedure({
    required this.id,
    required this.title,
    required this.organisation,
    required this.category,
    required this.letter,
    required this.createdAt,
    required this.updatedAt,
    this.status = ProcedureStatus.created,
    this.notes = '',
    this.reminderDate,
    this.archived = false,
  });

  final String id;
  final String title;
  final String organisation;
  final String category;
  final String letter;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ProcedureStatus status;
  final String notes;
  final DateTime? reminderDate;
  final bool archived;

  AdministrativeProcedure copyWith({
    ProcedureStatus? status,
    String? notes,
    DateTime? reminderDate,
    bool clearReminder = false,
    bool? archived,
    String? letter,
  }) =>
      AdministrativeProcedure(
        id: id,
        title: title,
        organisation: organisation,
        category: category,
        letter: letter ?? this.letter,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        status: status ?? this.status,
        notes: notes ?? this.notes,
        reminderDate:
            clearReminder ? null : (reminderDate ?? this.reminderDate),
        archived: archived ?? this.archived,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'organisation': organisation,
        'category': category,
        'letter': letter,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'status': status.name,
        'notes': notes,
        'reminderDate': reminderDate?.toIso8601String(),
        'archived': archived,
      };

  factory AdministrativeProcedure.fromJson(Map<String, dynamic> json) {
    final statusName =
        json['status'] as String? ?? ProcedureStatus.created.name;
    return AdministrativeProcedure(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Démarche administrative',
      organisation: json['organisation'] as String? ?? 'Non renseigné',
      category: json['category'] as String? ?? 'Autre',
      letter: json['letter'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      status: ProcedureStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => ProcedureStatus.created,
      ),
      notes: json['notes'] as String? ?? '',
      reminderDate: DateTime.tryParse(json['reminderDate'] as String? ?? ''),
      archived: json['archived'] as bool? ?? false,
    );
  }
}

class ProcedureStore extends ChangeNotifier {
  SharedPreferences? _prefs;
  final List<AdministrativeProcedure> _items = [];
  List<AdministrativeProcedure> get items => List.unmodifiable(_items);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString('administrativeProceduresV71');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _items
        ..clear()
        ..addAll(list.map((item) => AdministrativeProcedure.fromJson(
              Map<String, dynamic>.from(item as Map),
            )));
      _sort();
    } catch (_) {}
  }

  void _sort() => _items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _persist() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(
      'administrativeProceduresV71',
      jsonEncode(_items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> add(AdministrativeProcedure procedure) async {
    _items.insert(0, procedure);
    await _persist();
    notifyListeners();
  }

  Future<void> update(AdministrativeProcedure procedure) async {
    final index = _items.indexWhere((item) => item.id == procedure.id);
    if (index < 0) return;
    _items[index] = procedure;
    _sort();
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((item) => item.id == id);
    await _persist();
    notifyListeners();
  }
}

class SavedDocument {
  const SavedDocument({
    required this.id,
    required this.title,
    required this.category,
    required this.organisation,
    required this.createdAt,
    this.filePath,
    this.extractedText = '',
    this.deadline,
    this.favorite = false,
    this.status = 'À traiter',
    this.priority = 'Information',
    this.notes = '',
  });

  final String id;
  final String title;
  final String category;
  final String organisation;
  final DateTime createdAt;
  final String? filePath;
  final String extractedText;
  final String? deadline;
  final bool favorite;
  final String status;
  final String priority;
  final String notes;

  SavedDocument copyWith({
    String? title,
    String? category,
    String? organisation,
    String? deadline,
    bool? favorite,
    String? status,
    String? priority,
    String? notes,
  }) =>
      SavedDocument(
        id: id,
        title: title ?? this.title,
        category: category ?? this.category,
        organisation: organisation ?? this.organisation,
        createdAt: createdAt,
        filePath: filePath,
        extractedText: extractedText,
        deadline: deadline ?? this.deadline,
        favorite: favorite ?? this.favorite,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'organisation': organisation,
        'createdAt': createdAt.toIso8601String(),
        'filePath': filePath,
        'extractedText': extractedText,
        'deadline': deadline,
        'favorite': favorite,
        'status': status,
        'priority': priority,
        'notes': notes,
      };

  factory SavedDocument.fromJson(Map<String, dynamic> json) => SavedDocument(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Document',
        category: json['category'] as String? ?? 'Autre',
        organisation: json['organisation'] as String? ?? 'Non identifié',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        filePath: json['filePath'] as String?,
        extractedText: json['extractedText'] as String? ?? '',
        deadline: json['deadline'] as String?,
        favorite: json['favorite'] as bool? ?? false,
        status: json['status'] as String? ?? 'À traiter',
        priority: json['priority'] as String? ?? 'Information',
        notes: json['notes'] as String? ?? '',
      );
}

class DocumentStore extends ChangeNotifier {
  SharedPreferences? _prefs;
  final List<SavedDocument> _documents = [];
  List<SavedDocument> get documents => List.unmodifiable(_documents);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString('savedDocumentsV4');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _documents
        ..clear()
        ..addAll(list.map((e) =>
            SavedDocument.fromJson(Map<String, dynamic>.from(e as Map))));
      _documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString('savedDocumentsV4',
        jsonEncode(_documents.map((e) => e.toJson()).toList()));
  }

  Future<void> add(SavedDocument document) async {
    _documents.insert(0, document);
    await _persist();
    notifyListeners();
  }

  Future<void> update(SavedDocument document) async {
    final index = _documents.indexWhere((e) => e.id == document.id);
    if (index < 0) return;
    _documents[index] = document;
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _documents.removeWhere((e) => e.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    final index = _documents.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _documents[index] =
        _documents[index].copyWith(favorite: !_documents[index].favorite);
    await _persist();
    notifyListeners();
  }
}

final ProcedureStore appProcedureStore = ProcedureStore();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  final documentStore = DocumentStore();
  final procedureStore = appProcedureStore;
  await AccountController.instance.load();
  await settings.load();
  await documentStore.load();
  await procedureStore.load();
  runApp(AdminFacileApp(
    settings: settings,
    documentStore: documentStore,
    procedureStore: procedureStore,
  ));
}

enum AppThemePreference { system, light, dark }

extension AppThemePreferenceLabel on AppThemePreference {
  String get label => switch (this) {
        AppThemePreference.system => 'Automatique',
        AppThemePreference.light => 'Clair',
        AppThemePreference.dark => 'Sombre',
      };

  ThemeMode get themeMode => switch (this) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      };
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
  AppThemePreference themePreference = AppThemePreference.dark;

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
    final savedTheme =
        _prefs!.getString('themePreference') ?? AppThemePreference.dark.name;
    themePreference = AppThemePreference.values.firstWhere(
      (value) => value.name == savedTheme,
      orElse: () => AppThemePreference.dark,
    );
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

  Future<void> setThemePreference(AppThemePreference value) async {
    themePreference = value;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString('themePreference', value.name);
    notifyListeners();
  }

  Future<void> toggleLightDark() async {
    final next = themePreference == AppThemePreference.dark
        ? AppThemePreference.light
        : AppThemePreference.dark;
    await setThemePreference(next);
  }
}

ThemeData _buildAdminTheme(Brightness brightness, bool comfortMode) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF136DF2),
    brightness: brightness,
    primary: const Color(0xFF136DF2),
    secondary: const Color(0xFF20B98B),
    tertiary: const Color(0xFFF5A623),
    surface: isDark ? const Color(0xFF08172B) : Colors.white,
  );
  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF020C1D) : const Color(0xFFF4F7FC),
    cardTheme: CardThemeData(
      color: isDark ? const Color(0xFF09182C) : Colors.white,
      elevation: isDark ? 0 : 1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF0C203A) : Colors.white,
      border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? const Color(0xFF061426) : Colors.white,
      indicatorColor:
          isDark ? const Color(0xFF123B78) : const Color(0xFFDCEAFF),
    ),
    textTheme: comfortMode
        ? const TextTheme(
            bodyMedium: TextStyle(fontSize: 18),
            bodyLarge: TextStyle(fontSize: 20),
            titleMedium: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            titleLarge: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          )
        : null,
  );
}

class AdminFacileApp extends StatelessWidget {
  const AdminFacileApp({
    super.key,
    required this.settings,
    required this.documentStore,
    required this.procedureStore,
  });
  final AppSettings settings;
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AdminFacile V15.3.1',
        themeMode: settings.themePreference.themeMode,
        theme: _buildAdminTheme(Brightness.light, settings.comfortMode),
        darkTheme: _buildAdminTheme(Brightness.dark, settings.comfortMode),
        home: _StartupSplash(
          settings: settings,
          documentStore: documentStore,
          procedureStore: procedureStore,
        ),
      ),
    );
  }
}

class _StartupSplash extends StatefulWidget {
  const _StartupSplash({
    required this.settings,
    required this.documentStore,
    required this.procedureStore,
  });
  final AppSettings settings;
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;

  @override
  State<_StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<_StartupSplash> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AppShell(
            settings: widget.settings,
            documentStore: widget.documentStore,
            procedureStore: widget.procedureStore,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _BrandLockup(
                      markSize: 86, titleSize: 38, subtitleSize: 17),
                  const SizedBox(height: 28),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      );
}

class AdminFacileMark extends StatelessWidget {
  const AdminFacileMark({super.key, this.size = 54});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _ShieldLogoPainter()),
      );
}

class _ShieldLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()
      ..moveTo(size.width * .5, 0)
      ..lineTo(size.width * .92, size.height * .15)
      ..lineTo(size.width * .87, size.height * .68)
      ..quadraticBezierTo(
          size.width * .75, size.height * .88, size.width * .5, size.height)
      ..quadraticBezierTo(size.width * .25, size.height * .88, size.width * .13,
          size.height * .68)
      ..lineTo(size.width * .08, size.height * .15)
      ..close();
    canvas.drawPath(outer, Paint()..color = const Color(0xFF1574FF));
    final inner = Path()
      ..moveTo(size.width * .5, size.height * .10)
      ..lineTo(size.width * .80, size.height * .21)
      ..lineTo(size.width * .76, size.height * .62)
      ..quadraticBezierTo(size.width * .68, size.height * .77, size.width * .5,
          size.height * .87)
      ..quadraticBezierTo(size.width * .32, size.height * .77, size.width * .24,
          size.height * .62)
      ..lineTo(size.width * .20, size.height * .21)
      ..close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFF061A38));
    final tp = TextPainter(
      text: TextSpan(
          text: 'A',
          style: TextStyle(
              color: Colors.white,
              fontSize: size.width * .56,
              fontWeight: FontWeight.w800,
              height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2,
            (size.height - tp.height) / 2 - size.height * .01));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup(
      {this.markSize = 56, this.titleSize = 27, this.subtitleSize = 13});
  final double markSize;
  final double titleSize;
  final double subtitleSize;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdminFacileMark(size: markSize),
          const SizedBox(width: 12),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                    text: TextSpan(
                        style: TextStyle(
                            fontSize: titleSize, fontWeight: FontWeight.w800),
                        children: const [
                      TextSpan(text: 'Admin'),
                      TextSpan(
                          text: 'Facile',
                          style: TextStyle(color: Color(0xFF2588FF))),
                    ])),
                Text('Votre assistant administratif',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: subtitleSize)),
              ]),
        ],
      );
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.settings,
    required this.documentStore,
    required this.procedureStore,
  });
  final AppSettings settings;
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        settings: widget.settings,
        procedureStore: widget.procedureStore,
        openMenu: () => _scaffoldKey.currentState?.openDrawer(),
        openGlobalSearch: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GlobalSearchScreen(
                documentStore: widget.documentStore,
                procedureStore: widget.procedureStore,
                settings: widget.settings))),
        openScanner: () => setState(() => index = 1),
        openLetters: () => setState(() => index = 2),
        openSearch: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => JsonLibraryScreen(settings: widget.settings))),
        openProblem: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                ProblemDescriptionScreen(settings: widget.settings))),
        openAiWriter: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                GeminiLetterWriterScreen(settings: widget.settings))),
        openTranslator: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TranslationScreen()),
        ),
        openDictation: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DictationScreen()),
        ),
        openProcedures: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProceduresScreen(store: widget.procedureStore),
          ),
        ),
        openProfile: () => setState(() => index = 4),
      ),
      ScannerScreen(
          documentStore: widget.documentStore,
          procedureStore: widget.procedureStore),
      LetterLibraryScreen(settings: widget.settings),
      DocumentsScreen(documentStore: widget.documentStore),
      ProfileScreen(settings: widget.settings),
    ];
    return Scaffold(
      key: _scaffoldKey,
      drawer: _AdminDrawer(
        selectedIndex: index,
        settings: widget.settings,
        onSelect: (value) {
          Navigator.of(context).pop();
          setState(() => index = value);
        },
        openAssistant: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  ProblemDescriptionScreen(settings: widget.settings)));
        },
        openAiWriter: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  GeminiLetterWriterScreen(settings: widget.settings)));
        },
        openLibrary: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => JsonLibraryScreen(settings: widget.settings)));
        },
        openProcedures: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ProceduresScreen(store: widget.procedureStore)));
        },
        openTranslation: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TranslationScreen()));
        },
        openSearch: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GlobalSearchScreen(
                  documentStore: widget.documentStore,
                  procedureStore: widget.procedureStore,
                  settings: widget.settings)));
        },
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF061426)
              : Colors.white,
          indicatorColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF123B78)
              : const Color(0xFFDCEAFF),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF2588FF)
                  : Theme.of(context).colorScheme.onSurfaceVariant)),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF2588FF)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 11)),
        ),
        child: NavigationBar(
          selectedIndex: index,
          height: widget.settings.comfortMode ? 82 : 72,
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
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: 'Documents'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profil'),
          ],
        ),
      ),
    );
  }
}

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer(
      {required this.selectedIndex,
      required this.settings,
      required this.onSelect,
      required this.openAssistant,
      required this.openAiWriter,
      required this.openLibrary,
      required this.openProcedures,
      required this.openTranslation,
      required this.openSearch});
  final int selectedIndex;
  final AppSettings settings;
  final ValueChanged<int> onSelect;
  final VoidCallback openAssistant,
      openAiWriter,
      openLibrary,
      openProcedures,
      openTranslation,
      openSearch;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      backgroundColor: dark ? const Color(0xFF061426) : Colors.white,
      child: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(children: [
              const AdminFacileMark(size: 48),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('AdminFacile',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 21,
                            fontWeight: FontWeight.w900)),
                    Text('Votre espace administratif',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12))
                  ]))
            ])),
        const Divider(height: 1),
        Expanded(
            child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
              _DrawerEntry(
                  icon: Icons.home_rounded,
                  label: 'Accueil',
                  selected: selectedIndex == 0,
                  onTap: () => onSelect(0)),
              _DrawerEntry(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Assistant administratif',
                  onTap: openAssistant),
              _DrawerEntry(
                  icon: Icons.draw_rounded,
                  label: 'Rédiger avec Gemini',
                  onTap: openAiWriter),
              _DrawerEntry(
                  icon: Icons.edit_note_rounded,
                  label: 'Générer une lettre',
                  selected: selectedIndex == 2,
                  onTap: () => onSelect(2)),
              _DrawerEntry(
                  icon: Icons.document_scanner_rounded,
                  label: 'Scanner un document',
                  selected: selectedIndex == 1,
                  onTap: () => onSelect(1)),
              _DrawerEntry(
                  icon: Icons.folder_copy_rounded,
                  label: 'Mes démarches',
                  onTap: openProcedures),
              _DrawerEntry(
                  icon: Icons.folder_rounded,
                  label: 'Mes documents',
                  selected: selectedIndex == 3,
                  onTap: () => onSelect(3)),
              _DrawerEntry(
                  icon: Icons.menu_book_rounded,
                  label: 'Bibliothèque de modèles',
                  onTap: openLibrary),
              _DrawerEntry(
                  icon: Icons.translate_rounded,
                  label: 'Traduction',
                  onTap: openTranslation),
              _DrawerEntry(
                  icon: Icons.search_rounded,
                  label: 'Recherche globale',
                  onTap: openSearch),
              const Divider(indent: 18, endIndent: 18),
              _DrawerEntry(
                  icon: Icons.settings_rounded,
                  label: 'Paramètres et profil',
                  selected: selectedIndex == 4,
                  onTap: () => onSelect(4)),
            ])),
        Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: const Color(0xFF2588FF)),
              const SizedBox(width: 10),
              Expanded(child: Text(dark ? 'Mode sombre' : 'Mode clair')),
              Switch(value: dark, onChanged: (_) => settings.toggleLightDark())
            ])),
      ])),
    );
  }
}

class _DrawerEntry extends StatelessWidget {
  const _DrawerEntry(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.selected = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        selected: selected,
        selectedTileColor: const Color(0xFF2588FF).withValues(alpha: .14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon,
            color: selected
                ? const Color(0xFF2588FF)
                : Theme.of(context).colorScheme.onSurfaceVariant),
        title: Text(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      ));
}

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen(
      {super.key,
      required this.documentStore,
      required this.procedureStore,
      required this.settings});
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;
  final AppSettings settings;
  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final controller = TextEditingController();
  String query = '';
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  bool matches(String value) =>
      value.toLowerCase().contains(query.trim().toLowerCase());
  @override
  Widget build(BuildContext context) {
    final procedures = query.trim().isEmpty
        ? <AdministrativeProcedure>[]
        : widget.procedureStore.items
            .where((e) => matches(
                '${e.title} ${e.organisation} ${e.category} ${e.notes}'))
            .toList();
    final documents = query.trim().isEmpty
        ? <SavedDocument>[]
        : widget.documentStore.documents
            .where((e) => matches(
                '${e.title} ${e.organisation} ${e.category} ${e.extractedText}'))
            .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Recherche globale')),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(18), children: [
        TextField(
            controller: controller,
            autofocus: true,
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          controller.clear();
                          setState(() => query = '');
                        }),
                hintText: 'CAF, Orange, facture, résiliation…')),
        const SizedBox(height: 18),
        if (query.trim().isEmpty)
          const _SearchEmptyState(
              title: 'Recherchez partout',
              subtitle:
                  'Retrouvez vos démarches et vos documents depuis un seul écran.'),
        if (query.trim().isNotEmpty && procedures.isEmpty && documents.isEmpty)
          const _SearchEmptyState(
              title: 'Aucun résultat',
              subtitle:
                  'Essayez un organisme, un sujet ou un mot présent dans le document.'),
        if (procedures.isNotEmpty) ...[
          Text('Démarches (${procedures.length})',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...procedures.map((e) => Card(
              child: ListTile(
                  leading: Icon(e.status.icon, color: const Color(0xFF2588FF)),
                  title: Text(e.title),
                  subtitle: Text('${e.organisation} • ${e.status.label}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          ProceduresScreen(store: widget.procedureStore)))))),
          const SizedBox(height: 16),
        ],
        if (documents.isNotEmpty) ...[
          Text('Documents (${documents.length})',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...documents.map((e) => Card(
              child: ListTile(
                  leading: const Icon(Icons.description_rounded,
                      color: Color(0xFF20B98B)),
                  title: Text(e.title),
                  subtitle: Text('${e.organisation} • ${e.category}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DocumentsScreen(
                          documentStore: widget.documentStore)))))),
        ],
        if (query.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      JsonLibraryScreen(settings: widget.settings))),
              icon: const Icon(Icons.menu_book_rounded),
              label: Text('Chercher « $query » dans les modèles')),
        ],
      ])),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 55),
      child: Column(children: [
        const Icon(Icons.manage_search_rounded,
            size: 76, color: Color(0xFF2588FF)),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 7),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4))
      ]));
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.procedureStore,
    required this.openScanner,
    required this.openLetters,
    required this.openSearch,
    required this.openProblem,
    required this.openAiWriter,
    required this.openTranslator,
    required this.openDictation,
    required this.openProcedures,
    required this.openMenu,
    required this.openGlobalSearch,
    required this.openProfile,
  });

  final AppSettings settings;
  final ProcedureStore procedureStore;
  final VoidCallback openScanner;
  final VoidCallback openLetters;
  final VoidCallback openSearch;
  final VoidCallback openProblem;
  final VoidCallback openAiWriter;
  final VoidCallback openTranslator;
  final VoidCallback openDictation;
  final VoidCallback openProcedures;
  final VoidCallback openMenu;
  final VoidCallback openGlobalSearch;
  final VoidCallback openProfile;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: procedureStore,
        builder: (context, _) {
          final active = procedureStore.items
              .where(
                  (e) => !e.archived && e.status != ProcedureStatus.completed)
              .toList();
          final completed = procedureStore.items
              .where((e) => e.status == ProcedureStatus.completed)
              .length;
          final reminders = active.where((e) => e.reminderDate != null).length;
          final waiting = active
              .where((e) =>
                  e.status == ProcedureStatus.waiting ||
                  e.status == ProcedureStatus.sent)
              .length;
          final recent = active.take(3).toList();
          final dark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              gradient: dark
                  ? const RadialGradient(
                      center: Alignment.topRight,
                      radius: 1.3,
                      colors: [Color(0xFF09244C), Color(0xFF020C1D)],
                      stops: [0, .7])
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFEAF3FF), Color(0xFFF7F9FD)]),
            ),
            child: SafeArea(
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
                children: [
                  _DarkHeader(
                    greeting: settings.greeting,
                    settings: settings,
                    openMenu: openMenu,
                    openSearch: openGlobalSearch,
                    openProfile: openProfile,
                  ),
                  const SizedBox(height: 20),
                  _DarkHeroCard(onScan: openScanner, onWrite: openAiWriter),
                  const SizedBox(height: 18),
                  _ShortcutGrid(
                      activeCount: active.length,
                      openProblem: openProblem,
                      openSearch: openSearch,
                      openProcedures: openProcedures,
                      openLetters: openLetters),
                  const SizedBox(height: 22),
                  Row(children: [
                    Expanded(
                        child: Text('Mes démarches en cours',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 21,
                                fontWeight: FontWeight.w800))),
                    TextButton(
                        onPressed: openProcedures,
                        child: const Text('Voir tout',
                            style: TextStyle(color: Color(0xFF4C9CFF)))),
                  ]),
                  const SizedBox(height: 6),
                  if (recent.isEmpty)
                    _DarkEmptyProcedures(onTap: openProblem)
                  else
                    ...recent.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _DarkProcedurePreview(
                            item: e, onTap: openProcedures))),
                  const SizedBox(height: 12),
                  _DarkStats(
                      reminders: reminders,
                      completed: completed,
                      waiting: waiting),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: _SmallDarkAction(
                            icon: Icons.translate,
                            label: 'Traduire',
                            onTap: openTranslator)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _SmallDarkAction(
                            icon: Icons.mic_none,
                            label: 'Dictée libre',
                            onTap: openDictation)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _SmallDarkAction(
                            icon: Icons.document_scanner_outlined,
                            label: 'Scanner',
                            onTap: openScanner)),
                  ]),
                ],
              ),
            ),
          );
        },
      );
}

class _DarkHeader extends StatelessWidget {
  const _DarkHeader({
    required this.greeting,
    required this.settings,
    required this.openMenu,
    required this.openSearch,
    required this.openProfile,
  });
  final String greeting;
  final AppSettings settings;
  final VoidCallback openMenu;
  final VoidCallback openSearch;
  final VoidCallback openProfile;
  @override
  Widget build(BuildContext context) => Row(children: [
        _HeaderCircle(icon: Icons.menu_rounded, onTap: openMenu),
        const SizedBox(width: 10),
        const Expanded(
            child:
                Align(alignment: Alignment.centerLeft, child: _BrandLockup())),
        _HeaderCircle(
          icon: Theme.of(context).brightness == Brightness.dark
              ? Icons.light_mode_rounded
              : Icons.dark_mode_rounded,
          onTap: () => settings.setThemePreference(
              Theme.of(context).brightness == Brightness.dark
                  ? AppThemePreference.light
                  : AppThemePreference.dark),
        ),
        const SizedBox(width: 10),
        _HeaderCircle(icon: Icons.search_rounded, onTap: openSearch),
        const SizedBox(width: 10),
        Stack(clipBehavior: Clip.none, children: [
          _HeaderCircle(icon: Icons.notifications_none_rounded, onTap: () {}),
          const Positioned(
              right: -2,
              top: -5,
              child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(0xFFFF3B3B),
                  child: Text('3',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)))),
        ]),
        const SizedBox(width: 10),
        AnimatedBuilder(
          animation: AccountController.instance,
          builder: (context, _) {
            final account = AccountController.instance;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Tooltip(
                  message: account.isSignedIn
                      ? 'Compte connecté : ${account.email ?? ''}'
                      : 'Se connecter',
                  child: _HeaderCircle(
                    icon: account.isSignedIn
                        ? Icons.account_circle_rounded
                        : Icons.login_rounded,
                    onTap: openProfile,
                  ),
                ),
                if (account.isSignedIn)
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 6,
                      backgroundColor: Color(0xFF20D09B),
                    ),
                  ),
              ],
            );
          },
        ),
      ]);
}

class _HeaderCircle extends StatelessWidget {
  const _HeaderCircle({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
        color: dark ? const Color(0xFF0D1C33) : Colors.white,
        elevation: dark ? 0 : 2,
        shape: const CircleBorder(),
        child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(icon,
                    color: dark ? Colors.white : const Color(0xFF0A2B55),
                    size: 26))));
  }
}

class _DarkHeroCard extends StatelessWidget {
  const _DarkHeroCard({required this.onScan, required this.onWrite});
  final VoidCallback onScan;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final compact = c.maxWidth < 390;
        final configured = GeminiDocumentAnalyzer.isConfigured;
        return Container(
          constraints: const BoxConstraints(minHeight: 270),
          padding: EdgeInsets.all(compact ? 18 : 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF073B94), Color(0xFF041A3C), Color(0xFF072757)],
            ),
            border: Border.all(color: const Color(0xFF1477FF)),
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 24,
                  offset: Offset(0, 10))
            ],
          ),
          child: Row(children: [
            Expanded(
              flex: compact ? 7 : 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: configured
                          ? const Color(0xFF0B9B69)
                          : const Color(0xFFB66B10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(configured ? Icons.check_circle : Icons.info_outline,
                          color: Colors.white, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        configured ? 'GEMINI CONNECTÉ' : 'IA À CONFIGURER',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Assistant IA Gemini',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 24 : 29,
                        height: 1.1,
                        fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Scannez et comprenez un courrier, ou rédigez une lettre professionnelle sur mesure.',
                    style: TextStyle(
                        color: const Color(0xFFD7E2F3),
                        fontSize: compact ? 13 : 15,
                        height: 1.4),
                  ),
                  const SizedBox(height: 17),
                  Wrap(spacing: 9, runSpacing: 9, children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF075CF5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: onScan,
                      icon: const Icon(Icons.document_scanner_rounded),
                      label: const Text('Analyser un courrier',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF72AAFF)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: onWrite,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Rédiger avec Gemini',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: compact ? 3 : 4,
              child: SizedBox(
                height: 205,
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 122,
                    height: 166,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FAFF),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 20,
                            offset: Offset(0, 10))
                      ],
                    ),
                    child: const Icon(Icons.description_rounded,
                        color: Color(0xFF75A9F6), size: 82),
                  ),
                  const Positioned(
                      right: 0,
                      top: 38,
                      child: CircleAvatar(
                          radius: 32,
                          backgroundColor: Color(0xFF0965EB),
                          child: Icon(Icons.auto_awesome,
                              color: Colors.white, size: 38))),
                  const Positioned(
                      left: 0,
                      bottom: 18,
                      child: Icon(Icons.psychology_alt_rounded,
                          color: Color(0xFFFFC72C), size: 58)),
                ]),
              ),
            ),
          ]),
        );
      });
}

class _ShortcutGrid extends StatelessWidget {
  const _ShortcutGrid(
      {required this.activeCount,
      required this.openProblem,
      required this.openSearch,
      required this.openProcedures,
      required this.openLetters});
  final int activeCount;
  final VoidCallback openProblem, openSearch, openProcedures, openLetters;
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: _DarkShortcut(
                icon: Icons.smart_toy_rounded,
                label: 'Assistant\nadministratif',
                accent: const Color(0xFF2388FF),
                onTap: openProblem)),
        const SizedBox(width: 8),
        Expanded(
            child: _DarkShortcut(
                icon: Icons.menu_book_rounded,
                label: 'Bibliothèque\nde modèles',
                accent: const Color(0xFF20D09B),
                onTap: openSearch)),
        const SizedBox(width: 8),
        Expanded(
            child: _DarkShortcut(
                icon: Icons.folder_rounded,
                label: 'Mes\ndémarches',
                accent: const Color(0xFFFFAD1F),
                badge: activeCount,
                onTap: openProcedures)),
        const SizedBox(width: 8),
        Expanded(
            child: _DarkShortcut(
                icon: Icons.star_rounded,
                label: 'Favoris',
                accent: const Color(0xFF9B55FF),
                onTap: openSearch)),
        const SizedBox(width: 8),
        Expanded(
            child: _DarkShortcut(
                icon: Icons.history_rounded,
                label: 'Historique',
                accent: const Color(0xFFFF557D),
                onTap: openLetters)),
      ]);
}

class _DarkShortcut extends StatelessWidget {
  const _DarkShortcut(
      {required this.icon,
      required this.label,
      required this.accent,
      required this.onTap,
      this.badge});
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final int? badge;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AspectRatio(
        aspectRatio: .63,
        child: Material(
            color: dark ? const Color(0xFF08172B) : Colors.white,
            elevation: dark ? 0 : 1,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                    decoration: BoxDecoration(
                        border:
                            Border.all(color: accent.withValues(alpha: .38)),
                        borderRadius: BorderRadius.circular(18)),
                    child: Stack(children: [
                      Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, color: accent, size: 35),
                            const SizedBox(height: 10),
                            SizedBox(
                                width: double.infinity,
                                child: Text(label,
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: label.startsWith('Mes')
                                            ? accent
                                            : (dark
                                                ? Colors.white
                                                : const Color(0xFF102748)),
                                        fontSize: 10.5,
                                        height: 1.14,
                                        fontWeight: FontWeight.w600))),
                          ]),
                      if ((badge ?? 0) > 0)
                        Positioned(
                            right: 0,
                            top: 0,
                            child: CircleAvatar(
                                radius: 10,
                                backgroundColor: const Color(0xFFFF3B3B),
                                child: Text('${badge! > 99 ? '99+' : badge}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold)))),
                    ])))));
  }
}

class _DarkProcedurePreview extends StatelessWidget {
  const _DarkProcedurePreview({required this.item, required this.onTap});
  final AdministrativeProcedure item;
  final VoidCallback onTap;
  Color get statusColor => switch (item.status) {
        ProcedureStatus.created => const Color(0xFFFFB719),
        ProcedureStatus.sent => const Color(0xFF1976FF),
        ProcedureStatus.waiting => const Color(0xFF8B4DFF),
        ProcedureStatus.reminder => const Color(0xFFFF7A20),
        ProcedureStatus.completed => const Color(0xFF20D09B)
      };
  String d(DateTime v) =>
      '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';
  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xFF09182C),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF17345D)),
                  borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                CircleAvatar(
                    radius: 25,
                    backgroundColor: const Color(0xFF12325C),
                    child: Text(
                        item.organisation.isEmpty
                            ? 'A'
                            : item.organisation[0].toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900))),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: statusColor, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(item.status.label,
                            style: const TextStyle(
                                color: Color(0xFFCFD8E8), fontSize: 12))
                      ]),
                      Text('Créée le ${d(item.createdAt)}',
                          style: const TextStyle(
                              color: Color(0xFF93A2B8), fontSize: 11))
                    ])),
                if (item.reminderDate != null) ...[
                  const Icon(Icons.calendar_month_outlined,
                      color: Color(0xFF79A7EB), size: 23),
                  const SizedBox(width: 6),
                  SizedBox(
                      width: 70,
                      child: Text('Relance le\n${d(item.reminderDate!)}',
                          style: const TextStyle(
                              color: Color(0xFFD5DEEC),
                              fontSize: 10.5,
                              height: 1.25)))
                ],
                const Icon(Icons.chevron_right, color: Colors.white),
              ]))));
}

class _DarkEmptyProcedures extends StatelessWidget {
  const _DarkEmptyProcedures({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xFF09182C),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF17345D)),
                  borderRadius: BorderRadius.circular(18)),
              child: const Row(children: [
                CircleAvatar(
                    backgroundColor: Color(0xFF12325C),
                    child: Icon(Icons.folder_open_outlined,
                        color: Color(0xFF4C9CFF))),
                SizedBox(width: 12),
                Expanded(
                    child: Text(
                        'Aucune démarche en cours. Créez votre première lettre pour commencer le suivi.',
                        style: TextStyle(color: Colors.white, height: 1.3))),
                Icon(Icons.arrow_forward, color: Colors.white)
              ]))));
}

class _DarkStats extends StatelessWidget {
  const _DarkStats(
      {required this.reminders,
      required this.completed,
      required this.waiting});
  final int reminders, completed, waiting;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF07162A),
          border: Border.all(color: const Color(0xFF15345F)),
          borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('À ne pas manquer',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _DarkStat(
                  icon: Icons.notifications_rounded,
                  value: reminders,
                  label: 'Relances\nà venir',
                  accent: const Color(0xFFAF65FF))),
          const SizedBox(width: 8),
          Expanded(
              child: _DarkStat(
                  icon: Icons.check_circle_outline,
                  value: completed,
                  label: 'Démarches\nterminées',
                  accent: const Color(0xFF20D09B))),
          const SizedBox(width: 8),
          Expanded(
              child: _DarkStat(
                  icon: Icons.folder_rounded,
                  value: waiting,
                  label: 'En attente\nde réponse',
                  accent: const Color(0xFF2388FF)))
        ]),
      ]));
}

class _DarkStat extends StatelessWidget {
  const _DarkStat(
      {required this.icon,
      required this.value,
      required this.label,
      required this.accent});
  final IconData icon;
  final int value;
  final String label;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
      decoration: BoxDecoration(
          color: const Color(0xFF0C203A),
          borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        Icon(icon, color: accent, size: 28),
        const SizedBox(width: 8),
        Text('$value',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w900)),
        const SizedBox(width: 6),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 10.5, height: 1.18)))
      ]));
}

class _SmallDarkAction extends StatelessWidget {
  const _SmallDarkAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFD7E5F8),
          side: const BorderSide(color: Color(0xFF24456F)),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      icon: Icon(icon, size: 18),
      label: FittedBox(child: Text(label)));
}

class PrivacyCard extends StatefulWidget {
  const PrivacyCard({super.key});

  @override
  State<PrivacyCard> createState() => _PrivacyCardState();
}

class _PrivacyCardState extends State<PrivacyCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF102B3B) : const Color(0xFFE4F5EC);
    final foreground = dark ? const Color(0xFFE8FFF2) : const Color(0xFF173E2A);
    final accent = dark ? const Color(0xFF64E09B) : const Color(0xFF197443);
    return Card(
      color: background,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: .45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => expanded = !expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: .16),
                    shape: BoxShape.circle),
                child: Icon(Icons.shield_outlined, color: accent, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('Confidentialité',
                      style: TextStyle(
                          color: foreground,
                          fontSize: 17,
                          fontWeight: FontWeight.w900))),
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  color: accent),
            ]),
            if (expanded) ...[
              const SizedBox(height: 12),
              Text(
                'Vos documents restent enregistrés localement sur votre appareil. '
                'Lorsque vous utilisez Gemini, seul le texte nécessaire à l’analyse est envoyé : le PDF ou la photo ne sont pas transmis.\n\n'
                'Vérifiez toujours les informations importantes avant tout partage ou envoi.',
                style: TextStyle(
                    color: foreground,
                    height: 1.45,
                    fontWeight: FontWeight.w500),
              ),
            ] else ...[
              const SizedBox(height: 7),
              Text('Stockage local • Touchez pour en savoir plus',
                  style: TextStyle(
                      color: foreground.withValues(alpha: .85),
                      fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
    );
  }
}

enum DocumentProcessingStep { idle, scanning, ocr, gemini, completed }

extension DocumentProcessingStepLabel on DocumentProcessingStep {
  String get label => switch (this) {
        DocumentProcessingStep.idle => 'Prêt',
        DocumentProcessingStep.scanning => 'Scan du document…',
        DocumentProcessingStep.ocr => 'Reconnaissance du texte (OCR)…',
        DocumentProcessingStep.gemini => 'Analyse Gemini…',
        DocumentProcessingStep.completed => 'Traitement terminé',
      };

  IconData get icon => switch (this) {
        DocumentProcessingStep.idle => Icons.document_scanner_outlined,
        DocumentProcessingStep.scanning => Icons.document_scanner,
        DocumentProcessingStep.ocr => Icons.text_snippet_outlined,
        DocumentProcessingStep.gemini => Icons.auto_awesome,
        DocumentProcessingStep.completed => Icons.check_circle_outline,
      };
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen(
      {super.key, required this.documentStore, required this.procedureStore});
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final picker = ImagePicker();
  final textController = TextEditingController();
  bool processing = false;
  DocumentProcessingStep processingStep = DocumentProcessingStep.idle;
  String? scanError;
  String? imagePath;
  String? pdfPath;
  int scannedPages = 0;
  bool ocrAttempted = false;
  int ocrCharacterCount = 0;
  String? ocrError;

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  String _normalisePath(String value) {
    if (value.startsWith('file://')) return Uri.parse(value).toFilePath();
    return value;
  }

  Future<void> _readImage(String path) async {
    setState(() {
      processing = true;
      processingStep = DocumentProcessingStep.ocr;
      scanError = null;
      imagePath = path;
      textController.clear();
      ocrAttempted = true;
      ocrCharacterCount = 0;
      ocrError = null;
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(path));
      if (!mounted) return;
      final recognizedText = result.text.trim();
      textController.text = recognizedText;
      ocrCharacterCount = recognizedText.length;
      if (recognizedText.isEmpty) {
        ocrError =
            'Aucun texte reconnu. Reprenez la photo avec une meilleure lumière.';
      }
      setState(() => processingStep = DocumentProcessingStep.completed);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        scanError =
            'Le texte du document n’a pas pu être reconnu. Vérifiez la netteté et la lumière, puis réessayez.';
      });
    } finally {
      await recognizer.close();
      if (mounted) {
        setState(() {
          processing = false;
          if (processingStep != DocumentProcessingStep.completed) {
            processingStep = DocumentProcessingStep.idle;
          }
        });
      }
    }
  }

  Future<void> _extractTextFromPdf(String path) async {
    ocrAttempted = true;
    ocrError = null;
    ocrCharacterCount = 0;
    textController.clear();
    if (path.startsWith('content://')) {
      throw const FileSystemException(
        'Le PDF doit être copié dans le stockage de l’application avant la reconnaissance du texte.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      throw const FileSystemException('Le PDF créé est introuvable.');
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final buffer = StringBuffer();
    final temp = await getTemporaryDirectory();
    int pageIndex = 0;
    try {
      final bytes = await file.readAsBytes();
      await for (final page in Printing.raster(bytes, dpi: 150)) {
        if (pageIndex >= 10) break;
        final pngBytes = await page.toPng();
        final pageFile = File(
            '${temp.path}/adminfacile_ocr_${DateTime.now().microsecondsSinceEpoch}_$pageIndex.png');
        await pageFile.writeAsBytes(pngBytes, flush: true);
        imagePath ??= pageFile.path;
        final recognized = await recognizer
            .processImage(InputImage.fromFilePath(pageFile.path));
        final pageText = recognized.text.trim();
        if (pageText.isNotEmpty) {
          if (buffer.isNotEmpty)
            buffer.writeln('\n--- Page ${pageIndex + 1} ---\n');
          buffer.write(pageText);
        }
        pageIndex++;
      }
      final text = buffer.toString().trim();
      textController.text = text;
      ocrCharacterCount = text.length;
      if (text.isEmpty) {
        ocrError =
            'Aucun texte n’a été détecté. Essayez avec davantage de lumière ou utilisez « Photo simple ».';
      }
    } finally {
      await recognizer.close();
    }
  }

  Future<void> _retryOcr() async {
    final path = pdfPath;
    if (path == null) return;
    setState(() {
      processing = true;
      processingStep = DocumentProcessingStep.ocr;
      scanError = null;
      ocrError = null;
    });
    try {
      await _extractTextFromPdf(path);
      if (!mounted) return;
      setState(() => processingStep = DocumentProcessingStep.completed);
    } catch (error, stackTrace) {
      debugPrint('Erreur OCR PDF : $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        ocrAttempted = true;
        ocrCharacterCount = 0;
        ocrError =
            'La lecture du texte a échoué. Vous pouvez réessayer ou utiliser « Photo simple ».';
      });
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  Future<void> scanA4() async {
    setState(() {
      processing = true;
      processingStep = DocumentProcessingStep.scanning;
      scanError = null;
      ocrError = null;
      ocrAttempted = false;
      ocrCharacterCount = 0;
      imagePath = null;
      textController.clear();
    });
    try {
      final PdfScanResult? result =
          await FlutterDocScanner().getScannedDocumentAsPdf(page: 10);
      if (result == null) {
        if (mounted)
          setState(() => processingStep = DocumentProcessingStep.idle);
        return;
      }
      final uri = result.pdfUri.trim();
      if (uri.isEmpty) throw const FormatException('Aucun PDF n’a été créé.');

      final sourcePath = _normalisePath(uri);
      final dir = await getApplicationDocumentsDirectory();
      final target =
          File('${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (sourcePath.startsWith('content://')) {
        pdfPath = sourcePath;
      } else {
        final source = File(sourcePath);
        if (!await source.exists())
          throw const FileSystemException('Le PDF créé est introuvable.');
        await source.copy(target.path);
        pdfPath = target.path;
      }
      scannedPages = result.pageCount > 0 ? result.pageCount : 1;
      if (!mounted) return;
      setState(() => processingStep = DocumentProcessingStep.ocr);

      try {
        await _extractTextFromPdf(pdfPath!);
      } catch (error, stackTrace) {
        debugPrint('Erreur OCR après scan : $error\n$stackTrace');
        ocrAttempted = true;
        ocrCharacterCount = 0;
        ocrError =
            'Le PDF a bien été créé, mais le texte n’a pas pu être lu automatiquement.';
      }

      if (!mounted) return;
      setState(() => processingStep = DocumentProcessingStep.completed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'PDF créé • OCR ${ocrCharacterCount > 0 ? 'terminé' : 'à réessayer'}')),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => scanError =
          'Le scanner est momentanément indisponible. Vérifiez l’autorisation de la caméra puis réessayez.');
      debugPrint('Erreur scanner plateforme : ${error.code} ${error.message}');
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => scanError =
          'Le document n’a pas pu être scanné. Vérifiez que la feuille est bien visible et réessayez.');
      debugPrint('Erreur scan inattendue : $error\n$stackTrace');
    } finally {
      if (mounted) {
        setState(() {
          processing = false;
          if (processingStep != DocumentProcessingStep.completed)
            processingStep = DocumentProcessingStep.idle;
        });
      }
    }
  }

  Future<void> pickAndRead(ImageSource source) async {
    setState(() => scanError = null);
    try {
      final file = await picker.pickImage(
          source: source, imageQuality: 92, maxWidth: 2200);
      if (file == null) return;
      pdfPath = null;
      scannedPages = 0;
      await _readImage(file.path);
    } catch (error) {
      if (!mounted) return;
      setState(() => processing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lecture impossible : $error')));
    }
  }

  Future<void> importFile() async {
    setState(() => scanError = null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'txt', 'pdf'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final selected = result.files.single;
      final path = selected.path;
      if (path == null)
        throw Exception('Le chemin du fichier est inaccessible.');
      final extension = (selected.extension ?? '').toLowerCase();
      if (extension == 'txt') {
        final content = await File(path).readAsString();
        if (!mounted) return;
        setState(() {
          imagePath = null;
          pdfPath = null;
          textController.text = content;
        });
      } else if (extension == 'pdf') {
        if (!mounted) return;
        setState(() {
          imagePath = null;
          pdfPath = path;
          scannedPages = 0;
          processing = true;
          processingStep = DocumentProcessingStep.ocr;
          ocrAttempted = false;
          ocrCharacterCount = 0;
          ocrError = null;
        });
        try {
          await _extractTextFromPdf(path);
          if (!mounted) return;
          setState(() => processingStep = DocumentProcessingStep.completed);
        } catch (error, stackTrace) {
          debugPrint('Erreur OCR PDF importé : $error\n$stackTrace');
          if (!mounted) return;
          setState(() {
            ocrAttempted = true;
            ocrCharacterCount = 0;
            ocrError =
                'Le PDF a été importé, mais son texte n’a pas pu être lu automatiquement.';
          });
        } finally {
          if (mounted) setState(() => processing = false);
        }
      } else {
        pdfPath = null;
        await _readImage(path);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import impossible : $error')));
    }
  }

  Future<void> _openPdf() async {
    final path = pdfPath;
    if (path == null) return;
    if (path.startsWith('content://')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Ce PDF doit d’abord être enregistré localement pour être ouvert.')),
      );
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PdfDocumentPreviewScreen(bytes: bytes, title: 'Document scanné'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ouverture impossible : $error')));
    }
  }

  Future<void> _savePdfLocally() async {
    if (pdfPath == null) return;
    final path = pdfPath!;
    if (path.startsWith('content://')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Ce document doit d’abord être copié dans le stockage de l’application.'),
        ),
      );
      return;
    }

    try {
      final bytes = await File(path).readAsBytes();
      final now = DateTime.now();
      final stamp = '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le document PDF',
        fileName: 'AdminFacile_$stamp.pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document enregistré localement.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enregistrement impossible : $error')),
      );
    }
  }

  Future<void> _archiveDocument() async {
    if ((pdfPath == null || pdfPath!.startsWith('content://')) &&
        textController.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Scannez ou ajoutez d’abord un document.')));
      return;
    }
    setState(() => processing = true);
    try {
      String? archivedPath;
      if (pdfPath != null && !pdfPath!.startsWith('content://')) {
        final dir = await getApplicationDocumentsDirectory();
        final target = File(
            '${dir.path}/archive_${DateTime.now().millisecondsSinceEpoch}.pdf');
        archivedPath = (await File(pdfPath!).copy(target.path)).path;
      }
      final insight = LocalDocumentAnalyzer.analyze(textController.text);
      final now = DateTime.now();
      await widget.documentStore.add(SavedDocument(
        id: now.microsecondsSinceEpoch.toString(),
        title: insight.organisation == 'Non identifiée'
            ? 'Document administratif'
            : 'Courrier ${insight.organisation}',
        category: insight.category,
        organisation: insight.organisation,
        createdAt: now,
        filePath: archivedPath,
        extractedText: textController.text.trim(),
        deadline: insight.dates.isEmpty ? null : insight.dates.first,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document ajouté à Mes documents.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Archivage impossible : $error')));
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  Future<void> _sharePdf({String? subject}) async {
    if (pdfPath == null) return;
    final path = pdfPath!;
    if (path.startsWith('content://')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Utilisez “Imprimer / partager le PDF” pour ce document.')));
      return;
    }
    await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        subject: subject ?? 'Document AdminFacile',
        text: 'Document envoyé depuis AdminFacile.'));
  }

  Future<void> _printPdf() async {
    if (pdfPath == null) return;
    final path = pdfPath!;
    if (path.startsWith('content://')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Le PDF doit d’abord être enregistré dans le stockage de l’application.')));
      return;
    }
    final bytes = await File(path).readAsBytes();
    await Printing.layoutPdf(
        onLayout: (_) async => bytes, name: 'Document AdminFacile');
  }

  void prepareReply() {
    if (textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Ajoutez d’abord le texte du courrier pour l’analyser.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SmartAnalysisScreen(
            sourceText: textController.text,
            procedureStore: widget.procedureStore)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Scanner un document A4',
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text(
          'Placez la feuille dans le cadre. L’application détecte les bords, recadre le document et corrige la perspective.'),
      const SizedBox(height: 18),
      SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: processing ? null : scanA4,
            icon: const Icon(Icons.document_scanner),
            label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Scanner une feuille A4')),
          )),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: OutlinedButton.icon(
                onPressed:
                    processing ? null : () => pickAndRead(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Photo simple'))),
        const SizedBox(width: 10),
        Expanded(
            child: OutlinedButton.icon(
                onPressed: processing ? null : importFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Importer'))),
      ]),
      const SizedBox(height: 20),
      if (processing)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Icon(processingStep.icon, size: 30),
              const SizedBox(height: 8),
              Text(
                processingStep.label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: switch (processingStep) {
                  DocumentProcessingStep.scanning => 0.25,
                  DocumentProcessingStep.ocr => 0.55,
                  DocumentProcessingStep.gemini => 0.82,
                  DocumentProcessingStep.completed => 1,
                  DocumentProcessingStep.idle => null,
                },
              ),
            ]),
          ),
        ),
      if (!processing && scanError != null)
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                  'Le scan a échoué',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                )),
              ]),
              const SizedBox(height: 8),
              Text(
                scanError!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: scanA4,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ]),
          ),
        ),
      if (!processing && pdfPath != null)
        Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.picture_as_pdf, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                              'PDF prêt${scannedPages > 0 ? ' • $scannedPages page${scannedPages > 1 ? 's' : ''}' : ''}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 17)))
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                          onPressed: _openPdf,
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Ouvrir')),
                      FilledButton.tonalIcon(
                          onPressed: _savePdfLocally,
                          icon: const Icon(Icons.save_alt),
                          label: const Text('Enregistrer')),
                      FilledButton.tonalIcon(
                          onPressed: _archiveDocument,
                          icon: const Icon(Icons.folder_copy_outlined),
                          label: const Text('Ajouter à Mes documents')),
                      OutlinedButton.icon(
                          onPressed: _sharePdf,
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Transmettre')),
                      OutlinedButton.icon(
                          onPressed: _printPdf,
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Imprimer')),
                    ]),
                    const SizedBox(height: 14),
                    _ProcessingStatusCard(
                      pdfReady: pdfPath != null,
                      ocrAttempted: ocrAttempted,
                      ocrCharacters: ocrCharacterCount,
                      ocrError: ocrError,
                      geminiReady: textController.text.trim().isNotEmpty,
                      onRetryOcr: processing ? null : _retryOcr,
                    ),
                  ])),
        ),
      if (!processing && imagePath != null) ...[
        ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(File(imagePath!),
                height: 220, width: double.infinity, fit: BoxFit.contain)),
        const SizedBox(height: 18),
      ],
      TextField(
          controller: textController,
          minLines: 8,
          maxLines: 16,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: 'Contenu du document',
              alignLabelWithHint: true,
              hintText:
                  'Le texte reconnu apparaîtra ici. Vous pouvez aussi le coller ou le dicter.',
              suffixIcon: VoiceInputButton(controller: textController))),
      const SizedBox(height: 14),
      if (textController.text.trim().isNotEmpty)
        Row(children: [
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: textController.text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Texte copié')));
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copier'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton.icon(
                  onPressed: prepareReply,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Analyser avec Gemini'))),
        ])
      else
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Analyse Gemini disponible après l’OCR'),
          ),
        ),
      const SizedBox(height: 18),
      const PrivacyCard(),
    ]));
  }
}

class _ProcessingStatusCard extends StatelessWidget {
  const _ProcessingStatusCard({
    required this.pdfReady,
    required this.ocrAttempted,
    required this.ocrCharacters,
    required this.ocrError,
    required this.geminiReady,
    required this.onRetryOcr,
  });
  final bool pdfReady;
  final bool ocrAttempted;
  final int ocrCharacters;
  final String? ocrError;
  final bool geminiReady;
  final VoidCallback? onRetryOcr;

  Widget line(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 9),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontWeight: FontWeight.w700)))
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final ok = Theme.of(context).colorScheme.primary;
    final error = Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: .55),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('État du traitement',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 7),
        line(
            pdfReady ? Icons.check_circle : Icons.radio_button_unchecked,
            pdfReady ? ok : Colors.grey,
            pdfReady ? 'PDF créé' : 'PDF non créé'),
        if (!ocrAttempted)
          line(Icons.hourglass_empty, Colors.grey, 'OCR en attente')
        else if (ocrCharacters > 0)
          line(Icons.check_circle, ok,
              'OCR terminé • $ocrCharacters caractères reconnus')
        else
          line(Icons.error_outline, error, ocrError ?? 'Aucun texte détecté'),
        line(
            geminiReady ? Icons.check_circle : Icons.lock_outline,
            geminiReady ? ok : Colors.grey,
            geminiReady ? 'Prêt pour Gemini' : 'Gemini attend le texte OCR'),
        if (ocrAttempted && ocrCharacters == 0 && onRetryOcr != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: onRetryOcr,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer l’OCR')),
        ],
      ]),
    );
  }
}

class PdfDocumentPreviewScreen extends StatelessWidget {
  const PdfDocumentPreviewScreen(
      {super.key, required this.bytes, required this.title});
  final Uint8List bytes;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: PdfPreview(
          build: (_) async => bytes,
          canChangeOrientation: false,
          canChangePageFormat: false,
          allowPrinting: true,
          allowSharing: true,
          pdfFileName: 'AdminFacile_document.pdf',
        ),
      );
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
    TranslationLanguage('Turc', TranslateLanguage.turkish),
    TranslationLanguage('Anglais', TranslateLanguage.english),
    TranslationLanguage('Arabe', TranslateLanguage.arabic),
    TranslationLanguage('Espagnol', TranslateLanguage.spanish),
    TranslationLanguage('Allemand', TranslateLanguage.german),
    TranslationLanguage('Italien', TranslateLanguage.italian),
    TranslationLanguage('Portugais', TranslateLanguage.portuguese),
  ];

  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _resultController = TextEditingController();
  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();
  final SpeechToText _translationSpeech = SpeechToText();
  TranslationLanguage _source = languages[0];
  TranslationLanguage _target = languages[2];
  bool _translating = false;
  bool _speechAvailable = false;
  bool _speechInitializing = true;
  bool _speechListening = false;
  String _dictationPrefix = '';
  String _speechStatus = 'Initialisation du microphone…';
  String _status = 'Les modèles de langue seront téléchargés au premier usage.';

  @override
  void initState() {
    super.initState();
    _initializeTranslationSpeech();
  }

  Future<void> _initializeTranslationSpeech() async {
    try {
      final available = await _translationSpeech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            _speechListening = status == 'listening';
            _speechStatus =
                _speechListening ? 'Je vous écoute…' : 'Microphone prêt';
          });
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _speechListening = false;
            _speechStatus = 'Erreur micro : ${error.errorMsg}';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _speechAvailable = available;
        _speechInitializing = false;
        _speechStatus = available
            ? 'Microphone prêt'
            : 'Reconnaissance vocale indisponible ou permission refusée';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _speechInitializing = false;
        _speechStatus = 'Impossible d’initialiser le microphone : $error';
      });
    }
  }

  Future<String?> _speechLocaleForSource() async {
    final wanted = _source.language.bcpCode.toLowerCase();
    final locales = await _translationSpeech.locales();
    for (final locale in locales) {
      final id = locale.localeId.toLowerCase();
      if (id == wanted ||
          id.startsWith('${wanted}_') ||
          id.startsWith('$wanted-')) {
        return locale.localeId;
      }
    }
    return null;
  }

  Future<void> _toggleTranslationDictation() async {
    if (_speechInitializing) return;
    if (!_speechAvailable) {
      await _initializeTranslationSpeech();
      return;
    }
    if (_translationSpeech.isListening) {
      await _translationSpeech.stop();
      if (mounted) setState(() => _speechListening = false);
      return;
    }

    final localeId = await _speechLocaleForSource();
    _dictationPrefix = _sourceController.text.trim();
    await _translationSpeech.listen(
      onResult: (result) {
        final spoken = result.recognizedWords.trim();
        final separator =
            _dictationPrefix.isEmpty || spoken.isEmpty ? '' : '\n';
        _sourceController.text = '$_dictationPrefix$separator$spoken';
        _sourceController.selection = TextSelection.collapsed(
          offset: _sourceController.text.length,
        );
        if (mounted) setState(() {});
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
    if (mounted) {
      setState(() {
        _speechListening = true;
        _speechStatus = localeId == null
            ? 'Je vous écoute avec la langue du téléphone…'
            : 'Je vous écoute en ${_source.label}…';
      });
    }
  }

  @override
  void dispose() {
    _translationSpeech.cancel();
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
      final paragraphs = text.split(RegExp(r'\n\s*\n'));
      final translatedParagraphs = <String>[];
      for (final paragraph in paragraphs) {
        final value = paragraph.trim();
        if (value.isEmpty) continue;
        translatedParagraphs.add(await translator.translateText(value));
      }
      final translated = translatedParagraphs.join('\n\n');
      if (!mounted) return;
      setState(() {
        _resultController.text = translated;
        _status =
            'Traduction terminée. Relisez les noms, références et formulations administratives avant l’envoi.';
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
      appBar: AppBar(title: const Text('Traduction administrative • V7.0')),
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
              decoration: InputDecoration(
                labelText: 'Texte à traduire',
                alignLabelWithHint: true,
                hintText: 'Écrivez, collez ou dictez le texte à traduire.',
                suffixIcon: VoiceInputButton(controller: _sourceController),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed:
                  _speechInitializing ? null : _toggleTranslationDictation,
              icon: Icon(_speechListening ? Icons.stop_circle : Icons.mic),
              label: Text(
                _speechListening
                    ? 'Arrêter la dictée'
                    : 'Dicter le texte à traduire',
              ),
            ),
            const SizedBox(height: 8),
            Text(_speechStatus),
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
              decoration: InputDecoration(
                labelText: 'Traduction',
                alignLabelWithHint: true,
                suffixIcon: VoiceInputButton(controller: _resultController),
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

class DocumentAmountItem {
  const DocumentAmountItem({required this.label, required this.amount});
  final String label;
  final String amount;
}

class DocumentInsight {
  const DocumentInsight({
    required this.category,
    required this.summary,
    required this.organisation,
    required this.dates,
    required this.amounts,
    required this.references,
    required this.actions,
    required this.priority,
    required this.documentsToPrepare,
    required this.warnings,
    this.simpleExplanation = '',
    this.documentType = 'courrier',
    this.supplier = '',
    this.billingPeriod = '',
    this.dueDate = '',
    this.amountDue = '',
    this.amountDetails = const [],
    this.suggestions = const [],
  });

  final String category;
  final String summary;
  final String organisation;
  final List<String> dates;
  final List<String> amounts;
  final List<String> references;
  final List<String> actions;
  final String priority;
  final List<String> documentsToPrepare;
  final List<String> warnings;
  final String simpleExplanation;
  final String documentType;
  final String supplier;
  final String billingPeriod;
  final String dueDate;
  final String amountDue;
  final List<DocumentAmountItem> amountDetails;
  final List<String> suggestions;

  bool get urgent => priority == 'Urgent';
  bool get isInvoice => documentType.toLowerCase().contains('facture');
}

class GeminiDocumentAnalyzer {
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );

  static bool get isConfigured => _apiKey.trim().isNotEmpty;

  static Future<DocumentInsight> analyze(String sourceText) async {
    if (!isConfigured) {
      throw const GeminiConfigurationException(
        'Clé Gemini absente. Relancez avec --dart-define=GEMINI_API_KEY=...',
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$_model:generateContent?key=$_apiKey',
    );

    final prompt = '''
Tu es un assistant administratif prudent. Analyse uniquement le courrier fourni.
Réponds en français, en JSON valide uniquement, sans markdown.
N'invente aucune date, aucun montant, aucune référence, aucune obligation et aucun droit.
Quand une information n'est pas présente, utilise une chaîne vide ou une liste vide.
Le niveau de priorité doit être exactement: Urgent, Important ou Information.
Adapte l'analyse au document. Commence par identifier précisément le type réel du document et son émetteur.
Pour une facture, renvoie UNIQUEMENT les informations utiles au client :
- type_document doit être précis : facture_gaz, facture_electricite, facture_eau, facture_telecom, facture_internet, facture_assurance ou facture_autre ;
- categorie doit être un titre lisible comme « Facture de gaz » ;
- fournisseur doit être le nom commercial qui émet la facture (exemples : PRIMAGAZ, EDF, ENGIE, Orange, SFR, Veolia) ;
- montant_a_payer doit être uniquement le total final dû par le client ;
- date_echeance doit être uniquement la date limite de paiement ;
- periode_facturation seulement si elle est clairement indiquée.
N'utilise jamais « Impôts et finances » pour une facture d'énergie ou de télécommunication.
Ignore totalement le capital social, SIREN/SIRET, adresses, téléphones, coordonnées bancaires, HT, TVA, sous-totaux, acomptes, frais théoriques et mentions légales.
Pour une facture, mets urgence à « Information », laisse vides les listes montants, detail_montants, références, pièces et avertissements, et limite les actions à : rappel, contestation, question.
Pour un courrier demandant une action, indique les pièces, délais et conséquences utiles. N'ajoute pas de sections inutiles.

Retourne cet objet JSON :
{
  "type_document": "courrier|facture_gaz|facture_electricite|facture_eau|facture_telecom|facture_internet|facture_assurance|facture_autre|mise_en_demeure|contrat|autre",
  "organisme": "",
  "categorie": "",
  "fournisseur": "",
  "periode_facturation": "",
  "date_echeance": "",
  "montant_a_payer": "",
  "urgence": "Information",
  "resume": "",
  "explication_simple": "",
  "dates_importantes": [],
  "montants": [],
  "detail_montants": [{"libelle": "", "montant": ""}],
  "references": [],
  "actions": [],
  "pieces_a_preparer": [],
  "points_vigilance": [],
  "suggestions": []
}

COURRIER :
${sourceText.trim()}
''';

    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.1,
              'responseMimeType': 'application/json',
              'maxOutputTokens': 2048,
            },
          }),
        )
        .timeout(const Duration(seconds: 35));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        detail = ((decoded['error'] as Map?)?['message'] ?? detail).toString();
      } catch (_) {}
      throw GeminiApiException(
        'Gemini a renvoyé ${response.statusCode}: $detail',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw const GeminiApiException('Gemini n’a renvoyé aucune analyse.');
    }
    final content = (candidates.first as Map?)?['content'] as Map?;
    final parts = content?['parts'] as List?;
    final text = parts
        ?.map((part) => (part as Map?)?['text']?.toString() ?? '')
        .join()
        .trim();
    if (text == null || text.isEmpty) {
      throw const GeminiApiException('Réponse Gemini vide.');
    }

    final data = jsonDecode(text) as Map<String, dynamic>;
    List<String> strings(String key) => ((data[key] as List?) ?? const [])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
    String value(String key, {String fallback = ''}) {
      final result = data[key]?.toString().trim() ?? '';
      return result.isEmpty ? fallback : result;
    }

    final actions = strings('actions');
    final priority = value('urgence', fallback: 'Information');
    final amountDetails = ((data['detail_montants'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => DocumentAmountItem(
              label: item['libelle']?.toString().trim() ?? '',
              amount: item['montant']?.toString().trim() ?? '',
            ))
        .where((item) => item.label.isNotEmpty && item.amount.isNotEmpty)
        .toList();
    return DocumentInsight(
      category: value('categorie', fallback: 'Courrier administratif'),
      summary: value(
        'resume',
        fallback: 'Gemini n’a pas pu produire un résumé suffisamment précis.',
      ),
      organisation: value('organisme', fallback: 'Non identifiée'),
      dates: strings('dates_importantes'),
      amounts: strings('montants'),
      references: strings('references'),
      actions: actions.isEmpty
          ? const ['Relire le document original et vérifier les informations.']
          : actions,
      priority: const {'Urgent', 'Important', 'Information'}.contains(priority)
          ? priority
          : 'Information',
      documentsToPrepare: strings('pieces_a_preparer'),
      warnings: strings('points_vigilance'),
      simpleExplanation: value('explication_simple'),
      documentType: value('type_document', fallback: 'courrier'),
      supplier: value('fournisseur'),
      billingPeriod: value('periode_facturation'),
      dueDate: value('date_echeance'),
      amountDue: value('montant_a_payer'),
      amountDetails: amountDetails,
      suggestions: strings('suggestions'),
    );
  }
}

class GeminiDocumentChat {
  static Future<String> ask(
      {required String sourceText, required String question}) async {
    if (!GeminiDocumentAnalyzer.isConfigured) {
      throw const GeminiConfigurationException(
        'Clé Gemini absente. Relancez avec --dart-define=GEMINI_API_KEY=...',
      );
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${GeminiDocumentAnalyzer._model}:generateContent?key=${GeminiDocumentAnalyzer._apiKey}',
    );
    final prompt = '''
Tu aides une personne à comprendre un document administratif.
Réponds en français simple, en 5 phrases maximum.
Base-toi uniquement sur le document. Si l'information n'y figure pas, dis-le clairement.
Ne donne pas de certitude juridique et recommande une vérification professionnelle si nécessaire.

DOCUMENT :
${sourceText.trim()}

QUESTION :
${question.trim()}
''';
    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 700},
          }),
        )
        .timeout(const Duration(seconds: 35));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiApiException('Gemini a renvoyé ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'];
    Map<String, dynamic>? content;
    if (candidates is List && candidates.isNotEmpty) {
      final firstCandidate = candidates.first;
      if (firstCandidate is Map) {
        final rawContent = firstCandidate['content'];
        if (rawContent is Map) {
          content = Map<String, dynamic>.from(rawContent);
        }
      }
    }
    final parts = content?['parts'] as List?;
    final text = parts
            ?.map((e) => (e as Map?)?['text']?.toString() ?? '')
            .join()
            .trim() ??
        '';
    if (text.isEmpty) throw const GeminiApiException('Réponse Gemini vide.');
    return text;
  }
}

class DocumentChatScreen extends StatefulWidget {
  const DocumentChatScreen({
    super.key,
    required this.sourceText,
    required this.initialInsight,
  });
  final String sourceText;
  final DocumentInsight initialInsight;
  @override
  State<DocumentChatScreen> createState() => _DocumentChatScreenState();
}

class _DocumentChatScreenState extends State<DocumentChatScreen> {
  final question = TextEditingController();
  final List<Map<String, String>> messages = [];
  bool loading = false;

  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggested]) async {
    final value = (suggested ?? question.text).trim();
    if (value.isEmpty || loading) return;
    setState(() {
      messages.add({'role': 'user', 'text': value});
      loading = true;
      question.clear();
    });
    try {
      final answer = await GeminiDocumentChat.ask(
        sourceText: widget.sourceText,
        question: value,
      );
      if (mounted) {
        setState(() => messages.add({'role': 'assistant', 'text': answer}));
      }
    } catch (error) {
      if (mounted) {
        setState(() => messages.add({
              'role': 'assistant',
              'text': 'Réponse impossible : $error',
            }));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Questions sur le document')),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(widget.initialInsight.summary),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        'Que dois-je faire ?',
                        'Que signifie le montant principal ?',
                        'Dois-je répondre ?',
                        'Puis-je demander un délai ?',
                      ]
                          .map((text) => ActionChip(
                                label: Text(text),
                                onPressed: () => _send(text),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    ...messages.map((message) {
                      final mine = message['role'] == 'user';
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 560),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: mine
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(message['text'] ?? ''),
                        ),
                      );
                    }),
                    if (loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  8,
                  12,
                  12 + MediaQuery.paddingOf(context).bottom,
                ),
                child: TextField(
                  controller: question,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: 'Posez une question sur le document…',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VoiceInputButton(controller: question),
                        IconButton(
                          onPressed: loading ? null : _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ],
          ),
        ),
      );
}

class GeminiGeneratedLetter {
  const GeminiGeneratedLetter(
      {required this.title, required this.subject, required this.body});
  final String title;
  final String subject;
  final String body;
}

class GeminiLetterWriter {
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );

  static bool get isConfigured => _apiKey.trim().isNotEmpty;

  static Future<Map<String, dynamic>> _requestJson(String prompt) async {
    if (!isConfigured) {
      throw const GeminiConfigurationException(
        'Clé Gemini absente. Relancez avec --dart-define=GEMINI_API_KEY=...',
      );
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$_model:generateContent?key=$_apiKey',
    );
    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.2,
              'responseMimeType': 'application/json',
              'maxOutputTokens': 2500,
            },
          }),
        )
        .timeout(const Duration(seconds: 40));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiApiException('Gemini a renvoyé ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    final parts =
        ((candidates?.first as Map?)?['content'] as Map?)?['parts'] as List?;
    final text =
        parts?.map((e) => (e as Map?)?['text']?.toString() ?? '').join().trim();
    if (text == null || text.isEmpty)
      throw const GeminiApiException('Réponse Gemini vide.');
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  }

  static Future<GeminiGeneratedLetter> generate({
    required String recipient,
    required String request,
    required String context,
    required String tone,
  }) async {
    final data = await _requestJson('''
Tu es un rédacteur administratif prudent et professionnel.
Rédige un modèle de courrier en français à partir des informations fournies.
N'invente aucun fait, aucune date, aucun numéro de contrat, aucune adresse et aucune référence juridique.
N'affirme pas qu'une loi s'applique si cela n'est pas certain.
Le texte doit être directement exploitable dans une lettre, avec des paragraphes clairs.
Utilise des formulations fermes uniquement si le ton demandé est ferme.
Réponds uniquement en JSON valide :
{"titre":"","objet":"","corps":""}

DESTINATAIRE : ${recipient.trim()}
DEMANDE : ${request.trim()}
CONTEXTE : ${context.trim()}
TON : $tone
''');
    String value(String key) => data[key]?.toString().trim() ?? '';
    final body = value('corps');
    if (body.isEmpty)
      throw const GeminiApiException('Gemini n’a pas généré la lettre.');
    return GeminiGeneratedLetter(
      title: value('titre').isEmpty
          ? 'Lettre personnalisée Gemini'
          : value('titre'),
      subject:
          value('objet').isEmpty ? 'Demande administrative' : value('objet'),
      body: body,
    );
  }

  static Future<String> improve(
      {required String letter, required String tone}) async {
    final data = await _requestJson('''
Tu es un rédacteur administratif prudent.
Améliore la lettre ci-dessous sans modifier les faits, dates, montants, références, noms ni demandes.
Corrige la grammaire, clarifie les paragraphes et adapte le ton demandé.
N'ajoute aucune référence juridique non présente.
Réponds uniquement en JSON valide : {"lettre":""}
TON : $tone
LETTRE :
${letter.trim()}
''');
    final result = data['lettre']?.toString().trim() ?? '';
    if (result.isEmpty)
      throw const GeminiApiException('Gemini n’a pas amélioré la lettre.');
    return result;
  }
}

class GeminiLetterWriterScreen extends StatefulWidget {
  const GeminiLetterWriterScreen({super.key, required this.settings});
  final AppSettings settings;
  @override
  State<GeminiLetterWriterScreen> createState() =>
      _GeminiLetterWriterScreenState();
}

class _GeminiLetterWriterScreenState extends State<GeminiLetterWriterScreen> {
  final recipient = TextEditingController();
  final request = TextEditingController();
  final contextDetails = TextEditingController();
  String tone = 'Professionnel';
  String domain = 'Télécommunications';
  bool loading = false;
  String? error;

  @override
  void dispose() {
    recipient.dispose();
    request.dispose();
    contextDetails.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (request.text.trim().isEmpty) {
      setState(() => error = 'Décrivez la lettre que vous souhaitez rédiger.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final generated = await GeminiLetterWriter.generate(
        recipient: recipient.text,
        request: request.text,
        context: contextDetails.text,
        tone: tone,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LetterFormScreen(
          settings: widget.settings,
          template: switch (domain) {
            'Assurance' => LetterTemplate.insurance,
            'Banque' => LetterTemplate.bank,
            'CAF' => LetterTemplate.caf,
            'CPAM' => LetterTemplate.cpam,
            'Impôts' => LetterTemplate.taxes,
            'Retraite' => LetterTemplate.retirement,
            'Employeur' => LetterTemplate.employer,
            'Logement' => LetterTemplate.housing,
            'Énergie' => LetterTemplate.energy,
            _ => LetterTemplate.telecom,
          },
          model: ProfessionalLetterModel(
              title: generated.title,
              subject: generated.subject,
              body: generated.body),
          initialRecipient: recipient.text.trim(),
        ),
      ));
    } on GeminiConfigurationException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) setState(() => error = 'Génération impossible : $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rédiger avec Gemini')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: const Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.auto_awesome_rounded),
                          SizedBox(width: 10),
                          Expanded(
                              child: Text('Assistant de rédaction IA',
                                  style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold)))
                        ]),
                        SizedBox(height: 8),
                        Text(
                            'Décrivez votre situation. Gemini prépare un modèle professionnel que vous pourrez vérifier, compléter et modifier.'),
                      ]))),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: domain,
            decoration:
                const InputDecoration(labelText: 'Domaine administratif'),
            items: const [
              'Assurance',
              'Banque',
              'CAF',
              'CPAM',
              'Impôts',
              'Retraite',
              'Employeur',
              'Logement',
              'Énergie',
              'Télécommunications'
            ]
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => domain = value);
            },
          ),
          const SizedBox(height: 14),
          TextField(
              controller: recipient,
              decoration: InputDecoration(
                  labelText: 'Organisme ou destinataire',
                  prefixIcon: const Icon(Icons.business_outlined),
                  suffixIcon: VoiceInputButton(controller: recipient))),
          const SizedBox(height: 14),
          TextField(
              controller: request,
              minLines: 4,
              maxLines: 7,
              decoration: InputDecoration(
                  labelText: 'Que souhaitez-vous demander ?',
                  alignLabelWithHint: true,
                  hintText:
                      'Exemple : résilier mon abonnement Internet à la suite de mon déménagement.',
                  suffixIcon: VoiceInputButton(controller: request))),
          const SizedBox(height: 14),
          TextField(
              controller: contextDetails,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                  labelText: 'Informations utiles',
                  alignLabelWithHint: true,
                  hintText:
                      'Dates, démarches déjà effectuées, problème rencontré…',
                  suffixIcon: VoiceInputButton(controller: contextDetails))),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: tone,
            decoration: const InputDecoration(labelText: 'Ton de la lettre'),
            items: const ['Courtois', 'Professionnel', 'Ferme']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => tone = value);
            },
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                    padding: const EdgeInsets.all(14), child: Text(error!))),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: loading ? null : _generate,
            icon: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_rounded),
            label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Text(loading
                    ? 'Gemini rédige la lettre…'
                    : 'Générer la lettre avec Gemini')),
          ),
          const SizedBox(height: 12),
          Text(
              'Vérifiez toujours le contenu avant l’envoi. Le texte saisi est transmis à Gemini pour générer la lettre.',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

class GeminiConfigurationException implements Exception {
  const GeminiConfigurationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeminiApiException implements Exception {
  const GeminiApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LocalDocumentAnalyzer {
  static DocumentInsight analyze(String rawText) {
    final text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = text.toLowerCase();
    String category = 'Courrier administratif';
    const categories = <String, List<String>>{
      'Facture de gaz': ['primagaz', 'facture de gaz', 'consommation gaz'],
      'Facture d’électricité': ['facture électricité', 'facture electricite'],
      'Énergie et télécom': [
        'électricité',
        'gaz',
        'internet',
        'téléphone',
        'abonnement'
      ],
      'Impôts et finances': [
        'impôt',
        'fiscal',
        'trésor public',
        'taxe',
        'amende'
      ],
      'Prestations sociales': [
        'caf',
        'allocation',
        'msa',
        'retraite',
        'carsat',
        'cpam'
      ],
      'Assurance': ['assurance', 'sinistre', 'indemnisation'],
      'Banque et crédit': ['banque', 'prélèvement', 'crédit', 'mensualité'],
      'Travail et employeur': [
        'employeur',
        'salaire',
        'contrat de travail',
        'ressources humaines'
      ],
      'Logement': ['loyer', 'bail', 'propriétaire', 'locataire'],
      'Santé': ['hôpital', 'médecin', 'mutuelle', 'santé', 'soins'],
    };
    for (final entry in categories.entries) {
      if (entry.value.any(lower.contains)) {
        category = entry.key;
        break;
      }
    }

    final dates = <String>{};
    final datePatterns = [
      RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b'),
      RegExp(
          r'\b\d{1,2}\s+(?:janvier|février|fevrier|mars|avril|mai|juin|juillet|août|aout|septembre|octobre|novembre|décembre|decembre)\s+\d{4}\b',
          caseSensitive: false),
    ];
    for (final pattern in datePatterns) {
      for (final match in pattern.allMatches(text)) {
        dates.add(match.group(0)!.trim());
      }
    }

    final amounts = <String>{};
    for (final match in RegExp(
            r'\b\d{1,3}(?:[ .]\d{3})*(?:[,.]\d{1,2})?\s?(?:€|euros?)(?=\s|[.,;:!?)]|$)',
            caseSensitive: false)
        .allMatches(text)) {
      amounts.add(match.group(0)!.trim());
    }

    final references = <String>{};
    for (final match in RegExp(
            r'(?:référence|ref\.?|dossier|contrat|client|allocataire|facture)\s*[:°nº#-]*\s*([A-Z0-9][A-Z0-9\-/.]{3,})',
            caseSensitive: false)
        .allMatches(text)) {
      references.add(match.group(0)!.trim());
    }

    String organisation = 'Non identifiée';
    const organisations = [
      'PRIMAGAZ',
      'EDF',
      'ENGIE',
      'TotalEnergies',
      'Veolia',
      'Suez',
      'Orange',
      'SFR',
      'Free',
      'Bouygues',
      'CAF',
      'CPAM',
      'CARSAT',
      'MSA',
      'URSSAF',
      'France Travail',
      'Assurance Maladie',
      'Trésor public'
    ];
    for (final org in organisations) {
      if (lower.contains(org.toLowerCase())) {
        organisation = org;
        break;
      }
    }

    final actions = <String>[];
    final documents = <String>[];
    final warnings = <String>[];
    if (RegExp(r'\b(payer|régler|versement|prélèvement)\b',
            caseSensitive: false)
        .hasMatch(text)) {
      actions.add(
          'Vérifier le montant, le bénéficiaire et les modalités de paiement.');
      warnings.add(
          'Ne communiquez jamais vos coordonnées bancaires à partir d’un lien douteux.');
    }
    if (RegExp(r'\b(transmettre|envoyer|joindre|fournir)\b',
            caseSensitive: false)
        .hasMatch(text)) {
      actions.add('Préparer et transmettre les justificatifs demandés.');
      documents.add('Copie du courrier reçu');
      documents.add('Justificatifs expressément demandés');
    }
    if (RegExp(r'\b(contester|recours|réclamation)\b', caseSensitive: false)
        .hasMatch(text)) {
      actions.add('Vérifier le délai et les modalités de contestation.');
      documents.add('Preuves et documents soutenant votre contestation');
      warnings.add(
          'Conservez une preuve d’envoi et une copie complète de votre réponse.');
    }
    if (dates.isNotEmpty)
      actions.add('Enregistrer l’échéance et programmer un rappel.');
    if (actions.isEmpty)
      actions.add(
          'Relire le courrier et demander des précisions avant toute action importante.');
    if (documents.isEmpty)
      documents.add('Le courrier original et toute pièce liée au dossier');
    if (warnings.isEmpty)
      warnings.add(
          'Vérifiez toujours les dates, références et coordonnées avant de répondre.');

    final urgentPattern = RegExp(
        r'\b(urgent|mise en demeure|dernier rappel|sous \d+ jours|avant le|au plus tard|suspension|majoration)\b',
        caseSensitive: false);
    final importantPattern = RegExp(
        r'\b(répondre|transmettre|fournir|payer|régler|convocation|délai)\b',
        caseSensitive: false);
    final priority = urgentPattern.hasMatch(text)
        ? 'Urgent'
        : (importantPattern.hasMatch(text) || dates.isNotEmpty
            ? 'Important'
            : 'Information');

    final sentences = rawText
        .replaceAll('\n', ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((e) => e.trim())
        .where((e) => e.length > 25)
        .take(3)
        .toList();
    final joined = sentences.join(' ');
    final summary = joined.isEmpty
        ? 'Le texte est trop court pour produire un résumé fiable.'
        : (joined.length > 430 ? '${joined.substring(0, 430)}…' : joined);

    return DocumentInsight(
      category: category,
      summary: summary,
      organisation: organisation,
      dates: dates.take(5).toList(),
      amounts: amounts.take(5).toList(),
      references: references.take(5).toList(),
      actions: actions,
      priority: priority,
      documentsToPrepare: documents.toSet().toList(),
      warnings: warnings.toSet().toList(),
      documentType: RegExp(r'\b(facture|total ttc|tva|hors taxes?)\b',
                  caseSensitive: false)
              .hasMatch(text)
          ? (lower.contains('gaz') || lower.contains('primagaz')
              ? 'facture_gaz'
              : lower.contains('électricité') || lower.contains('electricite')
                  ? 'facture_electricite'
                  : lower.contains('eau')
                      ? 'facture_eau'
                      : lower.contains('orange') ||
                              lower.contains('sfr') ||
                              lower.contains('bouygues') ||
                              lower.contains('free')
                          ? 'facture_telecom'
                          : 'facture_autre')
          : 'courrier',
      supplier: organisation == 'Non identifiée' ? '' : organisation,
      dueDate: dates.isEmpty ? '' : dates.first,
      amountDue: amounts.isEmpty ? '' : amounts.last,
      amountDetails: amounts
          .map((amount) =>
              DocumentAmountItem(label: 'Montant repéré', amount: amount))
          .toList(),
    );
  }
}

class SmartAnalysisScreen extends StatefulWidget {
  const SmartAnalysisScreen({
    super.key,
    required this.sourceText,
    required this.procedureStore,
  });

  final String sourceText;
  final ProcedureStore procedureStore;

  @override
  State<SmartAnalysisScreen> createState() => _SmartAnalysisScreenState();
}

class _SmartAnalysisScreenState extends State<SmartAnalysisScreen> {
  late DocumentInsight insight;
  final Set<int> completedActions = <int>{};
  bool addedToProcedures = false;
  bool showSimpleExplanation = false;
  DateTime? reminderDate;
  bool aiLoading = false;
  bool aiUsed = false;
  String? aiError;
  bool showDetails = false;

  @override
  void initState() {
    super.initState();
    insight = LocalDocumentAnalyzer.analyze(widget.sourceText);
    if (GeminiDocumentAnalyzer.isConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _explainWithGemini());
    } else {
      aiError =
          'Gemini n’est pas configuré. Relancez l’application avec votre clé API.';
    }
  }

  Color _priorityColor(BuildContext context) => switch (insight.priority) {
        'Urgent' => Colors.red,
        'Important' => Colors.orange,
        _ => Colors.green,
      };

  IconData get _priorityIcon => switch (insight.priority) {
        'Urgent' => Icons.warning_amber_rounded,
        'Important' => Icons.schedule_outlined,
        _ => Icons.info_outline,
      };

  String get _simpleExplanation {
    if (insight.simpleExplanation.trim().isNotEmpty) {
      return insight.simpleExplanation.trim();
    }
    final organisation = insight.organisation == 'Non identifiée'
        ? 'un organisme administratif'
        : insight.organisation;
    final deadline = insight.dates.isEmpty
        ? 'Aucune date limite précise n’a été reconnue.'
        : 'Une date importante a été repérée : ${insight.dates.first}.';
    final amount = insight.amounts.isEmpty
        ? ''
        : ' Le courrier mentionne aussi ${insight.amounts.first}.';
    final consequence = insight.priority == 'Urgent'
        ? 'Il vaut mieux agir rapidement pour éviter un retard, une suspension ou des frais supplémentaires.'
        : insight.priority == 'Important'
            ? 'Le courrier semble demander une action ou une vérification.'
            : 'Le courrier semble surtout informatif, mais il faut vérifier les détails.';
    return 'Ce courrier vient probablement de $organisation. '
        '${insight.actions.first} $deadline$amount $consequence';
  }

  int get _completionScore {
    final total = insight.actions.length + insight.documentsToPrepare.length;
    if (total == 0) return 100;
    final checked = completedActions.length.clamp(0, insight.actions.length);
    final base = ((checked / total) * 100).round();
    final reminderBonus = reminderDate == null ? 0 : 10;
    final procedureBonus = addedToProcedures ? 10 : 0;
    return (base + reminderBonus + procedureBonus).clamp(0, 100).toInt();
  }

  Widget card(
          BuildContext context, IconData icon, String title, Widget child) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );

  Widget chips(List<String> values, String empty) => values.isEmpty
      ? Text(empty)
      : Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((e) => Chip(label: Text(e))).toList(),
        );

  Widget _amountBreakdown() {
    final items = insight.amountDetails;
    if (items.isEmpty) {
      return chips(insight.amounts, 'Aucun montant clairement détecté.');
    }
    return Column(
      children: items
          .map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(item.label)),
                    const SizedBox(width: 12),
                    Text(item.amount,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _invoiceOverview(BuildContext context) {
    final supplier =
        insight.supplier.isNotEmpty ? insight.supplier : insight.organisation;
    final amount = insight.amountDue.isNotEmpty
        ? insight.amountDue
        : (insight.amountDetails.isNotEmpty
            ? insight.amountDetails.last.amount
            : (insight.amounts.isNotEmpty
                ? insight.amounts.last
                : 'Non détecté'));
    final rawType = insight.documentType.toLowerCase();
    final type = switch (rawType) {
      'facture_gaz' => 'Facture de gaz',
      'facture_electricite' => 'Facture d’électricité',
      'facture_eau' => 'Facture d’eau',
      'facture_telecom' => 'Facture de téléphone',
      'facture_internet' => 'Facture Internet',
      'facture_assurance' => 'Facture d’assurance',
      _ =>
        insight.category.trim().isEmpty ? 'Facture' : insight.category.trim(),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const CircleAvatar(
                backgroundColor: Color(0xFF123B78),
                child: Icon(Icons.receipt_long_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  type,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Text('Fournisseur', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              supplier == 'Non identifiée' ? 'Non détecté' : supplier,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            Text('Montant à payer',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              amount,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF20B98B),
                  ),
            ),
            const SizedBox(height: 18),
            Text('À payer avant',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              insight.dueDate.isEmpty ? 'Date non détectée' : insight.dueDate,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (insight.billingPeriod.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Période : ${insight.billingPeriod}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget bulletList(List<String> values,
          {IconData icon = Icons.check_circle_outline}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: values
            .map(
              (value) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 9),
                    Expanded(child: Text(value)),
                  ],
                ),
              ),
            )
            .toList(),
      );

  Widget _actionChecklist() => Column(
        children: List.generate(insight.actions.length, (index) {
          final checked = completedActions.contains(index);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: checked,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              insight.actions[index],
              style: checked
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            onChanged: (value) => setState(() {
              if (value ?? false) {
                completedActions.add(index);
              } else {
                completedActions.remove(index);
              }
            }),
          );
        }),
      );

  Future<void> _explainWithGemini() async {
    if (aiLoading) return;
    setState(() {
      aiLoading = true;
      aiError = null;
    });
    try {
      final result = await GeminiDocumentAnalyzer.analyze(widget.sourceText);
      if (!mounted) return;
      setState(() {
        insight = result;
        aiUsed = true;
        showSimpleExplanation = true;
        completedActions.clear();
      });
    } on GeminiConfigurationException catch (error) {
      if (!mounted) return;
      setState(() => aiError = error.message);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => aiError =
          'Gemini met trop de temps à répondre. Vérifiez Internet puis réessayez.');
    } catch (error) {
      if (!mounted) return;
      setState(() => aiError = 'Analyse Gemini impossible : $error');
    } finally {
      if (mounted) setState(() => aiLoading = false);
    }
  }

  Future<void> _addToProcedures() async {
    if (addedToProcedures) return;
    final now = DateTime.now();
    await widget.procedureStore.add(
      AdministrativeProcedure(
        id: now.microsecondsSinceEpoch.toString(),
        title: insight.organisation == 'Non identifiée'
            ? insight.category
            : 'Courrier ${insight.organisation}',
        organisation: insight.organisation,
        category: insight.category,
        letter: widget.sourceText.trim(),
        createdAt: now,
        updatedAt: now,
        status: insight.priority == 'Urgent'
            ? ProcedureStatus.reminder
            : ProcedureStatus.created,
        reminderDate: reminderDate,
        notes: 'Source : ${aiUsed ? 'Gemini Flash-Lite' : 'Analyse locale'}\n'
            'Priorité : ${insight.priority}\n'
            'Score de préparation : $_completionScore %\n'
            'Actions conseillées : ${insight.actions.join(' • ')}',
      ),
    );
    if (!mounted) return;
    setState(() => addedToProcedures = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Démarche ajoutée à Mes démarches.')),
    );
  }

  Future<void> _chooseReminder() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: reminderDate ?? now.add(const Duration(days: 3)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
      helpText: 'Programmer un rappel',
      cancelText: 'Annuler',
      confirmText: 'Enregistrer',
    );
    if (selected == null || !mounted) return;
    setState(() => reminderDate = selected);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Rappel prévu le ${selected.day.toString().padLeft(2, '0')}/'
          '${selected.month.toString().padLeft(2, '0')}/${selected.year}.',
        ),
      ),
    );
  }

  String _analysisReport() => 'ADMINFACILE • ANALYSE DU COURRIER\n\n'
      'Priorité : ${insight.priority}\n'
      'Score de préparation : $_completionScore %\n'
      'Résumé : ${insight.summary}\n\n'
      'Explication simple : $_simpleExplanation\n\n'
      'Organisme : ${insight.organisation}\n'
      'Catégorie : ${insight.category}\n'
      'Dates : ${insight.dates.join(', ')}\n'
      'Montants : ${insight.amountDetails.isEmpty ? insight.amounts.join(', ') : insight.amountDetails.map((e) => '${e.label}: ${e.amount}').join(' ; ')}\n'
      'Références : ${insight.references.join(', ')}\n\n'
      'Actions :\n- ${insight.actions.join('\n- ')}\n\n'
      'Pièces à préparer :\n- ${insight.documentsToPrepare.join('\n- ')}';

  Future<void> _copyAnalysis() async {
    await Clipboard.setData(ClipboardData(text: _analysisReport()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Analyse copiée')),
    );
  }

  Future<void> _shareAnalysis() async {
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Analyse administrative AdminFacile',
        text: _analysisReport(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(insight.isInvoice
              ? 'Analyse de votre facture'
              : 'Analyse de votre document'),
          actions: [
            IconButton(
              tooltip: 'Partager l’analyse',
              onPressed: _shareAnalysis,
              icon: const Icon(Icons.share_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (aiLoading && !aiUsed) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Row(children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Gemini identifie le document et extrait uniquement les informations utiles…',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (!insight.isInvoice && !aiLoading)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _priorityColor(context).withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _priorityColor(context).withValues(alpha: .45),
                    ),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: _priorityColor(context),
                      foregroundColor: Colors.white,
                      child: Icon(_priorityIcon),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Priorité : ${insight.priority}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            insight.priority == 'Urgent'
                                ? 'Une action rapide semble nécessaire.'
                                : insight.priority == 'Important'
                                    ? 'Une action ou une échéance a été détectée.'
                                    : 'Aucune urgence évidente n’a été détectée.',
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              if (!insight.isInvoice && !aiLoading) const SizedBox(height: 10),
              if (aiUsed) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: Icon(Icons.auto_awesome, size: 18),
                    label: Text('Analyse réalisée avec Gemini'),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (aiError != null && !aiLoading) ...[
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(aiError!),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _explainWithGemini,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer avec Gemini'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (insight.isInvoice) _invoiceOverview(context),
              if (insight.isInvoice) const SizedBox(height: 12),
              if (!insight.isInvoice || showDetails)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.task_alt_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Préparation du dossier : $_completionScore %',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: _completionScore / 100),
                        const SizedBox(height: 8),
                        Text(
                          _completionScore >= 80
                              ? 'Votre dossier semble presque prêt.'
                              : 'Cochez les actions réalisées et programmez un rappel.',
                        ),
                      ],
                    ),
                  ),
                ),
              if (!insight.isInvoice || showDetails)
                card(
                  context,
                  Icons.summarize_outlined,
                  'Résumé du document',
                  Text(insight.summary),
                ),
              if (!insight.isInvoice || showDetails)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.lightbulb_outline_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Explication en langage simple',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 250),
                          crossFadeState: showSimpleExplanation
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    aiLoading ? null : _explainWithGemini,
                                icon: aiLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.auto_awesome),
                                label: Text(
                                  aiLoading
                                      ? 'Analyse Gemini en cours…'
                                      : 'Expliquer simplement avec Gemini',
                                ),
                              ),
                              if (!GeminiDocumentAnalyzer.isConfigured) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Clé Gemini non détectée. Lancez l’application avec '
                                  '--dart-define=GEMINI_API_KEY=VOTRE_CLE.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                              if (aiError != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  aiError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed:
                                      aiLoading ? null : _explainWithGemini,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Réessayer'),
                                ),
                              ],
                            ],
                          ),
                          secondChild: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_simpleExplanation),
                              const SizedBox(height: 10),
                              TextButton.icon(
                                onPressed: () => setState(
                                  () => showSimpleExplanation = false,
                                ),
                                icon: const Icon(Icons.visibility_off_outlined),
                                label: const Text('Masquer l’explication'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!insight.isInvoice || showDetails)
                card(
                  context,
                  Icons.account_balance_outlined,
                  'Document identifié',
                  Text(
                    'Organisme : ${insight.organisation}\n'
                    'Catégorie : ${insight.category}',
                  ),
                ),
              if (!insight.isInvoice || showDetails)
                card(
                  context,
                  Icons.checklist_outlined,
                  'Plan d’action',
                  _actionChecklist(),
                ),
              if (!insight.isInvoice || showDetails)
                card(
                  context,
                  Icons.folder_copy_outlined,
                  'Pièces à préparer',
                  bulletList(
                    insight.documentsToPrepare,
                    icon: Icons.attach_file,
                  ),
                ),
              if (!insight.isInvoice || showDetails)
                card(
                  context,
                  Icons.error_outline,
                  'Conséquences et points de vigilance',
                  bulletList(insight.warnings, icon: Icons.shield_outlined),
                ),
              if (!insight.isInvoice || showDetails)
                card(
                  context,
                  Icons.event_outlined,
                  'Dates repérées',
                  chips(insight.dates, 'Aucune date clairement détectée.'),
                ),
              if (!insight.isInvoice || showDetails)
                card(
                  context,
                  Icons.euro_outlined,
                  'Montants repérés',
                  _amountBreakdown(),
                ),
              if (!insight.isInvoice || showDetails)
                card(
                  context,
                  Icons.numbers_outlined,
                  'Références repérées',
                  chips(
                    insight.references,
                    'Aucune référence clairement détectée.',
                  ),
                ),
              if (insight.isInvoice) ...[
                Text(
                  'Que souhaitez-vous faire ?',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReplyScreen(
                        sourceText: widget.sourceText,
                        insight: insight,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Contester cette facture'),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _chooseReminder,
                  icon: const Icon(Icons.alarm_add_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Text('Créer un rappel de paiement'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 4),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DocumentChatScreen(
                      sourceText: widget.sourceText,
                      initialInsight: insight,
                    ),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Poser une question sur ce document'),
                ),
              ),
              if (!insight.isInvoice) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReplyScreen(
                        sourceText: widget.sourceText,
                        insight: insight,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    child: Text('Générer une réponse adaptée'),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _chooseReminder,
                  icon: const Icon(Icons.alarm_add_outlined),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Text(
                      reminderDate == null
                          ? 'Programmer un rappel'
                          : 'Rappel : ${reminderDate!.day.toString().padLeft(2, '0')}/'
                              '${reminderDate!.month.toString().padLeft(2, '0')}/'
                              '${reminderDate!.year}',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: addedToProcedures ? null : _addToProcedures,
                  icon: Icon(
                    addedToProcedures ? Icons.check_circle : Icons.add_task,
                  ),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Text(
                      addedToProcedures
                          ? 'Ajouté à Mes démarches'
                          : 'Ajouter à Mes démarches',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyAnalysis,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copier'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _shareAnalysis,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Partager'),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 14),
              Text(
                'Analyse indicative : vérifiez toujours les dates, '
                'montants, références et obligations avant d’envoyer une réponse.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
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
  const ReplyScreen({super.key, required this.sourceText, this.insight});
  final String sourceText;
  final DocumentInsight? insight;
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
    final detected = widget.insight;
    final contextLine = detected == null
        ? ''
        : 'Concernant votre courrier de type ${detected.category.toLowerCase()}${detected.organisation == 'Non identifiée' ? '' : ' provenant de ${detected.organisation}'}, ';
    final body = switch (intent) {
      ReplyIntent.understand =>
        '${contextLine}je vous remercie de bien vouloir m’apporter des précisions complémentaires afin que je puisse comprendre les démarches attendues.',
      ReplyIntent.agree =>
        '${contextLine}je vous confirme avoir pris connaissance de votre courrier et accepter la proposition ou la demande indiquée.',
      ReplyIntent.disagree =>
        '${contextLine}je conteste les éléments indiqués et vous remercie de réexaminer ma situation ainsi que de me transmettre les justificatifs utiles.',
      ReplyIntent.askDelay =>
        '${contextLine}j’ai bien reçu votre courrier. En raison de ma situation actuelle, je sollicite un délai supplémentaire pour effectuer les démarches demandées.',
      ReplyIntent.sendDocuments =>
        '${contextLine}veuillez trouver ci-joint les documents demandés. Je vous remercie de bien vouloir confirmer leur bonne réception.',
    };
    final extra = details.text.trim();
    draft.text = '''Objet : Réponse à votre courrier

Madame, Monsieur,

$body

${extra.isEmpty ? '' : 'Précisions complémentaires :\n$extra\n\n'}Je reste à votre disposition pour tout complément d’information.

Cordialement,''';
    setState(() {});
  }

  Future<Uint8List> _buildReplyPdf() async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => [
          pw.Text('AdminFacile - Réponse administrative',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 24),
          pw.Text(draft.text.trim(),
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 4)),
        ],
      ),
    );
    return document.save();
  }

  Future<void> _shareReply({bool email = false}) async {
    if (draft.text.trim().isEmpty) return;
    final bytes = await _buildReplyPdf();
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/reponse_adminfacile_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: email ? 'Réponse à votre courrier' : 'Document AdminFacile',
        text: email
            ? 'Bonjour, veuillez trouver ci-joint ma réponse.'
            : 'Document préparé avec AdminFacile.',
      ),
    );
  }

  Future<void> _printReply() async {
    if (draft.text.trim().isEmpty) return;
    final bytes = await _buildReplyPdf();
    await Printing.layoutPdf(
        onLayout: (_) async => bytes, name: 'Réponse AdminFacile');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Réponse assistée • V3.1')),
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
          const Text('Envoyer ou conserver',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.tonalIcon(
                onPressed: draft.text.trim().isEmpty
                    ? null
                    : () => _shareReply(email: true),
                icon: const Icon(Icons.email_outlined),
                label: const Text('E-mail')),
            FilledButton.tonalIcon(
                onPressed: draft.text.trim().isEmpty ? null : _shareReply,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Transmettre')),
            FilledButton.tonalIcon(
                onPressed: draft.text.trim().isEmpty ? null : _printReply,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Imprimer')),
            OutlinedButton.icon(
                onPressed: draft.text.trim().isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                            ClipboardData(text: draft.text));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Réponse copiée')));
                      },
                icon: const Icon(Icons.copy),
                label: const Text('Copier')),
          ]),
          const SizedBox(height: 18),
          const Text(
            'Modèle général : vérifiez toujours les dates, montants, références et obligations du courrier original.',
          ),
        ]),
      );
}

class IntentMatch {
  const IntentMatch(
      {required this.template,
      required this.model,
      required this.score,
      this.organisation = ''});
  final LetterTemplate template;
  final ProfessionalLetterModel model;
  final int score;
  final String organisation;
}

class LocalIntentEngine {
  static const Map<String, LetterTemplate> _organisations = {
    'orange': LetterTemplate.telecom,
    'sfr': LetterTemplate.telecom,
    'bouygues': LetterTemplate.telecom,
    'free': LetterTemplate.telecom,
    'red by sfr': LetterTemplate.telecom,
    'sosh': LetterTemplate.telecom,
    'edf': LetterTemplate.energy,
    'engie': LetterTemplate.energy,
    'totalenergies': LetterTemplate.energy,
    'enedis': LetterTemplate.energy,
    'grdf': LetterTemplate.energy,
    'caf': LetterTemplate.caf,
    'cpam': LetterTemplate.cpam,
    'ameli': LetterTemplate.cpam,
    'impots': LetterTemplate.taxes,
    'impôt': LetterTemplate.taxes,
    'carsat': LetterTemplate.retirement,
    'agirc-arrco': LetterTemplate.retirement,
  };

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ô', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<IntentMatch> analyze(String text) {
    final query = _normalize(text);
    LetterTemplate? forcedTemplate;
    var organisation = '';
    for (final entry in _organisations.entries) {
      if (query.contains(_normalize(entry.key))) {
        forcedTemplate = entry.value;
        organisation = entry.key;
        break;
      }
    }

    final categoryKeywords = <LetterTemplate, List<String>>{
      LetterTemplate.insurance: [
        'assurance',
        'assureur',
        'mutuelle',
        'sinistre',
        'indemnisation'
      ],
      LetterTemplate.bank: [
        'banque',
        'bancaire',
        'carte',
        'prelevement',
        'virement',
        'compte'
      ],
      LetterTemplate.caf: ['caf', 'allocation', 'apl', 'rsa', 'prime activite'],
      LetterTemplate.cpam: [
        'cpam',
        'ameli',
        'securite sociale',
        'remboursement sante',
        'arret maladie'
      ],
      LetterTemplate.taxes: ['impot', 'fiscal', 'taxe', 'tresor public'],
      LetterTemplate.retirement: ['retraite', 'carsat', 'pension', 'agirc'],
      LetterTemplate.employer: [
        'employeur',
        'travail',
        'salaire',
        'conge',
        'demission'
      ],
      LetterTemplate.housing: [
        'logement',
        'loyer',
        'bail',
        'proprietaire',
        'locataire',
        'preavis'
      ],
      LetterTemplate.energy: [
        'electricite',
        'gaz',
        'energie',
        'compteur',
        'edf',
        'engie'
      ],
      LetterTemplate.telecom: [
        'telephone',
        'mobile',
        'internet',
        'box',
        'fibre',
        'operateur'
      ],
    };

    final actionKeywords = <String, List<String>>{
      'resiliation': [
        'resilier',
        'resiliation',
        'mettre fin',
        'arreter abonnement',
        'cloturer contrat'
      ],
      'contestation': [
        'contester',
        'contestation',
        'pas d accord',
        'erreur',
        'injustifie'
      ],
      'remboursement': ['rembourser', 'remboursement', 'trop percu', 'avoir'],
      'facture': ['facture', 'facturation', 'montant'],
      'panne': ['panne', 'coupure', 'interruption', 'dysfonctionnement'],
      'preavis': ['preavis', 'quitter logement', 'depart logement'],
      'demission': ['demission', 'quitter emploi'],
      'attestation': ['attestation', 'certificat', 'justificatif'],
      'echelonnement': [
        'echelonnement',
        'paiement en plusieurs fois',
        'delai de paiement'
      ],
      'changement': ['changement', 'modifier', 'mise a jour'],
    };

    final matches = <IntentMatch>[];
    for (final template in LetterTemplate.values) {
      if (forcedTemplate != null && template != forcedTemplate) continue;
      var categoryScore = 0;
      for (final kw in categoryKeywords[template] ?? const <String>[]) {
        if (query.contains(kw)) categoryScore += 12;
      }
      for (final model in template.models) {
        final haystack =
            _normalize('${model.title} ${model.subject} ${model.body}');
        var score = categoryScore;
        for (final word in query.split(' ').where((w) => w.length >= 4)) {
          if (haystack.contains(word)) score += 2;
        }
        for (final entry in actionKeywords.entries) {
          final actionDetected = entry.value.any(query.contains);
          if (actionDetected && haystack.contains(entry.key)) score += 20;
          if (actionDetected && entry.value.any(haystack.contains)) score += 12;
        }
        if (forcedTemplate == template) score += 25;
        matches.add(IntentMatch(
            template: template,
            model: model,
            score: score,
            organisation: organisation));
      }
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  static IntentMatch best(String text) => analyze(text).first;
}

class ProblemDescriptionScreen extends StatefulWidget {
  const ProblemDescriptionScreen({super.key, required this.settings});
  final AppSettings settings;
  @override
  State<ProblemDescriptionScreen> createState() =>
      _ProblemDescriptionScreenState();
}

class _ProblemDescriptionScreenState extends State<ProblemDescriptionScreen> {
  final controller = TextEditingController();
  final SpeechToText speech = SpeechToText();
  bool available = false;
  bool listening = false;
  String? localeId;
  String prefix = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final ok = await speech.initialize(onStatus: (status) {
      if (mounted) setState(() => listening = status == 'listening');
    }, onError: (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Microphone : ${error.errorMsg}')));
    });
    if (ok) {
      for (final locale in await speech.locales()) {
        if (locale.localeId.toLowerCase().startsWith('fr')) {
          localeId = locale.localeId;
          break;
        }
      }
    }
    if (mounted) setState(() => available = ok);
  }

  Future<void> _toggle() async {
    if (speech.isListening) {
      await speech.stop();
      return;
    }
    if (!available) {
      await _initSpeech();
      if (!available) return;
    }
    prefix = controller.text.trim();
    await speech.listen(
      onResult: (result) {
        final spoken = result.recognizedWords.trim();
        controller.text =
            '$prefix${prefix.isEmpty || spoken.isEmpty ? '' : ' '}$spoken';
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
        if (mounted) setState(() {});
      },
      listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          listenMode: ListenMode.dictation),
    );
  }

  void _generate() {
    final text = controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Décrivez d’abord votre problème.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssistantSuggestionsScreen(
          settings: widget.settings,
          request: text,
        ),
      ),
    );
  }

  @override
  void dispose() {
    speech.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Assistant administratif • V7.0')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Expliquez naturellement votre besoin',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Exemples : « résilier Orange », « contester une facture EDF », « préavis logement » ou « remboursement CPAM ».'),
          const SizedBox(height: 16),
          TextField(
              controller: controller,
              minLines: 8,
              maxLines: 14,
              decoration: InputDecoration(
                  labelText: 'Votre problème',
                  alignLabelWithHint: true,
                  suffixIcon: IconButton(
                      onPressed: _toggle,
                      icon: Icon(listening ? Icons.stop_circle : Icons.mic)))),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
              onPressed: _toggle,
              icon: Icon(listening ? Icons.stop_circle : Icons.mic),
              label: Text(
                  listening ? 'Arrêter la dictée' : 'Décrire avec le micro')),
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome),
              label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Afficher les meilleures lettres'))),
        ]),
      );
}

class AssistantSuggestion {
  const AssistantSuggestion({required this.record, required this.score});
  final JsonLetterRecord record;
  final int score;
}

class AssistantSuggestionsScreen extends StatefulWidget {
  const AssistantSuggestionsScreen({
    super.key,
    required this.settings,
    required this.request,
  });

  final AppSettings settings;
  final String request;

  @override
  State<AssistantSuggestionsScreen> createState() =>
      _AssistantSuggestionsScreenState();
}

class _AssistantSuggestionsScreenState
    extends State<AssistantSuggestionsScreen> {
  bool loading = true;
  String? error;
  List<AssistantSuggestion> suggestions = const [];

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôö]'), 'o')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> _loadSuggestions() async {
    try {
      final raw = await rootBundle.loadString('assets/letters/library.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final records = (data['templates'] as List<dynamic>)
          .map((e) => JsonLetterRecord.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();

      final query = _normalize(widget.request);
      final words = query.split(' ').where((word) => word.length > 2).toSet();

      const organisationCategories = <String, String>{
        'orange': 'telecommunications',
        'sosh': 'telecommunications',
        'sfr': 'telecommunications',
        'red': 'telecommunications',
        'bouygues': 'telecommunications',
        'free': 'telecommunications',
        'edf': 'energie',
        'engie': 'energie',
        'enedis': 'energie',
        'grdf': 'energie',
        'totalenergies': 'energie',
        'caf': 'caf',
        'cpam': 'cpam',
        'ameli': 'cpam',
        'carsat': 'retraite',
        'agirc': 'retraite',
      };

      String? forcedCategory;
      for (final entry in organisationCategories.entries) {
        if (query.contains(entry.key)) {
          forcedCategory = entry.value;
          break;
        }
      }

      const actions = <String, List<String>>{
        'resiliation': [
          'resilier',
          'resiliation',
          'annuler',
          'mettre fin',
          'cloturer'
        ],
        'contestation': ['contester', 'contestation', 'injustifie', 'erreur'],
        'remboursement': ['rembourser', 'remboursement', 'trop percu'],
        'facture': ['facture', 'facturation'],
        'panne': ['panne', 'coupure', 'dysfonctionnement'],
        'preavis': ['preavis', 'quitter logement'],
        'demission': ['demission', 'quitter emploi'],
      };

      String? detectedAction;
      for (final entry in actions.entries) {
        if (entry.value.any(query.contains)) {
          detectedAction = entry.key;
          break;
        }
      }

      final scored = <AssistantSuggestion>[];
      for (final record in records) {
        final title = _normalize(record.title);
        final subject = _normalize(record.subject);
        final category = _normalize('${record.category} ${record.subcategory}');
        final keywords = _normalize(record.keywords.join(' '));
        final body = _normalize(record.body);
        final haystack = '$title $subject $category $keywords $body';

        if (forcedCategory != null && !category.contains(forcedCategory)) {
          continue;
        }

        var score = forcedCategory == null ? 0 : 200;
        if (forcedCategory != null && category.contains(forcedCategory)) {
          score += 100;
        }
        for (final word in words) {
          if (title.contains(word)) score += 18;
          if (subject.contains(word)) score += 14;
          if (keywords.contains(word)) score += 12;
          if (category.contains(word)) score += 10;
          if (body.contains(word)) score += 2;
        }

        if (detectedAction != null) {
          final actionWords = actions[detectedAction]!;
          if (haystack.contains(detectedAction)) score += 120;
          if (actionWords.any(haystack.contains)) score += 80;
          if (!haystack.contains(detectedAction) &&
              !actionWords.any(haystack.contains)) {
            continue;
          }
        }

        if (title.contains(query)) score += 60;
        if (subject.contains(query)) score += 40;
        if (title.contains('standard') || keywords.contains('standard'))
          score += 8;

        if (score > 0) {
          scored.add(AssistantSuggestion(record: record, score: score));
        }
      }

      scored.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0
            ? byScore
            : a.record.title.compareTo(b.record.title);
      });

      if (!mounted) return;
      setState(() {
        suggestions = scored.take(5).toList();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  LetterTemplate _templateFor(String value) => switch (value) {
        'Assurance' => LetterTemplate.insurance,
        'Banque' => LetterTemplate.bank,
        'CAF' => LetterTemplate.caf,
        'CPAM' => LetterTemplate.cpam,
        'Impôts' => LetterTemplate.taxes,
        'Retraite' => LetterTemplate.retirement,
        'Employeur' => LetterTemplate.employer,
        'Logement' => LetterTemplate.housing,
        'Énergie' => LetterTemplate.energy,
        _ => LetterTemplate.telecom,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Lettres recommandées')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text('Recherche impossible : $error'))
                : ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      Text(
                        'Votre demande',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(widget.request),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Les 5 courriers les plus adaptés',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Vérifiez le titre et l’objet avant de personnaliser la lettre.',
                      ),
                      const SizedBox(height: 12),
                      if (suggestions.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Aucun courrier suffisamment pertinent n’a été trouvé. '
                              'Précisez l’organisme et l’action, par exemple : « résilier box Orange ».',
                            ),
                          ),
                        ),
                      ...suggestions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final suggestion = entry.value;
                        final record = suggestion.record;
                        final confidence = suggestion.score >= 300
                            ? 'Correspondance forte'
                            : suggestion.score >= 180
                                ? 'Correspondance probable'
                                : 'Suggestion à vérifier';
                        return Card(
                          child: ListTile(
                            minVerticalPadding: 14,
                            leading: CircleAvatar(child: Text('${index + 1}')),
                            title: Text(
                              record.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '$confidence • ${record.category} • ${record.subcategory}\n${record.subject}',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LetterFormScreen(
                                  settings: widget.settings,
                                  template: _templateFor(record.category),
                                  model: ProfessionalLetterModel(
                                    title: record.title,
                                    subject: record.subject,
                                    body: record.body,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
      );
}

enum LetterTemplate {
  insurance,
  bank,
  caf,
  cpam,
  taxes,
  retirement,
  employer,
  housing,
  energy,
  telecom
}

extension LetterTemplateInfo on LetterTemplate {
  String get title => switch (this) {
        LetterTemplate.insurance => 'Assurance',
        LetterTemplate.bank => 'Banque',
        LetterTemplate.caf => 'CAF',
        LetterTemplate.cpam => 'CPAM',
        LetterTemplate.taxes => 'Impôts',
        LetterTemplate.retirement => 'Retraite',
        LetterTemplate.employer => 'Employeur',
        LetterTemplate.housing => 'Logement',
        LetterTemplate.energy => 'Énergie',
        LetterTemplate.telecom => 'Télécommunications',
      };
  String get category => title;
  IconData get icon => switch (this) {
        LetterTemplate.insurance => Icons.shield_outlined,
        LetterTemplate.bank => Icons.account_balance_outlined,
        LetterTemplate.caf => Icons.family_restroom_outlined,
        LetterTemplate.cpam => Icons.health_and_safety_outlined,
        LetterTemplate.taxes => Icons.receipt_long_outlined,
        LetterTemplate.retirement => Icons.elderly_outlined,
        LetterTemplate.employer => Icons.badge_outlined,
        LetterTemplate.housing => Icons.home_outlined,
        LetterTemplate.energy => Icons.bolt_outlined,
        LetterTemplate.telecom => Icons.router_outlined,
      };
}

class ProfessionalLetterModel {
  const ProfessionalLetterModel(
      {required this.title, required this.subject, required this.body});
  final String title;
  final String subject;
  final String body;
}

extension ProfessionalModels on LetterTemplate {
  List<ProfessionalLetterModel> get models => switch (this) {
        LetterTemplate.insurance => const [
            ProfessionalLetterModel(
                title: 'Résiliation assurance auto',
                subject: 'Résiliation de mon contrat d’assurance automobile',
                body:
                    'Par la présente, je vous informe de ma décision de résilier mon contrat d’assurance automobile référencé ci-dessus. Je vous demande de prendre en compte cette résiliation à la date souhaitée et de me confirmer par écrit sa date d’effet ainsi que l’arrêt de toute facturation ultérieure.'),
            ProfessionalLetterModel(
                title: 'Résiliation assurance habitation',
                subject: 'Résiliation de mon contrat d’assurance habitation',
                body:
                    'Je vous informe de ma décision de mettre fin à mon contrat d’assurance habitation référencé ci-dessus. Je vous remercie d’enregistrer ma demande, de m’indiquer la date effective de résiliation et de procéder, le cas échéant, au remboursement de toute cotisation versée au-delà de cette date.'),
            ProfessionalLetterModel(
                title: 'Résiliation mutuelle santé',
                subject: 'Résiliation de mon contrat de complémentaire santé',
                body:
                    'Je vous notifie par la présente ma volonté de résilier mon contrat de complémentaire santé. Je vous demande de cesser toute cotisation à compter de la date effective de résiliation et de m’adresser une confirmation écrite de la clôture du contrat.'),
            ProfessionalLetterModel(
                title: 'Déclaration de sinistre',
                subject:
                    'Déclaration de sinistre et demande de prise en charge',
                body:
                    'Je vous informe de la survenance du sinistre décrit ci-dessous et vous demande d’ouvrir un dossier de prise en charge. Je vous remercie de me communiquer rapidement le numéro de dossier, la liste des justificatifs attendus et les prochaines étapes de l’indemnisation.'),
            ProfessionalLetterModel(
                title: 'Contestation d’indemnisation',
                subject: 'Contestation du montant de l’indemnisation proposée',
                body:
                    'Après examen de votre proposition, je conteste le montant d’indemnisation retenu, que je considère insuffisant au regard des dommages subis et des justificatifs transmis. Je vous demande de procéder à un réexamen complet de mon dossier et de me communiquer une réponse motivée par écrit.'),
            ProfessionalLetterModel(
                title: 'Demande de remboursement',
                subject: 'Demande de remboursement au titre de mon contrat',
                body:
                    'Je sollicite le remboursement des frais exposés dans le cadre de mon contrat et détaillés ci-dessous. Je vous remercie de vérifier les pièces jointes, de procéder au règlement dans les meilleurs délais et de m’informer de toute pièce complémentaire nécessaire.'),
            ProfessionalLetterModel(
                title: 'Changement de véhicule',
                subject:
                    'Mise à jour de mon contrat à la suite d’un changement de véhicule',
                body:
                    'Je vous informe d’un changement de véhicule et souhaite faire modifier mon contrat en conséquence. Je vous remercie de m’adresser un avenant précisant les nouvelles garanties, la cotisation applicable et la date de prise d’effet.'),
            ProfessionalLetterModel(
                title: 'Changement d’adresse',
                subject:
                    'Modification de mon adresse sur mon contrat d’assurance',
                body:
                    'Je vous informe de mon changement d’adresse et vous demande de mettre à jour l’ensemble de mes coordonnées dans votre dossier. Je vous remercie de me confirmer cette modification et de m’adresser, si nécessaire, un nouvel échéancier ou un avenant.'),
            ProfessionalLetterModel(
                title: 'Demande d’attestation',
                subject: 'Demande d’attestation d’assurance',
                body:
                    'Je vous prie de bien vouloir m’adresser une attestation d’assurance à jour correspondant au contrat référencé ci-dessus. Ce document m’est nécessaire pour la démarche précisée ci-dessous.'),
            ProfessionalLetterModel(
                title: 'Réclamation sur cotisation',
                subject: 'Contestation du montant de ma cotisation d’assurance',
                body:
                    'Je conteste le montant de la cotisation qui m’a été facturée, celui-ci ne correspondant pas aux conditions convenues ou à ma situation actuelle. Je vous demande de vérifier le calcul appliqué, de corriger toute erreur et de m’adresser un décompte détaillé.'),
          ],
        LetterTemplate.bank => const [
            ProfessionalLetterModel(
                title: 'Clôture de compte bancaire',
                subject: 'Demande de clôture de mon compte bancaire',
                body:
                    'Je vous demande de procéder à la clôture définitive du compte référencé ci-dessus, après règlement des opérations en cours. Je vous remercie de virer le solde créditeur éventuel sur le compte dont je communiquerai les coordonnées et de me confirmer par écrit la date de clôture.'),
            ProfessionalLetterModel(
                title: 'Contestation de prélèvement',
                subject: 'Contestation d’un prélèvement bancaire',
                body:
                    'Je conteste le prélèvement indiqué ci-dessous, que je considère non autorisé ou injustifié. Je vous demande d’en examiner l’origine, de procéder au remboursement lorsque les conditions sont réunies et de prendre les mesures nécessaires pour empêcher tout nouveau débit similaire.'),
            ProfessionalLetterModel(
                title: 'Opposition carte bancaire',
                subject: 'Demande d’opposition sur carte bancaire',
                body:
                    'Je vous informe de la perte, du vol ou de l’utilisation frauduleuse de ma carte bancaire et vous demande d’enregistrer immédiatement une opposition. Je vous remercie de me confirmer la prise en compte de cette demande et de m’indiquer les modalités de remplacement de la carte.'),
            ProfessionalLetterModel(
                title: 'Remboursement de frais bancaires',
                subject: 'Demande de remboursement de frais bancaires',
                body:
                    'Je sollicite le remboursement des frais bancaires mentionnés ci-dessous, dont le montant me paraît injustifié ou disproportionné. Je vous demande de réexaminer ma situation et de me transmettre une réponse détaillée.'),
            ProfessionalLetterModel(
                title: 'Demande de relevés',
                subject: 'Demande de duplicata de relevés bancaires',
                body:
                    'Je vous prie de bien vouloir me transmettre les relevés de compte correspondant à la période précisée ci-dessous. Je vous remercie de m’indiquer au préalable les éventuels frais liés à cette demande.'),
            ProfessionalLetterModel(
                title: 'Modification de coordonnées',
                subject: 'Mise à jour de mes coordonnées bancaires',
                body:
                    'Je vous informe de la modification de mes coordonnées personnelles et vous demande de mettre à jour mon dossier. Je vous remercie de me confirmer la bonne prise en compte de ces changements.'),
            ProfessionalLetterModel(
                title: 'Demande de procuration',
                subject: 'Demande de mise en place d’une procuration bancaire',
                body:
                    'Je souhaite mettre en place une procuration sur le compte référencé ci-dessus au bénéfice de la personne indiquée dans les précisions. Je vous remercie de me communiquer la procédure, les justificatifs nécessaires et les limites éventuelles de cette procuration.'),
            ProfessionalLetterModel(
                title: 'Réclamation sur virement',
                subject: 'Réclamation concernant un virement bancaire',
                body:
                    'Je vous signale une anomalie concernant le virement décrit ci-dessous. Je vous demande d’effectuer les vérifications nécessaires, de retracer l’opération et de me communiquer une réponse écrite accompagnée, le cas échéant, des mesures correctives.'),
            ProfessionalLetterModel(
                title: 'Demande d’échelonnement',
                subject: 'Demande d’aménagement temporaire de mes échéances',
                body:
                    'En raison des difficultés exposées ci-dessous, je sollicite un aménagement temporaire de mes échéances. Je vous propose d’étudier avec moi une solution réaliste et vous remercie de me transmettre une proposition écrite.'),
            ProfessionalLetterModel(
                title: 'Contestations agios',
                subject: 'Contestation d’agios et frais d’incident',
                body:
                    'Je conteste les agios et frais d’incident portés sur mon compte, dont je demande le détail et la justification. Je vous remercie de réexaminer leur application et de procéder à une régularisation si une erreur ou une disproportion est constatée.'),
          ],
        LetterTemplate.caf => const [
            ProfessionalLetterModel(
                title: 'Demande de réexamen',
                subject: 'Demande de réexamen de mon dossier CAF',
                body:
                    'Je vous demande de procéder à un réexamen complet de mon dossier au regard des éléments précisés ci-dessous. Je vous remercie de vérifier les informations enregistrées, de corriger toute erreur et de m’adresser une décision motivée.'),
            ProfessionalLetterModel(
                title: 'Contestation de trop-perçu',
                subject: 'Contestation d’un trop-perçu CAF',
                body:
                    'Je conteste la dette ou le trop-perçu qui m’a été notifié, dont le calcul ne me paraît pas correspondre à ma situation. Je vous demande de suspendre les retenues le temps de l’examen, de me transmettre le détail du calcul et de réviser la décision si nécessaire.'),
            ProfessionalLetterModel(
                title: 'Demande de remise de dette',
                subject: 'Demande de remise gracieuse de dette',
                body:
                    'Compte tenu de ma situation financière et personnelle exposée ci-dessous, je sollicite une remise totale ou partielle de la dette réclamée. Je vous remercie d’examiner cette demande avec bienveillance et de me notifier votre décision par écrit.'),
            ProfessionalLetterModel(
                title: 'Changement de situation',
                subject: 'Déclaration d’un changement de situation',
                body:
                    'Je vous informe du changement de situation décrit ci-dessous et vous demande de mettre à jour mon dossier dans les meilleurs délais. Je vous remercie de me confirmer sa prise en compte et de m’indiquer son impact éventuel sur mes droits.'),
            ProfessionalLetterModel(
                title: 'Retard de versement',
                subject:
                    'Réclamation pour retard de versement d’une prestation',
                body:
                    'Je constate que la prestation attendue n’a pas été versée à la date habituelle. Je vous demande de vérifier l’état de mon dossier, de régulariser le paiement si mes droits sont ouverts et de m’informer précisément du motif de ce retard.'),
            ProfessionalLetterModel(
                title: 'Demande d’attestation',
                subject: 'Demande d’attestation CAF',
                body:
                    'Je vous prie de bien vouloir me délivrer l’attestation précisée ci-dessous, nécessaire à l’accomplissement de mes démarches. Je vous remercie de me l’adresser dans les meilleurs délais.'),
            ProfessionalLetterModel(
                title: 'Prime d’activité',
                subject:
                    'Demande de vérification de mes droits à la prime d’activité',
                body:
                    'Je vous demande de vérifier le calcul et l’ouverture de mes droits à la prime d’activité au regard de ma situation et de mes revenus déclarés. Je vous remercie de me communiquer le détail du calcul retenu.'),
            ProfessionalLetterModel(
                title: 'Aide au logement',
                subject: 'Demande de réexamen de mon aide au logement',
                body:
                    'Je sollicite le réexamen de mon aide au logement, dont le montant ou l’interruption ne semble pas correspondre aux éléments de mon dossier. Je vous remercie de vérifier les informations prises en compte et de régulariser mes droits le cas échéant.'),
            ProfessionalLetterModel(
                title: 'Allocation familiale',
                subject:
                    'Demande de vérification de mes allocations familiales',
                body:
                    'Je vous demande de vérifier mes droits aux allocations familiales et le montant versé au regard de la composition actuelle de mon foyer. Je vous remercie de corriger toute anomalie et de m’adresser un décompte explicatif.'),
            ProfessionalLetterModel(
                title: 'Demande de délai',
                subject: 'Demande d’échelonnement d’une dette CAF',
                body:
                    'Ne pouvant régler immédiatement la totalité de la somme réclamée, je sollicite la mise en place d’un échéancier adapté à mes ressources. Je vous remercie de suspendre les mesures de recouvrement pendant l’étude de ma proposition.'),
          ],
        LetterTemplate.cpam => const [
            ProfessionalLetterModel(
                title: 'Remboursement de soins',
                subject: 'Réclamation concernant un remboursement de soins',
                body:
                    'Je constate l’absence ou l’insuffisance du remboursement des soins mentionnés ci-dessous. Je vous demande de vérifier le traitement de la feuille de soins ou de la télétransmission et de procéder à la régularisation de mon dossier.'),
            ProfessionalLetterModel(
                title: 'Indemnités journalières',
                subject: 'Réclamation concernant mes indemnités journalières',
                body:
                    'Je vous demande de vérifier le calcul ou le versement de mes indemnités journalières pour la période précisée. Je vous remercie de me communiquer les éléments retenus et de régulariser rapidement toute somme restant due.'),
            ProfessionalLetterModel(
                title: 'Carte Vitale',
                subject:
                    'Demande de délivrance ou de remplacement de ma carte Vitale',
                body:
                    'Je sollicite la délivrance, le remplacement ou la mise à jour de ma carte Vitale. Je vous remercie de m’indiquer les justificatifs nécessaires et de me confirmer l’enregistrement de ma demande.'),
            ProfessionalLetterModel(
                title: 'Attestation de droits',
                subject:
                    'Demande d’attestation de droits à l’Assurance Maladie',
                body:
                    'Je vous prie de bien vouloir m’adresser une attestation de droits à jour. Ce document m’est nécessaire pour la démarche indiquée ci-dessous.'),
            ProfessionalLetterModel(
                title: 'Contestation de décision',
                subject: 'Contestation d’une décision de la CPAM',
                body:
                    'Je conteste la décision qui m’a été notifiée, celle-ci ne tenant pas suffisamment compte des éléments de ma situation. Je vous demande de réexaminer mon dossier et de me transmettre une réponse motivée indiquant les voies de recours disponibles.'),
            ProfessionalLetterModel(
                title: 'Affiliation',
                subject: 'Demande d’affiliation à l’Assurance Maladie',
                body:
                    'Je sollicite mon affiliation à l’Assurance Maladie et vous transmets les informations utiles à l’étude de ma demande. Je vous remercie de m’indiquer les pièces manquantes et de me confirmer l’ouverture de mes droits.'),
            ProfessionalLetterModel(
                title: 'Changement de situation',
                subject:
                    'Déclaration d’un changement de situation auprès de la CPAM',
                body:
                    'Je vous informe du changement de situation décrit ci-dessous et vous demande de mettre à jour mon dossier. Je vous remercie de me confirmer la prise en compte de cette modification.'),
            ProfessionalLetterModel(
                title: 'Accident du travail',
                subject:
                    'Demande de reconnaissance et de suivi d’un accident du travail',
                body:
                    'Je vous transmets les éléments relatifs à l’accident du travail décrit ci-dessous et vous demande de m’informer de l’avancement de son instruction. Je vous remercie de me préciser les justificatifs nécessaires et les modalités de prise en charge.'),
            ProfessionalLetterModel(
                title: 'Transport médical',
                subject:
                    'Demande de remboursement de frais de transport médical',
                body:
                    'Je sollicite le remboursement des frais de transport médical détaillés ci-dessous. Je vous remercie de vérifier les justificatifs transmis et de procéder au règlement lorsque les conditions de prise en charge sont remplies.'),
            ProfessionalLetterModel(
                title: 'Complément de dossier',
                subject:
                    'Transmission de pièces complémentaires à mon dossier CPAM',
                body:
                    'À la suite de votre demande, je vous transmets les pièces complémentaires mentionnées ci-dessous. Je vous remercie de les rattacher à mon dossier et de me confirmer que celui-ci est désormais complet.'),
          ],
        LetterTemplate.taxes => const [
            ProfessionalLetterModel(
                title: 'Réclamation impôt',
                subject: 'Réclamation concernant mon avis d’imposition',
                body:
                    'Je conteste tout ou partie de l’imposition figurant sur l’avis référencé ci-dessus. Je vous demande de vérifier les éléments retenus, de corriger toute erreur et de m’adresser une décision motivée accompagnée d’un nouveau calcul.'),
            ProfessionalLetterModel(
                title: 'Délai de paiement',
                subject: 'Demande de délai de paiement de mes impôts',
                body:
                    'En raison des difficultés financières exposées ci-dessous, je sollicite un délai de paiement ou un échéancier pour la somme due. Je vous remercie d’examiner ma situation et de me proposer des modalités compatibles avec mes ressources.'),
            ProfessionalLetterModel(
                title: 'Remise gracieuse',
                subject: 'Demande de remise gracieuse',
                body:
                    'Compte tenu de circonstances exceptionnelles et de ma situation financière, je sollicite une remise totale ou partielle des majorations ou sommes précisées ci-dessous. Je vous remercie d’examiner cette demande avec bienveillance.'),
            ProfessionalLetterModel(
                title: 'Correction déclaration',
                subject: 'Demande de correction de ma déclaration de revenus',
                body:
                    'Je souhaite corriger les informations indiquées dans ma déclaration de revenus pour la période concernée. Je vous remercie de prendre en compte les éléments rectificatifs ci-dessous et de m’adresser un avis corrigé.'),
            ProfessionalLetterModel(
                title: 'Changement d’adresse',
                subject:
                    'Signalement d’un changement d’adresse aux services fiscaux',
                body:
                    'Je vous informe de mon changement d’adresse et vous demande de mettre à jour mon dossier fiscal. Je vous remercie de me confirmer la prise en compte de cette modification.'),
            ProfessionalLetterModel(
                title: 'Prélèvement à la source',
                subject:
                    'Demande de vérification de mon prélèvement à la source',
                body:
                    'Je constate une anomalie dans le taux ou le montant de mon prélèvement à la source. Je vous demande de vérifier les informations retenues, de corriger le taux si nécessaire et de m’expliquer le calcul appliqué.'),
            ProfessionalLetterModel(
                title: 'Taxe foncière',
                subject:
                    'Contestation ou demande d’explication concernant la taxe foncière',
                body:
                    'Je sollicite la vérification du montant de ma taxe foncière, qui me paraît ne pas correspondre à la situation du bien ou aux éléments déclarés. Je vous remercie de me transmettre le détail du calcul et de procéder à toute correction nécessaire.'),
            ProfessionalLetterModel(
                title: 'Duplicata avis',
                subject: 'Demande de duplicata d’un avis d’imposition',
                body:
                    'Je vous prie de bien vouloir m’adresser un duplicata de l’avis d’imposition ou de non-imposition correspondant à l’année indiquée. Ce document m’est nécessaire pour une démarche administrative.'),
            ProfessionalLetterModel(
                title: 'Mainlevée saisie',
                subject:
                    'Demande de régularisation et de mainlevée après paiement',
                body:
                    'La somme réclamée ayant été réglée ou régularisée, je vous demande de mettre à jour mon dossier et de procéder, le cas échéant, à la mainlevée de la mesure de recouvrement. Je vous remercie de m’en confirmer l’exécution par écrit.'),
            ProfessionalLetterModel(
                title: 'Erreur d’état civil',
                subject:
                    'Demande de correction de mes informations personnelles',
                body:
                    'Je constate une erreur dans mes informations d’état civil ou mes coordonnées figurant sur les documents fiscaux. Je vous demande de procéder à leur correction et de m’adresser un document rectifié.'),
          ],
        LetterTemplate.retirement => const [
            ProfessionalLetterModel(
                title: 'Relevé de carrière',
                subject: 'Demande de relevé de carrière actualisé',
                body:
                    'Je vous prie de bien vouloir m’adresser un relevé de carrière actualisé et détaillé. Je souhaite vérifier que l’ensemble de mes périodes d’activité et cotisations ont bien été prises en compte.'),
            ProfessionalLetterModel(
                title: 'Correction de carrière',
                subject: 'Demande de correction de mon relevé de carrière',
                body:
                    'Je constate l’absence ou l’inexactitude de certaines périodes sur mon relevé de carrière. Je vous demande de procéder aux vérifications nécessaires et d’intégrer les justificatifs mentionnés ci-dessous.'),
            ProfessionalLetterModel(
                title: 'Estimation retraite',
                subject: 'Demande d’estimation de ma future retraite',
                body:
                    'Je sollicite une estimation actualisée du montant de ma retraite et des différentes dates possibles de départ. Je vous remercie de m’indiquer les hypothèses de calcul retenues.'),
            ProfessionalLetterModel(
                title: 'Liquidation retraite',
                subject: 'Demande d’ouverture de mes droits à la retraite',
                body:
                    'Je souhaite engager la liquidation de mes droits à la retraite à compter de la date précisée ci-dessous. Je vous remercie de m’indiquer les pièces nécessaires et de me confirmer l’enregistrement de ma demande.'),
            ProfessionalLetterModel(
                title: 'Retard de paiement',
                subject:
                    'Réclamation concernant le retard de paiement de ma pension',
                body:
                    'Je constate que ma pension n’a pas été versée à la date habituelle ou que son montant est incomplet. Je vous demande de vérifier mon dossier, de régulariser la situation et de m’indiquer la cause du retard.'),
            ProfessionalLetterModel(
                title: 'Pension de réversion',
                subject: 'Demande de pension de réversion',
                body:
                    'Je sollicite l’étude de mes droits à une pension de réversion à la suite du décès mentionné ci-dessous. Je vous remercie de m’indiquer les justificatifs requis et les délais prévisionnels de traitement.'),
            ProfessionalLetterModel(
                title: 'Contestation calcul',
                subject: 'Contestation du calcul de ma pension',
                body:
                    'Je conteste le montant de la pension qui m’a été notifié, celui-ci ne semblant pas prendre en compte l’ensemble de ma carrière ou de mes droits. Je vous demande un réexamen complet et un décompte détaillé.'),
            ProfessionalLetterModel(
                title: 'Attestation paiement',
                subject: 'Demande d’attestation de paiement de pension',
                body:
                    'Je vous prie de bien vouloir m’adresser une attestation récapitulant les pensions versées pour la période indiquée. Ce document m’est nécessaire pour mes démarches.'),
            ProfessionalLetterModel(
                title: 'Changement coordonnées',
                subject: 'Modification de mes coordonnées de retraité',
                body:
                    'Je vous informe du changement de mes coordonnées postales, bancaires ou personnelles. Je vous demande de mettre à jour mon dossier et de me confirmer cette modification.'),
            ProfessionalLetterModel(
                title: 'Cumul emploi retraite',
                subject: 'Demande d’information sur le cumul emploi-retraite',
                body:
                    'Je souhaite obtenir une confirmation écrite des conditions applicables à ma situation concernant le cumul emploi-retraite. Je vous remercie de m’indiquer les plafonds, déclarations et justificatifs nécessaires.'),
          ],
        LetterTemplate.employer => const [
            ProfessionalLetterModel(
                title: 'Démission',
                subject: 'Notification de ma démission',
                body:
                    'Par la présente, je vous informe de ma décision de démissionner de mes fonctions. Je vous demande de prendre acte de cette décision et de me confirmer la date de fin de contrat en tenant compte du préavis applicable.'),
            ProfessionalLetterModel(
                title: 'Demande de congés',
                subject: 'Demande de congés',
                body:
                    'Je sollicite l’autorisation de prendre des congés aux dates précisées ci-dessous. Je vous remercie de me confirmer votre accord ou de me proposer, le cas échéant, une période compatible avec les nécessités du service.'),
            ProfessionalLetterModel(
                title: 'Demande de formation',
                subject: 'Demande d’accès à une formation professionnelle',
                body:
                    'Je souhaite suivre la formation décrite ci-dessous afin de développer mes compétences professionnelles. Je vous demande d’étudier les possibilités de prise en charge et d’aménagement de mon temps de travail.'),
            ProfessionalLetterModel(
                title: 'Attestation de travail',
                subject: 'Demande d’attestation de travail',
                body:
                    'Je vous prie de bien vouloir me délivrer une attestation de travail mentionnant mon emploi, ma date d’entrée et, si nécessaire, les fonctions exercées. Ce document m’est nécessaire pour la démarche indiquée.'),
            ProfessionalLetterModel(
                title: 'Rupture conventionnelle',
                subject:
                    'Demande d’entretien en vue d’une rupture conventionnelle',
                body:
                    'Je souhaite solliciter un entretien afin d’examiner la possibilité d’une rupture conventionnelle de mon contrat de travail. Cette demande vise à rechercher une solution négociée respectueuse des intérêts de chacune des parties.'),
            ProfessionalLetterModel(
                title: 'Réclamation salaire',
                subject: 'Réclamation concernant le paiement de mon salaire',
                body:
                    'Je constate une erreur ou un retard dans le paiement de mon salaire pour la période précisée. Je vous demande de vérifier les éléments de paie et de procéder à la régularisation des sommes dues dans les meilleurs délais.'),
            ProfessionalLetterModel(
                title: 'Temps partiel',
                subject: 'Demande de passage à temps partiel',
                body:
                    'Je sollicite un passage à temps partiel selon les modalités précisées ci-dessous. Je vous remercie d’étudier ma demande et de me communiquer les conditions d’organisation susceptibles d’être retenues.'),
            ProfessionalLetterModel(
                title: 'Changement horaires',
                subject: 'Demande d’aménagement de mes horaires de travail',
                body:
                    'Pour les raisons exposées ci-dessous, je sollicite un aménagement de mes horaires de travail. Je vous propose d’examiner une organisation compatible avec mes contraintes et les besoins du service.'),
            ProfessionalLetterModel(
                title: 'Contestation avertissement',
                subject: 'Contestation d’un avertissement disciplinaire',
                body:
                    'Je conteste l’avertissement qui m’a été notifié, les faits reprochés ne correspondant pas, selon moi, à la réalité ou au contexte exposé ci-dessous. Je vous demande de réexaminer cette mesure et d’intégrer mes observations à mon dossier.'),
            ProfessionalLetterModel(
                title: 'Demande augmentation',
                subject: 'Demande de réévaluation de ma rémunération',
                body:
                    'Au regard de l’évolution de mes responsabilités, de mes résultats et de mon ancienneté, je souhaite solliciter une réévaluation de ma rémunération. Je vous remercie de bien vouloir convenir d’un entretien afin d’examiner cette demande.'),
          ],
        LetterTemplate.housing => const [
            ProfessionalLetterModel(
                title: 'Préavis de départ',
                subject: 'Notification de congé et préavis de départ',
                body:
                    'Je vous informe de ma décision de quitter le logement mentionné ci-dessus. Je vous demande de prendre acte de mon congé à compter de la réception de ce courrier et de me proposer une date pour l’état des lieux de sortie et la remise des clés.'),
            ProfessionalLetterModel(
                title: 'Restitution dépôt garantie',
                subject: 'Demande de restitution du dépôt de garantie',
                body:
                    'Le logement ayant été libéré et les clés restituées, je vous demande de procéder à la restitution de mon dépôt de garantie, déduction faite uniquement des sommes dûment justifiées. Je vous remercie de m’adresser le décompte détaillé de toute retenue.'),
            ProfessionalLetterModel(
                title: 'Demande de travaux',
                subject: 'Demande de réalisation de travaux dans le logement',
                body:
                    'Je vous signale les désordres décrits ci-dessous et vous demande de faire réaliser les travaux nécessaires afin de rétablir des conditions normales d’usage et de sécurité. Je vous remercie de me communiquer rapidement un calendrier d’intervention.'),
            ProfessionalLetterModel(
                title: 'Contestation charges',
                subject: 'Contestation et demande de justificatifs de charges',
                body:
                    'Je conteste le montant ou la régularisation des charges qui m’est réclamée. Je vous demande de me transmettre le décompte détaillé, les justificatifs correspondants et de rectifier toute somme indûment facturée.'),
            ProfessionalLetterModel(
                title: 'Signalement insalubrité',
                subject:
                    'Signalement de problèmes affectant la salubrité du logement',
                body:
                    'Je vous informe de problèmes sérieux affectant la salubrité ou la sécurité du logement. Je vous demande d’organiser une intervention urgente et de m’indiquer les mesures prises pour remédier durablement à la situation.'),
            ProfessionalLetterModel(
                title: 'Demande quittance',
                subject: 'Demande de quittances de loyer',
                body:
                    'Je vous prie de bien vouloir m’adresser les quittances de loyer correspondant aux périodes précisées ci-dessous, les loyers et charges ayant été intégralement réglés.'),
            ProfessionalLetterModel(
                title: 'Réclamation voisinage',
                subject: 'Signalement de troubles de voisinage',
                body:
                    'Je vous signale les troubles répétés décrits ci-dessous, qui portent atteinte à la jouissance paisible de mon logement. Je vous demande d’intervenir auprès des personnes concernées et de m’informer des mesures prises.'),
            ProfessionalLetterModel(
                title: 'Renouvellement bail',
                subject: 'Demande de renouvellement ou de confirmation du bail',
                body:
                    'Je souhaite obtenir une confirmation écrite concernant le renouvellement de mon bail et les conditions applicables à la prochaine période. Je vous remercie de me transmettre tout document ou avenant nécessaire.'),
            ProfessionalLetterModel(
                title: 'Sinistre logement',
                subject: 'Déclaration d’un sinistre dans le logement',
                body:
                    'Je vous informe du sinistre survenu dans le logement et décrit ci-dessous. Je vous demande d’organiser les mesures nécessaires, de me communiquer les coordonnées des intervenants et de préciser la répartition des démarches entre bailleur, locataire et assureurs.'),
            ProfessionalLetterModel(
                title: 'Attestation hébergement',
                subject: 'Demande d’attestation relative à mon logement',
                body:
                    'Je vous prie de bien vouloir me délivrer l’attestation ou le document relatif au logement précisé ci-dessous. Ce document est nécessaire à l’accomplissement de ma démarche administrative.'),
          ],
        LetterTemplate.energy => const [
            ProfessionalLetterModel(
                title: 'Résiliation électricité',
                subject: 'Résiliation de mon contrat d’électricité',
                body:
                    'Je vous informe de ma décision de résilier mon contrat d’électricité pour le point de livraison référencé ci-dessus. Je vous demande de prendre en compte la date de fin souhaitée, d’établir la facture de clôture et de me confirmer la résiliation par écrit.'),
            ProfessionalLetterModel(
                title: 'Résiliation gaz',
                subject: 'Résiliation de mon contrat de gaz',
                body:
                    'Je vous demande de procéder à la résiliation de mon contrat de gaz à la date indiquée. Je vous remercie d’enregistrer le relevé de compteur communiqué, d’établir la facture de clôture et de mettre fin aux prélèvements.'),
            ProfessionalLetterModel(
                title: 'Contestation facture',
                subject: 'Contestation d’une facture d’énergie',
                body:
                    'Je conteste le montant de la facture référencée ci-dessus, qui ne correspond pas à ma consommation habituelle ou aux relevés disponibles. Je vous demande de vérifier le calcul, les index et le tarif appliqué, puis de m’adresser une facture rectifiée.'),
            ProfessionalLetterModel(
                title: 'Échéancier paiement',
                subject: 'Demande d’échelonnement d’une facture d’énergie',
                body:
                    'Compte tenu de mes difficultés temporaires, je sollicite un échéancier pour régler la somme due. Je vous remercie de suspendre les mesures de recouvrement pendant l’étude de ma demande et de me proposer un plan adapté.'),
            ProfessionalLetterModel(
                title: 'Remboursement trop-perçu',
                subject: 'Demande de remboursement d’un trop-perçu d’énergie',
                body:
                    'Après vérification de mon compte, un solde créditeur ou un trop-perçu apparaît en ma faveur. Je vous demande de procéder à son remboursement et de m’adresser un relevé de compte détaillé.'),
            ProfessionalLetterModel(
                title: 'Erreur compteur',
                subject: 'Signalement d’une anomalie de compteur ou de relevé',
                body:
                    'Je vous signale une anomalie concernant le compteur ou le relevé de consommation décrit ci-dessous. Je vous demande d’organiser une vérification technique et de suspendre toute facturation contestée jusqu’au résultat du contrôle.'),
            ProfessionalLetterModel(
                title: 'Coupure abusive',
                subject:
                    'Réclamation concernant une coupure ou menace de coupure',
                body:
                    'Je conteste la coupure ou la menace de coupure qui m’a été notifiée, compte tenu des éléments précisés ci-dessous. Je vous demande de réexaminer immédiatement mon dossier et de me proposer une solution permettant le maintien ou le rétablissement du service.'),
            ProfessionalLetterModel(
                title: 'Changement titulaire',
                subject: 'Demande de changement de titulaire du contrat',
                body:
                    'Je vous demande de modifier le titulaire du contrat d’énergie pour le logement référencé ci-dessus. Je vous remercie de m’indiquer les justificatifs nécessaires et de confirmer la date de prise d’effet.'),
            ProfessionalLetterModel(
                title: 'Déménagement',
                subject:
                    'Signalement d’un déménagement et transfert de contrat',
                body:
                    'Je vous informe de mon prochain déménagement et souhaite organiser la clôture ou le transfert de mon contrat. Je vous remercie de me préciser les relevés à transmettre, les dates à retenir et les éventuels frais applicables.'),
            ProfessionalLetterModel(
                title: 'Geste commercial',
                subject: 'Demande de geste commercial',
                body:
                    'En raison des dysfonctionnements ou désagréments décrits ci-dessous, je sollicite un geste commercial sur ma prochaine facture. Je vous remercie d’examiner ma demande et de me communiquer votre décision par écrit.'),
          ],
        LetterTemplate.telecom => const [
            ProfessionalLetterModel(
                title: 'Résiliation mobile',
                subject: 'Résiliation de mon abonnement de téléphonie mobile',
                body:
                    'Par la présente, je vous informe de ma décision de résilier mon abonnement de téléphonie mobile référencé ci-dessus. Je vous demande de prendre en compte cette résiliation à la date souhaitée, de mettre fin à toute facturation ultérieure et de m’en confirmer la date d’effet par écrit.'),
            ProfessionalLetterModel(
                title: 'Résiliation box Internet',
                subject: 'Résiliation de mon abonnement Internet',
                body:
                    'Je vous informe de ma décision de résilier mon abonnement Internet référencé ci-dessus. Je vous demande de me confirmer la date effective de résiliation, l’arrêt des prélèvements et les modalités précises de restitution du matériel.'),
            ProfessionalLetterModel(
                title: 'Rétractation abonnement',
                subject: 'Exercice de mon droit de rétractation',
                body:
                    'Je vous informe de ma décision de me rétracter de la souscription mentionnée ci-dessus. Je vous demande d’annuler le contrat, de mettre fin à toute facturation et de me rembourser les sommes éventuellement perçues.'),
            ProfessionalLetterModel(
                title: 'Contestation facture',
                subject: 'Contestation d’une facture de télécommunications',
                body:
                    'Je conteste le montant de la facture référencée ci-dessus, qui comporte selon moi des erreurs ou des services non sollicités. Je vous demande de procéder à une vérification détaillée et de m’adresser une facture rectifiée.'),
            ProfessionalLetterModel(
                title: 'Panne prolongée',
                subject:
                    'Réclamation pour interruption ou dégradation du service',
                body:
                    'Je vous signale une interruption ou une dégradation persistante du service depuis la date indiquée. Je vous demande de rétablir rapidement le service, de m’informer du diagnostic et d’appliquer une compensation pour la période d’indisponibilité.'),
            ProfessionalLetterModel(
                title: 'Remboursement',
                subject: 'Demande de remboursement',
                body:
                    'Je sollicite le remboursement des sommes facturées à tort ou correspondant à une période durant laquelle le service n’a pas été fourni correctement. Je vous remercie de procéder à la régularisation et de m’adresser un avoir détaillé.'),
            ProfessionalLetterModel(
                title: 'Portabilité numéro',
                subject: 'Demande relative à la portabilité de mon numéro',
                body:
                    'Je vous demande de vérifier le traitement de la portabilité de mon numéro, qui n’a pas été réalisée conformément à ma demande. Je vous remercie de régulariser la situation et de me confirmer le maintien ou le transfert effectif du numéro.'),
            ProfessionalLetterModel(
                title: 'Restitution matériel',
                subject: 'Confirmation de restitution du matériel',
                body:
                    'Je vous informe avoir restitué le matériel associé à mon abonnement selon les modalités précisées ci-dessous. Je vous demande de confirmer sa bonne réception et d’annuler toute facturation ou pénalité liée à une prétendue non-restitution.'),
            ProfessionalLetterModel(
                title: 'Suppression option',
                subject: 'Demande de suppression d’une option payante',
                body:
                    'Je vous demande de supprimer immédiatement l’option payante mentionnée ci-dessous, que je ne souhaite plus conserver ou que je n’ai pas sollicitée. Je vous remercie de confirmer sa désactivation et de régulariser les sommes indûment facturées.'),
            ProfessionalLetterModel(
                title: 'Geste commercial',
                subject: 'Demande de geste commercial',
                body:
                    'Compte tenu des incidents, retards ou désagréments décrits ci-dessous, je sollicite un geste commercial adapté. Je vous remercie d’examiner ma demande et de me communiquer votre proposition par écrit.'),
          ],
      };
}

class JsonLetterRecord {
  const JsonLetterRecord(
      {required this.id,
      required this.category,
      required this.subcategory,
      required this.title,
      required this.subject,
      required this.body,
      required this.keywords});
  final String id;
  final String category;
  final String subcategory;
  final String title;
  final String subject;
  final String body;
  final List<String> keywords;

  factory JsonLetterRecord.fromJson(Map<String, dynamic> json) =>
      JsonLetterRecord(
        id: json['id'] as String,
        category: json['category'] as String,
        subcategory: json['subcategory'] as String? ?? 'Demandes générales',
        title: json['title'] as String,
        subject: json['subject'] as String,
        body: json['body'] as String,
        keywords:
            List<String>.from(json['keywords'] as List<dynamic>? ?? const []),
      );
}

class JsonLibraryScreen extends StatefulWidget {
  const JsonLibraryScreen({super.key, required this.settings});
  final AppSettings settings;
  @override
  State<JsonLibraryScreen> createState() => _JsonLibraryScreenState();
}

class _JsonLibraryScreenState extends State<JsonLibraryScreen> {
  static const _favoritesKey = 'jsonLibraryFavoritesV66';
  static const _historyKey = 'jsonLibraryHistoryV66';

  final controller = TextEditingController();
  List<JsonLetterRecord> records = const [];
  final Set<String> favorites = <String>{};
  List<String> history = <String>[];
  String? category;
  String? subcategory;
  bool favoritesOnly = false;
  bool recentOnly = false;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    controller.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/letters/library.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = (data['templates'] as List<dynamic>)
          .map((e) =>
              JsonLetterRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final prefs = await SharedPreferences.getInstance();
      favorites
        ..clear()
        ..addAll(prefs.getStringList(_favoritesKey) ?? const <String>[]);
      history = prefs.getStringList(_historyKey) ?? <String>[];
      if (mounted) {
        setState(() {
          records = list;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite(String id) async {
    setState(() {
      if (!favorites.add(id)) favorites.remove(id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, favorites.toList()..sort());
  }

  Future<void> _openRecord(JsonLetterRecord item) async {
    history.remove(item.id);
    history.insert(0, item.id);
    if (history.length > 30) history = history.take(30).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, history);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LetterFormScreen(
          settings: widget.settings,
          template: _templateFor(item.category),
          model: ProfessionalLetterModel(
            title: item.title,
            subject: item.subject,
            body: item.body,
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  List<String> get categories =>
      (records.map((e) => e.category).toSet().toList()..sort());

  List<String> get subcategories => (records
      .where((e) => category == null || e.category == category)
      .map((e) => e.subcategory)
      .toSet()
      .toList()
    ..sort());

  List<JsonLetterRecord> get filtered {
    final q = controller.text.trim().toLowerCase();
    final words = q
        .replaceAll(RegExp(r'[^a-zA-ZÀ-ÿ0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty);
    final historyPositions = <String, int>{
      for (var i = 0; i < history.length; i++) history[i]: i,
    };
    final result = records.where((e) {
      if (category != null && e.category != category) return false;
      if (subcategory != null && e.subcategory != subcategory) return false;
      if (favoritesOnly && !favorites.contains(e.id)) return false;
      if (recentOnly && !historyPositions.containsKey(e.id)) return false;
      final haystack = '${e.category} ${e.subcategory} ${e.title} '
              '${e.subject} ${e.body} ${e.keywords.join(' ')}'
          .toLowerCase();
      return words.every(haystack.contains);
    }).toList();
    if (recentOnly) {
      result.sort((a, b) => (historyPositions[a.id] ?? 999)
          .compareTo(historyPositions[b.id] ?? 999));
    } else {
      result.sort((a, b) => a.title.compareTo(b.title));
    }
    return result;
  }

  LetterTemplate _templateFor(String value) => switch (value) {
        'Assurance' => LetterTemplate.insurance,
        'Banque' => LetterTemplate.bank,
        'CAF' => LetterTemplate.caf,
        'CPAM' => LetterTemplate.cpam,
        'Impôts' => LetterTemplate.taxes,
        'Retraite' => LetterTemplate.retirement,
        'Employeur' => LetterTemplate.employer,
        'Logement' => LetterTemplate.housing,
        'Énergie' => LetterTemplate.energy,
        _ => LetterTemplate.telecom,
      };

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('Bibliothèque professionnelle V6.7')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Text('Impossible de charger la bibliothèque : $error'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: 'Rechercher parmi 500 courriers',
                          hintText:
                              'Ex. résiliation Orange, facture EDF, préavis…',
                          suffixIcon: controller.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: controller.clear,
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          ChoiceChip(
                            label: const Text('Tous'),
                            selected: !favoritesOnly && !recentOnly,
                            onSelected: (_) => setState(() {
                              favoritesOnly = false;
                              recentOnly = false;
                            }),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            avatar: const Icon(Icons.star, size: 18),
                            label: Text('Favoris (${favorites.length})'),
                            selected: favoritesOnly,
                            onSelected: (_) => setState(() {
                              favoritesOnly = true;
                              recentOnly = false;
                            }),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            avatar: const Icon(Icons.history, size: 18),
                            label: Text('Récents (${history.length})'),
                            selected: recentOnly,
                            onSelected: (_) => setState(() {
                              recentOnly = true;
                              favoritesOnly = false;
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          ChoiceChip(
                            label: const Text('Toutes catégories'),
                            selected: category == null,
                            onSelected: (_) => setState(() {
                              category = null;
                              subcategory = null;
                            }),
                          ),
                          const SizedBox(width: 8),
                          ...categories.expand((c) => [
                                ChoiceChip(
                                  label: Text(c),
                                  selected: category == c,
                                  onSelected: (_) => setState(() {
                                    category = c;
                                    subcategory = null;
                                  }),
                                ),
                                const SizedBox(width: 8),
                              ]),
                        ],
                      ),
                    ),
                    if (category != null)
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            ChoiceChip(
                              label: const Text('Toutes les demandes'),
                              selected: subcategory == null,
                              onSelected: (_) =>
                                  setState(() => subcategory = null),
                            ),
                            const SizedBox(width: 8),
                            ...subcategories.expand((s) => [
                                  ChoiceChip(
                                    label: Text(s),
                                    selected: subcategory == s,
                                    onSelected: (_) =>
                                        setState(() => subcategory = s),
                                  ),
                                  const SizedBox(width: 8),
                                ]),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${items.length} courrier${items.length > 1 ? 's' : ''} '
                              'sur ${records.length}',
                            ),
                          ),
                          const Icon(Icons.cloud_off, size: 18),
                          const SizedBox(width: 6),
                          const Text('Hors ligne'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(28),
                                child: Text(
                                  'Aucun courrier ne correspond à ces filtres. '
                                  'Essayez un mot plus simple ou affichez tous les modèles.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final favorite = favorites.contains(item.id);
                                return Card(
                                  child: ListTile(
                                    minVerticalPadding: 14,
                                    leading: CircleAvatar(
                                      child:
                                          Text(item.category.characters.first),
                                    ),
                                    title: Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${item.category} • ${item.subcategory}\n${item.subject}',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    isThreeLine: true,
                                    trailing: IconButton(
                                      tooltip: favorite
                                          ? 'Retirer des favoris'
                                          : 'Ajouter aux favoris',
                                      onPressed: () => _toggleFavorite(item.id),
                                      icon: Icon(
                                        favorite
                                            ? Icons.star
                                            : Icons.star_border,
                                      ),
                                    ),
                                    onTap: () => _openRecord(item),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

class TemplateSearchScreen extends StatefulWidget {
  const TemplateSearchScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<TemplateSearchScreen> createState() => _TemplateSearchScreenState();
}

class _TemplateSearchScreenState extends State<TemplateSearchScreen> {
  final controller = TextEditingController();
  final Set<String> favorites = <String>{};
  bool favoritesOnly = false;
  bool loading = true;

  String _key(LetterTemplate template, ProfessionalLetterModel model) =>
      '${template.name}::${model.title}';

  @override
  void initState() {
    super.initState();
    controller.addListener(() => setState(() {}));
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    favorites
      ..clear()
      ..addAll(
          prefs.getStringList('favoriteLetterModelsV5') ?? const <String>[]);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _toggleFavorite(String key) async {
    setState(() {
      if (!favorites.add(key)) favorites.remove(key);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'favoriteLetterModelsV5', favorites.toList()..sort());
  }

  List<({LetterTemplate template, ProfessionalLetterModel model})> get results {
    final query = controller.text.trim().toLowerCase();
    final words = query
        .replaceAll(RegExp(r'[^a-zA-ZÀ-ÿ0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final all = <({LetterTemplate template, ProfessionalLetterModel model})>[];
    for (final template in LetterTemplate.values) {
      for (final model in template.models) {
        final key = _key(template, model);
        if (favoritesOnly && !favorites.contains(key)) continue;
        final haystack =
            '${template.title} ${model.title} ${model.subject} ${model.body}'
                .toLowerCase();
        if (words.every((word) => haystack.contains(word))) {
          all.add((template: template, model: model));
        }
      }
    }
    return all;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = results;
    return Scaffold(
      appBar: AppBar(title: const Text('Recherche de courriers')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Votre besoin ou un organisme',
              hintText: 'Ex. résiliation mobile, CAF, facture EDF…',
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: controller.clear,
                      icon: const Icon(Icons.close)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            ChoiceChip(
              label: const Text('Tous les modèles'),
              selected: !favoritesOnly,
              onSelected: (_) => setState(() => favoritesOnly = false),
            ),
            const SizedBox(width: 10),
            ChoiceChip(
              avatar: const Icon(Icons.star, size: 18),
              label: Text('Favoris (${favorites.length})'),
              selected: favoritesOnly,
              onSelected: (_) => setState(() => favoritesOnly = true),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
                '${items.length} courrier${items.length > 1 ? 's' : ''} trouvé${items.length > 1 ? 's' : ''}'),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                          'Aucun modèle trouvé. Essayez avec un mot plus simple, par exemple « résiliation », « facture » ou « logement ».',
                          textAlign: TextAlign.center),
                    ))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final key = _key(item.template, item.model);
                        final favorite = favorites.contains(key);
                        return Card(
                          child: ListTile(
                            minVerticalPadding: 14,
                            leading:
                                CircleAvatar(child: Icon(item.template.icon)),
                            title: Text(item.model.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '${item.template.title} • ${item.model.subject}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              tooltip: favorite
                                  ? 'Retirer des favoris'
                                  : 'Ajouter aux favoris',
                              onPressed: () => _toggleFavorite(key),
                              icon: Icon(
                                  favorite ? Icons.star : Icons.star_border),
                            ),
                            onTap: () =>
                                Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => LetterFormScreen(
                                settings: widget.settings,
                                template: item.template,
                                model: item.model,
                              ),
                            )),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
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
          const Text(
              '10 domaines et 100 courriers professionnels prêts à personnaliser.'),
          const SizedBox(height: 20),
          ...LetterTemplate.values.map((template) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                    child: ListTile(
                  minVerticalPadding: 18,
                  leading: CircleAvatar(child: Icon(template.icon)),
                  title: Text(template.title),
                  subtitle: const Text('10 modèles professionnels'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LetterModelListScreen(
                          settings: settings, template: template))),
                )),
              )),
        ],
      ));
}

class LetterModelListScreen extends StatelessWidget {
  const LetterModelListScreen(
      {super.key, required this.settings, required this.template});
  final AppSettings settings;
  final LetterTemplate template;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(template.title)),
        body: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: template.models.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final model = template.models[index];
            return Card(
                child: ListTile(
              minVerticalPadding: 16,
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(model.title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(model.subject,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LetterFormScreen(
                    settings: settings, template: template, model: model),
              )),
            ));
          },
        ),
      );
}

class LetterFormScreen extends StatefulWidget {
  const LetterFormScreen({
    super.key,
    required this.settings,
    required this.template,
    required this.model,
    this.initialRecipient = '',
  });
  final AppSettings settings;
  final LetterTemplate template;
  final ProfessionalLetterModel model;
  final String initialRecipient;
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
  final SpeechToText _letterSpeech = SpeechToText();
  bool _speechAvailable = false;
  bool _listeningDetails = false;
  bool _initializingSpeech = true;
  String? _speechLocaleId;
  String _detailsPrefix = '';

  @override
  void initState() {
    super.initState();
    firstName = TextEditingController(text: widget.settings.firstName);
    lastName = TextEditingController(text: widget.settings.lastName);
    address = TextEditingController(text: widget.settings.address);
    postalCode = TextEditingController(text: widget.settings.postalCode);
    city = TextEditingController(text: widget.settings.city);
    recipient.text = widget.initialRecipient;
    _initializeLetterSpeech();
  }

  Future<void> _initializeLetterSpeech() async {
    try {
      final available = await _letterSpeech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _listeningDetails = status == 'listening');
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _listeningDetails = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Microphone : ${error.errorMsg}')),
          );
        },
      );
      String? french;
      if (available) {
        final locales = await _letterSpeech.locales();
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
        _speechLocaleId = french;
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

  Future<void> _toggleDetailsDictation() async {
    if (_initializingSpeech) return;
    if (!_speechAvailable) {
      await _initializeLetterSpeech();
      if (!_speechAvailable && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('La reconnaissance vocale n’est pas disponible.')),
        );
      }
      return;
    }
    if (_letterSpeech.isListening) {
      await _letterSpeech.stop();
      if (mounted) setState(() => _listeningDetails = false);
      return;
    }

    _detailsPrefix = details.text.trim();
    await _letterSpeech.listen(
      onResult: (result) {
        final spoken = result.recognizedWords.trim();
        final separator = _detailsPrefix.isEmpty || spoken.isEmpty ? '' : '\n';
        details.text = '$_detailsPrefix$separator$spoken';
        details.selection =
            TextSelection.collapsed(offset: details.text.length);
        if (mounted) setState(() {});
      },
      listenOptions: SpeechListenOptions(
        localeId: _speechLocaleId,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
    if (mounted) setState(() => _listeningDetails = true);
  }

  @override
  void dispose() {
    _letterSpeech.cancel();
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

  Future<void> generate() async {
    if (!formKey.currentState!.validate()) return;
    final letter = LetterGenerator.generate(
      template: widget.template,
      model: widget.model,
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
    final now = DateTime.now();
    await appProcedureStore.add(
      AdministrativeProcedure(
        id: now.microsecondsSinceEpoch.toString(),
        title: widget.model.title,
        organisation: recipient.text.trim(),
        category: widget.template.category,
        letter: letter,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LetterPreviewScreen(
          letter: letter,
          defaultSubject: widget.model.subject,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.model.title)),
        body: Form(
            key: formKey,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.model.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(widget.model.subject)
                          ]))),
              const SizedBox(height: 18),
              Text('Vos coordonnées',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextFormField(
                        controller: firstName,
                        validator: requiredField,
                        decoration: InputDecoration(
                            labelText: 'Prénom',
                            suffixIcon:
                                VoiceInputButton(controller: firstName)))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextFormField(
                        controller: lastName,
                        validator: requiredField,
                        decoration: InputDecoration(
                            labelText: 'Nom',
                            suffixIcon:
                                VoiceInputButton(controller: lastName)))),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                  controller: address,
                  validator: requiredField,
                  decoration: InputDecoration(
                      labelText: 'Adresse',
                      suffixIcon: VoiceInputButton(controller: address))),
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
                        decoration: InputDecoration(
                            labelText: 'Ville',
                            suffixIcon: VoiceInputButton(controller: city)))),
              ]),
              const SizedBox(height: 22),
              Text('Destinataire et demande',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                  controller: recipient,
                  validator: requiredField,
                  decoration: InputDecoration(
                      labelText: 'Organisme, entreprise ou employeur',
                      suffixIcon: VoiceInputButton(controller: recipient))),
              const SizedBox(height: 12),
              TextFormField(
                  controller: recipientAddress,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: 'Adresse du destinataire (facultatif)',
                      suffixIcon:
                          VoiceInputButton(controller: recipientAddress))),
              const SizedBox(height: 12),
              TextFormField(
                  controller: reference,
                  decoration: InputDecoration(
                      labelText: 'Référence ou numéro de contrat',
                      suffixIcon: VoiceInputButton(controller: reference))),
              const SizedBox(height: 12),
              TextFormField(
                controller: details,
                minLines: 5,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: 'Précisez votre demande',
                  alignLabelWithHint: true,
                  hintText: 'Écrivez ou dictez les détails de votre demande.',
                  suffixIcon: VoiceInputButton(controller: details),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed:
                      _initializingSpeech ? null : _toggleDetailsDictation,
                  icon: Icon(_listeningDetails ? Icons.stop_circle : Icons.mic),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Text(_listeningDetails
                        ? 'Arrêter la dictée'
                        : 'Dicter ma demande'),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _listeningDetails
                    ? 'Je vous écoute… La dictée s’ajoute dans « Précisez votre demande ». '
                    : 'Le microphone remplit uniquement les détails de cette lettre.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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

class EmailPreparationScreen extends StatefulWidget {
  const EmailPreparationScreen({
    super.key,
    required this.pdfPath,
    required this.defaultSubject,
  });

  final String pdfPath;
  final String defaultSubject;

  @override
  State<EmailPreparationScreen> createState() => _EmailPreparationScreenState();
}

class _EmailPreparationScreenState extends State<EmailPreparationScreen> {
  final recipientController = TextEditingController();
  late final TextEditingController subjectController =
      TextEditingController(text: widget.defaultSubject);
  final messageController = TextEditingController(
    text:
        'Bonjour,\n\nVeuillez trouver mon courrier administratif en pièce jointe.\n\nCordialement,',
  );

  Future<void> _openMailApp() async {
    final recipient = recipientController.text.trim();
    if (recipient.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(recipient)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Vérifiez l’adresse e-mail du destinataire.')),
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(widget.pdfPath)],
        subject: subjectController.text.trim(),
        text:
            '${recipient.isEmpty ? '' : 'Destinataire : $recipient\n\n'}${messageController.text.trim()}',
      ),
    );
  }

  @override
  void dispose() {
    recipientController.dispose();
    subjectController.dispose();
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Préparer l’e-mail')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'AdminFacile préparera le message et le PDF. Vous choisirez ensuite Gmail, Outlook ou une autre application pour vérifier et envoyer.',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: recipientController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Destinataire (facultatif)',
                prefixIcon: const Icon(Icons.alternate_email),
                suffixIcon: VoiceInputButton(controller: recipientController),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: subjectController,
              decoration: InputDecoration(
                labelText: 'Objet',
                prefixIcon: const Icon(Icons.subject),
                suffixIcon: VoiceInputButton(controller: subjectController),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: messageController,
              minLines: 7,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: 'Message',
                alignLabelWithHint: true,
                suffixIcon: VoiceInputButton(controller: messageController),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Lettre AdminFacile.pdf'),
                subtitle:
                    const Text('Le document sera ajouté en pièce jointe.'),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _openMailApp,
              icon: const Icon(Icons.forward_to_inbox),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Choisir Gmail ou Outlook'),
              ),
            ),
          ],
        ),
      );
}

class LetterPreviewScreen extends StatefulWidget {
  const LetterPreviewScreen({
    super.key,
    required this.letter,
    this.defaultSubject = 'Courrier administratif',
  });
  final String letter;
  final String defaultSubject;
  @override
  State<LetterPreviewScreen> createState() => _LetterPreviewScreenState();
}

class _LetterPreviewScreenState extends State<LetterPreviewScreen> {
  bool improving = false;
  late final TextEditingController controller =
      TextEditingController(text: widget.letter);

  Future<void> _improveWithGemini() async {
    var tone = 'Professionnel';
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Améliorer avec Gemini'),
          content: DropdownButtonFormField<String>(
            initialValue: tone,
            decoration: const InputDecoration(labelText: 'Ton souhaité'),
            items: const [
              'Courtois',
              'Professionnel',
              'Ferme',
              'Plus concis',
              'Plus détaillé'
            ]
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) {
              if (value != null) setDialogState(() => tone = value);
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, tone),
                child: const Text('Améliorer')),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() => improving = true);
    try {
      final improved = await GeminiLetterWriter.improve(
          letter: controller.text, tone: selected);
      if (!mounted) return;
      controller.text = improved;
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Lettre améliorée avec Gemini. Relisez-la avant l’envoi.')));
    } on GeminiConfigurationException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Amélioration impossible : $e')));
    } finally {
      if (mounted) setState(() => improving = false);
    }
  }

  Future<Uint8List> _buildPdf() async {
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(42),
      build: (_) => [
        pw.Text(controller.text,
            style: const pw.TextStyle(fontSize: 12, lineSpacing: 4))
      ],
    ));
    return pdf.save();
  }

  Future<File> _temporaryPdf() async {
    final bytes = await _buildPdf();
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/lettre_adminfacile_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _savePdf() async {
    final bytes = await _buildPdf();
    final output = await FilePicker.platform.saveFile(
      dialogTitle: 'Enregistrer la lettre en PDF',
      fileName:
          'lettre_adminfacile_${DateTime.now().millisecondsSinceEpoch}.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
    if (!mounted || output == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document enregistré en PDF.')));
  }

  Future<void> _email() async {
    final file = await _temporaryPdf();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmailPreparationScreen(
          pdfPath: file.path,
          defaultSubject: widget.defaultSubject,
        ),
      ),
    );
  }

  Future<void> _print() async {
    final bytes = await _buildPdf();
    await Printing.layoutPdf(
        onLayout: (_) async => bytes, name: 'Courrier AdminFacile');
  }

  Future<void> _openLaPoste() async {
    final uri = Uri.parse('https://www.laposte.fr/');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Impossible d’ouvrir le site de La Poste.')),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Lettre générée'),
          actions: [
            IconButton(
              tooltip: 'Enregistrer en PDF',
              onPressed: _savePdf,
              icon: const Icon(Icons.save_alt_outlined),
            ),
            IconButton(
              tooltip: 'Imprimer',
              onPressed: _print,
              icon: const Icon(Icons.print_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: controller,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                labelText: 'Document modifiable',
                alignLabelWithHint: true,
                helperText:
                    'Vous pouvez corriger la lettre avant de l’enregistrer, l’envoyer ou l’imprimer.',
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Material(
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: improving ? null : _improveWithGemini,
                      icon: improving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome_rounded),
                      label: Text(improving
                          ? 'Amélioration en cours…'
                          : 'Améliorer cette lettre avec Gemini'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _savePdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Enregistrer'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _email,
                          icon: const Icon(Icons.email_outlined),
                          label: const Text('Envoyer'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _print,
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Imprimer'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openLaPoste,
                      icon: const Icon(Icons.local_post_office_outlined),
                      label: const Text('Envoyer par La Poste'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class ProceduresScreen extends StatefulWidget {
  const ProceduresScreen({super.key, required this.store});
  final ProcedureStore store;

  @override
  State<ProceduresScreen> createState() => _ProceduresScreenState();
}

class _ProceduresScreenState extends State<ProceduresScreen> {
  bool showArchived = false;
  String query = '';

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _edit(AdministrativeProcedure item) async {
    var selectedStatus = item.status;
    var reminderDate = item.reminderDate;
    final notes = TextEditingController(text: item.notes);
    final result = await showDialog<AdministrativeProcedure>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier la démarche'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<ProcedureStatus>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(labelText: 'Statut'),
                  items: ProcedureStatus.values
                      .map((status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null)
                      setDialogState(() => selectedStatus = value);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notes,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: 'Notes personnelles',
                    alignLabelWithHint: true,
                    suffixIcon: VoiceInputButton(controller: notes),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_repeat),
                  title: const Text('Date de relance'),
                  subtitle: Text(reminderDate == null
                      ? 'Aucune date'
                      : _date(reminderDate!)),
                  trailing: reminderDate == null
                      ? null
                      : IconButton(
                          tooltip: 'Supprimer la date',
                          onPressed: () =>
                              setDialogState(() => reminderDate = null),
                          icon: const Icon(Icons.clear),
                        ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: reminderDate ??
                          DateTime.now().add(const Duration(days: 14)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null)
                      setDialogState(() => reminderDate = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                item.copyWith(
                  status: selectedStatus,
                  notes: notes.text.trim(),
                  reminderDate: reminderDate,
                  clearReminder: reminderDate == null,
                ),
              ),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    notes.dispose();
    if (result != null) await widget.store.update(result);
  }

  Future<void> _confirmDelete(AdministrativeProcedure item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette démarche ?'),
        content: Text('« ${item.title} » sera supprimée définitivement.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed == true) await widget.store.remove(item.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mes démarches')),
        body: AnimatedBuilder(
          animation: widget.store,
          builder: (context, _) {
            final normalized = query.trim().toLowerCase();
            final items = widget.store.items.where((item) {
              if (item.archived != showArchived) return false;
              if (normalized.isEmpty) return true;
              return '${item.title} ${item.organisation} ${item.category} ${item.notes} ${item.status.label}'
                  .toLowerCase()
                  .contains(normalized);
            }).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Rechercher une démarche',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('En cours'),
                        icon: Icon(Icons.folder_open)),
                    ButtonSegment(
                        value: true,
                        label: Text('Archivées'),
                        icon: Icon(Icons.archive_outlined)),
                  ],
                  selected: {showArchived},
                  onSelectionChanged: (value) =>
                      setState(() => showArchived = value.first),
                ),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.assignment_outlined, size: 44),
                          SizedBox(height: 12),
                          Text('Aucune démarche dans cette section.'),
                          SizedBox(height: 6),
                          Text(
                              'Une démarche est créée automatiquement lorsque vous générez une lettre.'),
                        ],
                      ),
                    ),
                  ),
                for (final item in items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(child: Icon(item.status.icon)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 3),
                                    Text(item.organisation.isEmpty
                                        ? item.category
                                        : item.organisation),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Plus d’actions',
                                icon: const Icon(Icons.more_horiz_rounded),
                                onSelected: (value) async {
                                  if (value == 'edit') await _edit(item);
                                  if (value == 'archive') {
                                    await widget.store.update(item.copyWith(
                                        archived: !item.archived));
                                  }
                                  if (value == 'delete')
                                    await _confirmDelete(item);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'edit', child: Text('Modifier')),
                                  PopupMenuItem(
                                    value: 'archive',
                                    child: Text(item.archived
                                        ? 'Désarchiver'
                                        : 'Archiver'),
                                  ),
                                  const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Supprimer')),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                  avatar: Icon(item.status.icon, size: 18),
                                  label: Text(item.status.label)),
                              Chip(
                                  avatar: const Icon(Icons.calendar_today,
                                      size: 17),
                                  label: Text(
                                      'Créée le ${_date(item.createdAt)}')),
                              if (item.reminderDate != null)
                                Chip(
                                    avatar: const Icon(
                                        Icons.notifications_active,
                                        size: 17),
                                    label: Text(
                                        'Relance le ${_date(item.reminderDate!)}')),
                            ],
                          ),
                          if (item.notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(item.notes,
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => LetterPreviewScreen(
                                        letter: item.letter,
                                        defaultSubject: item.title,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.description_outlined),
                                  label: const Text('Ouvrir la lettre'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: 'Modifier le suivi',
                                onPressed: () => _edit(item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, required this.documentStore});
  final DocumentStore documentStore;
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final searchController = TextEditingController();
  String category = 'Tous';
  String quickFilter = 'Tous';
  String sortMode = 'Plus récents';

  static const statuses = ['À traiter', 'En cours', 'Terminé', 'Archivé'];
  static const priorities = ['Urgent', 'Important', 'Information'];
  static const suggestedCategories = [
    'CAF',
    'CPAM',
    'Impôts',
    'Banque',
    'Assurance',
    'Employeur',
    'Énergie',
    'Télécommunications',
    'Logement',
    'Autre'
  ];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<SavedDocument> _filtered(List<SavedDocument> source) {
    final query = searchController.text.trim().toLowerCase();
    final result = source.where((doc) {
      final categoryOk = category == 'Tous' || doc.category == category;
      final filterOk = switch (quickFilter) {
        'Favoris' => doc.favorite,
        'Urgents' => doc.priority == 'Urgent',
        'À traiter' => doc.status == 'À traiter',
        'Archivés' => doc.status == 'Archivé',
        _ => true,
      };
      final haystack =
          '${doc.title} ${doc.category} ${doc.organisation} ${doc.extractedText} ${doc.deadline ?? ''} ${doc.status} ${doc.priority} ${doc.notes}'
              .toLowerCase();
      return categoryOk &&
          filterOk &&
          (query.isEmpty || haystack.contains(query));
    }).toList();
    result.sort((a, b) => switch (sortMode) {
          'Plus anciens' => a.createdAt.compareTo(b.createdAt),
          'Organisme' => a.organisation
              .toLowerCase()
              .compareTo(b.organisation.toLowerCase()),
          'Priorité' =>
            _priorityRank(a.priority).compareTo(_priorityRank(b.priority)),
          _ => b.createdAt.compareTo(a.createdAt),
        });
    return result;
  }

  int _priorityRank(String value) =>
      switch (value) { 'Urgent' => 0, 'Important' => 1, _ => 2 };

  IconData _priorityIcon(String value) => switch (value) {
        'Urgent' => Icons.error_outline,
        'Important' => Icons.priority_high_rounded,
        _ => Icons.info_outline,
      };

  Future<void> _openFile(SavedDocument doc) async {
    if (doc.filePath == null || !File(doc.filePath!).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Le fichier PDF n’est plus disponible, mais le texte archivé reste accessible.')));
      return;
    }
    await Printing.layoutPdf(
        onLayout: (_) async => File(doc.filePath!).readAsBytes(),
        name: doc.title);
  }

  Future<String> _prepareCloudFile(SavedDocument doc) async {
    final existingPath = doc.filePath;
    if (existingPath != null && await File(existingPath).exists()) {
      return existingPath;
    }

    final pdf = pw.Document();
    final content = doc.extractedText.trim().isNotEmpty
        ? doc.extractedText.trim()
        : doc.notes.trim().isNotEmpty
            ? doc.notes.trim()
            : 'Document administratif enregistré dans AdminFacile.';
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => [
          pw.Text(
            doc.title,
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Organisme : ${doc.organisation}'),
          pw.Text('Catégorie : ${doc.category}'),
          pw.SizedBox(height: 18),
          pw.Text(content),
        ],
      ),
    );
    final directory = await getTemporaryDirectory();
    final safeTitle = doc.title
        .replaceAll(RegExp(r'[^a-zA-Z0-9À-ÿ._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final target = File(
      '${directory.path}/${safeTitle.isEmpty ? 'document' : safeTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await target.writeAsBytes(await pdf.save(), flush: true);
    return target.path;
  }

  Future<void> _uploadToCloud(SavedDocument doc) async {
    if (!AccountController.instance.isSignedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Connectez-vous avec le bouton en haut à droite ou dans Profil.'),
        ),
      );
      return;
    }
    try {
      final uploadPath = await _prepareCloudFile(doc);
      await CloudDocumentsController.instance.uploadFile(
        localPath: uploadPath,
        displayName: doc.title,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document enregistré dans votre espace sécurisé.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Envoi impossible : $error')),
      );
    }
  }

  Future<void> _editDocument(SavedDocument doc) async {
    final title = TextEditingController(text: doc.title);
    final organisation = TextEditingController(text: doc.organisation);
    final notes = TextEditingController(text: doc.notes);
    String selectedCategory = doc.category;
    String selectedStatus = doc.status;
    String selectedPriority = doc.priority;
    final categories = <String>{
      ...suggestedCategories,
      ...widget.documentStore.documents.map((e) => e.category)
    }.toList();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier le document'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: title,
                    decoration: InputDecoration(
                        labelText: 'Titre',
                        suffixIcon: VoiceInputButton(controller: title))),
                const SizedBox(height: 12),
                TextField(
                    controller: organisation,
                    decoration: InputDecoration(
                        labelText: 'Organisme',
                        suffixIcon:
                            VoiceInputButton(controller: organisation))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: categories.contains(selectedCategory)
                      ? selectedCategory
                      : 'Autre',
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: categories
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedCategory = v ?? 'Autre'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(labelText: 'Statut'),
                  items: statuses
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedStatus = v ?? 'À traiter'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedPriority,
                  decoration: const InputDecoration(labelText: 'Priorité'),
                  items: priorities
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setDialogState(
                      () => selectedPriority = v ?? 'Information'),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: notes,
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(
                        labelText: 'Notes personnelles',
                        alignLabelWithHint: true,
                        suffixIcon: VoiceInputButton(controller: notes))),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (saved == true) {
      await widget.documentStore.update(doc.copyWith(
        title: title.text.trim().isEmpty ? 'Document' : title.text.trim(),
        organisation: organisation.text.trim().isEmpty
            ? 'Non identifié'
            : organisation.text.trim(),
        category: selectedCategory,
        status: selectedStatus,
        priority: selectedPriority,
        notes: notes.text.trim(),
      ));
    }
    title.dispose();
    organisation.dispose();
    notes.dispose();
  }

  Future<void> _showDetails(SavedDocument doc) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .76,
        maxChildSize: .95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Text(doc.title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${doc.organisation} • ${doc.category}'),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(
                  avatar: Icon(_priorityIcon(doc.priority), size: 18),
                  label: Text(doc.priority)),
              Chip(
                  avatar: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(doc.status)),
              if (doc.deadline != null)
                Chip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text(doc.deadline!)),
            ]),
            if (doc.notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Notes',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(doc.notes),
            ],
            const SizedBox(height: 14),
            const Text('Texte reconnu',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SelectableText(doc.extractedText.isEmpty
                ? 'Aucun texte OCR enregistré.'
                : doc.extractedText),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: AnimatedBuilder(
          animation: widget.documentStore,
          builder: (_, __) {
            final categories = <String>{
              'Tous',
              ...widget.documentStore.documents.map((e) => e.category)
            }.toList();
            if (!categories.contains(category)) category = 'Tous';
            final docs = _filtered(widget.documentStore.documents);
            final total = widget.documentStore.documents.length;
            final urgent = widget.documentStore.documents
                .where((e) => e.priority == 'Urgent')
                .length;
            final pending = widget.documentStore.documents
                .where((e) => e.status == 'À traiter')
                .length;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Coffre-fort documentaire',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                    'Classez, retrouvez et suivez tous vos documents administratifs au même endroit.'),
                const SizedBox(height: 14),
                _CloudSummaryCard(
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CloudSpaceScreen()),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: _DocumentStatCard(
                          icon: Icons.folder_copy_outlined,
                          value: '$total',
                          label: 'Documents')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _DocumentStatCard(
                          icon: Icons.error_outline,
                          value: '$urgent',
                          label: 'Urgents')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _DocumentStatCard(
                          icon: Icons.pending_actions_outlined,
                          value: '$pending',
                          label: 'À traiter')),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: 'Rechercher dans le titre, l’OCR ou les notes',
                    suffixIcon: searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear)),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'Tous',
                          label: Text('Tous'),
                          icon: Icon(Icons.folder_outlined)),
                      ButtonSegment(
                          value: 'Favoris',
                          label: Text('Favoris'),
                          icon: Icon(Icons.star_outline)),
                      ButtonSegment(
                          value: 'Urgents',
                          label: Text('Urgents'),
                          icon: Icon(Icons.error_outline)),
                      ButtonSegment(
                          value: 'À traiter',
                          label: Text('À traiter'),
                          icon: Icon(Icons.pending_actions_outlined)),
                      ButtonSegment(
                          value: 'Archivés',
                          label: Text('Archivés'),
                          icon: Icon(Icons.archive_outlined)),
                    ],
                    selected: {quickFilter},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) =>
                        setState(() => quickFilter = value.first),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Catégorie'),
                    items: categories
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => category = value ?? 'Tous'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: DropdownButtonFormField<String>(
                    initialValue: sortMode,
                    decoration: const InputDecoration(labelText: 'Trier par'),
                    items: const [
                      'Plus récents',
                      'Plus anciens',
                      'Organisme',
                      'Priorité'
                    ]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => sortMode = value ?? 'Plus récents'),
                  )),
                ]),
                const SizedBox(height: 16),
                if (docs.isEmpty)
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Column(children: [
                            Icon(Icons.folder_open, size: 52),
                            SizedBox(height: 12),
                            Text(
                                'Aucun document ne correspond aux filtres sélectionnés.',
                                textAlign: TextAlign.center)
                          ])))
                else
                  ...docs.map((doc) => Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _showDetails(doc),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 52,
                                          height: 64,
                                          decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                          child: Icon(
                                              doc.filePath == null
                                                  ? Icons.description_outlined
                                                  : Icons
                                                      .picture_as_pdf_outlined,
                                              size: 30),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(doc.title,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16)),
                                              const SizedBox(height: 3),
                                              Text(doc.organisation,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              Text(
                                                  '${doc.category} • ${doc.createdAt.day.toString().padLeft(2, '0')}/${doc.createdAt.month.toString().padLeft(2, '0')}/${doc.createdAt.year}'),
                                            ])),
                                        IconButton(
                                            onPressed: () => widget
                                                .documentStore
                                                .toggleFavorite(doc.id),
                                            icon: Icon(doc.favorite
                                                ? Icons.star
                                                : Icons.star_border)),
                                      ]),
                                  const SizedBox(height: 10),
                                  Wrap(spacing: 7, runSpacing: 7, children: [
                                    Chip(
                                        avatar: Icon(
                                            _priorityIcon(doc.priority),
                                            size: 17),
                                        label: Text(doc.priority)),
                                    Chip(
                                        avatar: const Icon(Icons.flag_outlined,
                                            size: 17),
                                        label: Text(doc.status)),
                                    if (doc.deadline != null)
                                      Chip(
                                          avatar:
                                              const Icon(Icons.event, size: 17),
                                          label: Text(doc.deadline!)),
                                  ]),
                                  if (doc.extractedText.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                            doc.extractedText.length > 145
                                                ? '${doc.extractedText.substring(0, 145)}…'
                                                : doc.extractedText,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis)),
                                  if (doc.notes.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Row(children: [
                                          const Icon(
                                              Icons.sticky_note_2_outlined,
                                              size: 18),
                                          const SizedBox(width: 6),
                                          Expanded(
                                              child: Text(doc.notes,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis))
                                        ])),
                                  const SizedBox(height: 10),
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    OutlinedButton.icon(
                                        onPressed: () => _editDocument(doc),
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Modifier')),
                                    if (doc.filePath != null)
                                      OutlinedButton.icon(
                                          onPressed: () => _openFile(doc),
                                          icon: const Icon(
                                              Icons.visibility_outlined),
                                          label: const Text('Aperçu')),
                                    AnimatedBuilder(
                                      animation:
                                          CloudDocumentsController.instance,
                                      builder: (context, _) =>
                                          IconButton.filledTonal(
                                        tooltip:
                                            'Enregistrer dans mon espace sécurisé',
                                        onPressed: CloudDocumentsController
                                                .instance.busy
                                            ? null
                                            : () => _uploadToCloud(doc),
                                        icon: const Icon(
                                            Icons.cloud_upload_outlined),
                                      ),
                                    ),
                                    if (doc.filePath != null)
                                      IconButton.filledTonal(
                                          tooltip: 'Partager',
                                          onPressed: () => SharePlus.instance
                                              .share(ShareParams(
                                                  files: [XFile(doc.filePath!)],
                                                  subject: doc.title)),
                                          icon:
                                              const Icon(Icons.share_outlined)),
                                    IconButton.filledTonal(
                                        tooltip: 'Supprimer',
                                        onPressed: () =>
                                            widget.documentStore.remove(doc.id),
                                        icon: const Icon(Icons.delete_outline)),
                                  ]),
                                ]),
                          ),
                        ),
                      )),
              ],
            );
          },
        ),
      );
}

class _DocumentStatCard extends StatelessWidget {
  const _DocumentStatCard(
      {required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            Text(value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
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
        const _AccountStorageCard(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.palette_outlined,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                const Text('Apparence',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))
              ]),
              const SizedBox(height: 8),
              const Text('Choisissez le thème de l’application.'),
              const SizedBox(height: 14),
              SegmentedButton<AppThemePreference>(
                segments: const [
                  ButtonSegment(
                      value: AppThemePreference.system,
                      icon: Icon(Icons.phone_android),
                      label: Text('Auto')),
                  ButtonSegment(
                      value: AppThemePreference.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Clair')),
                  ButtonSegment(
                      value: AppThemePreference.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Sombre')),
                ],
                selected: {widget.settings.themePreference},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    widget.settings.setThemePreference(selection.first),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
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
            decoration: InputDecoration(
                labelText: 'Prénom',
                suffixIcon:
                    VoiceInputButton(controller: fields['firstName']!))),
        const SizedBox(height: 12),
        TextField(
            controller: fields['lastName'],
            decoration: InputDecoration(
                labelText: 'Nom',
                suffixIcon: VoiceInputButton(controller: fields['lastName']!))),
        const SizedBox(height: 12),
        TextField(
            controller: fields['address'],
            decoration: InputDecoration(
                labelText: 'Adresse',
                suffixIcon: VoiceInputButton(controller: fields['address']!))),
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
                  decoration: InputDecoration(
                      labelText: 'Ville',
                      suffixIcon:
                          VoiceInputButton(controller: fields['city']!)))),
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

class _CloudSummaryCard extends StatelessWidget {
  const _CloudSummaryCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AccountController.instance,
        builder: (context, _) {
          final account = AccountController.instance;
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  account.isSignedIn
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(account.isSignedIn
                  ? 'Mon espace sécurisé'
                  : 'Stockage utilisateur'),
              subtitle: Text(
                account.isSignedIn
                    ? 'Connecté avec ${account.email}'
                    : 'Connectez-vous pour sauvegarder vos PDF dans le cloud.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpen,
            ),
          );
        },
      );
}

class _AccountStorageCard extends StatelessWidget {
  const _AccountStorageCard();

  Future<void> _openAuthDialog(BuildContext context,
      {required bool create}) async {
    final email = TextEditingController();
    final password = TextEditingController();
    bool obscure = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(create ? 'Créer mon compte' : 'Me connecter'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                    labelText: 'Adresse e-mail',
                    prefixIcon: Icon(Icons.email_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setDialogState(() => obscure = !obscure),
                    icon: Icon(obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                  ),
                ),
              ),
              if (create) ...[
                const SizedBox(height: 10),
                const Text(
                    'Le mot de passe doit contenir au moins 6 caractères.'),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(create ? 'Créer' : 'Connexion')),
          ],
        ),
      ),
    );
    if (accepted != true) {
      email.dispose();
      password.dispose();
      return;
    }
    try {
      if (create) {
        await AccountController.instance
            .createAccount(email: email.text, password: password.text);
      } else {
        await AccountController.instance
            .signIn(email: email.text, password: password.text);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                create ? 'Compte créé et connecté.' : 'Connexion réussie.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      email.dispose();
      password.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AccountController.instance,
        builder: (context, _) {
          final account = AccountController.instance;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.cloud_outlined,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                          child: Text('Mon espace sécurisé',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800))),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      !account.isConfigured
                          ? 'Supabase doit être configuré pour activer les comptes et le stockage.'
                          : account.isSignedIn
                              ? 'Connecté avec ${account.email}. Vos documents cloud sont privés.'
                              : 'Créez un compte ou connectez-vous pour retrouver vos documents sur un autre téléphone.',
                    ),
                    const SizedBox(height: 14),
                    if (account.isSignedIn) ...[
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const CloudSpaceScreen())),
                        icon: const Icon(Icons.folder_outlined),
                        label: const Text('Ouvrir mon espace sécurisé'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: account.busy
                            ? null
                            : AccountController.instance.signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Se déconnecter'),
                      ),
                    ] else ...[
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton.icon(
                          onPressed: !account.isConfigured || account.busy
                              ? null
                              : () => _openAuthDialog(context, create: false),
                          icon: const Icon(Icons.login),
                          label: const Text('Se connecter'),
                        ),
                        OutlinedButton.icon(
                          onPressed: !account.isConfigured || account.busy
                              ? null
                              : () => _openAuthDialog(context, create: true),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Créer un compte'),
                        ),
                      ]),
                    ],
                  ]),
            ),
          );
        },
      );
}

class CloudSpaceScreen extends StatefulWidget {
  const CloudSpaceScreen({super.key});

  @override
  State<CloudSpaceScreen> createState() => _CloudSpaceScreenState();
}

class _CloudSpaceScreenState extends State<CloudSpaceScreen> {
  @override
  void initState() {
    super.initState();
    if (AccountController.instance.isSignedIn) {
      Future<void>.microtask(() async {
        try {
          await CloudDocumentsController.instance.refresh();
        } catch (_) {}
      });
    }
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Mon espace sécurisé'),
          actions: [
            IconButton(
              tooltip: 'Actualiser',
              onPressed: AccountController.instance.isSignedIn
                  ? () async {
                      try {
                        await CloudDocumentsController.instance.refresh();
                      } catch (error) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$error')));
                      }
                    }
                  : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge(
              [AccountController.instance, CloudDocumentsController.instance]),
          builder: (context, _) {
            final account = AccountController.instance;
            final cloud = CloudDocumentsController.instance;
            if (!cloud.isConfigured) {
              return const _CloudEmptyState(
                icon: Icons.settings_outlined,
                title: 'Supabase à configurer',
                subtitle:
                    'La connexion au stockage sécurisé n’est pas disponible. Vérifiez votre connexion Internet.',
              );
            }
            if (!account.isSignedIn) {
              return const _CloudEmptyState(
                icon: Icons.lock_outline,
                title: 'Connexion nécessaire',
                subtitle:
                    'Ouvrez Profil pour créer un compte ou vous connecter.',
              );
            }
            if (cloud.busy && cloud.documents.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (cloud.documents.isEmpty) {
              return const _CloudEmptyState(
                icon: Icons.cloud_upload_outlined,
                title: 'Votre espace est vide',
                subtitle:
                    'Dans Mes documents, appuyez sur l’icône cloud pour sauvegarder un PDF.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: cloud.documents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final document = cloud.documents[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                        child: Icon(Icons.picture_as_pdf_outlined)),
                    title: Text(document.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_size(document.size)),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Plus d’actions',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (action) async {
                        try {
                          if (action == 'download') {
                            final path = await cloud.download(document);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Téléchargé dans : $path')));
                          } else if (action == 'delete') {
                            await cloud.delete(document);
                          }
                        } catch (error) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$error')));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'download',
                            child: ListTile(
                                leading: Icon(Icons.download_outlined),
                                title: Text('Télécharger'))),
                        PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                                leading: Icon(Icons.delete_outline),
                                title: Text('Supprimer'))),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}

class _CloudEmptyState extends StatelessWidget {
  const _CloudEmptyState(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 76, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
          ]),
        ),
      );
}

class LetterGenerator {
  static String generate({
    required LetterTemplate template,
    ProfessionalLetterModel? model,
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
    final selectedModel = model ?? template.models.first;
    final subject = selectedModel.subject;
    final body = selectedModel.body;
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
