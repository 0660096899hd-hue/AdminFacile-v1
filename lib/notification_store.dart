import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppNotificationType {
  deadline,
  procedureAction,
  documentAdded,
  synchronized,
  synchronizationError,
  documentAction,
  reminder,
  account,
}

enum NotificationTargetType { document, procedure, account }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.createdAt,
    this.read = false,
    this.targetType,
    this.targetId,
  });

  final String id;
  final AppNotificationType type;
  final String message;
  final DateTime createdAt;
  final bool read;
  final NotificationTargetType? targetType;
  final String? targetId;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        message: message,
        createdAt: createdAt,
        read: read ?? this.read,
        targetType: targetType,
        targetId: targetId,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
        'targetType': targetType?.name,
        'targetId': targetId,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? '';
    final targetName = json['targetType'] as String?;
    return AppNotification(
      id: json['id'] as String,
      type: AppNotificationType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => AppNotificationType.reminder,
      ),
      message: json['message'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      read: json['read'] as bool? ?? false,
      targetType: targetName == null
          ? null
          : NotificationTargetType.values
              .cast<NotificationTargetType?>()
              .firstWhere(
                (value) => value?.name == targetName,
                orElse: () => null,
              ),
      targetId: json['targetId'] as String?,
    );
  }
}

class NotificationStore extends ChangeNotifier {
  static const _storageKey = 'appNotificationsV204';
  SharedPreferences? _prefs;
  final List<AppNotification> _items = [];

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((item) => !item.read).length;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _items
        ..clear()
        ..addAll(decoded.map((item) => AppNotification.fromJson(
              Map<String, dynamic>.from(item as Map),
            )));
      _sort();
    } catch (_) {
      _items.clear();
    }
  }

  Future<void> add(AppNotification notification) async {
    final index = _items.indexWhere((item) => item.id == notification.id);
    if (index >= 0) {
      _items[index] = notification;
    } else {
      _items.add(notification);
    }
    _sort();
    await _persist();
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || _items[index].read) return;
    _items[index] = _items[index].copyWith(read: true);
    await _persist();
    notifyListeners();
  }

  Future<void> markAllRead() async {
    if (unreadCount == 0) return;
    for (var index = 0; index < _items.length; index++) {
      _items[index] = _items[index].copyWith(read: true);
    }
    await _persist();
    notifyListeners();
  }

  void _sort() => _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> _persist() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_items.map((item) => item.toJson()).toList()),
    );
  }
}
