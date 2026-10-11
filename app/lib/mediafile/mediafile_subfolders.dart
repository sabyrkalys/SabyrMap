/// Subfolder names under the device's mediafile root, shared between
/// IconLibraryScanner (which reads this folder for the waypoint icon
/// picker) and MediaFileFolderScreen (which manages it in-app) so a
/// future rename can't silently desync the two.
const String kCustomTypesSubfolder = 'custom-types';

/// Local map files (.mbtiles) shown in the map catalog.
const String kMapsSubfolder = 'maps';

/// Orthophotos (.mbtiles of aerial imagery): every file here is one
/// territory; the map shows them all at once over the base map.
const String kOrthophotoSubfolder = 'orthophoto';
