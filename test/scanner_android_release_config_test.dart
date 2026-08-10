import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V20.3.1 conserve les constructeurs des registrars ML Kit en release',
      () {
    final rules = File('android/app/proguard-rules.pro').readAsStringSync();
    expect(
      rules,
      contains(
        '-keepclassmembers class * implements '
        'com.google.firebase.components.ComponentRegistrar',
      ),
    );
    expect(rules, contains('public <init>();'));
  });

  test('V20.3.1 protège et journalise chaque étape native critique', () {
    final source = File(
      'android/app/src/main/kotlin/fr/adminfacile/app/MainActivity.kt',
    ).readAsStringSync();

    for (final step in [
      'options_create',
      'options_ready',
      'client_create',
      'client_ready',
      'intent_sender_create',
      'intent_sender_ready',
      'activity_launched',
      'activity_result',
    ]) {
      expect(source, contains('logStep("$step"'), reason: step);
    }
    for (final code in [
      'MLKIT_OPTIONS_FAILED',
      'MLKIT_CLIENT_FAILED',
      'MLKIT_INTENT_FAILED',
      'MLKIT_LAUNCH_FAILED',
      'MLKIT_UNAVAILABLE',
    ]) {
      expect(source, contains('"$code"'), reason: code);
    }
    expect(source, contains('catch (error: Throwable)'));
    expect(source, contains('SCANNER_NATIVE id='));
  });

  test('V20.3.1 utilise le scanner ML Kit et la version Android attendus', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(
      gradle,
      contains(
        'com.google.android.gms:play-services-mlkit-document-scanner:16.0.0',
      ),
    );
    expect(gradle, contains('applicationId = "fr.adminfacile.app"'));
    expect(pubspec, contains('version: 20.3.1+84'));
  });
}
