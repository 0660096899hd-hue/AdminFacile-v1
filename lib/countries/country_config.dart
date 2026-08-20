import 'package:flutter/widgets.dart';

enum CountryContentStatus { active, placeholder }

class AdministrativeOrganizationConfig {
  const AdministrativeOrganizationConfig({
    required this.code,
    required this.displayName,
  });

  final String code;
  final String displayName;
}

class CountryContentConfig {
  const CountryContentConfig({
    required this.status,
    required this.administrativeOrganizations,
    required this.modelPackId,
    required this.parameters,
    this.modelAssetPath,
  });

  final CountryContentStatus status;
  final List<AdministrativeOrganizationConfig> administrativeOrganizations;
  final String modelPackId;
  final String? modelAssetPath;
  final Map<String, String> parameters;
}

class CountryConfig {
  const CountryConfig({
    required this.flavor,
    required this.countryCode,
    required this.applicationName,
    required this.localizedApplicationNames,
    required this.androidApplicationId,
    required this.primaryLocale,
    required this.supportedLocales,
    required this.supportsRightToLeft,
    required this.content,
  });

  final String flavor;
  final String countryCode;
  final String applicationName;
  final Map<String, String> localizedApplicationNames;
  final String androidApplicationId;
  final Locale primaryLocale;
  final List<Locale> supportedLocales;
  final bool supportsRightToLeft;
  final CountryContentConfig content;

  Locale resolveLocale(List<Locale>? preferredLocales) {
    for (final preferred in preferredLocales ?? const <Locale>[]) {
      for (final supported in supportedLocales) {
        if (preferred.languageCode == supported.languageCode) return supported;
      }
    }
    return primaryLocale;
  }

  bool usesRightToLeft(Locale locale) =>
      supportsRightToLeft && locale.languageCode == 'ar';

  String applicationNameFor(Locale locale) =>
      localizedApplicationNames[locale.languageCode] ?? applicationName;
}
