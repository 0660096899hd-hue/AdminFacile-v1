import 'country_config.dart';
import 'es/spain_country_config.dart';
import 'fr/france_country_config.dart';
import 'it/italy_country_config.dart';
import 'ma/morocco_country_config.dart';

class CountryRegistry {
  const CountryRegistry._();

  static const Map<String, CountryConfig> byFlavor = {
    'france': franceCountryConfig,
    'spain': spainCountryConfig,
    'italy': italyCountryConfig,
    'morocco': moroccoCountryConfig,
  };

  static CountryConfig resolve(String? flavor) {
    if (flavor == null || flavor.trim().isEmpty) return franceCountryConfig;
    final config = byFlavor[flavor.trim().toLowerCase()];
    if (config == null) {
      throw UnsupportedError('Flavor pays non pris en charge : $flavor');
    }
    return config;
  }
}
