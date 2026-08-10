import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/voice_input_button.dart';
import 'signature_pad.dart';
import 'letter_signature_service.dart';
import 'signature_image_service.dart';
import 'scanner_processing_service.dart';
import 'document_scanner_service.dart';
import 'professional_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _defaultSupabaseUrl = 'https://pmnjphgaxcmxmhurhucm.supabase.co';
const String _defaultSupabasePublishableKey =
    'sb_publishable_XFIAQwu98Rbgn2xFwXkKpw_DJnQrRE_';

const String _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: _defaultSupabaseUrl,
);

const String _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: _defaultSupabasePublishableKey,
);

bool get _supabaseConfigured =>
    _supabaseUrl.trim().isNotEmpty && _supabasePublishableKey.trim().isNotEmpty;

bool _supabaseReady = false;
String? _supabaseInitializationError;
ProfessionalAuthService? _authService;
late AppSettings appSettings;

User? get _currentSupabaseUser =>
    _supabaseReady ? Supabase.instance.client.auth.currentUser : null;

String procedureCloudPath(String userId, String procedureId) =>
    '$userId/procedures/$procedureId.pdf';

String cloudOperationMessage(Object error) {
  if (error is TimeoutException) {
    return 'Le service cloud met trop de temps à répondre. Réessayez.';
  }
  if (error is SocketException) return 'Vérifiez votre connexion Internet.';
  if (error is AuthException) {
    return 'Votre session cloud n’est plus valide. Reconnectez-vous.';
  }
  return 'Le service cloud est momentanément indisponible.';
}

enum ProcedureCloudState { notSynced, uploading, synced, failed }

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
    this.signed = false,
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
  final bool signed;

  AdministrativeProcedure copyWith({
    ProcedureStatus? status,
    String? notes,
    DateTime? reminderDate,
    bool clearReminder = false,
    bool? archived,
    String? letter,
    bool? signed,
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
        signed: signed ?? this.signed,
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
        'signed': signed,
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
      signed: json['signed'] as bool? ?? false,
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
    this.detectedDocumentType = 'Document inconnu',
    this.detectedAmount = '',
    this.detectedDueDate = '',
    this.detectedReference = '',
    this.detectedOrganisation = '',
    this.detectedPriority = 'À vérifier',
    this.analysisConfidence = 0.0,
    this.userCorrectedAnalysis = false,
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
  final String detectedDocumentType;
  final String detectedAmount;
  final String detectedDueDate;
  final String detectedReference;
  final String detectedOrganisation;
  final String detectedPriority;
  final double analysisConfidence;
  final bool userCorrectedAnalysis;

  SavedDocument copyWith({
    String? title,
    String? category,
    String? organisation,
    String? deadline,
    bool? favorite,
    String? status,
    String? priority,
    String? notes,
    String? detectedDocumentType,
    String? detectedAmount,
    String? detectedDueDate,
    String? detectedReference,
    String? detectedOrganisation,
    String? detectedPriority,
    double? analysisConfidence,
    bool? userCorrectedAnalysis,
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
        detectedDocumentType: detectedDocumentType ?? this.detectedDocumentType,
        detectedAmount: detectedAmount ?? this.detectedAmount,
        detectedDueDate: detectedDueDate ?? this.detectedDueDate,
        detectedReference: detectedReference ?? this.detectedReference,
        detectedOrganisation: detectedOrganisation ?? this.detectedOrganisation,
        detectedPriority: detectedPriority ?? this.detectedPriority,
        analysisConfidence: analysisConfidence ?? this.analysisConfidence,
        userCorrectedAnalysis:
            userCorrectedAnalysis ?? this.userCorrectedAnalysis,
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
        'detectedDocumentType': detectedDocumentType,
        'detectedAmount': detectedAmount,
        'detectedDueDate': detectedDueDate,
        'detectedReference': detectedReference,
        'detectedOrganisation': detectedOrganisation,
        'detectedPriority': detectedPriority,
        'analysisConfidence': analysisConfidence,
        'userCorrectedAnalysis': userCorrectedAnalysis,
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
        detectedDocumentType:
            json['detectedDocumentType'] as String? ?? 'Document inconnu',
        detectedAmount: json['detectedAmount'] as String? ?? '',
        detectedDueDate: json['detectedDueDate'] as String? ?? '',
        detectedReference: json['detectedReference'] as String? ?? '',
        detectedOrganisation: json['detectedOrganisation'] as String? ??
            json['organisation'] as String? ??
            '',
        detectedPriority: json['detectedPriority'] as String? ?? 'À vérifier',
        analysisConfidence:
            (json['analysisConfidence'] as num?)?.toDouble() ?? 0.0,
        userCorrectedAnalysis: json['userCorrectedAnalysis'] as bool? ?? false,
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

  if (_supabaseConfigured) {
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _supabasePublishableKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          autoRefreshToken: true,
          detectSessionInUri: true,
        ),
      );
      _supabaseReady = true;
      _authService = ProfessionalAuthService(
        SupabaseAuthGateway(Supabase.instance.client),
      );
    } catch (error, stackTrace) {
      _supabaseInitializationError = error.toString();
      debugPrint('Supabase.initialize a échoué : $error\n$stackTrace');
    }
  }

  final settings = AppSettings();
  appSettings = settings;
  final documentStore = DocumentStore();
  final procedureStore = appProcedureStore;

  await settings.load();
  await Future.wait([documentStore.load(), procedureStore.load()]);

  runApp(
    AdminFacileApp(
      settings: settings,
      documentStore: documentStore,
      procedureStore: procedureStore,
      authSession: SupabaseAppAuthSession(),
    ),
  );

  // La synchronisation réseau ne doit jamais retarder le premier écran.
  if (settings.signatureMigratedOnLoad && settings.hasSignature) {
    unawaited(_syncMigratedSignature(settings));
  }
}

Future<void> _syncMigratedSignature(AppSettings settings) async {
  final user = _currentSupabaseUser;
  if (user == null) return;
  try {
    final bytes = await File(settings.signaturePath).readAsBytes();
    await Supabase.instance.client.storage
        .from('admin-documents')
        .uploadBinary(
          '${user.id}/profile/signature.png',
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/png',
          ),
        )
        .timeout(const Duration(seconds: 20));
  } catch (error) {
    debugPrint('Synchronisation de la signature migrée impossible : $error');
  }
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
  String signaturePath = '';
  bool autoInsertSignature = false;
  bool signatureMigratedOnLoad = false;
  AppThemePreference themePreference = AppThemePreference.dark;

  String get greeting {
    final name = firstName.trim();
    if (name.isEmpty) return 'Bienvenue';
    final normalized =
        '${name[0].toUpperCase()}${name.substring(1).toLowerCase()}';
    return 'Bonjour $normalized';
  }

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
    signaturePath = _prefs!.getString('signaturePathV17') ?? '';
    autoInsertSignature = _prefs!.getBool('autoInsertSignatureV17') ?? false;
    final savedTheme =
        _prefs!.getString('themePreference') ?? AppThemePreference.dark.name;
    themePreference = AppThemePreference.values.firstWhere(
      (value) => value.name == savedTheme,
      orElse: () => AppThemePreference.dark,
    );
    signatureMigratedOnLoad = await _migrateSignatureIfNeeded();
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

  bool get hasSignature =>
      signaturePath.isNotEmpty && File(signaturePath).existsSync();

  Future<void> saveSignatureBytes(Uint8List bytes,
      {Directory? directory}) async {
    directory ??= await getApplicationDocumentsDirectory();
    final normalized =
        await SignatureImageService.normalizeSignatureToTransparentPng(bytes);
    final file = File('${directory.path}/adminfacile_signature_v1735.png');
    await file.writeAsBytes(normalized, flush: true);
    signaturePath = file.path;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString('signaturePathV17', signaturePath);
    await prefs.setBool('signatureTransparentPngV1735', true);
    notifyListeners();
  }

  Future<bool> _migrateSignatureIfNeeded() async {
    if (signaturePath.isEmpty ||
        (_prefs?.getBool('signatureTransparentPngV1735') ?? false)) {
      return false;
    }
    final legacyFile = File(signaturePath);
    if (!await legacyFile.exists()) return false;
    try {
      final normalized =
          await SignatureImageService.normalizeSignatureToTransparentPng(
        await legacyFile.readAsBytes(),
      );
      final directory = legacyFile.parent;
      final migrated =
          File('${directory.path}/adminfacile_signature_v1735.png');
      await migrated.writeAsBytes(normalized, flush: true);
      signaturePath = migrated.path;
      await _prefs!.setString('signaturePathV17', signaturePath);
      await _prefs!.setBool('signatureTransparentPngV1735', true);
      // L’ancien fichier est volontairement conservé : aucune donnée n’est
      // supprimée pendant la migration.
      return true;
    } catch (_) {
      // L'image brute n'est plus utilisée dans les PDF après un échec.
      signaturePath = '';
      return false;
    }
  }

  Future<void> removeSignature() async {
    final file = File(signaturePath);
    if (await file.exists()) await file.delete();
    signaturePath = '';
    autoInsertSignature = false;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.remove('signaturePathV17');
    await prefs.remove('signatureTransparentPngV1733');
    await prefs.remove('signatureTransparentPngV1734');
    await prefs.remove('signatureTransparentPngV1735');
    await prefs.setBool('autoInsertSignatureV17', false);
    notifyListeners();
  }

  Future<void> setAutoInsertSignature(bool value) async {
    autoInsertSignature = value && hasSignature;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setBool('autoInsertSignatureV17', autoInsertSignature);
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
    required this.authSession,
  });
  final AppSettings settings;
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;
  final AppAuthSession authSession;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AdminFacile',
        themeMode: settings.themePreference.themeMode,
        theme: _buildAdminTheme(Brightness.light, settings.comfortMode),
        darkTheme: _buildAdminTheme(Brightness.dark, settings.comfortMode),
        home: AuthGate(
          settings: settings,
          documentStore: documentStore,
          procedureStore: procedureStore,
          authSession: authSession,
        ),
      ),
    );
  }
}

abstract interface class AppAuthSession {
  bool get isServiceAvailable;
  bool get isAuthenticated;
  ProfessionalAuthService? get service;
  Stream<bool> get changes;
}

class SupabaseAppAuthSession implements AppAuthSession {
  @override
  bool get isServiceAvailable => _supabaseReady && _authService != null;

  @override
  bool get isAuthenticated =>
      isServiceAvailable &&
      Supabase.instance.client.auth.currentSession != null &&
      Supabase.instance.client.auth.currentUser != null;

  @override
  ProfessionalAuthService? get service => _authService;

  @override
  Stream<bool> get changes {
    if (!_supabaseReady) return const Stream<bool>.empty();
    return Supabase.instance.client.auth.onAuthStateChange.map(
      (state) => state.session != null && state.session?.user != null,
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.settings,
    required this.documentStore,
    required this.procedureStore,
    required this.authSession,
  });
  final AppSettings settings;
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;
  final AppAuthSession authSession;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<bool>? _subscription;
  bool _splashComplete = false;
  late bool _authenticated;

  @override
  void initState() {
    super.initState();
    _authenticated = widget.authSession.isAuthenticated;
    _subscription = widget.authSession.changes.listen(
      (authenticated) {
        if (mounted) setState(() => _authenticated = authenticated);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('AUTH_GATE stream_error type=${error.runtimeType}');
        if (mounted) setState(() => _authenticated = false);
      },
    );
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _splashComplete = true;
        _authenticated = widget.authSession.isAuthenticated;
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Widget _splash() => Scaffold(
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

  @override
  Widget build(BuildContext context) {
    if (!_splashComplete) return _splash();
    if (!_authenticated) {
      return WelcomeAuthScreen(authSession: widget.authSession);
    }
    return AppShell(
      settings: widget.settings,
      documentStore: widget.documentStore,
      procedureStore: widget.procedureStore,
    );
  }
}

class WelcomeAuthScreen extends StatefulWidget {
  const WelcomeAuthScreen({super.key, required this.authSession});
  final AppAuthSession authSession;

  @override
  State<WelcomeAuthScreen> createState() => _WelcomeAuthScreenState();
}

class _WelcomeAuthScreenState extends State<WelcomeAuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool? createAccount;
  bool busy = false;
  bool passwordVisible = false;
  String? message;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final service = widget.authSession.service;
    if (service == null) {
      setState(() => message = 'Service temporairement indisponible.');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (createAccount == true) {
        final result = await service.signUp(
          email: email.text,
          password: password.text,
        );
        if (mounted && result.emailConfirmationRequired) {
          setState(() {
            message = 'Compte créé. Vérifiez votre e-mail pour le confirmer.';
            createAccount = false;
            password.clear();
          });
        }
      } else {
        await service.signIn(email: email.text, password: password.text);
      }
    } on AuthOperationException catch (error) {
      if (mounted) setState(() => message = error.displayMessage);
    } catch (error) {
      if (mounted) {
        setState(() => message = ProfessionalAuthService.mapError(
              error,
              operation: createAccount == true ? 'signUp' : 'signIn',
            ).displayMessage);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final service = widget.authSession.service;
    if (service == null) {
      setState(() => message = 'Service temporairement indisponible.');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await service.sendPasswordReset(email.text);
      if (mounted) {
        setState(() => message =
            'E-mail de récupération envoyé. Vérifiez aussi vos courriers indésirables.');
      }
    } on AuthOperationException catch (error) {
      if (mounted) setState(() => message = error.displayMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const Key('auth-welcome-screen'),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AdminFacileMark(size: 82)),
                    const SizedBox(height: 18),
                    Text('AdminFacile',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text('Simplifiez vos démarches administratives',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 30),
                    if (createAccount == null) ...[
                      FilledButton(
                        key: const Key('auth-create-account'),
                        onPressed: widget.authSession.isServiceAvailable
                            ? () => setState(() {
                                  createAccount = true;
                                  passwordVisible = false;
                                })
                            : null,
                        child: const Text('Créer mon compte'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        key: const Key('auth-existing-account'),
                        onPressed: widget.authSession.isServiceAvailable
                            ? () => setState(() {
                                  createAccount = false;
                                  passwordVisible = false;
                                })
                            : null,
                        child: const Text('J’ai déjà un compte'),
                      ),
                      if (!widget.authSession.isServiceAvailable) ...[
                        const SizedBox(height: 16),
                        const Text('Service temporairement indisponible.',
                            textAlign: TextAlign.center),
                      ],
                    ] else ...[
                      Text(createAccount! ? 'Créer mon compte' : 'Connexion',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('auth-email'),
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration:
                            const InputDecoration(labelText: 'Adresse e-mail'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('auth-password'),
                        controller: password,
                        obscureText: !passwordVisible,
                        autofillHints: createAccount!
                            ? const [AutofillHints.newPassword]
                            : const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          suffixIcon: IconButton(
                            key: const Key('auth-password-visibility'),
                            tooltip: passwordVisible
                                ? 'Masquer le mot de passe'
                                : 'Afficher le mot de passe',
                            icon: Icon(passwordVisible
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () => setState(
                                () => passwordVisible = !passwordVisible),
                          ),
                        ),
                        onSubmitted: (_) => busy ? null : _submit(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const Key('auth-submit'),
                        onPressed: busy ? null : _submit,
                        child: busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(createAccount!
                                ? 'Créer mon compte'
                                : 'Se connecter'),
                      ),
                      if (!createAccount!)
                        TextButton(
                          key: const Key('auth-forgot-password'),
                          onPressed: busy ? null : _resetPassword,
                          child: const Text('Mot de passe oublié ?'),
                        ),
                      TextButton(
                        key: const Key('auth-back'),
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  createAccount = null;
                                  passwordVisible = false;
                                }),
                        child: const Text('Retour'),
                      ),
                    ],
                    if (message != null) ...[
                      const SizedBox(height: 12),
                      Text(message!,
                          key: const Key('auth-message'),
                          textAlign: TextAlign.center),
                    ],
                  ],
                ),
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
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    if (_supabaseReady) {
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen(
        (_) {
          if (mounted) setState(() {});
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('onAuthStateChange a échoué : $error\n$stackTrace');
        },
      );
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      LegacyHomeScreen(
        settings: widget.settings,
        documentStore: widget.documentStore,
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
                GeminiLetterWriterV156Screen(settings: widget.settings))),
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
        openDocuments: () => setState(() => index = 3),
        openSecureSpace: () => Navigator.of(context).push(
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
                  GeminiLetterWriterV156Screen(settings: widget.settings)));
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
        _DrawerEntry(
          key: const Key('drawer-premium-entry'),
          icon: Icons.workspace_premium_rounded,
          iconColor: const Color(0xFFB8860B),
          label: 'Version Premium',
          subtitle: 'Débloquer toutes les fonctionnalités',
          onTap: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Version Premium'),
              content:
                  const Text('La version Premium sera bientôt disponible.'),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Fermer'),
                ),
              ],
            ),
          ),
        ),
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
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap,
      this.subtitle,
      this.iconColor,
      this.selected = false});
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? iconColor;
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
            color: iconColor ??
                (selected
                    ? const Color(0xFF2588FF)
                    : Theme.of(context).colorScheme.onSurfaceVariant)),
        title: Text(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      ));
}

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen(
      {super.key,
      required this.documentStore,
      required this.procedureStore,
      required this.settings,
      this.initialModels});
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;
  final AppSettings settings;
  final List<JsonLetterRecord>? initialModels;
  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final controller = TextEditingController();
  String query = '';
  List<JsonLetterRecord> models = const [];
  final Set<String> favoriteModelIds = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialModels != null) {
      models = widget.initialModels!;
      _loadFavoriteIds();
    } else {
      _loadModels();
    }
  }

  Future<void> _loadFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => favoriteModelIds.addAll(
        prefs.getStringList('jsonLibraryFavoritesV66') ?? const <String>[]));
  }

  Future<void> _loadModels() async {
    final loaded = await BundledLetterCatalog.load();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      models = loaded;
      favoriteModelIds.addAll(
          prefs.getStringList('jsonLibraryFavoritesV66') ?? const <String>[]);
    });
  }

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
    final modelResults = query.trim().isEmpty
        ? <JsonLetterRecord>[]
        : V173LetterCatalog.search(models, query);
    final favoriteResults = modelResults
        .where((model) => favoriteModelIds.contains(model.id))
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
        if (query.trim().isNotEmpty &&
            procedures.isEmpty &&
            documents.isEmpty &&
            modelResults.isEmpty)
          const _SearchEmptyState(
              title: 'Aucun résultat',
              subtitle:
                  'Essayez un organisme, un sujet ou un mot présent dans le document.'),
        if (modelResults.isNotEmpty) ...[
          Text('Modèles de lettres (${modelResults.length})',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...modelResults.take(4).map((model) => Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(model.title),
                  subtitle: Text('${model.category} • ${model.description}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LetterModelDetailScreen(
                          settings: widget.settings, record: model))),
                ),
              )),
          if (modelResults.length > 4)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        JsonLibraryScreen(settings: widget.settings))),
                child: const Text('Voir tout'),
              ),
            ),
          const SizedBox(height: 16),
        ],
        if (procedures.isNotEmpty) ...[
          Text('Mes démarches (${procedures.length})',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...procedures.take(4).map((e) => Card(
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
          Text('Mes documents (${documents.length})',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...documents.take(4).map((e) => Card(
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
        if (favoriteResults.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Favoris (${favoriteResults.length})',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...favoriteResults.take(4).map((model) => Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.star_rounded, color: Color(0xFFFFAD1F)),
                  title: Text(model.title),
                  subtitle: Text(model.category),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LetterModelDetailScreen(
                          settings: widget.settings, record: model))),
                ),
              )),
        ],
        if (query.trim().isNotEmpty && modelResults.isEmpty) ...[
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

class DashboardMetrics {
  DashboardMetrics({
    required List<AdministrativeProcedure> procedures,
    required List<SavedDocument> documents,
    DateTime? now,
  }) {
    final today = DateUtils.dateOnly(now ?? DateTime.now());
    final inSevenDays = today.add(const Duration(days: 7));
    activeProcedures = procedures
        .where((item) =>
            !item.archived && item.status != ProcedureStatus.completed)
        .length;
    completedProcedures = procedures
        .where((item) => item.status == ProcedureStatus.completed)
        .length;
    waitingProcedures = procedures
        .where((item) =>
            !item.archived &&
            (item.status == ProcedureStatus.waiting ||
                item.status == ProcedureStatus.sent))
        .length;
    proceduresWithReminder = procedures
        .where((item) => !item.archived && item.reminderDate != null)
        .length;
    remindersToday = procedures.where((item) {
      final date = item.reminderDate;
      return !item.archived && date != null && DateUtils.isSameDay(date, today);
    }).length;
    remindersNextSevenDays = procedures.where((item) {
      final date = item.reminderDate;
      if (item.archived || date == null) return false;
      final day = DateUtils.dateOnly(date);
      return day.isAfter(today) && !day.isAfter(inSevenDays);
    }).length;
    documentsWithDeadline = documents.where((item) {
      final date = parseDocumentDeadline(item.deadline);
      return date != null && !date.isBefore(today);
    }).length;
    urgentDeadlines = documents.where((item) {
      final date = parseDocumentDeadline(item.deadline);
      return date != null &&
          !date.isBefore(today) &&
          !date.isAfter(inSevenDays);
    }).length;
    favoriteDocuments = documents.where((item) => item.favorite).length;
    documentCount = documents.length;
  }

  late final int activeProcedures;
  late final int completedProcedures;
  late final int waitingProcedures;
  late final int proceduresWithReminder;
  late final int remindersToday;
  late final int remindersNextSevenDays;
  late final int documentsWithDeadline;
  late final int urgentDeadlines;
  late final int favoriteDocuments;
  late final int documentCount;

  bool get hasUrgent => remindersToday > 0 || urgentDeadlines > 0;
  bool get hasWarning =>
      remindersNextSevenDays > 0 ||
      waitingProcedures > 0 ||
      documentsWithDeadline > 0;

  static DateTime? parseDocumentDeadline(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final direct = DateTime.tryParse(value.trim());
    if (direct != null) return DateUtils.dateOnly(direct);
    final match =
        RegExp(r'(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})').firstMatch(value);
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    return date.day == day && date.month == month && date.year == year
        ? date
        : null;
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.documentStore,
    required this.procedureStore,
    required this.openScanner,
    required this.openLetters,
    required this.openSearch,
    required this.openProblem,
    required this.openAiWriter,
    required this.openTranslator,
    required this.openDictation,
    required this.openProcedures,
    required this.openDocuments,
    required this.openSecureSpace,
    required this.openMenu,
    required this.openGlobalSearch,
    required this.openProfile,
  });

  final AppSettings settings;
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;
  final VoidCallback openScanner;
  final VoidCallback openLetters;
  final VoidCallback openSearch;
  final VoidCallback openProblem;
  final VoidCallback openAiWriter;
  final VoidCallback openTranslator;
  final VoidCallback openDictation;
  final VoidCallback openProcedures;
  final VoidCallback openDocuments;
  final VoidCallback openSecureSpace;
  final VoidCallback openMenu;
  final VoidCallback openGlobalSearch;
  final VoidCallback openProfile;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([settings, procedureStore, documentStore]),
        builder: (context, _) {
          final metrics = DashboardMetrics(
            procedures: procedureStore.items,
            documents: documentStore.documents,
          );
          final procedures = procedureStore.items.take(3).toList();
          final documents = documentStore.documents.take(3).toList();
          final scheme = Theme.of(context).colorScheme;
          final syncColor = _currentSupabaseUser != null
              ? Colors.green
              : scheme.onSurfaceVariant;
          final dark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? const [Color(0xFF07162A), Color(0xFF020C1D)]
                    : const [Color(0xFFF1F6FD), Color(0xFFFAFBFD)],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: LayoutBuilder(builder: (context, constraints) {
                final tablet = constraints.maxWidth >= 700;
                return ListView(
                  key: const Key('dashboard-v16'),
                  padding: EdgeInsets.symmetric(
                    horizontal: tablet ? 32 : 16,
                    vertical: 10,
                  ),
                  children: [
                    Row(children: [
                      IconButton(
                        tooltip: 'Menu',
                        onPressed: openMenu,
                        icon: const Icon(Icons.menu_rounded),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(settings.greeting,
                                key: const Key('dashboard-greeting'),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            Text('Votre assistant administratif',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Recherche globale',
                        onPressed: openGlobalSearch,
                        icon: const Icon(Icons.search_rounded),
                      ),
                      IconButton.filledTonal(
                        key: const Key('dashboard-profile-button'),
                        tooltip: 'Profil',
                        onPressed: openProfile,
                        icon: const Icon(Icons.person_rounded),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: dark ? 0 : 1,
                      color: dark ? const Color(0xFF0A1B31) : scheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        child: Row(children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: scheme.primaryContainer,
                            child: Icon(
                              _currentSupabaseUser == null
                                  ? Icons.person_outline_rounded
                                  : Icons.person_rounded,
                              size: 19,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentSupabaseUser == null
                                      ? 'Compte déconnecté'
                                      : 'Compte connecté',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  _supabaseConfigured
                                      ? 'Synchronisation disponible'
                                      : 'Synchronisation indisponible',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            key: const Key('synchronization-badge'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: syncColor.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _currentSupabaseUser != null
                                  ? 'Synchronisé'
                                  : 'Local',
                              style: TextStyle(
                                  color: syncColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _DashboardTitle('Aujourd’hui'),
                    const SizedBox(height: 6),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      childAspectRatio: tablet ? 4.2 : 2.25,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      children: [
                        _MetricCard(
                            key: const Key('active-procedures-count'),
                            icon: Icons.pending_actions_rounded,
                            value: metrics.activeProcedures,
                            label: 'En cours',
                            color: scheme.primary),
                        _MetricCard(
                            icon: Icons.notifications_active_outlined,
                            value: metrics.proceduresWithReminder,
                            label: 'Relances',
                            color: scheme.primary),
                        _MetricCard(
                            icon: Icons.hourglass_top_rounded,
                            value: metrics.waitingProcedures,
                            label: 'En attente',
                            color: scheme.primary),
                        _MetricCard(
                            icon: Icons.check_circle_outline_rounded,
                            value: metrics.completedProcedures,
                            label: 'Terminées',
                            color: scheme.primary),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _DashboardTitle('Actions rapides'),
                    const SizedBox(height: 6),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 8,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: tablet ? 4 : 2,
                        mainAxisExtent: 84,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemBuilder: (context, index) => [
                        _QuickAction(Icons.document_scanner_outlined, 'Scanner',
                            openScanner),
                        _QuickAction(Icons.auto_awesome_rounded,
                            'Rédiger avec Gemini', openAiWriter),
                        _QuickAction(
                            Icons.edit_note_rounded, 'Lettre', openLetters),
                        _QuickAction(Icons.folder_copy_outlined, 'Démarches',
                            openProcedures),
                        _QuickAction(
                            Icons.folder_outlined, 'Documents', openDocuments),
                        _QuickAction(
                            Icons.cloud_outlined, 'Cloud', openSecureSpace),
                        _QuickAction(Icons.translate_rounded, 'Traduire',
                            openTranslator),
                        _QuickAction(Icons.search_rounded, 'Rechercher',
                            openGlobalSearch),
                      ][index],
                    ),
                    const SizedBox(height: 14),
                    const _DashboardTitle('À ne pas manquer'),
                    const SizedBox(height: 6),
                    _AttentionList(metrics: metrics),
                    const SizedBox(height: 14),
                    Row(children: [
                      const Expanded(
                          child: _DashboardTitle('Activité récente')),
                      TextButton(
                          onPressed: openDocuments,
                          child: const Text('Documents')),
                      TextButton(
                          onPressed: openProcedures,
                          child: const Text('Démarches')),
                    ]),
                    _RecentActivity(
                        procedures: procedures,
                        documents: documents,
                        openProcedures: openProcedures,
                        openDocuments: openDocuments),
                  ],
                );
              }),
            ),
          );
        },
      );
}

class _DashboardTitle extends StatelessWidget {
  const _DashboardTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w800));
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {super.key,
      required this.icon,
      required this.value,
      required this.label,
      required this.color});
  final IconData icon;
  final int value;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$value',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            height: 1,
                            color: color,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ])),
      );
}

class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.metrics});
  final DashboardMetrics metrics;
  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, Color)>[
      if (metrics.remindersToday > 0)
        (
          Icons.notification_important_rounded,
          '${metrics.remindersToday} relance(s) aujourd’hui',
          Colors.red
        ),
      if (metrics.remindersNextSevenDays > 0)
        (
          Icons.event_rounded,
          '${metrics.remindersNextSevenDays} relance(s) dans les 7 jours',
          Colors.orange
        ),
      if (metrics.waitingProcedures > 0)
        (
          Icons.hourglass_top_rounded,
          '${metrics.waitingProcedures} démarche(s) en attente de réponse',
          Colors.orange
        ),
      if (metrics.documentsWithDeadline > 0)
        (
          Icons.schedule_rounded,
          '${metrics.documentsWithDeadline} document(s) avec échéance',
          metrics.urgentDeadlines > 0 ? Colors.red : Colors.orange
        ),
    ];
    if (items.isEmpty) {
      return const Card(
          margin: EdgeInsets.zero,
          child: ListTile(
              dense: true,
              visualDensity: VisualDensity(vertical: -4),
              leading: Icon(Icons.check_circle_rounded, color: Colors.green),
              title: Text('Aucune action urgente')));
    }
    return Card(
        margin: EdgeInsets.zero,
        child: Column(children: [
          for (final item in items)
            ListTile(
                dense: true,
                visualDensity: const VisualDensity(vertical: -3),
                leading: Icon(item.$1, color: item.$3),
                title:
                    Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis))
        ]));
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      key: ValueKey('quick-action-$label'),
      margin: EdgeInsets.zero,
      child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon,
                      size: 22,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700))),
                Icon(Icons.chevron_right_rounded,
                    size: 17,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ]))));
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity(
      {required this.procedures,
      required this.documents,
      required this.openProcedures,
      required this.openDocuments});
  final List<AdministrativeProcedure> procedures;
  final List<SavedDocument> documents;
  final VoidCallback openProcedures;
  final VoidCallback openDocuments;
  @override
  Widget build(BuildContext context) {
    if (procedures.isEmpty && documents.isEmpty) {
      return const Card(
          child: ListTile(
              leading: Icon(Icons.history_rounded),
              title: Text('Aucune activité récente')));
    }
    return Card(
        key: const Key('recent-activity'),
        child: Column(children: [
          for (final item in procedures)
            ListTile(
                dense: true,
                visualDensity: const VisualDensity(vertical: -3),
                onTap: openProcedures,
                leading: const Icon(Icons.assignment_outlined),
                title: Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item.status.label)),
          for (final item in documents)
            ListTile(
                dense: true,
                visualDensity: const VisualDensity(vertical: -3),
                onTap: openDocuments,
                leading: const Icon(Icons.description_outlined),
                title: Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item.category)),
        ]));
  }
}

class LegacyHomeScreen extends StatelessWidget {
  const LegacyHomeScreen({
    super.key,
    required this.settings,
    required this.documentStore,
    required this.procedureStore,
    required this.openScanner,
    required this.openLetters,
    required this.openSearch,
    required this.openProblem,
    required this.openAiWriter,
    required this.openTranslator,
    required this.openDictation,
    required this.openProcedures,
    required this.openDocuments,
    required this.openSecureSpace,
    required this.openMenu,
    required this.openGlobalSearch,
    required this.openProfile,
  });

  final AppSettings settings;
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;
  final VoidCallback openScanner;
  final VoidCallback openLetters;
  final VoidCallback openSearch;
  final VoidCallback openProblem;
  final VoidCallback openAiWriter;
  final VoidCallback openTranslator;
  final VoidCallback openDictation;
  final VoidCallback openProcedures;
  final VoidCallback openDocuments;
  final VoidCallback openSecureSpace;
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
                key: const Key('dashboard-v17'),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
                children: [
                  _DarkHeader(
                      greeting: settings.greeting,
                      settings: settings,
                      openMenu: openMenu,
                      openSearch: openGlobalSearch,
                      openProfile: openProfile,
                      notificationCount: reminders),
                  const SizedBox(height: 20),
                  _DarkHeroCard(
                      onScan: openScanner,
                      onWrite: openAiWriter,
                      onUseModel: openSearch),
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
  const _DarkHeader(
      {required this.greeting,
      required this.settings,
      required this.openMenu,
      required this.openSearch,
      required this.openProfile,
      required this.notificationCount});
  final String greeting;
  final AppSettings settings;
  final VoidCallback openMenu;
  final VoidCallback openSearch;
  final VoidCallback openProfile;
  final int notificationCount;
  @override
  Widget build(BuildContext context) => Row(children: [
        _HeaderCircle(icon: Icons.menu_rounded, onTap: openMenu),
        const SizedBox(width: 10),
        Expanded(
          child: Row(children: [
            const AdminFacileMark(size: 38),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AdminFacile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  Text('Votre assistant administratif',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Rechercher',
          child: _HeaderCircle(
            key: const Key('dashboard-global-search'),
            icon: Icons.search_rounded,
            onTap: openSearch,
          ),
        ),
        const SizedBox(width: 6),
        Stack(clipBehavior: Clip.none, children: [
          _HeaderCircle(
              icon: Icons.notifications_none_rounded, onTap: openSearch),
          if (notificationCount > 0)
            Positioned(
                right: -2,
                top: -5,
                child: CircleAvatar(
                    radius: 10,
                    backgroundColor: const Color(0xFFFF3B3B),
                    child: Text(
                        '${notificationCount > 9 ? '9+' : notificationCount}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)))),
        ]),
        const SizedBox(width: 6),
        Tooltip(
          message:
              _currentSupabaseUser == null ? 'Se connecter' : 'Compte connecté',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _HeaderCircle(
                key: const Key('dashboard-profile-button'),
                icon: _currentSupabaseUser == null
                    ? Icons.person_outline_rounded
                    : Icons.person_rounded,
                onTap: openProfile,
              ),
              if (_currentSupabaseUser != null)
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 6,
                    backgroundColor: Color(0xFF20B98B),
                  ),
                ),
            ],
          ),
        ),
      ]);
}

class _HeaderCircle extends StatelessWidget {
  const _HeaderCircle({super.key, required this.icon, this.onTap});
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
  const _DarkHeroCard(
      {required this.onScan, required this.onWrite, required this.onUseModel});
  final VoidCallback onScan;
  final VoidCallback onWrite;
  final VoidCallback onUseModel;

  Future<void> _chooseLetterMethod(BuildContext context) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Choisissez une méthode',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            ListTile(
              key: const Key('letter-method-gemini'),
              leading: const Icon(Icons.auto_awesome_rounded),
              title: const Text('Générer avec Gemini'),
              onTap: () => Navigator.pop(context, 'gemini'),
            ),
            ListTile(
              key: const Key('letter-method-model'),
              leading: const Icon(Icons.description_outlined),
              title: const Text('Utiliser un modèle'),
              onTap: () => Navigator.pop(context, 'model'),
            ),
          ]),
        ),
      ),
    );
    if (method == 'gemini') {
      onWrite();
    } else if (method == 'model') {
      onUseModel();
    }
  }

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
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: configured
                            ? const Color(0xFF0B9B69)
                            : const Color(0xFFB66B10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            configured
                                ? Icons.check_circle
                                : Icons.info_outline,
                            color: Colors.white,
                            size: 15),
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
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Simplifiez vos démarches au quotidien',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 24 : 29,
                        height: 1.1,
                        fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Générez, envoyez et suivez vos courriers administratifs simplement.',
                    style: TextStyle(
                        color: const Color(0xFFD7E2F3),
                        fontSize: compact ? 13 : 15,
                        height: 1.4),
                  ),
                  const SizedBox(height: 17),
                  Wrap(spacing: 9, runSpacing: 9, children: [
                    FilledButton.icon(
                      key: const Key('create-letter-v17'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF075CF5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _chooseLetterMethod(context),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Créer une lettre',
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
                      onPressed: onScan,
                      icon: const Icon(Icons.document_scanner_rounded),
                      label: const Text('Scanner un document',
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
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final shortcuts = [
          _DarkShortcut(
              icon: Icons.smart_toy_rounded,
              label: 'Assistant\nadministratif',
              accent: const Color(0xFF2388FF),
              onTap: openProblem),
          _DarkShortcut(
              icon: Icons.folder_rounded,
              label: 'Mes\ndémarches',
              accent: const Color(0xFFFFAD1F),
              badge: activeCount,
              onTap: openProcedures),
          _DarkShortcut(
              icon: Icons.star_rounded,
              label: 'Favoris',
              accent: const Color(0xFF9B55FF),
              onTap: openSearch),
          _DarkShortcut(
              icon: Icons.history_rounded,
              label: 'Historique',
              accent: const Color(0xFFFF557D),
              onTap: openLetters),
        ];
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: shortcuts.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: c.maxWidth >= 700 ? 5 : 2,
            mainAxisExtent: 104,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (_, index) => shortcuts[index],
        );
      });
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
    return Material(
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
                    border: Border.all(color: accent.withValues(alpha: .38)),
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
                ]))));
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 100;
          final valueWidget = Text('$value',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900));
          final labelWidget = Text(label,
              textAlign: compact ? TextAlign.center : TextAlign.start,
              style: const TextStyle(
                  color: Colors.white, fontSize: 10.5, height: 1.18));
          return Container(
            constraints: const BoxConstraints(minHeight: 82),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
            decoration: BoxDecoration(
                color: const Color(0xFF0C203A),
                borderRadius: BorderRadius.circular(15)),
            child: compact
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: accent, size: 24),
                    const SizedBox(height: 4),
                    valueWidget,
                    const SizedBox(height: 3),
                    labelWidget,
                  ])
                : Row(children: [
                    Icon(icon, color: accent, size: 28),
                    const SizedBox(width: 8),
                    valueWidget,
                    const SizedBox(width: 6),
                    Expanded(child: labelWidget),
                  ]),
          );
        },
      );
}

class _SmallDarkAction extends StatelessWidget {
  const _SmallDarkAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: light
            ? const [
                BoxShadow(
                    color: Color(0x180A4A8A),
                    blurRadius: 8,
                    offset: Offset(0, 3))
              ]
            : null,
      ),
      child: OutlinedButton.icon(
        key: Key('dashboard-small-action-$label'),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: light ? Colors.white : Colors.transparent,
          foregroundColor:
              light ? const Color(0xFF0A3A70) : const Color(0xFFD7E5F8),
          side: BorderSide(
              color: light ? const Color(0xFF8EC5FF) : const Color(0xFF24456F)),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, size: 18),
        label: FittedBox(child: Text(label)),
      ),
    );
  }
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
                'Vos documents restent enregistrés localement par défaut. Si vous choisissez la synchronisation, le document PDF ou l’image et votre signature sont envoyés dans votre espace privé Supabase ; votre adresse e-mail y sert à gérer le compte. '
                'Lorsque vous utilisez Gemini, seul le texte nécessaire à l’analyse est envoyé : le PDF ou la photo ne sont pas transmis à Gemini.\n\n'
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
      {super.key,
      required this.documentStore,
      required this.procedureStore,
      this.scannerService = const AndroidMlKitDocumentScannerService()});
  final DocumentStore documentStore;
  final ProcedureStore procedureStore;
  final DocumentScannerService scannerService;
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
  List<String> _sourceScanImagePaths = const [];
  List<String> _renderedScanImagePaths = const [];
  int scannedPages = 0;
  bool ocrAttempted = false;
  int ocrCharacterCount = 0;
  String? ocrError;
  DocumentInsight? _correctedInsight;
  bool _userCorrectedAnalysis = false;

  DocumentInsight get _currentInsight =>
      _correctedInsight ??
      SmartDocumentLocalAnalyzer.analyze(textController.text);

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  Future<void> _renderCapturedImages({bool refreshOcr = true}) async {
    if (_sourceScanImagePaths.isEmpty) return;
    setState(() {
      processing = true;
      processingStep = DocumentProcessingStep.scanning;
      scanError = null;
    });
    try {
      final directory = await getTemporaryDirectory();
      final pdfPages = <Uint8List>[];
      for (final path in _sourceScanImagePaths) {
        pdfPages.add(await File(path).readAsBytes());
      }
      final renderedPaths = List<String>.unmodifiable(_sourceScanImagePaths);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final output = File('${directory.path}/scan_mlkit_$stamp.pdf');
      await output.writeAsBytes(
        await ScannerProcessingService.buildA4Pdf(pdfPages),
        flush: true,
      );
      if (!mounted) return;
      setState(() {
        pdfPath = output.path;
        imagePath = renderedPaths.first;
        _renderedScanImagePaths = renderedPaths;
        scannedPages = renderedPaths.length;
        processingStep = refreshOcr
            ? DocumentProcessingStep.ocr
            : DocumentProcessingStep.completed;
      });
      if (refreshOcr) await _extractTextFromImages(renderedPaths);
      if (mounted) {
        setState(() => processingStep = DocumentProcessingStep.completed);
      }
    } catch (error, stackTrace) {
      debugPrint('Rendu des images ML Kit impossible : $error\n$stackTrace');
      if (mounted) {
        setState(() => scanError =
            'Le document capturé est conservé, mais son rendu n’a pas pu être préparé.');
      }
    } finally {
      if (mounted) setState(() => processing = false);
    }
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

  Future<void> _extractTextFromImages(List<String> paths) async {
    ocrAttempted = true;
    ocrError = null;
    ocrCharacterCount = 0;
    textController.clear();
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final buffer = StringBuffer();
    try {
      for (var index = 0; index < paths.length && index < 10; index++) {
        final file = File(paths[index]);
        if (!await file.exists()) {
          throw FileSystemException('Page scannée introuvable.', paths[index]);
        }
        final recognized =
            await recognizer.processImage(InputImage.fromFilePath(file.path));
        final pageText = recognized.text.trim();
        if (pageText.isNotEmpty) {
          if (buffer.isNotEmpty) {
            buffer.writeln('\n--- Page ${index + 1} ---\n');
          }
          buffer.write(pageText);
        }
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
          if (buffer.isNotEmpty) {
            buffer.writeln('\n--- Page ${pageIndex + 1} ---\n');
          }
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

  // Conservé pour une relance OCR depuis les parcours avancés futurs.
  // ignore: unused_element
  Future<void> _retryOcr() async {
    final path = pdfPath;
    if (path == null && _renderedScanImagePaths.isEmpty) return;
    setState(() {
      processing = true;
      processingStep = DocumentProcessingStep.ocr;
      scanError = null;
      ocrError = null;
    });
    try {
      if (_renderedScanImagePaths.isNotEmpty) {
        await _extractTextFromImages(_renderedScanImagePaths);
      } else {
        await _extractTextFromPdf(path!);
      }
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
    });
    try {
      final result = await widget.scannerService.scan(pageLimit: 10);
      if (result == null) {
        if (mounted) {
          setState(() => processingStep = DocumentProcessingStep.idle);
        }
        return;
      }
      final paths = result.imagePaths.take(10).toList(growable: false);
      if (paths.isEmpty || paths.any((path) => !File(path).existsSync())) {
        throw const FileSystemException('La capture est introuvable.');
      }
      if (!mounted) return;
      setState(() {
        ocrAttempted = false;
        ocrCharacterCount = 0;
        textController.clear();
        _sourceScanImagePaths = paths;
        _renderedScanImagePaths = const [];
      });

      await _renderCapturedImages();

      if (!mounted) return;
      setState(() => processingStep = DocumentProcessingStep.completed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result.partialResult
                ? 'PDF prêt • ${result.pageCount} page${result.pageCount > 1 ? 's récupérées' : ' récupérée'}'
                : 'PDF prêt • ${result.pageCount} page${result.pageCount > 1 ? 's' : ''}')),
      );
    } on DocumentScannerUnavailableException catch (error) {
      if (!mounted) return;
      setState(() => scanError = DocumentScannerUnavailableException.message);
      debugPrint(
          'SCANNER_FLUTTER event=native_failure code=${error.code ?? 'unknown'} type=${error.cause.runtimeType}');
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => scanError = DocumentScannerUnavailableException.message);
      debugPrint('Erreur scanner ML Kit inattendue : $error\n$stackTrace');
    } finally {
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

  Future<void> pickAndRead(ImageSource source) async {
    setState(() => scanError = null);
    try {
      final file = await picker.pickImage(
          source: source, imageQuality: 92, maxWidth: 2200);
      if (file == null) return;
      pdfPath = null;
      _sourceScanImagePaths = const [];
      _renderedScanImagePaths = const [];
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
      if (path == null) {
        throw Exception('Le chemin du fichier est inaccessible.');
      }
      final extension = (selected.extension ?? '').toLowerCase();
      if (extension == 'txt') {
        final content = await File(path).readAsString();
        if (!mounted) return;
        setState(() {
          imagePath = null;
          pdfPath = null;
          _sourceScanImagePaths = const [];
          _renderedScanImagePaths = const [];
          textController.text = content;
        });
      } else if (extension == 'pdf') {
        if (!mounted) return;
        setState(() {
          imagePath = null;
          pdfPath = path;
          _sourceScanImagePaths = const [];
          _renderedScanImagePaths = const [];
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
        _sourceScanImagePaths = const [];
        _renderedScanImagePaths = const [];
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
      final insight = _currentInsight;
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
        detectedDocumentType: insight.documentType,
        detectedAmount: insight.totalAmount,
        detectedDueDate: insight.dueDate,
        detectedReference:
            insight.references.isEmpty ? '' : insight.references.first,
        detectedOrganisation: insight.organisation,
        detectedPriority: insight.priority,
        analysisConfidence: insight.confidence,
        userCorrectedAnalysis: _userCorrectedAnalysis,
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

  Future<void> _correctAnalysis() async {
    final original = _currentInsight;
    var type = original.documentType;
    var priority = original.priority;
    final organisation = TextEditingController(text: original.organisation);
    final amount = TextEditingController(text: original.totalAmount);
    final dueDate = TextEditingController(text: original.dueDate);
    final reference = TextEditingController(
        text: original.references.isEmpty ? '' : original.references.first);
    final category = TextEditingController(text: original.category);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Corriger les informations'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue:
                    SmartDocumentLocalAnalyzer.documentTypes.contains(type)
                        ? type
                        : 'Document inconnu',
                decoration:
                    const InputDecoration(labelText: 'Type du document'),
                items: SmartDocumentLocalAnalyzer.documentTypes
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => type = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: organisation,
                  decoration: const InputDecoration(
                      labelText: 'Fournisseur ou organisme')),
              const SizedBox(height: 10),
              TextField(
                  controller: amount,
                  decoration:
                      const InputDecoration(labelText: 'Montant total')),
              const SizedBox(height: 10),
              TextField(
                  controller: dueDate,
                  decoration: const InputDecoration(labelText: 'Date limite')),
              const SizedBox(height: 10),
              TextField(
                  controller: reference,
                  decoration: const InputDecoration(labelText: 'Référence')),
              const SizedBox(height: 10),
              TextField(
                  controller: category,
                  decoration: const InputDecoration(labelText: 'Catégorie')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: const [
                  'Aucune action urgente détectée',
                  'À vérifier',
                  'Échéance ou réponse proche'
                ].contains(priority)
                    ? priority
                    : 'À vérifier',
                decoration: const InputDecoration(labelText: 'Priorité'),
                items: const [
                  'Aucune action urgente détectée',
                  'À vérifier',
                  'Échéance ou réponse proche'
                ]
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => priority = value);
                },
              ),
            ]),
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
    if (saved == true && mounted) {
      setState(() {
        _userCorrectedAnalysis = true;
        _correctedInsight = DocumentInsight(
          category: category.text.trim().isEmpty ? type : category.text.trim(),
          summary: original.summary,
          organisation: organisation.text.trim().isEmpty
              ? 'Non identifiée'
              : organisation.text.trim(),
          dates: dueDate.text.trim().isEmpty ? const [] : [dueDate.text.trim()],
          amounts: amount.text.trim().isEmpty ? const [] : [amount.text.trim()],
          references: reference.text.trim().isEmpty
              ? const []
              : [reference.text.trim()],
          actions: original.actions,
          priority: priority,
          documentsToPrepare: original.documentsToPrepare,
          warnings: original.warnings,
          documentType: type,
          supplier: organisation.text.trim(),
          dueDate: dueDate.text.trim(),
          amountDetails: amount.text.trim().isEmpty
              ? const []
              : [
                  DocumentAmountItem(
                      label: 'Montant total à payer',
                      amount: amount.text.trim())
                ],
          confidence: original.confidence,
          requestedDocuments: original.requestedDocuments,
          suggestedAction: original.suggestedAction,
        );
      });
    }
    organisation.dispose();
    amount.dispose();
    dueDate.dispose();
    reference.dispose();
    category.dispose();
  }

  // Conservé pour la logique structurée V17.1, désormais masquée par défaut.
  // ignore: unused_element
  Widget _smartCard(BuildContext context) {
    final insight = _currentInsight;
    Color color = switch (insight.priority) {
      'Échéance ou réponse proche' => Colors.red,
      'À vérifier' => Colors.orange,
      _ => Colors.green,
    };
    Widget line(String label, String value) => value.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 9),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800))
            ]),
          );
    return Card(
      key: const Key('scanner-smart-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome, color: color),
            const SizedBox(width: 9),
            Expanded(
                child: Text(insight.documentType,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)))
          ]),
          line(
              insight.isInvoice ? 'Fournisseur' : 'Organisme',
              insight.organisation == 'Non identifiée'
                  ? 'Non détecté'
                  : insight.organisation),
          line('Montant à payer', insight.totalAmount),
          line('À payer avant', insight.dueDate),
          line('Référence',
              insight.references.isEmpty ? '' : insight.references.first),
          const SizedBox(height: 12),
          Chip(
              avatar: CircleAvatar(backgroundColor: color, radius: 6),
              label: Text(insight.priority)),
          const Text(
              'Vérifiez les informations importantes dans le document original.'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Tooltip(
              message: 'Corriger',
              child: OutlinedButton.icon(
                  key: const Key('correct-analysis'),
                  onPressed: _correctAnalysis,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Corriger')),
            ),
            Tooltip(
              message: 'Améliorer avec Gemini',
              child: FilledButton.tonalIcon(
                  key: const Key('scanner-gemini-improve'),
                  onPressed: prepareReply,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Améliorer avec Gemini')),
            ),
            PopupMenuButton<String>(
              key: const Key('scanner-smart-more-menu'),
              tooltip: 'Plus d’actions',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (action) {
                if (action == 'Contester cette facture') {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LetterFormScreen(
                      settings: appSettings,
                      template: LetterTemplate.energy,
                      model: ProfessionalLetterModel(
                        title: 'Contestation de facture',
                        subject: 'Contestation de la facture',
                        body:
                            'Je conteste cette facture et demande sa vérification.',
                      ),
                      initialRecipient: insight.organisation == 'Non identifiée'
                          ? ''
                          : insight.organisation,
                      initialDetails:
                          'Montant détecté : ${insight.totalAmount.isEmpty ? '[À COMPLÉTER]' : insight.totalAmount}\n\nContexte OCR :\n${textController.text}',
                    ),
                  ));
                } else if (action == 'Ajouter un rappel' ||
                    action == 'Poser une question' ||
                    action == 'Rédiger une réponse') {
                  prepareReply();
                } else if (action == 'Sauvegarder' ||
                    action == 'Enregistrer dans Mes documents') {
                  _archiveDocument();
                } else if (action == 'Partager') {
                  if (pdfPath != null) _sharePdf();
                } else if (action == 'Voir le texte complet') {
                  Scrollable.ensureVisible(
                    context,
                    duration: const Duration(milliseconds: 250),
                  );
                }
              },
              itemBuilder: (_) => insight.actions
                  .map((action) => PopupMenuItem(
                        value: action,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(switch (action) {
                            'Ajouter un rappel' => Icons.alarm_add_outlined,
                            'Contester cette facture' => Icons.edit_note,
                            'Poser une question' => Icons.help_outline,
                            'Sauvegarder' ||
                            'Enregistrer dans Mes documents' =>
                              Icons.save_outlined,
                            'Partager' => Icons.share_outlined,
                            'Voir le texte complet' =>
                              Icons.text_snippet_outlined,
                            'Sauvegarder dans le cloud' =>
                              Icons.cloud_upload_outlined,
                            _ => Icons.arrow_forward,
                          }),
                          title: Text(action),
                        ),
                      ))
                  .toList(),
            ),
          ]),
        ]),
      ),
    );
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
      const SizedBox(height: 10),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.crop_free_rounded),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cadrez toute la feuille. Après la capture, ajustez les quatre poignées si nécessaire, choisissez le filtre puis validez dans le scanner.',
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: processing ? null : scanA4,
            icon: const Icon(Icons.document_scanner),
            label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Scanner')),
          )),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: OutlinedButton.icon(
                onPressed:
                    processing ? null : () => pickAndRead(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Photo'))),
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
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('scanner-fallback-camera'),
                    onPressed: () => pickAndRead(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Prendre une photo'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('scanner-fallback-import'),
                    onPressed: importFile,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Importer un document'),
                  ),
                ],
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
                    Row(children: [
                      Tooltip(
                        message: 'Ouvrir',
                        child: FilledButton.icon(
                            key: const Key('scanner-pdf-open'),
                            onPressed: _openPdf,
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('Ouvrir')),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        key: const Key('scanner-pdf-more-menu'),
                        tooltip: 'Plus d’actions',
                        icon: const Icon(Icons.more_horiz_rounded),
                        onSelected: (value) {
                          if (value == 'archive') {
                            _archiveDocument();
                          } else if (value == 'share') {
                            _sharePdf();
                          } else if (value == 'print') {
                            _printPdf();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'archive',
                              child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.folder_copy_outlined),
                                  title: Text('Ajouter à Mes documents'))),
                          PopupMenuItem(
                              value: 'share',
                              child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.share_outlined),
                                  title: Text('Transmettre'))),
                          PopupMenuItem(
                              value: 'print',
                              child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.print_outlined),
                                  title: Text('Imprimer'))),
                        ],
                      ),
                    ]),
                  ])),
        ),
      if (!processing && imagePath != null) ...[
        ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(File(imagePath!),
                height: 220, width: double.infinity, fit: BoxFit.contain)),
        const SizedBox(height: 18),
      ],
      if (textController.text.trim().isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<String>(
            key: const Key('scanner-advanced-analysis'),
            tooltip: 'Analyse avancée',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'ocr') {
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Texte OCR'),
                    content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                          child: SelectableText(textController.text)),
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Fermer'))
                    ],
                  ),
                );
              } else if (value == 'analysis') {
                prepareReply();
              } else if (value == 'correct') {
                _correctAnalysis();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                enabled: false,
                child: Text('Analyse avancée',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              PopupMenuItem(
                value: 'ocr',
                child: ListTile(
                    dense: true,
                    leading: Icon(Icons.text_snippet_outlined),
                    title: Text('Voir le texte OCR')),
              ),
              PopupMenuItem(
                value: 'analysis',
                child: ListTile(
                    dense: true,
                    leading: Icon(Icons.auto_awesome_outlined),
                    title: Text('Analyse Gemini')),
              ),
              PopupMenuItem(
                value: 'correct',
                child: ListTile(
                    dense: true,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Corriger les informations')),
              ),
            ],
          ),
        ),
      const SizedBox(height: 18),
      const PrivacyCard(),
    ]));
  }
}

// Conservé pour les diagnostics de traitement avancés.
// ignore: unused_element
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

/// Aperçu interne : aucune impression n'est lancée pendant l'ouverture.
class InternalDocumentPreviewScreen extends StatelessWidget {
  const InternalDocumentPreviewScreen({
    super.key,
    required this.bytes,
    required this.title,
    required this.isImage,
  });

  final Uint8List bytes;
  final String title;
  final bool isImage;

  Future<void> _share() async {
    final dir = await getTemporaryDirectory();
    final extension = isImage ? 'jpg' : 'pdf';
    final file = File('${dir.path}/adminfacile_preview.$extension');
    await file.writeAsBytes(bytes, flush: true);
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: title),
      );
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _download() async {
    await FilePicker.platform.saveFile(
      dialogTitle: 'Télécharger le document',
      fileName: isImage ? 'document.jpg' : 'document.pdf',
      type: FileType.custom,
      allowedExtensions: [isImage ? 'jpg' : 'pdf'],
      bytes: bytes,
    );
  }

  Future<void> _print() async {
    if (!isImage) {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: title);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const Key('internal-document-preview'),
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
                key: const Key('preview-share'),
                tooltip: 'Partager',
                onPressed: _share,
                icon: const Icon(Icons.share_outlined)),
            IconButton(
                key: const Key('preview-download'),
                tooltip: 'Télécharger',
                onPressed: _download,
                icon: const Icon(Icons.download_outlined)),
            if (!isImage)
              IconButton(
                  key: const Key('preview-print'),
                  tooltip: 'Imprimer',
                  onPressed: _print,
                  icon: const Icon(Icons.print_outlined)),
          ],
        ),
        body: isImage
            ? InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
              )
            : PdfPreview(
                key: const Key('internal-pdf-preview'),
                build: (_) async => bytes,
                allowPrinting: false,
                allowSharing: false,
                canChangeOrientation: false,
                canChangePageFormat: false,
                useActions: false,
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
    this.amountDetails = const [],
    this.suggestions = const [],
    this.confidence = 0.0,
    this.requestedDocuments = const [],
    this.suggestedAction = '',
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
  final List<DocumentAmountItem> amountDetails;
  final List<String> suggestions;
  final double confidence;
  final List<String> requestedDocuments;
  final String suggestedAction;

  bool get urgent => priority == 'Urgent';
  bool get isInvoice => documentType.toLowerCase().contains('facture');
  String get totalAmount {
    for (final item in amountDetails) {
      if (item.label == 'Montant total à payer') return item.amount;
    }
    return '';
  }
}

const String geminiUnavailableMessage =
    'Assistant IA momentanément indisponible.';

/// Transport IA commun.
///
/// En production, [GEMINI_PROXY_URL] doit désigner un backend HTTPS qui garde
/// la clé Google côté serveur. [GEMINI_API_KEY] reste accepté uniquement pour
/// les builds de bêta interne : une dart-define est compilée dans le binaire et
/// ne constitue donc pas un secret.
class GeminiTransport {
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _proxyUrl = String.fromEnvironment('GEMINI_PROXY_URL');
  static const String _model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );
  static const int _timeoutSeconds = int.fromEnvironment(
    'GEMINI_TIMEOUT_SECONDS',
    defaultValue: 40,
  );

  @visibleForTesting
  static String? testProxyUrl;
  @visibleForTesting
  static Duration? testTimeout;
  @visibleForTesting
  static Future<http.Response> Function(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  })? testPost;

  static String get _effectiveProxyUrl => testProxyUrl ?? _proxyUrl;
  static bool get usesProxy => _effectiveProxyUrl.trim().isNotEmpty;
  static bool get usesEmbeddedKey => !usesProxy && _apiKey.trim().isNotEmpty;
  static bool get isConfigured => usesProxy || usesEmbeddedKey;
  static String get configurationMode => usesProxy
      ? 'proxy'
      : usesEmbeddedKey
          ? 'direct-beta'
          : 'disabled';

  static Future<Map<String, dynamic>> request(
    String prompt,
    Map<String, Object> generationConfig,
  ) async {
    if (!isConfigured) throw const GeminiConfigurationException();

    final Uri uri;
    final Map<String, String> headers = {'Content-Type': 'application/json'};
    final Map<String, Object> body;
    if (usesProxy) {
      uri = Uri.parse(_effectiveProxyUrl.trim());
      if (uri.scheme != 'https' &&
          !(kDebugMode &&
              (uri.host == 'localhost' || uri.host == '127.0.0.1'))) {
        throw const GeminiConfigurationException();
      }
      final token = _supabaseReady
          ? Supabase.instance.client.auth.currentSession?.accessToken
          : null;
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      body = {
        'model': _model,
        'prompt': prompt,
        'generationConfig': generationConfig,
      };
    } else {
      uri = Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/$_model:generateContent',
        {'key': _apiKey},
      );
      body = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': generationConfig,
      };
    }

    try {
      final post = testPost ?? http.post;
      final response = await post(uri, headers: headers, body: jsonEncode(body))
          .timeout(
              testTimeout ?? Duration(seconds: _timeoutSeconds.clamp(5, 120)));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const GeminiApiException();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const GeminiApiException();
      return Map<String, dynamic>.from(decoded);
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } on GeminiApiException {
      rethrow;
    } on FormatException {
      throw const GeminiApiException();
    } catch (_) {
      throw const GeminiApiException();
    }
  }
}

class GeminiDocumentAnalyzer {
  static bool get isConfigured => GeminiTransport.isConfigured;

  static Future<DocumentInsight> analyze(String sourceText) async {
    if (!isConfigured) {
      throw const GeminiConfigurationException();
    }

    final prompt = '''
Tu es un assistant administratif prudent. Analyse uniquement le document fourni.
Réponds en français, en JSON valide uniquement, sans markdown.
N'invente aucune date, aucun montant, aucune référence, aucune obligation et aucun droit.
Quand une information n'est pas présente, utilise une chaîne vide ou une liste vide.
Pour une facture, conserve uniquement le montant total réellement dû. Ignore capital social, SIREN/SIRET, mentions légales, HT intermédiaire et TVA seule.
Le résumé fait deux phrases maximum. confidence est un nombre entre 0 et 1.

Retourne cet objet JSON :
{
  "documentType": "",
  "organisation": "",
  "amount": "",
  "dueDate": "",
  "reference": "",
  "summary": "",
  "requestedDocuments": [],
  "suggestedAction": "",
  "confidence": 0.0
}

COURRIER :
${sourceText.trim()}
''';

    final decoded = await GeminiTransport.request(prompt, const {
      'temperature': 0.1,
      'responseMimeType': 'application/json',
      'maxOutputTokens': 2048,
    });
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

    final amount = value('amount');
    final dueDate = value('dueDate');
    final reference = value('reference');
    final rawConfidence = data['confidence'];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble().clamp(0.0, 1.0)
        : double.tryParse('$rawConfidence')?.clamp(0.0, 1.0) ?? 0.0;
    final requested = strings('requestedDocuments');
    final documentType = value('documentType', fallback: 'Document inconnu');
    final organisation = value('organisation', fallback: 'Non identifiée');
    return DocumentInsight(
      category: documentType,
      summary: value(
        'summary',
        fallback: 'Gemini n’a pas pu produire un résumé suffisamment précis.',
      ),
      organisation: organisation,
      dates: dueDate.isEmpty ? const [] : [dueDate],
      amounts: amount.isEmpty ? const [] : [amount],
      references: reference.isEmpty ? const [] : [reference],
      actions: const ['Vérifier le document original avant toute action.'],
      priority: value('suggestedAction', fallback: 'À vérifier'),
      documentsToPrepare: requested,
      requestedDocuments: requested,
      warnings: const [
        'Vérifiez les informations importantes dans le document original.'
      ],
      documentType: documentType,
      supplier: organisation == 'Non identifiée' ? '' : organisation,
      dueDate: dueDate,
      amountDetails: amount.isEmpty
          ? const []
          : [
              DocumentAmountItem(label: 'Montant total à payer', amount: amount)
            ],
      confidence: confidence,
      suggestedAction: value('suggestedAction'),
    );
  }
}

class GeminiDocumentChat {
  static Future<String> ask(
      {required String sourceText, required String question}) async {
    if (!GeminiDocumentAnalyzer.isConfigured) {
      throw const GeminiConfigurationException();
    }
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
    final decoded = await GeminiTransport.request(
      prompt,
      const {'temperature': 0.2, 'maxOutputTokens': 700},
    );
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
              'text': geminiUnavailableMessage,
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
  static bool get isConfigured => GeminiTransport.isConfigured;

  static Future<Map<String, dynamic>> _requestJson(String prompt) async {
    if (!isConfigured) {
      throw const GeminiConfigurationException();
    }
    final decoded = await GeminiTransport.request(prompt, const {
      'temperature': 0.2,
      'responseMimeType': 'application/json',
      'maxOutputTokens': 2500,
    });
    final candidates = decoded['candidates'] as List?;
    final parts =
        ((candidates?.first as Map?)?['content'] as Map?)?['parts'] as List?;
    final text =
        parts?.map((e) => (e as Map?)?['text']?.toString() ?? '').join().trim();
    if (text == null || text.isEmpty) {
      throw const GeminiApiException('Réponse Gemini vide.');
    }
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
    if (body.isEmpty) {
      throw const GeminiApiException('Gemini n’a pas généré la lettre.');
    }
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
    if (result.isEmpty) {
      throw const GeminiApiException('Gemini n’a pas amélioré la lettre.');
    }
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
    } catch (_) {
      if (mounted) setState(() => error = geminiUnavailableMessage);
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

enum GeminiLetterTypeV156 {
  complaint('Réclamation'),
  cancellation('Résiliation'),
  dispute('Contestation'),
  documentRequest('Demande de document'),
  organisationReply('Réponse à un organisme'),
  reminder('Relance'),
  freeLetter('Lettre libre');

  const GeminiLetterTypeV156(this.label);
  final String label;
}

enum GeminiLetterToneV156 {
  courteous('Courtois'),
  professional('Professionnel'),
  firm('Ferme'),
  verySimple('Très simple');

  const GeminiLetterToneV156(this.label);
  final String label;
}

enum LetterFormatV1561 {
  official('Courrier officiel'),
  email('E-mail'),
  registered('Lettre recommandée'),
  formalNotice('Mise en demeure');

  const LetterFormatV1561(this.label);
  final String label;
}

String buildFormattedLetterV1561({
  required LetterFormatV1561 format,
  required String recipient,
  required String subject,
  required String body,
  required AppSettings settings,
}) {
  String completed(String value, String placeholder) =>
      value.trim().isEmpty ? '[$placeholder À COMPLÉTER]' : value.trim();

  final fullName = capitalizeProfileName(
      '${settings.firstName} ${settings.lastName}'.trim());
  final senderName = completed(fullName, 'NOM');
  final senderAddress = completed(settings.address, 'ADRESSE');
  final senderLocality = '${settings.postalCode} ${settings.city}'.trim();
  final senderCity = completed(senderLocality, 'VILLE');
  final safeRecipient = completed(recipient, 'DESTINATAIRE');
  final safeSubject = completed(subject, 'OBJET');
  final safeBody = completed(body, 'MESSAGE');
  final signature = completed(fullName, 'NOM ET SIGNATURE');

  if (format == LetterFormatV1561.email) {
    return '''Destinataire : $safeRecipient
Objet : $safeSubject

$safeBody

$signature''';
  }

  final heading = switch (format) {
    LetterFormatV1561.registered =>
      'Lettre recommandée avec accusé de réception\n\n',
    LetterFormatV1561.formalNotice => 'MISE EN DEMEURE\n\n',
    _ => '',
  };
  return '''$senderName
$senderAddress
$senderCity

$safeRecipient
[ADRESSE DU DESTINATAIRE À COMPLÉTER]

[VILLE ET DATE À COMPLÉTER]

${heading}Objet : $safeSubject

Madame, Monsieur,

$safeBody

Veuillez agréer, Madame, Monsieur, l'expression de mes salutations distinguées.

$signature''';
}

class OfficialLetterSheet extends StatelessWidget {
  const OfficialLetterSheet({
    super.key,
    required this.child,
    this.email = false,
  });

  final Widget child;
  final bool email;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          key: const Key('official-letter-sheet'),
          width: double.infinity,
          constraints: BoxConstraints(maxWidth: email ? 760 : 720),
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width < 500 ? 22 : 48,
            vertical: email ? 28 : 44,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: const InputDecorationTheme(
                filled: false,
                border: InputBorder.none,
              ),
              textSelectionTheme: const TextSelectionThemeData(
                cursorColor: Color(0xFF136DF2),
                selectionColor: Color(0x663B82F6),
                selectionHandleColor: Color(0xFF136DF2),
              ),
            ),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.black),
              child: child,
            ),
          ),
        ),
      );
}

class OfficialSignatureBlock extends StatelessWidget {
  const OfficialSignatureBlock({
    super.key,
    required this.signed,
    required this.signaturePath,
    required this.senderName,
  });

  final bool signed;
  final String signaturePath;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    if (!signed) return const SizedBox.shrink();
    final file = File(signaturePath);
    final hasImage = signaturePath.trim().isNotEmpty && file.existsSync();
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Signature de l’expéditeur',
              style: TextStyle(color: Colors.black87, fontSize: 13)),
          const SizedBox(height: 5),
          Container(
            key: const Key('official-signature-frame'),
            width: 150,
            height: 75,
            padding: const EdgeInsets.all(8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade400, width: .7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: hasImage
                ? Image.file(file,
                    key: const Key('official-signature-image'),
                    width: 95,
                    height: 45,
                    fit: BoxFit.contain)
                : const Text('Signature à apposer',
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
          ),
          const SizedBox(height: 4),
          if (senderName.trim().isNotEmpty)
            Text(capitalizeProfileName(senderName),
                style: const TextStyle(color: Colors.black, fontSize: 13)),
        ],
      ),
    );
  }
}

Future<Uint8List> buildSignedLetterPdf({
  required String text,
  required String subject,
  Uint8List? signatureBytes,
  String senderName = '',
}) async {
  return LetterSignatureService.buildLetterPdf(
    text: text,
    subject: subject,
    signed: signatureBytes != null,
    signatureBytes: signatureBytes,
    senderName: senderName,
  );
}

bool shouldInsertSignature(AppSettings? settings) =>
    settings != null && settings.autoInsertSignature && settings.hasSignature;

class LetterSignatureOption extends StatelessWidget {
  const LetterSignatureOption({
    super.key,
    required this.settings,
    required this.value,
    required this.onChanged,
  });
  final AppSettings settings;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        key: const Key('letter-signature-option'),
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        title: const Text('Ajouter ma signature à cette lettre'),
        subtitle: Text(settings.hasSignature
            ? 'La signature apparaîtra au-dessus du nom de l’expéditeur.'
            : 'Aucune signature enregistrée dans le Profil.'),
        secondary: settings.hasSignature
            ? SizedBox(
                width: 64,
                child: Image.file(File(settings.signaturePath),
                    height: 36, fit: BoxFit.contain))
            : const Icon(Icons.draw_outlined),
      );
}

GeminiGeneratedLetter buildLocalGeminiLetter({
  required String recipient,
  required String subject,
  required String situation,
  required String desiredResult,
  required String importantInformation,
  required GeminiLetterTypeV156 type,
  required GeminiLetterToneV156 tone,
}) {
  String value(String text, String marker) =>
      text.trim().isEmpty ? '[$marker À COMPLÉTER]' : text.trim();
  final safeRecipient = value(recipient, 'DESTINATAIRE');
  final safeSubject = value(subject, 'OBJET');
  final safeSituation = value(situation, 'SITUATION');
  final safeResult = value(desiredResult, 'RÉSULTAT SOUHAITÉ');
  final safeDetails = value(importantInformation, 'INFORMATIONS IMPORTANTES');
  final opening = switch (tone) {
    GeminiLetterToneV156.courteous =>
      'Je vous prie de bien vouloir examiner ma demande.',
    GeminiLetterToneV156.professional =>
      'Je vous adresse ce courrier afin de formaliser ma demande.',
    GeminiLetterToneV156.firm =>
      'Je vous demande de traiter cette demande dans les meilleurs délais.',
    GeminiLetterToneV156.verySimple => 'Je vous écris au sujet de ma demande.',
  };
  return GeminiGeneratedLetter(
    title: '${type.label} – $safeRecipient',
    subject: safeSubject,
    body: '''$opening

Ma situation : $safeSituation

Résultat souhaité : $safeResult

Informations importantes : $safeDetails

Je vous remercie de me confirmer les suites données à ce courrier.''',
  );
}

class GeminiLetterV156Service {
  static Future<GeminiGeneratedLetter> generate({
    required String recipient,
    required String subject,
    required String situation,
    required String desiredResult,
    required String importantInformation,
    required GeminiLetterTypeV156 type,
    required GeminiLetterToneV156 tone,
    required LetterFormatV1561 format,
  }) async {
    if (!GeminiLetterWriter.isConfigured) {
      return buildLocalGeminiLetter(
        recipient: recipient,
        subject: subject,
        situation: situation,
        desiredResult: desiredResult,
        importantInformation: importantInformation,
        type: type,
        tone: tone,
      );
    }
    final data = await GeminiLetterWriter._requestJson('''
Rédige le corps d'une lettre administrative française claire, courte et professionnelle.
Retourne uniquement ce JSON : {"titre":"","objet":"","corps":""}.
N'ajoute aucune explication autour de la lettre.
Dans "corps", n'ajoute ni coordonnées, ni objet, ni formule d'appel, ni formule de politesse, ni signature : l'application les compose selon le format choisi.
N'invente jamais de date, montant, numéro de contrat, nom, adresse, fait ou référence juridique.
Pour toute information nécessaire mais absente, insère un repère explicite entre crochets, par exemple [NUMÉRO DE CONTRAT À COMPLÉTER].
Type : ${type.label}
Format : ${format.label}
Ton : ${tone.label}
Destinataire : ${recipient.trim()}
Objet : ${subject.trim()}
Situation : ${situation.trim()}
Résultat souhaité : ${desiredResult.trim()}
Informations importantes : ${importantInformation.trim()}
''');
    String field(String key) => data[key]?.toString().trim() ?? '';
    if (field('corps').isEmpty) {
      throw const GeminiApiException('Réponse Gemini vide.');
    }
    return GeminiGeneratedLetter(
      title: field('titre').isEmpty ? type.label : field('titre'),
      subject: field('objet').isEmpty ? '[OBJET À COMPLÉTER]' : field('objet'),
      body: field('corps'),
    );
  }
}

class GeminiLetterWriterV156Screen extends StatefulWidget {
  const GeminiLetterWriterV156Screen({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<GeminiLetterWriterV156Screen> createState() =>
      _GeminiLetterWriterV156ScreenState();
}

class _GeminiLetterWriterV156ScreenState
    extends State<GeminiLetterWriterV156Screen> {
  final recipient = TextEditingController();
  final subject = TextEditingController();
  final situation = TextEditingController();
  final result = TextEditingController();
  final information = TextEditingController();
  final letter = TextEditingController();
  GeminiLetterTypeV156 type = GeminiLetterTypeV156.complaint;
  GeminiLetterToneV156 tone = GeminiLetterToneV156.professional;
  LetterFormatV1561 format = LetterFormatV1561.official;
  String status = 'Prêt';
  String? error;
  bool loading = false;
  bool saved = false;
  bool addSignature = false;

  @override
  void initState() {
    super.initState();
    addSignature =
        widget.settings.hasSignature && widget.settings.autoInsertSignature;
  }

  @override
  void dispose() {
    for (final controller in [
      recipient,
      subject,
      situation,
      result,
      information,
      letter
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _generate() async {
    if (situation.text.trim().isEmpty && result.text.trim().isEmpty) {
      setState(
          () => error = 'Décrivez votre situation ou le résultat souhaité.');
      return;
    }
    setState(() {
      loading = true;
      status = 'Rédaction avec Gemini';
      error = null;
      saved = false;
    });
    try {
      final generated = await GeminiLetterV156Service.generate(
        recipient: recipient.text,
        subject: subject.text,
        situation: situation.text,
        desiredResult: result.text,
        importantInformation: information.text,
        type: type,
        tone: tone,
        format: format,
      );
      if (!mounted) return;
      setState(() {
        subject.text = normalizeFrenchTypography(generated.subject);
        letter.text = normalizeFrenchTypography(buildFormattedLetterV1561(
          format: format,
          recipient: recipient.text,
          subject: generated.subject,
          body: generated.body,
          settings: widget.settings,
        ));
        status = 'Lettre prête';
      });
    } catch (_) {
      if (!mounted) return;
      final local = buildLocalGeminiLetter(
        recipient: recipient.text,
        subject: subject.text,
        situation: situation.text,
        desiredResult: result.text,
        importantInformation: information.text,
        type: type,
        tone: tone,
      );
      setState(() {
        subject.text = normalizeFrenchTypography(local.subject);
        letter.text = normalizeFrenchTypography(buildFormattedLetterV1561(
          format: format,
          recipient: recipient.text,
          subject: local.subject,
          body: local.body,
          settings: widget.settings,
        ));
        status = 'Erreur de connexion';
        error = '$geminiUnavailableMessage Une lettre locale a été préparée.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _transform(String action) async {
    if (letter.text.trim().isEmpty || loading) return;
    setState(() {
      loading = true;
      status = 'Rédaction avec Gemini';
    });
    try {
      final improved = await GeminiLetterWriter.improve(
        letter: letter.text,
        tone: action,
      );
      if (!mounted) return;
      setState(() {
        letter.text = normalizeFrenchTypography(improved);
        status = 'Lettre prête';
        saved = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          status = 'Erreur de connexion';
          error = '$geminiUnavailableMessage '
              'La lettre reste modifiable manuellement.';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveProcedure() async {
    if (letter.text.trim().isEmpty || saved) return;
    final now = DateTime.now();
    await appProcedureStore.add(AdministrativeProcedure(
      id: 'gemini_${now.microsecondsSinceEpoch}',
      title: subject.text.trim().isEmpty ? type.label : subject.text.trim(),
      organisation: recipient.text.trim().isEmpty
          ? 'Non renseigné'
          : recipient.text.trim(),
      category: type.label,
      letter: letter.text.trim(),
      createdAt: now,
      updatedAt: now,
      notes: 'Lettre enregistrée localement par l’assistant V15.6.',
      signed: addSignature,
    ));
    if (!mounted) return;
    setState(() => saved = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Lettre enregistrée dans Mes démarches.'),
    ));
  }

  Future<Uint8List> _pdf() async {
    final signatureBytes = addSignature && widget.settings.hasSignature
        ? await File(widget.settings.signaturePath).readAsBytes()
        : null;
    return LetterSignatureService.buildLetterPdf(
      text: letter.text,
      subject:
          subject.text.trim().isEmpty ? '[OBJET À COMPLÉTER]' : subject.text,
      signed: addSignature,
      signatureBytes: signatureBytes,
      senderName:
          '${widget.settings.firstName} ${widget.settings.lastName}'.trim(),
    );
  }

  Future<void> _exportPdf() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Exporter la lettre en PDF',
      fileName: 'lettre_adminfacile.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: await _pdf(),
    );
    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lettre exportée en PDF.')),
      );
    }
  }

  Future<void> _share() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/lettre_adminfacile.pdf');
    await file.writeAsBytes(await _pdf(), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: subject.text.trim().isEmpty ? type.label : subject.text.trim(),
    ));
  }

  Widget _field(TextEditingController controller, String label,
      {int lines = 1}) {
    return TextField(
      controller: controller,
      minLines: lines,
      maxLines: lines == 1 ? 3 : lines + 4,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lines > 1,
        suffixIcon: VoiceInputButton(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rédiger avec Gemini')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: Text(status, key: const Key('gemini-status')),
              subtitle: Text(GeminiLetterWriter.isConfigured
                  ? 'Gemini disponible'
                  : 'Mode local disponible'),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<GeminiLetterTypeV156>(
            key: const Key('letter-type'),
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Type de courrier'),
            items: GeminiLetterTypeV156.values
                .map((item) => DropdownMenuItem(
                      value: item,
                      child: Text(item.label),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => type = value);
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<LetterFormatV1561>(
            key: const Key('letter-format'),
            initialValue: format,
            decoration: const InputDecoration(labelText: 'Format'),
            items: LetterFormatV1561.values
                .map((item) => DropdownMenuItem(
                      value: item,
                      child: Text(item.label),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => format = value);
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<GeminiLetterToneV156>(
            key: const Key('letter-tone'),
            initialValue: tone,
            decoration: const InputDecoration(labelText: 'Ton'),
            items: GeminiLetterToneV156.values
                .map((item) => DropdownMenuItem(
                      value: item,
                      child: Text(item.label),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => tone = value);
            },
          ),
          const SizedBox(height: 14),
          _field(recipient, 'Destinataire ou organisme'),
          const SizedBox(height: 14),
          _field(subject, 'Objet'),
          const SizedBox(height: 14),
          _field(situation, 'Situation de l’utilisateur', lines: 3),
          const SizedBox(height: 14),
          _field(result, 'Résultat souhaité', lines: 2),
          const SizedBox(height: 14),
          _field(information, 'Informations importantes à intégrer', lines: 3),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 8),
          LetterSignatureOption(
            key: const Key('gemini-signature-option'),
            settings: widget.settings,
            value: addSignature,
            onChanged: (value) => setState(() => addSignature = value),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('generate-letter-v156'),
            onPressed: loading ? null : _generate,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: const Text('Générer la lettre'),
          ),
          if (letter.text.trim().isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Lettre générée (modifiable)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            OfficialLetterSheet(
              email: format == LetterFormatV1561.email,
              child: Column(children: [
                TextField(
                  key: const Key('generated-letter'),
                  controller: letter,
                  minLines: format == LetterFormatV1561.email ? 10 : 22,
                  maxLines: null,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    height: 1.55,
                  ),
                  cursorColor: Color(0xFF136DF2),
                  onChanged: (_) {
                    if (saved) setState(() => saved = false);
                  },
                  decoration: InputDecoration(
                    hintText: 'Votre courrier',
                    hintStyle: const TextStyle(color: Colors.black54),
                    suffixIcon: VoiceInputButton(controller: letter),
                  ),
                ),
                if (addSignature) ...[
                  const SizedBox(height: 12),
                  OfficialSignatureBlock(
                    key: const Key('letter-signature-preview'),
                    signed: addSignature,
                    signaturePath: widget.settings.signaturePath,
                    senderName:
                        '${widget.settings.firstName} ${widget.settings.lastName}',
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final action in const [
                'Corriger',
                'Raccourcir',
                'Rendre plus ferme',
                'Rendre plus courtois',
                'Simplifier',
              ])
                ActionChip(
                  label: Text(action),
                  onPressed: loading ? null : () => _transform(action),
                ),
              ActionChip(
                label: const Text('Régénérer'),
                onPressed: loading ? null : _generate,
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('save-procedure'),
              onPressed: saved ? null : _saveProcedure,
              icon: const Icon(Icons.folder_copy_outlined),
              label: Text(saved
                  ? 'Enregistrée dans Mes démarches'
                  : 'Enregistrer dans Mes démarches'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Exporter en PDF'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Transmettre'),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          Text(
            'La lettre reste locale et n’est jamais envoyée automatiquement vers Supabase.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      );
}

class GeminiConfigurationException implements Exception {
  const GeminiConfigurationException([this.message = geminiUnavailableMessage]);
  final String message;
  @override
  String toString() => message;
}

class GeminiApiException implements Exception {
  const GeminiApiException([this.message = geminiUnavailableMessage]);
  final String message;
  @override
  String toString() => message;
}

class SmartDocumentLocalAnalyzer {
  static const documentTypes = <String>[
    'Facture de gaz',
    'Facture d’électricité',
    'Facture d’eau',
    'Facture téléphone',
    'Facture Internet',
    'Facture d’assurance',
    'Facture générique',
    'Courrier CAF',
    'Courrier CPAM',
    'Courrier des impôts',
    'Courrier bancaire',
    'Courrier d’assurance',
    'Courrier employeur',
    'Contrat',
    'Avis ou notification',
    'Document inconnu',
  ];

  static DocumentInsight analyze(String rawText, {DateTime? now}) {
    final text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = text.toLowerCase();
    bool any(Iterable<String> words) => words.any(lower.contains);

    var type = 'Document inconnu';
    var organisation = 'Non identifiée';
    var confidence = 0.25;
    if (any(['primagaz', 'propane']) ||
        (lower.contains('facture') && lower.contains('gaz'))) {
      type = 'Facture de gaz';
      organisation = lower.contains('primagaz') ? 'PRIMAGAZ' : 'Non identifiée';
      confidence = .95;
    } else if (any(['edf', 'électricité', 'electricite', ' kwh'])) {
      type = 'Facture d’électricité';
      organisation = lower.contains('edf') ? 'EDF' : 'Non identifiée';
      confidence = .93;
    } else if (lower.contains('facture') && any(['eau', 'm³', 'm3'])) {
      type = 'Facture d’eau';
      confidence = .82;
    } else if (any(['orange', 'sfr', 'bouygues telecom', 'free mobile'])) {
      organisation = lower.contains('orange')
          ? 'Orange'
          : lower.contains('sfr')
              ? 'SFR'
              : lower.contains('bouygues')
                  ? 'Bouygues Telecom'
                  : 'Free Mobile';
      type = any(['internet', 'fibre', 'livebox', 'box'])
          ? 'Facture Internet'
          : 'Facture téléphone';
      confidence = .88;
    } else if (lower.contains('facture') && lower.contains('assurance')) {
      type = 'Facture d’assurance';
      confidence = .8;
    } else if (lower.contains('facture')) {
      type = 'Facture générique';
      confidence = .72;
    } else if (RegExp(r'\bcaf\b', caseSensitive: false).hasMatch(text)) {
      type = 'Courrier CAF';
      organisation = 'CAF';
      confidence = .95;
    } else if (any(['cpam', 'assurance maladie', 'ameli'])) {
      type = 'Courrier CPAM';
      organisation = 'CPAM';
      confidence = .94;
    } else if (any([
      'impôts',
      'impots',
      'direction générale des finances',
      'trésor public'
    ])) {
      type = 'Courrier des impôts';
      organisation = 'Impôts';
      confidence = .9;
    } else if (any(['banque', 'compte bancaire', 'relevé de compte'])) {
      type = 'Courrier bancaire';
      confidence = .75;
    } else if (lower.contains('assurance')) {
      type = 'Courrier d’assurance';
      confidence = .72;
    } else if (any(
        ['employeur', 'ressources humaines', 'bulletin de salaire'])) {
      type = 'Courrier employeur';
      confidence = .75;
    } else if (lower.contains('contrat')) {
      type = 'Contrat';
      confidence = .7;
    } else if (any(['avis', 'notification'])) {
      type = 'Avis ou notification';
      confidence = .65;
    }

    final amountPattern = RegExp(
      r'(?:montant\s+(?:total\s+)?(?:à|a)\s+payer|net\s+(?:à|a)\s+payer|total\s+ttc|total\s+dû|total\s+du)\s*[:\-]?\s*(\d{1,3}(?:[ .]\d{3})*(?:[,.]\d{2})\s*€)',
      caseSensitive: false,
    );
    final amountMatch = amountPattern.firstMatch(text);
    final totalAmount = amountMatch?.group(1)?.trim() ?? '';

    final duePattern = RegExp(
      r'(?:à payer avant le|a payer avant le|date limite(?: de paiement)?|échéance|echeance|au plus tard le)\s*[:\-]?\s*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
      caseSensitive: false,
    );
    final dueDate = duePattern.firstMatch(text)?.group(1)?.trim() ?? '';
    final reference = RegExp(
          r'(?:référence (?:client|facture)|reference (?:client|facture)|n° de facture|numéro de facture)\s*[:#\-]?\s*([A-Z0-9][A-Z0-9./\-]{3,})',
          caseSensitive: false,
        ).firstMatch(text)?.group(1)?.trim() ??
        '';

    final explicitRequested = <String>[];
    for (final match in RegExp(
      r'(?:joindre|fournir|transmettre|envoyer)\s+(?:une?|la|le|les|votre|vos)?\s*([^.;]{3,80})',
      caseSensitive: false,
    ).allMatches(text)) {
      final value = match.group(1)?.trim() ?? '';
      if (value.isNotEmpty) explicitRequested.add(value);
    }

    DateTime? parsedDue;
    final parts = dueDate.split(RegExp(r'[/-]'));
    if (parts.length == 3) {
      final yearValue = int.tryParse(parts[2]);
      final year = yearValue == null
          ? null
          : yearValue < 100
              ? 2000 + yearValue
              : yearValue;
      if (year != null) {
        parsedDue = DateTime.tryParse(
          '$year-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}',
        );
      }
    }
    final today = now ?? DateTime.now();
    final days = parsedDue
        ?.difference(DateTime(today.year, today.month, today.day))
        .inDays;
    final priority = days != null && days >= 0 && days <= 14
        ? 'Échéance ou réponse proche'
        : confidence < .7 || type == 'Document inconnu'
            ? 'À vérifier'
            : 'Aucune action urgente détectée';

    final isInvoice = type.startsWith('Facture');
    final actions = isInvoice
        ? <String>[
            'Ajouter un rappel',
            'Contester cette facture',
            'Poser une question',
            'Sauvegarder',
            'Partager',
            'Voir le texte complet',
          ]
        : <String>[
            'Rédiger une réponse',
            'Ajouter un rappel',
            'Enregistrer dans Mes documents',
            'Sauvegarder dans le cloud',
            'Partager',
            'Voir le texte complet',
          ];
    final summary = text.isEmpty
        ? 'Aucun texte exploitable détecté.'
        : text.length > 180
            ? '${text.substring(0, 180)}…'
            : text;
    return DocumentInsight(
      category: type,
      summary: summary,
      organisation: organisation,
      dates: dueDate.isEmpty ? const [] : [dueDate],
      amounts: totalAmount.isEmpty ? const [] : [totalAmount],
      references: reference.isEmpty ? const [] : [reference],
      actions: actions,
      priority: priority,
      documentsToPrepare: explicitRequested,
      requestedDocuments: explicitRequested,
      warnings: const [
        'Vérifiez les informations importantes dans le document original.'
      ],
      documentType: type,
      supplier: organisation == 'Non identifiée' ? '' : organisation,
      dueDate: dueDate,
      amountDetails: totalAmount.isEmpty
          ? const []
          : [
              DocumentAmountItem(
                  label: 'Montant total à payer', amount: totalAmount)
            ],
      confidence: confidence,
      suggestedAction: priority,
    );
  }
}

class LocalDocumentAnalyzer {
  static DocumentInsight analyze(String rawText) {
    final text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = text.toLowerCase();
    String category = 'Courrier administratif';
    const categories = <String, List<String>>{
      'Impôts et finances': [
        'impôt',
        'fiscal',
        'trésor public',
        'taxe',
        'amende',
        'paiement'
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
      'Énergie et télécom': [
        'électricité',
        'gaz',
        'internet',
        'téléphone',
        'abonnement'
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
      'CAF',
      'CPAM',
      'CARSAT',
      'MSA',
      'URSSAF',
      'EDF',
      'ENGIE',
      'Orange',
      'SFR',
      'Free',
      'Bouygues',
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
    if (dates.isNotEmpty) {
      actions.add('Enregistrer l’échéance et programmer un rappel.');
    }
    if (actions.isEmpty) {
      actions.add(
          'Relire le courrier et demander des précisions avant toute action importante.');
    }
    if (documents.isEmpty) {
      documents.add('Le courrier original et toute pièce liée au dossier');
    }
    if (warnings.isEmpty) {
      warnings.add(
          'Vérifiez toujours les dates, références et coordonnées avant de répondre.');
    }

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
          ? 'facture'
          : 'courrier',
      supplier: organisation == 'Non identifiée' ? '' : organisation,
      dueDate: dates.isEmpty ? '' : dates.first,
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
    insight = SmartDocumentLocalAnalyzer.analyze(widget.sourceText);
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

  Widget _invoiceOverview(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.receipt_long_rounded),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                  insight.category.isEmpty ? 'Facture' : insight.category,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                )),
              ]),
              const SizedBox(height: 10),
              if (insight.supplier.isNotEmpty ||
                  insight.organisation != 'Non identifiée')
                Text(
                    'Fournisseur : ${insight.supplier.isNotEmpty ? insight.supplier : insight.organisation}'),
              if (insight.billingPeriod.isNotEmpty)
                Text('Période : ${insight.billingPeriod}'),
              if (insight.dueDate.isNotEmpty)
                Text('Échéance : ${insight.dueDate}'),
              const Divider(height: 28),
              _amountBreakdown(),
              if (insight.summary.isNotEmpty) ...[
                const Divider(height: 28),
                Text(insight.summary),
              ],
            ],
          ),
        ),
      );

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
    } on GeminiConfigurationException {
      if (!mounted) return;
      setState(() => aiError = geminiUnavailableMessage);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => aiError = geminiUnavailableMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => aiError = geminiUnavailableMessage);
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
          title: const Text('Assistant IA Premium'),
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
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: Icon(
                    aiUsed ? Icons.cloud_done_outlined : Icons.phone_android,
                    size: 18,
                  ),
                  label: Text(
                    aiUsed
                        ? 'Analyse Gemini Flash-Lite'
                        : 'Analyse locale provisoire',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (insight.isInvoice) _invoiceOverview(context),
              if (insight.isInvoice) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(() => showDetails = !showDetails),
                  icon:
                      Icon(showDetails ? Icons.expand_less : Icons.expand_more),
                  label: Text(showDetails
                      ? 'Masquer les détails'
                      : 'Voir plus de détails'),
                ),
                const SizedBox(height: 8),
              ],
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
                                  geminiUnavailableMessage,
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
              const SizedBox(height: 14),
              Text(
                'Analyse locale indicative : vérifiez toujours les dates, '
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
  const ReplyScreen({
    super.key,
    required this.sourceText,
    this.insight,
    this.settings,
  });
  final String sourceText;
  final DocumentInsight? insight;
  final AppSettings? settings;
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
  late bool addSignature;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings ?? appSettings;
    addSignature = LetterSignatureService.defaultForLetter(
      autoInsert: settings.autoInsertSignature,
      hasSignature: settings.hasSignature,
    );
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
    final settings = widget.settings ?? appSettings;
    return LetterSignatureService.buildLetterPdf(
      text: draft.text,
      subject: 'Réponse à votre courrier',
      heading: 'AdminFacile - Réponse administrative',
      signed: addSignature,
      signaturePath: settings.signaturePath,
      senderName: '${settings.firstName} ${settings.lastName}'.trim(),
    );
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
          LetterSignatureOption(
            key: const Key('reply-signature-option'),
            settings: widget.settings ?? appSettings,
            value: addSignature,
            onChanged: (value) => setState(() => addSignature = value),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Microphone : ${error.errorMsg}')));
      }
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
        if (title.contains('standard') || keywords.contains('standard')) {
          score += 8;
        }

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
                                  template: letterTemplateForCategory(
                                      record.category),
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
      required this.keywords,
      this.organisation = '',
      this.description = '',
      this.fields = const <String>[],
      this.recommendedTone = 'Professionnel'});
  final String id;
  final String category;
  final String subcategory;
  final String title;
  final String subject;
  final String body;
  final List<String> keywords;
  final String organisation;
  final String description;
  final List<String> fields;
  final String recommendedTone;

  factory JsonLetterRecord.fromJson(Map<String, dynamic> json) =>
      JsonLetterRecord(
        id: json['id'] as String,
        category: normalizeFrenchTypography(json['category'] as String),
        subcategory: normalizeFrenchTypography(
            json['subcategory'] as String? ?? 'Demandes générales'),
        title: normalizeFrenchTypography(json['title'] as String),
        subject: normalizeFrenchTypography(json['subject'] as String),
        body: normalizeFrenchTypography(json['body'] as String),
        keywords:
            List<String>.from(json['keywords'] as List<dynamic>? ?? const [])
                .map(normalizeFrenchTypography)
                .toList(),
        organisation:
            normalizeFrenchTypography(json['organisation'] as String? ?? ''),
        description: normalizeFrenchTypography(json['description'] as String? ??
            'Lettre personnalisable pour ${json['title'] as String}.'),
        fields: List<String>.from(json['fields'] as List<dynamic>? ??
                const ['destinataire', 'reference', 'precisions'])
            .map(normalizeFrenchTypography)
            .toList(),
        recommendedTone:
            ((json['tones'] as List<dynamic>?)?.isNotEmpty ?? false)
                ? (json['tones'] as List<dynamic>).first.toString()
                : 'Professionnel',
      );
}

/// Cache partagé du catalogue embarqué.
///
/// Les différents écrans de recherche utilisaient auparavant chacun une
/// lecture disque et un décodage JSON des 500+ modèles. Le catalogue étant
/// immuable pendant l'exécution, une seule future partagée suffit.
class BundledLetterCatalog {
  BundledLetterCatalog._();

  static Future<List<JsonLetterRecord>>? _cachedRecords;

  static Future<List<JsonLetterRecord>> load() =>
      _cachedRecords ??= _loadFromAssets();

  static Future<List<JsonLetterRecord>> _loadFromAssets() async {
    final raw = await rootBundle.loadString('assets/letters/library.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final records = (data['templates'] as List<dynamic>)
        .map(
          (entry) => JsonLetterRecord.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList(growable: true)
      ..addAll(V173LetterCatalog.additionalRecords);
    return List<JsonLetterRecord>.unmodifiable(records);
  }
}

class V173LetterCatalog {
  static const categories = <String>[
    'Administration',
    'CAF',
    'CPAM / Assurance Maladie',
    'Impôts',
    'France Travail',
    'Retraite',
    'Préfecture',
    'Mairie',
    'Éducation',
    'Logement',
    'Bailleur',
    'Énergie',
    'Eau',
    'Télécoms',
    'Banque',
    'Crédit',
    'Assurance',
    'Santé',
    'Travail',
    'Employeur',
    'Automobile',
    'Consommation',
    'Achats en ligne',
    'Transport',
    'Justice',
    'Famille',
    'Voisinage',
    'Résiliation',
    'Réclamation',
    'Contestation',
    'Mise en demeure',
    'Demande de document',
    'Relance',
    'Divers'
  ];

  static final List<JsonLetterRecord> additionalRecords = [
    for (var index = 0; index < categories.length; index++)
      JsonLetterRecord(
        id: 'v173_category_${index.toString().padLeft(2, '0')}',
        category: categories[index],
        subcategory: 'Demande courante',
        title: 'Demande auprès de ${categories[index]}',
        organisation: categories[index],
        description:
            'Présenter clairement une demande concernant ${categories[index]}.',
        subject: 'Demande concernant ${categories[index]}',
        body:
            'Je vous contacte au sujet de ma situation concernant ${categories[index]}. '
            'Les faits utiles et ma demande précise sont indiqués ci-dessous. '
            'Je vous remercie de m’informer de la suite donnée et des éventuels documents nécessaires.',
        keywords: [
          categories[index].toLowerCase(),
          'demande',
          'courrier',
          'dossier',
          'réponse'
        ],
        fields: const ['destinataire', 'référence', 'situation', 'demande'],
      ),
    const JsonLetterRecord(
        id: 'v173_orange_mobile_cancel',
        category: 'Télécoms',
        subcategory: 'Résiliation',
        organisation: 'Orange',
        title: 'Résiliation abonnement mobile Orange',
        description: 'Demander la clôture d’un forfait mobile Orange.',
        subject: 'Résiliation de mon abonnement mobile Orange',
        body:
            'Je vous demande de résilier mon abonnement mobile Orange identifié ci-dessous. Merci de me confirmer la date de fin du contrat et l’arrêt de la facturation.',
        keywords: ['résilier', 'résiliation', 'orange', 'mobile', 'forfait'],
        fields: ['numéro de ligne', 'référence client', 'date souhaitée']),
    const JsonLetterRecord(
        id: 'v173_orange_internet_cancel',
        category: 'Télécoms',
        subcategory: 'Résiliation',
        organisation: 'Orange',
        title: 'Résiliation Internet Orange',
        description: 'Résilier une offre Internet ou Livebox Orange.',
        subject: 'Résiliation de mon abonnement Internet Orange',
        body:
            'Je vous demande de résilier mon offre Internet Orange mentionnée ci-dessous. Merci de préciser la date de fin, les modalités de restitution du matériel et le solde éventuel.',
        keywords: ['résilier', 'résiliation', 'orange', 'internet', 'livebox'],
        fields: ['numéro client', 'adresse de la ligne', 'date souhaitée']),
    const JsonLetterRecord(
        id: 'v173_orange_after_cancel',
        category: 'Réclamation',
        subcategory: 'Télécoms',
        organisation: 'Orange',
        title: 'Réclamation après résiliation Orange',
        description: 'Signaler un problème persistant après une résiliation.',
        subject: 'Réclamation après la résiliation de mon abonnement Orange',
        body:
            'Malgré la résiliation de mon abonnement Orange, le problème décrit ci-dessous demeure. Je vous demande de vérifier mon dossier et de régulariser la situation.',
        keywords: ['orange', 'réclamation', 'après résiliation', 'facturation'],
        fields: ['référence client', 'date de résiliation', 'problème']),
    const JsonLetterRecord(
        id: 'v173_orange_cancel_fees',
        category: 'Contestation',
        subcategory: 'Télécoms',
        organisation: 'Orange',
        title: 'Contestation de frais de résiliation Orange',
        description: 'Contester des frais de clôture ou de résiliation.',
        subject: 'Contestation des frais de résiliation facturés',
        body:
            'Je conteste les frais de résiliation portés à mon compte Orange pour les raisons exposées ci-dessous. Merci de vérifier leur origine et de corriger la facturation si nécessaire.',
        keywords: [
          'orange',
          'contester',
          'contestation',
          'frais',
          'résiliation'
        ],
        fields: [
          'numéro client',
          'montant',
          'facture',
          'motif'
        ]),
    const JsonLetterRecord(
        id: 'v173_edf_invoice_dispute',
        category: 'Énergie',
        subcategory: 'Facturation',
        organisation: 'EDF',
        title: 'Contester une facture EDF',
        description: 'Demander la vérification d’une facture EDF contestée.',
        subject: 'Contestation de ma facture EDF',
        body:
            'Je conteste le montant ou les éléments de la facture EDF indiquée ci-dessous. Je vous demande de vérifier le relevé, la période et le calcul puis de me transmettre une réponse détaillée.',
        keywords: ['edf', 'facture', 'contester', 'montant', 'relevé'],
        fields: ['numéro client', 'facture', 'montant', 'motif']),
    const JsonLetterRecord(
        id: 'v173_edf_payment_plan',
        category: 'Énergie',
        subcategory: 'Paiement',
        organisation: 'EDF',
        title: 'Demande d’échéancier EDF',
        description: 'Proposer un règlement échelonné à EDF.',
        subject: 'Demande d’échelonnement de ma facture EDF',
        body:
            'Je rencontre une difficulté temporaire pour régler ma facture EDF. Je sollicite un échéancier adapté et vous propose les modalités précisées ci-dessous.',
        keywords: ['edf', 'facture', 'échéancier', 'paiement', 'délai'],
        fields: ['numéro client', 'montant', 'mensualité proposée']),
    const JsonLetterRecord(
        id: 'v173_edf_invoice_explanation',
        category: 'Énergie',
        subcategory: 'Facturation',
        organisation: 'EDF',
        title: 'Demande d’explication de facture EDF',
        description: 'Obtenir le détail d’une facture difficile à comprendre.',
        subject: 'Demande d’explication concernant ma facture EDF',
        body:
            'Je souhaite obtenir une explication détaillée de la facture EDF citée ci-dessous, notamment sur la période, les index et les montants appliqués.',
        keywords: ['edf', 'facture', 'explication', 'détail', 'consommation'],
        fields: ['numéro client', 'facture', 'éléments à expliquer']),
    const JsonLetterRecord(
        id: 'v173_edf_meter_error',
        category: 'Énergie',
        subcategory: 'Relevé',
        organisation: 'EDF',
        title: 'Signalement d’une erreur de relevé EDF',
        description: 'Faire corriger un index ou un relevé de compteur.',
        subject: 'Signalement d’une erreur de relevé',
        body:
            'Le relevé utilisé pour ma facture EDF semble différent de l’index visible sur mon compteur. Je vous demande de contrôler les données et de régulariser la facture si nécessaire.',
        keywords: ['edf', 'facture', 'erreur', 'relevé', 'compteur', 'index'],
        fields: ['numéro client', 'index constaté', 'date', 'facture']),
  ];

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôö]'), 'o')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<JsonLetterRecord> search(
      Iterable<JsonLetterRecord> records, String query) {
    final normalized = normalize(query)
        .replaceAll('resilier', 'resiliation')
        .replaceAll('rembourser', 'remboursement');
    final words = normalized.split(' ').where((e) => e.length > 1).toList();
    final scored = <({JsonLetterRecord record, int score})>[];
    for (final record in records) {
      final title = normalize(record.title);
      final organisation = normalize(record.organisation);
      final haystack = normalize('${record.title} ${record.category} '
              '${record.subcategory} ${record.organisation} ${record.description} '
              '${record.subject} ${record.keywords.join(' ')}')
          .replaceAll('resilier', 'resiliation');
      if (!words.every(haystack.contains)) continue;
      var score = 0;
      for (final word in words) {
        if (title.contains(word)) score += 12;
        if (organisation.contains(word)) score += 10;
        if (haystack.contains(word)) score += 2;
      }
      if (title.contains(normalized)) score += 30;
      scored.add((record: record, score: score));
    }
    scored.sort((a, b) => b.score != a.score
        ? b.score.compareTo(a.score)
        : a.record.title.compareTo(b.record.title));
    return scored.map((e) => e.record).toList();
  }
}

LetterTemplate letterTemplateForCategory(String value) => switch (value) {
      'Assurance' => LetterTemplate.insurance,
      'Banque' || 'Crédit' => LetterTemplate.bank,
      'CAF' => LetterTemplate.caf,
      'CPAM' || 'CPAM / Assurance Maladie' || 'Santé' => LetterTemplate.cpam,
      'Impôts' ||
      'Administration' ||
      'Préfecture' ||
      'Mairie' =>
        LetterTemplate.taxes,
      'Retraite' => LetterTemplate.retirement,
      'Employeur' || 'Travail' || 'France Travail' => LetterTemplate.employer,
      'Logement' || 'Bailleur' || 'Voisinage' => LetterTemplate.housing,
      'Énergie' || 'Eau' => LetterTemplate.energy,
      _ => LetterTemplate.telecom,
    };

class LetterModelDetailScreen extends StatefulWidget {
  const LetterModelDetailScreen(
      {super.key, required this.settings, required this.record});
  final AppSettings settings;
  final JsonLetterRecord record;

  @override
  State<LetterModelDetailScreen> createState() =>
      _LetterModelDetailScreenState();
}

class _LetterModelDetailScreenState extends State<LetterModelDetailScreen> {
  @override
  void initState() {
    super.initState();
    _recordUsage();
  }

  Future<void> _recordUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('jsonLibraryHistoryV66') ?? <String>[];
    history.remove(widget.record.id);
    history.insert(0, widget.record.id);
    await prefs.setStringList(
        'jsonLibraryHistoryV66', history.take(30).toList());
  }

  void _useModel() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LetterFormScreen(
        settings: widget.settings,
        template: letterTemplateForCategory(widget.record.category),
        model: ProfessionalLetterModel(
          title: widget.record.title,
          subject: widget.record.subject,
          body: widget.record.body,
        ),
        initialRecipient: widget.record.organisation,
        initialDetails: widget.record.fields.isEmpty
            ? ''
            : 'Champs à compléter : ${widget.record.fields.join(', ')}',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: Key('model-detail-${widget.record.id}'),
        appBar: AppBar(title: const Text('Aperçu du modèle')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(widget.record.title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${widget.record.category} • ${widget.record.subcategory}'),
              if (widget.record.organisation.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Organisme : ${widget.record.organisation}'),
              ],
              const SizedBox(height: 18),
              Text('Objet', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(widget.record.subject),
              const SizedBox(height: 18),
              Text('Aperçu', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(widget.record.body),
              if (widget.record.fields.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Champs à compléter',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(widget.record.fields.join(' • ')),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('use-selected-model'),
                onPressed: _useModel,
                icon: const Icon(Icons.edit_note_rounded),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Utiliser ce modèle'),
                ),
              ),
            ],
          ),
        ),
      );
}

class JsonLibraryScreen extends StatefulWidget {
  const JsonLibraryScreen(
      {super.key, required this.settings, this.initialRecords});
  final AppSettings settings;
  final List<JsonLetterRecord>? initialRecords;
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
      final list = widget.initialRecords != null
          ? List<JsonLetterRecord>.from(widget.initialRecords!)
          : await _loadBundledRecords();
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

  Future<List<JsonLetterRecord>> _loadBundledRecords() async {
    return BundledLetterCatalog.load();
  }

  Future<void> _toggleFavorite(String id) async {
    setState(() {
      if (!favorites.add(id)) favorites.remove(id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, favorites.toList()..sort());
  }

  Future<void> _openRecord(JsonLetterRecord item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LetterModelDetailScreen(settings: widget.settings, record: item),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    history = prefs.getStringList(_historyKey) ?? <String>[];
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
    final historyPositions = <String, int>{
      for (var i = 0; i < history.length; i++) history[i]: i,
    };
    var result = records.where((e) {
      if (category != null && e.category != category) return false;
      if (subcategory != null && e.subcategory != subcategory) return false;
      if (favoritesOnly && !favorites.contains(e.id)) return false;
      if (recentOnly && !historyPositions.containsKey(e.id)) return false;
      return true;
    }).toList();
    if (q.isNotEmpty) result = V173LetterCatalog.search(result, q);
    if (recentOnly) {
      result.sort((a, b) => (historyPositions[a.id] ?? 999)
          .compareTo(historyPositions[b.id] ?? 999));
    } else {
      result.sort((a, b) => a.title.compareTo(b.title));
    }
    return result;
  }

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
                          labelText:
                              'Rechercher parmi ${records.length} modèles',
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
                      child: Column(children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              '${items.length} courrier${items.length > 1 ? 's' : ''} '
                              'sur ${records.length}',
                            ),
                          ),
                          const Tooltip(
                            message:
                                'Les modèles sont disponibles même sans connexion Internet.',
                            child: Icon(Icons.offline_bolt_outlined, size: 18),
                          ),
                          const SizedBox(width: 6),
                          const Flexible(
                              child: Text('Disponible hors connexion')),
                        ]),
                        const SizedBox(height: 7),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          Chip(
                            avatar: Icon(Icons.auto_awesome_outlined, size: 16),
                            label: Text(GeminiDocumentAnalyzer.isConfigured
                                ? 'Gemini connecté'
                                : 'Gemini indisponible'),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            avatar: Icon(Icons.cloud_outlined, size: 16),
                            label: Text(_supabaseReady
                                ? 'Supabase synchronisé'
                                : 'Supabase indisponible'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ]),
                      ]),
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
                                  child: Column(children: [
                                    ListTile(
                                      minVerticalPadding: 12,
                                      leading: CircleAvatar(
                                        child: Text(
                                            item.category.characters.first),
                                      ),
                                      title: Text(item.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      subtitle: Text(
                                        '${item.category} • ${item.subcategory}\n${item.description}',
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      isThreeLine: true,
                                      trailing: IconButton(
                                        tooltip: favorite
                                            ? 'Retirer des favoris'
                                            : 'Ajouter aux favoris',
                                        onPressed: () =>
                                            _toggleFavorite(item.id),
                                        icon: Icon(favorite
                                            ? Icons.star
                                            : Icons.star_border),
                                      ),
                                      onTap: () => _openRecord(item),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 12),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.tonal(
                                          onPressed: () => _openRecord(item),
                                          child:
                                              const Text('Utiliser ce modèle'),
                                        ),
                                      ),
                                    ),
                                  ]),
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
          Text(
              'Plus de ${500 + V173LetterCatalog.additionalRecords.length} modèles de lettres administratives'),
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
    this.initialDetails = '',
  });
  final AppSettings settings;
  final LetterTemplate template;
  final ProfessionalLetterModel model;
  final String initialRecipient;
  final String initialDetails;
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
  late bool addSignature;

  @override
  void initState() {
    super.initState();
    firstName = TextEditingController(text: widget.settings.firstName);
    lastName = TextEditingController(text: widget.settings.lastName);
    address = TextEditingController(text: widget.settings.address);
    postalCode = TextEditingController(text: widget.settings.postalCode);
    city = TextEditingController(text: widget.settings.city);
    recipient.text = widget.initialRecipient;
    details.text = widget.initialDetails;
    addSignature = LetterSignatureService.defaultForLetter(
      autoInsert: widget.settings.autoInsertSignature,
      hasSignature: widget.settings.hasSignature,
    );
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
        signed: addSignature,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LetterPreviewScreen(
          letter: letter,
          defaultSubject: widget.model.subject,
          settings: widget.settings,
          initialSigned: addSignature,
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
              LetterSignatureOption(
                key: const Key('template-signature-option'),
                settings: widget.settings,
                value: addSignature,
                onChanged: (value) => setState(() => addSignature = value),
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
    this.settings,
    this.initialSigned,
    this.onSignedChanged,
  });
  final String letter;
  final String defaultSubject;
  final AppSettings? settings;
  final bool? initialSigned;
  final ValueChanged<bool>? onSignedChanged;
  @override
  State<LetterPreviewScreen> createState() => _LetterPreviewScreenState();
}

class _LetterPreviewScreenState extends State<LetterPreviewScreen> {
  bool improving = false;
  late bool addSignature;
  late final TextEditingController controller =
      TextEditingController(text: widget.letter);

  @override
  void initState() {
    super.initState();
    addSignature = widget.initialSigned ??
        (widget.settings == null
            ? false
            : LetterSignatureService.defaultForLetter(
                autoInsert: widget.settings!.autoInsertSignature,
                hasSignature: widget.settings!.hasSignature));
  }

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
      controller.text = normalizeFrenchTypography(improved);
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Lettre améliorée avec Gemini. Relisez-la avant l’envoi.')));
    } on GeminiConfigurationException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(geminiUnavailableMessage)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(geminiUnavailableMessage)));
      }
    } finally {
      if (mounted) setState(() => improving = false);
    }
  }

  Future<Uint8List> _buildPdf() async {
    final settings = widget.settings;
    return LetterSignatureService.buildLetterPdf(
      text: controller.text,
      subject: widget.defaultSubject,
      signed: addSignature,
      signaturePath: settings?.signaturePath ?? '',
      senderName: settings == null
          ? ''
          : '${settings.firstName} ${settings.lastName}'.trim(),
    );
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: OfficialLetterSheet(
              child: Column(children: [
                TextField(
                  key: const Key('letter-preview-editor'),
                  controller: controller,
                  minLines: 28,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  cursorColor: const Color(0xFF136DF2),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    height: 1.6,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Document modifiable',
                    hintStyle: TextStyle(color: Colors.black54),
                  ),
                ),
                if (widget.settings != null)
                  LetterSignatureOption(
                    key: const Key('preview-signature-option'),
                    settings: widget.settings!,
                    value: addSignature,
                    onChanged: (value) {
                      setState(() => addSignature = value);
                      widget.onSignedChanged?.call(value);
                    },
                  ),
                if (addSignature && widget.settings != null) ...[
                  const SizedBox(height: 12),
                  OfficialSignatureBlock(
                    key: const Key('preview-signature-image'),
                    signed: addSignature,
                    signaturePath: widget.settings!.signaturePath,
                    senderName:
                        '${widget.settings!.firstName} ${widget.settings!.lastName}',
                  ),
                ],
              ]),
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

  final Set<String> _uploadingProcedureIds = <String>{};
  final Set<String> _syncedProcedureIds = <String>{};
  final Set<String> _failedProcedureIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCloudState();
  }

  String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';

  Future<void> _loadCloudState() async {
    if (!_supabaseReady) return;

    final user = _currentSupabaseUser;
    if (user == null) return;

    try {
      final files = await Supabase.instance.client.storage
          .from('admin-documents')
          .list(path: '${user.id}/procedures');

      if (!mounted) return;

      setState(() {
        _syncedProcedureIds
          ..clear()
          ..addAll(
            files
                .where((file) => file.name.toLowerCase().endsWith('.pdf'))
                .map((file) => file.name.replaceAll('.pdf', '')),
          );
      });
    } catch (error) {
      debugPrint('Lecture des démarches cloud impossible : $error');
    }
  }

  Future<Uint8List> _procedurePdf(AdministrativeProcedure item) async {
    final prefs = await SharedPreferences.getInstance();
    final signaturePath = prefs.getString('signaturePathV17') ?? '';
    return LetterSignatureService.buildLetterPdf(
      text: item.letter,
      subject: item.title,
      heading: item.organisation.isEmpty ? item.category : item.organisation,
      signed: item.signed,
      signaturePath: signaturePath,
      senderName: '${appSettings.firstName} ${appSettings.lastName}'.trim(),
      notes: item.notes,
    );
  }

  Future<void> _downloadProcedure(AdministrativeProcedure item) async {
    final bytes = await _procedurePdf(item);
    await FilePicker.platform.saveFile(
      dialogTitle: 'Télécharger la démarche',
      fileName: '${item.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
  }

  Future<void> _shareProcedure(AdministrativeProcedure item) async {
    final bytes = await _procedurePdf(item);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/demarche_${item.id}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: item.title),
    );
  }

  // Conservé pour les parcours avancés existants.
  // ignore: unused_element
  Future<void> _printProcedure(AdministrativeProcedure item) async {
    final bytes = await _procedurePdf(item);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: item.title);
  }

  Future<void> _uploadProcedure(AdministrativeProcedure item) async {
    if (!_supabaseReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supabase n’est pas configuré dans cette version.'),
        ),
      );
      return;
    }

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connectez-vous dans Profil avant de sauvegarder cette démarche.',
          ),
        ),
      );
      return;
    }

    if (_uploadingProcedureIds.contains(item.id)) return;

    setState(() => _uploadingProcedureIds.add(item.id));
    _failedProcedureIds.remove(item.id);

    try {
      final bytes = await _procedurePdf(item);
      final cloudPath = procedureCloudPath(user.id, item.id);

      await client.storage
          .from('admin-documents')
          .uploadBinary(
            cloudPath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      setState(() => _syncedProcedureIds.add(item.id));
      _failedProcedureIds.remove(item.id);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '« ${item.title} » est sauvegardée dans votre espace sécurisé.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Envoi Supabase impossible : $error\n$stackTrace');

      if (!mounted) return;

      setState(() => _failedProcedureIds.add(item.id));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cloudOperationMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingProcedureIds.remove(item.id));
      }
    }
  }

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
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedStatus = value);
                    }
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
                  subtitle: Text(
                    reminderDate == null ? 'Aucune date' : _date(reminderDate!),
                  ),
                  trailing: reminderDate == null
                      ? null
                      : IconButton(
                          tooltip: 'Supprimer la date',
                          onPressed: () {
                            setDialogState(() => reminderDate = null);
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: reminderDate ??
                          DateTime.now().add(const Duration(days: 14)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(
                        const Duration(days: 3650),
                      ),
                    );

                    if (picked != null) {
                      setDialogState(() => reminderDate = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
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

    if (result != null) {
      await widget.store.update(result);
    }
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
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.store.remove(item.id);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Mes démarches'),
          actions: [
            IconButton(
              tooltip: 'Actualiser le cloud',
              onPressed: _loadCloudState,
              icon: const Icon(Icons.cloud_sync_outlined),
            ),
          ],
        ),
        body: AnimatedBuilder(
          animation: widget.store,
          builder: (context, _) {
            final normalized = query.trim().toLowerCase();

            final items = widget.store.items.where((item) {
              if (item.archived != showArchived) return false;
              if (normalized.isEmpty) return true;

              return '${item.title} ${item.organisation} '
                      '${item.category} ${item.notes} ${item.status.label}'
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
                      icon: Icon(Icons.folder_open),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Archivées'),
                      icon: Icon(Icons.archive_outlined),
                    ),
                  ],
                  selected: {showArchived},
                  onSelectionChanged: (value) {
                    setState(() => showArchived = value.first);
                  },
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
                            'Une démarche est créée automatiquement lorsque vous générez une lettre.',
                          ),
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
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ],
                                ),
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
                                label: Text(item.status.label),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: Key('procedure-open-${item.id}'),
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => LetterPreviewScreen(
                                          letter: item.letter,
                                          defaultSubject: item.title,
                                          settings: appSettings,
                                          initialSigned: item.signed,
                                          onSignedChanged: (value) =>
                                              widget.store.update(
                                                  item.copyWith(signed: value)),
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.description_outlined,
                                  ),
                                  label: const Text('Ouvrir la lettre'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_uploadingProcedureIds.contains(item.id))
                                const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              else if (_syncedProcedureIds.contains(item.id))
                                const Tooltip(
                                  message: 'Synchronisée',
                                  child: Icon(Icons.cloud_done_rounded,
                                      color: Colors.green, size: 22),
                                )
                              else if (_failedProcedureIds.contains(item.id))
                                Icon(Icons.error_outline,
                                    color: Theme.of(context).colorScheme.error),
                              PopupMenuButton<String>(
                                key: Key('procedure-more-${item.id}'),
                                tooltip: 'Plus d’actions',
                                icon: const Icon(Icons.more_horiz_rounded),
                                onSelected: (value) async {
                                  if (value == 'edit') {
                                    await _edit(item);
                                  } else if (value == 'cloud') {
                                    await _uploadProcedure(item);
                                  } else if (value == 'download') {
                                    await _downloadProcedure(item);
                                  } else if (value == 'share') {
                                    await _shareProcedure(item);
                                  } else if (value == 'delete') {
                                    await _confirmDelete(item);
                                  } else if (value == 'advancedPrint') {
                                    await _printProcedure(item);
                                  } else if (value == 'advancedArchive') {
                                    await widget.store.update(item.copyWith(
                                        archived: !item.archived));
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('Modifier'),
                                      dense: true,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'cloud',
                                    enabled: !_uploadingProcedureIds
                                        .contains(item.id),
                                    child: const ListTile(
                                      leading:
                                          Icon(Icons.cloud_upload_outlined),
                                      title: Text('Cloud'),
                                      dense: true,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'download',
                                    child: ListTile(
                                      leading: Icon(Icons.download_rounded),
                                      title: Text('Télécharger'),
                                      dense: true,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'share',
                                    child: ListTile(
                                      leading: Icon(Icons.share_outlined),
                                      title: Text('Partager'),
                                      dense: true,
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                    value: 'advancedPrint',
                                    child: ListTile(
                                      leading: Icon(Icons.print_outlined),
                                      title: Text('Imprimer'),
                                      dense: true,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'advancedArchive',
                                    child: ListTile(
                                      leading: Icon(item.archived
                                          ? Icons.unarchive_outlined
                                          : Icons.archive_outlined),
                                      title: Text(item.archived
                                          ? 'Désarchiver'
                                          : 'Archiver'),
                                      dense: true,
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: Icon(Icons.delete_outline),
                                      title: Text('Supprimer'),
                                      dense: true,
                                    ),
                                  ),
                                ],
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
  final Set<String> _uploadingDocumentIds = <String>{};
  final Set<String> _syncedDocumentIds = <String>{};
  final Set<String> _failedDocumentIds = <String>{};

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
    final path = doc.filePath!;
    final lower = path.toLowerCase();
    final isImage = lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg');
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InternalDocumentPreviewScreen(
        bytes: bytes,
        title: doc.title,
        isImage: isImage,
      ),
    ));
  }

  Future<void> _uploadDocument(SavedDocument doc) async {
    final user = _currentSupabaseUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            const Text('Connectez-vous dans Profil pour utiliser le cloud.'),
        action: SnackBarAction(
          label: 'Ouvrir le Profil',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ProfileScreen(settings: appSettings))),
        ),
      ));
      return;
    }
    setState(() {
      _uploadingDocumentIds.add(doc.id);
      _failedDocumentIds.remove(doc.id);
    });
    try {
      Uint8List bytes;
      var extension = 'pdf';
      var contentType = 'application/pdf';
      if (doc.filePath != null && await File(doc.filePath!).exists()) {
        bytes = await File(doc.filePath!).readAsBytes();
        final lower = doc.filePath!.toLowerCase();
        if (lower.endsWith('.png')) {
          extension = 'png';
          contentType = 'image/png';
        } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
          extension = 'jpg';
          contentType = 'image/jpeg';
        }
      } else {
        bytes = await LetterSignatureService.buildLetterPdf(
          text: doc.extractedText.isEmpty
              ? 'Document sans contenu textuel.'
              : doc.extractedText,
          subject: doc.title,
          signed: false,
        );
      }
      await Supabase.instance.client.storage
          .from('admin-documents')
          .uploadBinary(
            '${user.id}/documents/${doc.id}.$extension',
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          )
          .timeout(const Duration(seconds: 30));
      if (mounted) setState(() => _syncedDocumentIds.add(doc.id));
    } catch (error) {
      if (mounted) {
        setState(() => _failedDocumentIds.add(doc.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(cloudOperationMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingDocumentIds.remove(doc.id));
    }
  }

  // Conservé pour les parcours avancés existants.
  // ignore: unused_element
  Future<void> _downloadDocument(SavedDocument doc) async {
    final path = doc.filePath;
    if (path == null || !await File(path).exists()) return;
    final extension = path.split('.').last.toLowerCase();
    await FilePicker.platform.saveFile(
      dialogTitle: 'Télécharger le document',
      fileName: '${doc.title}.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: await File(path).readAsBytes(),
    );
  }

  Future<void> _shareDocument(SavedDocument doc) async {
    final path = doc.filePath;
    if (path == null || !await File(path).exists()) return;
    await SharePlus.instance
        .share(ShareParams(files: [XFile(path)], subject: doc.title));
  }

  Future<void> _printDocument(SavedDocument doc) async {
    final path = doc.filePath;
    if (path == null || !await File(path).exists()) return;
    if (!path.toLowerCase().endsWith('.pdf')) return;
    await Printing.layoutPdf(
        onLayout: (_) => File(path).readAsBytes(), name: doc.title);
  }

  Future<void> _confirmDeleteDocument(SavedDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce document ?'),
        content: Text('« ${doc.title} » sera supprimé définitivement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.documentStore.remove(doc.id);
    }
  }

  // Conservé pour les parcours avancés existants.
  // ignore: unused_element
  Future<void> _editDocument(SavedDocument doc) async {
    final title = TextEditingController(text: doc.title);
    final organisation = TextEditingController(text: doc.organisation);
    final notes = TextEditingController(text: doc.notes);
    final amount = TextEditingController(text: doc.detectedAmount);
    final dueDate = TextEditingController(text: doc.detectedDueDate);
    final reference = TextEditingController(text: doc.detectedReference);
    String selectedDocumentType = doc.detectedDocumentType;
    String selectedDetectedPriority = doc.detectedPriority;
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
                DropdownButtonFormField<String>(
                  initialValue: SmartDocumentLocalAnalyzer.documentTypes
                          .contains(selectedDocumentType)
                      ? selectedDocumentType
                      : 'Document inconnu',
                  decoration: const InputDecoration(labelText: 'Type détecté'),
                  items: SmartDocumentLocalAnalyzer.documentTypes
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setDialogState(
                      () => selectedDocumentType = v ?? 'Document inconnu'),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: amount,
                    decoration:
                        const InputDecoration(labelText: 'Montant total')),
                const SizedBox(height: 12),
                TextField(
                    controller: dueDate,
                    decoration:
                        const InputDecoration(labelText: 'Date limite')),
                const SizedBox(height: 12),
                TextField(
                    controller: reference,
                    decoration: const InputDecoration(labelText: 'Référence')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: const [
                    'Aucune action urgente détectée',
                    'À vérifier',
                    'Échéance ou réponse proche'
                  ].contains(selectedDetectedPriority)
                      ? selectedDetectedPriority
                      : 'À vérifier',
                  decoration:
                      const InputDecoration(labelText: 'Priorité détectée'),
                  items: const [
                    'Aucune action urgente détectée',
                    'À vérifier',
                    'Échéance ou réponse proche'
                  ]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setDialogState(
                      () => selectedDetectedPriority = v ?? 'À vérifier'),
                ),
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
        detectedDocumentType: selectedDocumentType,
        detectedAmount: amount.text.trim(),
        detectedDueDate: dueDate.text.trim(),
        detectedReference: reference.text.trim(),
        detectedOrganisation: organisation.text.trim(),
        detectedPriority: selectedDetectedPriority,
        userCorrectedAnalysis: true,
      ));
    }
    title.dispose();
    organisation.dispose();
    notes.dispose();
    amount.dispose();
    dueDate.dispose();
    reference.dispose();
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
                LayoutBuilder(builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 420;
                  final fields = <Widget>[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Catégorie'),
                      items: categories
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => category = value ?? 'Tous'),
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: sortMode,
                      decoration: const InputDecoration(labelText: 'Trier par'),
                      items: const [
                        'Plus récents',
                        'Plus anciens',
                        'Organisme',
                        'Priorité'
                      ]
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => sortMode = value ?? 'Plus récents'),
                    ),
                  ];
                  if (narrow) {
                    return Column(children: [
                      fields.first,
                      const SizedBox(height: 10),
                      fields.last,
                    ]);
                  }
                  return Row(children: [
                    Expanded(child: fields.first),
                    const SizedBox(width: 10),
                    Expanded(child: fields.last),
                  ]);
                }),
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
                                              Text(
                                                  '${doc.createdAt.day.toString().padLeft(2, '0')}/${doc.createdAt.month.toString().padLeft(2, '0')}/${doc.createdAt.year}'),
                                            ])),
                                      ]),
                                  const SizedBox(height: 10),
                                  Row(children: [
                                    Tooltip(
                                      message: doc.filePath == null
                                          ? 'Ouvrir'
                                          : 'Aperçu',
                                      child: OutlinedButton.icon(
                                        key: Key('document-preview-${doc.id}'),
                                        onPressed: () => doc.filePath == null
                                            ? _showDetails(doc)
                                            : _openFile(doc),
                                        icon: Icon(doc.filePath == null
                                            ? Icons.open_in_new_rounded
                                            : Icons.visibility_outlined),
                                        label: Text(doc.filePath == null
                                            ? 'Ouvrir'
                                            : 'Aperçu'),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (_uploadingDocumentIds.contains(doc.id))
                                      const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      )
                                    else if (_syncedDocumentIds
                                        .contains(doc.id))
                                      const Tooltip(
                                        message: 'Synchronisé',
                                        child: Icon(Icons.cloud_done_rounded,
                                            color: Colors.green, size: 22),
                                      )
                                    else if (_failedDocumentIds
                                        .contains(doc.id))
                                      Icon(Icons.error_outline,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          size: 22),
                                    PopupMenuButton<String>(
                                      key: Key('document-more-${doc.id}'),
                                      tooltip: 'Plus d’actions',
                                      icon:
                                          const Icon(Icons.more_horiz_rounded),
                                      onSelected: (value) {
                                        if (value == 'cloud') {
                                          _uploadDocument(doc);
                                        } else if (value == 'share') {
                                          _shareDocument(doc);
                                        } else if (value == 'print') {
                                          _printDocument(doc);
                                        } else if (value == 'advancedEdit') {
                                          _editDocument(doc);
                                        } else if (value ==
                                            'advancedDownload') {
                                          _downloadDocument(doc);
                                        } else if (value == 'delete') {
                                          _confirmDeleteDocument(doc);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'cloud',
                                          enabled: !_uploadingDocumentIds
                                              .contains(doc.id),
                                          child: const ListTile(
                                            leading: Icon(
                                                Icons.cloud_upload_outlined),
                                            title: Text('Cloud / Synchroniser'),
                                            dense: true,
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'share',
                                          enabled: doc.filePath != null,
                                          child: const ListTile(
                                            leading: Icon(Icons.share_outlined),
                                            title: Text('Partager'),
                                            dense: true,
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'print',
                                          enabled: doc.filePath != null,
                                          child: const ListTile(
                                            leading: Icon(Icons.print_outlined),
                                            title: Text('Imprimer'),
                                            dense: true,
                                          ),
                                        ),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                          value: 'advancedEdit',
                                          child: ListTile(
                                            leading: Icon(Icons.edit_outlined),
                                            title: Text(
                                                'Modifier les informations'),
                                            dense: true,
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'advancedDownload',
                                          enabled: doc.filePath != null,
                                          child: const ListTile(
                                            leading:
                                                Icon(Icons.download_rounded),
                                            title: Text('Télécharger'),
                                            dense: true,
                                          ),
                                        ),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: ListTile(
                                            leading: Icon(Icons.delete_outline),
                                            title: Text('Supprimer'),
                                            dense: true,
                                          ),
                                        ),
                                      ],
                                    ),
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

  final TextEditingController _accountEmailController = TextEditingController();
  final TextEditingController _accountPasswordController =
      TextEditingController();

  bool _authBusy = false;
  bool _createAccountMode = false;
  bool _accountPasswordVisible = false;

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

    _accountEmailController.text =
        _currentSupabaseUser?.email ?? widget.settings.email;
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }

    _accountEmailController.dispose();
    _accountPasswordController.dispose();

    super.dispose();
  }

  Future<void> save() async {
    await widget.settings.saveProfile(
      fields.map((key, value) => MapEntry(key, value.text)),
    );

    try {
      await _authService?.updateProfile({
        'first_name': fields['firstName']!.text.trim(),
        'last_name': fields['lastName']!.text.trim(),
        'display_name':
            '${fields['firstName']!.text.trim()} ${fields['lastName']!.text.trim()}'
                .trim(),
      });
    } on AuthOperationException catch (error) {
      if (!mounted) return;
      _showAuthMessage(error.displayMessage);
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil enregistré')),
    );
  }

  Future<void> _submitAccount() async {
    final service = _authService;
    if (!_supabaseReady || service == null) {
      _showAuthMessage(_supabaseInitializationError == null
          ? 'Le service de compte n’est pas configuré.'
          : kDebugMode
              ? 'Service temporairement indisponible.\n[DEBUG] fonction=Supabase.initialize\n$_supabaseInitializationError'
              : 'Service temporairement indisponible.');
      return;
    }

    final email = _accountEmailController.text.trim();
    final password = _accountPasswordController.text;

    setState(() => _authBusy = true);

    try {
      if (_createAccountMode) {
        final result = await service.signUp(
          email: email,
          password: password,
          metadata: {
            'first_name': fields['firstName']!.text.trim(),
            'last_name': fields['lastName']!.text.trim(),
          },
        );
        if (!mounted) return;
        _showAuthMessage(result.emailConfirmationRequired
            ? 'Compte créé. Vérifiez votre e-mail pour confirmer votre compte.'
            : 'Compte créé et connexion réussie.');
      } else {
        await service.signIn(
          email: email,
          password: password,
        );
        if (!mounted) return;
        _showAuthMessage('Connexion réussie.');
      }

      if (!mounted) return;

      setState(() {});
      _accountPasswordController.clear();
    } on AuthOperationException catch (error) {
      if (mounted) _showAuthMessage(error.displayMessage);
    } catch (error) {
      if (mounted) {
        _showAuthMessage(ProfessionalAuthService.mapError(
          error,
          operation: _createAccountMode ? 'signUp' : 'signIn',
        ).displayMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _signOut() async {
    final service = _authService;
    if (!_supabaseReady || service == null) return;
    setState(() => _authBusy = true);
    try {
      await service.signOut();
    } on AuthOperationException catch (error) {
      if (mounted) _showAuthMessage(error.displayMessage);
      return;
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }

    if (!mounted) return;

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vous êtes déconnecté.')),
    );
  }

  void _showAuthMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _resetPassword() async {
    final service = _authService;
    if (service == null) {
      _showAuthMessage('Service temporairement indisponible.');
      return;
    }
    setState(() => _authBusy = true);
    try {
      await service.sendPasswordReset(_accountEmailController.text);
      if (mounted) {
        _showAuthMessage(
            'E-mail de récupération envoyé. Vérifiez aussi vos courriers indésirables.');
      }
    } on AuthOperationException catch (error) {
      if (mounted) _showAuthMessage(error.displayMessage);
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    var passwordVisible = false;
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Changer le mot de passe'),
          content: TextField(
            key: const Key('auth-new-password'),
            controller: controller,
            obscureText: !passwordVisible,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Nouveau mot de passe',
              helperText: '6 caractères minimum',
              suffixIcon: IconButton(
                key: const Key('auth-new-password-visibility'),
                tooltip: passwordVisible
                    ? 'Masquer le mot de passe'
                    : 'Afficher le mot de passe',
                icon: Icon(
                    passwordVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setDialogState(() => passwordVisible = !passwordVisible),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Mettre à jour'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (password == null || !mounted) return;
    setState(() => _authBusy = true);
    try {
      await _authService!.updatePassword(password);
      if (mounted) _showAuthMessage('Mot de passe mis à jour.');
    } on AuthOperationException catch (error) {
      if (mounted) _showAuthMessage(error.displayMessage);
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _storeSignature(Uint8List bytes) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw const FileSystemException(
          'La signature dépasse la taille maximale de 5 Mo.');
    }
    await widget.settings.saveSignatureBytes(bytes);
    final normalizedBytes =
        await File(widget.settings.signaturePath).readAsBytes();
    final user = _currentSupabaseUser;
    if (_supabaseReady && user != null) {
      try {
        await Supabase.instance.client.storage
            .from('admin-documents')
            .uploadBinary(
              '${user.id}/profile/signature.png',
              normalizedBytes,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/png',
              ),
            )
            .timeout(const Duration(seconds: 20));
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Signature enregistrée sur ce téléphone. '
                '${cloudOperationMessage(error)}',
              ),
            ),
          );
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _drawSignature() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const SignaturePadScreen()),
    );
    if (bytes == null || !mounted) return;
    try {
      await _storeSignature(bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signature non enregistrée : $error')),
        );
      }
    }
  }

  Future<void> _importSignature() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null || !mounted) return;
    final extension = picked.extension?.toLowerCase();
    if (!const {'png', 'jpg', 'jpeg'}.contains(extension)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choisissez une image PNG, JPG ou JPEG.'),
      ));
      return;
    }
    final bytes = picked.bytes ??
        (picked.path == null ? null : await File(picked.path!).readAsBytes());
    if (bytes == null) return;
    try {
      await _storeSignature(bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import impossible : $error')),
        );
      }
    }
  }

  Future<void> _removeSignature() async {
    final user = _currentSupabaseUser;
    await widget.settings.removeSignature();
    if (_supabaseReady && user != null) {
      try {
        await Supabase.instance.client.storage
            .from('admin-documents')
            .remove(['${user.id}/profile/signature.png']).timeout(
                const Duration(seconds: 20));
      } catch (_) {
        // La copie locale est supprimée même si le réseau est indisponible.
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentSupabaseUser;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Mon profil',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ces informations seront automatiquement reprises dans vos lettres.',
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        user == null
                            ? Icons.cloud_off_outlined
                            : Icons.cloud_done_rounded,
                        color: user == null
                            ? Theme.of(context).colorScheme.primary
                            : Colors.green,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          user == null
                              ? 'Compte et espace sécurisé'
                              : 'Compte connecté',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (user != null) ...[
                    Text(user.email ?? 'Compte connecté'),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _authBusy ? null : _signOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Se déconnecter'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const Key('auth-change-password'),
                      onPressed: _authBusy ? null : _changePassword,
                      icon: const Icon(Icons.password_rounded),
                      label: const Text('Changer le mot de passe'),
                    ),
                  ] else ...[
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Connexion'),
                          icon: Icon(Icons.login_rounded),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Créer un compte'),
                          icon: Icon(Icons.person_add_alt_1_rounded),
                        ),
                      ],
                      selected: {_createAccountMode},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _createAccountMode = selection.first;
                          _accountPasswordVisible = false;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _accountEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Adresse e-mail du compte',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('profile-auth-password'),
                      controller: _accountPasswordController,
                      obscureText: !_accountPasswordVisible,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          key: const Key('profile-auth-password-visibility'),
                          tooltip: _accountPasswordVisible
                              ? 'Masquer le mot de passe'
                              : 'Afficher le mot de passe',
                          icon: Icon(_accountPasswordVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(() =>
                              _accountPasswordVisible =
                                  !_accountPasswordVisible),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _authBusy ? null : _submitAccount,
                      icon: _authBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              _createAccountMode
                                  ? Icons.person_add_alt_1_rounded
                                  : Icons.login_rounded,
                            ),
                      label: Text(
                        _createAccountMode
                            ? 'Créer mon compte'
                            : 'Se connecter',
                      ),
                    ),
                    if (!_createAccountMode) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        key: const Key('auth-reset-password'),
                        onPressed: _authBusy ? null : _resetPassword,
                        child: const Text('Mot de passe oublié ?'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            key: const Key('profile-signature-section'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.draw_outlined),
                    SizedBox(width: 10),
                    Text('Ma signature',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 10),
                  if (widget.settings.hasSignature) ...[
                    Container(
                      key: const Key('signature-preview'),
                      height: 90,
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.file(File(widget.settings.signaturePath),
                          fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      key: Key('signature-transparent-indicator'),
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 18, color: Colors.green),
                        SizedBox(width: 6),
                        Text('Fond transparent'),
                      ],
                    ),
                    SwitchListTile(
                      key: const Key('auto-signature-switch'),
                      contentPadding: EdgeInsets.zero,
                      value: widget.settings.autoInsertSignature,
                      onChanged: widget.settings.setAutoInsertSignature,
                      title: const Text(
                          'Insérer automatiquement ma signature dans les lettres'),
                    ),
                  ] else
                    const Text('Aucune signature enregistrée.'),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.tonalIcon(
                      key: const Key('draw-signature'),
                      onPressed: _drawSignature,
                      icon: const Icon(Icons.gesture_rounded),
                      label: const Text('Dessiner ma signature'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('import-signature'),
                      onPressed: _importSignature,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Importer une image'),
                    ),
                    if (widget.settings.hasSignature)
                      TextButton.icon(
                        onPressed: _removeSignature,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Supprimer'),
                      ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Apparence',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Choisissez le thème de l’application.'),
                  const SizedBox(height: 14),
                  SegmentedButton<AppThemePreference>(
                    segments: const [
                      ButtonSegment(
                        value: AppThemePreference.system,
                        icon: Icon(Icons.phone_android),
                        label: Text('Auto'),
                      ),
                      ButtonSegment(
                        value: AppThemePreference.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Clair'),
                      ),
                      ButtonSegment(
                        value: AppThemePreference.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Sombre'),
                      ),
                    ],
                    selected: {widget.settings.themePreference},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      widget.settings.setThemePreference(selection.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: widget.settings.comfortMode,
            onChanged: widget.settings.setComfortMode,
            secondary: const Icon(Icons.text_increase),
            title: const Text('Mode confort'),
            subtitle: const Text(
              'Texte plus grand et navigation plus lisible',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: fields['firstName'],
            decoration: InputDecoration(
              labelText: 'Prénom',
              suffixIcon: VoiceInputButton(
                controller: fields['firstName']!,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: fields['lastName'],
            decoration: InputDecoration(
              labelText: 'Nom',
              suffixIcon: VoiceInputButton(
                controller: fields['lastName']!,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: fields['address'],
            decoration: InputDecoration(
              labelText: 'Adresse',
              suffixIcon: VoiceInputButton(
                controller: fields['address']!,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: fields['postalCode'],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Code postal',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: fields['city'],
                  decoration: InputDecoration(
                    labelText: 'Ville',
                    suffixIcon: VoiceInputButton(
                      controller: fields['city']!,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: fields['phone'],
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Téléphone'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: fields['email'],
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-mail'),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.save_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Enregistrer mon profil'),
            ),
          ),
          const SizedBox(height: 20),
          const PrivacyCard(),
        ],
      ),
    );
  }
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
    final sender = capitalizeProfileName('$firstName $lastName');
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
