import 'package:app/landmarks/models/landmark_location.dart';
import 'package:app/landmarks/settings/app_settings.dart';
import 'package:app/maps/settings/maps_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

LandmarkLocation loc(double lat, double lon) => LandmarkLocation(latitude: lat, longitude: lon);

Future<AppSettings> freshSettings() async {
  SharedPreferences.setMockInitialValues({});
  return AppSettings(await SharedPreferences.getInstance());
}

Future<MapsSettings> freshMapsSettings() async => MapsSettings(await freshSettings());
