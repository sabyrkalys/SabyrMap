import 'package:app/intents/intent_kind.dart';
import 'package:app/intents/intent_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every known action, with any namespace', () {
    final cases = {
      'app.sabyrmap.intent.action.DISPLAY_LOCATION': IntentKind.displayLocation,
      'DISPLAY_LOCATION': IntentKind.displayLocation,
      'x.LANDMARKS_FAST_WAYPOINT': IntentKind.fastWaypoint,
      'TRACKER_START': IntentKind.trackerStart,
      'TRACKER_STOP': IntentKind.trackerStop,
      'TRACKER_ADD_WAYPOINT': IntentKind.trackerAddWaypoint,
      'APP_STOP': IntentKind.appStop,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(IntentParser.parse(const {}, action: key).kind, value, reason: key);
    }
  });

  test('unknown or missing action', () {
    expect(IntentParser.parse(const {}, action: 'android.intent.action.VIEW').kind, IntentKind.unknown);
    expect(IntentParser.parse(const {}).kind, IntentKind.unknown);
  });

  test('extras in upper and lower case, numbers or strings', () {
    final upper = IntentParser.parse({
      'LATITUDE': 50.45,
      'LONGITUDE': '30.52',
      'ELEVATION': 179,
      'NAME': 'Bunker',
      'COMMENT': 'north',
      'MOVE_TO': true,
      'TIME': 1760000000,
    }, action: 'DISPLAY_LOCATION');
    expect((upper.location!.latitude, upper.location!.longitude), (50.45, 30.52));
    expect(upper.elevationMeters, 179);
    expect(upper.name, 'Bunker');
    expect(upper.comment, 'north');
    expect(upper.moveTo, isTrue);
    expect(upper.timestampSec, 1760000000);

    final lower = IntentParser.parse({'latitude': '50.45', 'longitude': 30.52, 'icon': 'flag', 'set_id': 's1', 'move_to': '1'});
    expect(lower.location!.latitude, 50.45);
    expect(lower.iconId, 'flag');
    expect(lower.setId, 's1');
    expect(lower.moveTo, isTrue);
  });

  test('invalid coordinates give no location', () {
    expect(IntentParser.parse({'latitude': 95, 'longitude': 30}).location, isNull);
    expect(IntentParser.parse({'latitude': 'x', 'longitude': 30}).location, isNull);
    expect(IntentParser.parse({'latitude': 50}).location, isNull);
  });
}
