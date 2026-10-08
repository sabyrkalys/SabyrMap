/// Where the app keeps its files on the device, built from one root so a
/// new location changes every path at once.
///
/// MOCK: waypoints live on the server for now and nothing is written here
/// yet. The root is a placeholder until local storage exists; then it
/// becomes the app's real files folder.
abstract final class StoragePaths {
  static const String _package = 'com.sabyrmap.app';

  static String get root => '/storage/emulated/0/Android/data/$_package/files';

  static String get landmarks => '$root/landmarks';

  static String get unsorted => '$landmarks/Unsorted placemarks';
}
