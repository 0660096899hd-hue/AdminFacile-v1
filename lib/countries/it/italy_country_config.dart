import 'package:flutter/widgets.dart';

import '../country_config.dart';

const italyCountryConfig = CountryConfig(
  flavor: 'italy',
  countryCode: 'IT',
  applicationName: 'Amministrazione Facile',
  localizedApplicationNames: {'it': 'Amministrazione Facile'},
  androidApplicationId: 'it.adminfacile.app',
  primaryLocale: Locale('it'),
  supportedLocales: [Locale('it')],
  supportsRightToLeft: false,
  content: CountryContentConfig(
    status: CountryContentStatus.placeholder,
    administrativeOrganizations: [
      AdministrativeOrganizationConfig(
        code: 'pubblica-amministrazione',
        displayName: 'Pubblica Amministrazione',
      ),
    ],
    modelPackId: 'it-placeholder-v1',
    parameters: {
      'administrativeSystem': 'italy',
      'contentMaturity': 'placeholder',
    },
  ),
);
