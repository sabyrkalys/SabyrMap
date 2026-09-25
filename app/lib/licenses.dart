import 'package:flutter/foundation.dart';

bool _registered = false;

/// Licences of bundled third-party assets that pub packages don't cover.
/// Shown on Flutter's standard licences page.
void registerThirdPartyLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Material Design Icons (sunrise, sunset)'],
      'assets/icons/sunrise.svg and assets/icons/sunset.svg are the icons '
      '"weather-sunset-up" and "weather-sunset-down" from Material Design Icons '
      'by Pictogrammers (https://pictogrammers.com), reformatted.\n\n'
      'Licensed under the Apache License, Version 2.0 (the "License"); you may '
      'not use these files except in compliance with the License. You may obtain '
      'a copy of the License at\n\n'
      '    http://www.apache.org/licenses/LICENSE-2.0\n\n'
      'Unless required by applicable law or agreed to in writing, software '
      'distributed under the License is distributed on an "AS IS" BASIS, '
      'WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. '
      'See the License for the specific language governing permissions and '
      'limitations under the License.',
    );
  });
}
