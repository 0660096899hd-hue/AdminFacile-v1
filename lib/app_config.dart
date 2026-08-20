import 'package:flutter/services.dart' show appFlavor;

import 'countries/country_config.dart';
import 'countries/country_registry.dart';

class AppConfig {
  const AppConfig._(this.country);

  final CountryConfig country;

  static AppConfig forFlavor(String? flavor) =>
      AppConfig._(CountryRegistry.resolve(flavor));
}

final AppConfig appConfig = AppConfig.forFlavor(appFlavor);
