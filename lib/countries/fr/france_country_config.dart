import 'package:flutter/widgets.dart';

import '../country_config.dart';

const franceCountryConfig = CountryConfig(
  flavor: 'france',
  countryCode: 'FR',
  applicationName: 'AdminFacile',
  localizedApplicationNames: {'fr': 'AdminFacile'},
  androidApplicationId: 'fr.adminfacile.app',
  primaryLocale: Locale('fr'),
  supportedLocales: [Locale('fr')],
  supportsRightToLeft: false,
  content: CountryContentConfig(
    status: CountryContentStatus.active,
    administrativeOrganizations: [
      AdministrativeOrganizationConfig(
        code: 'service-public',
        displayName: 'Service-Public.fr',
      ),
      AdministrativeOrganizationConfig(code: 'impots', displayName: 'Impôts'),
      AdministrativeOrganizationConfig(code: 'caf', displayName: 'CAF'),
      AdministrativeOrganizationConfig(code: 'cpam', displayName: 'CPAM'),
    ],
    modelPackId: 'fr-core-v1',
    modelAssetPath: 'assets/letters/library.json',
    parameters: {
      'administrativeSystem': 'france',
      'contentMaturity': 'production',
    },
  ),
);
