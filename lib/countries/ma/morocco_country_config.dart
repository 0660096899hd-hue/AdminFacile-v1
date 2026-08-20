import 'package:flutter/widgets.dart';

import '../country_config.dart';

const moroccoCountryConfig = CountryConfig(
  flavor: 'morocco',
  countryCode: 'MA',
  applicationName: 'AdminFacile Maroc',
  localizedApplicationNames: {
    'fr': 'AdminFacile Maroc',
    'ar': 'إدارة سهلة',
  },
  androidApplicationId: 'ma.adminfacile.app',
  primaryLocale: Locale('fr'),
  supportedLocales: [Locale('fr'), Locale('ar')],
  supportsRightToLeft: true,
  content: CountryContentConfig(
    status: CountryContentStatus.placeholder,
    administrativeOrganizations: [
      AdministrativeOrganizationConfig(
        code: 'administration-maroc',
        displayName: 'Administration marocaine',
      ),
    ],
    modelPackId: 'ma-placeholder-v1',
    parameters: {
      'administrativeSystem': 'morocco',
      'contentMaturity': 'placeholder',
    },
  ),
);
