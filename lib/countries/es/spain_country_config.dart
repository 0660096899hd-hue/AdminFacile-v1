import 'package:flutter/widgets.dart';

import '../country_config.dart';

const spainCountryConfig = CountryConfig(
  flavor: 'spain',
  countryCode: 'ES',
  applicationName: 'AdminFácil',
  localizedApplicationNames: {'es': 'AdminFácil'},
  androidApplicationId: 'es.adminfacile.app',
  primaryLocale: Locale('es'),
  supportedLocales: [Locale('es')],
  supportsRightToLeft: false,
  content: CountryContentConfig(
    status: CountryContentStatus.placeholder,
    administrativeOrganizations: [
      AdministrativeOrganizationConfig(
        code: 'administracion-general',
        displayName: 'Administración pública',
      ),
    ],
    modelPackId: 'es-placeholder-v1',
    parameters: {
      'administrativeSystem': 'spain',
      'contentMaturity': 'placeholder',
    },
  ),
);
