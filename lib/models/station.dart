import 'dart:math' as math;

class Station {
  final String code;
  final String name;
  final String shortName;
  final String line;
  final double latitude;
  final double longitude;
  final int necOrder; // Order along Northeast Corridor (0 = NY Penn -> 15 = Trenton)

  const Station({
    required this.code,
    required this.name,
    required this.shortName,
    required this.line,
    required this.latitude,
    required this.longitude,
    required this.necOrder,
  });

  double distanceMetersTo(double lat, double lng) {
    const double earthRadius = 6371000; // meters
    final double dLat = _degToRad(lat - latitude);
    final double dLon = _degToRad(lng - longitude);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(latitude)) *
            math.cos(_degToRad(lat)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'shortName': shortName,
        'line': line,
        'latitude': latitude,
        'longitude': longitude,
        'necOrder': necOrder,
      };
}

/// Complete bundled NJ Transit Northeast Corridor & key commuter stations
/// with accurate platform GPS coordinates for offline/hybrid geofencing.
const List<Station> kNjtStations = [
  Station(
    code: 'NY',
    name: 'New York Penn Station',
    shortName: 'NY Penn',
    line: 'Northeast Corridor',
    latitude: 40.750568,
    longitude: -73.993519,
    necOrder: 0,
  ),
  Station(
    code: 'SE',
    name: 'Secaucus Junction',
    shortName: 'Secaucus',
    line: 'Northeast Corridor',
    latitude: 40.761250,
    longitude: -74.075820,
    necOrder: 1,
  ),
  Station(
    code: 'NP',
    name: 'Newark Penn Station',
    shortName: 'Newark Penn',
    line: 'Northeast Corridor',
    latitude: 40.734200,
    longitude: -74.164500,
    necOrder: 2,
  ),
  Station(
    code: 'NA',
    name: 'Newark Liberty Airport',
    shortName: 'Newark Airport',
    line: 'Northeast Corridor',
    latitude: 40.704440,
    longitude: -74.190690,
    necOrder: 3,
  ),
  Station(
    code: 'NE',
    name: 'North Elizabeth',
    shortName: 'N. Elizabeth',
    line: 'Northeast Corridor',
    latitude: 40.680100,
    longitude: -74.205400,
    necOrder: 4,
  ),
  Station(
    code: 'EZ',
    name: 'Elizabeth',
    shortName: 'Elizabeth',
    line: 'Northeast Corridor',
    latitude: 40.667700,
    longitude: -74.215000,
    necOrder: 5,
  ),
  Station(
    code: 'LI',
    name: 'Linden',
    shortName: 'Linden',
    line: 'Northeast Corridor',
    latitude: 40.629300,
    longitude: -74.251900,
    necOrder: 6,
  ),
  Station(
    code: 'RA',
    name: 'Rahway',
    shortName: 'Rahway',
    line: 'Northeast Corridor',
    latitude: 40.606400,
    longitude: -74.276800,
    necOrder: 7,
  ),
  Station(
    code: 'MP',
    name: 'Metropark',
    shortName: 'Metropark',
    line: 'Northeast Corridor',
    latitude: 40.568650,
    longitude: -74.329680,
    necOrder: 8,
  ),
  Station(
    code: 'MC',
    name: 'Metuchen',
    shortName: 'Metuchen',
    line: 'Northeast Corridor',
    latitude: 40.540700,
    longitude: -74.360600,
    necOrder: 9,
  ),
  Station(
    code: 'ED',
    name: 'Edison',
    shortName: 'Edison',
    line: 'Northeast Corridor',
    latitude: 40.518600,
    longitude: -74.412200,
    necOrder: 10,
  ),
  Station(
    code: 'NB',
    name: 'New Brunswick',
    shortName: 'New Brunswick',
    line: 'Northeast Corridor',
    latitude: 40.496600,
    longitude: -74.446000,
    necOrder: 11,
  ),
  Station(
    code: 'JA',
    name: 'Jersey Ave',
    shortName: 'Jersey Ave',
    line: 'Northeast Corridor',
    latitude: 40.476500,
    longitude: -74.467300,
    necOrder: 12,
  ),
  Station(
    code: 'PJ',
    name: 'Princeton Junction',
    shortName: 'Princeton Jct',
    line: 'Northeast Corridor',
    latitude: 40.316800,
    longitude: -74.623100,
    necOrder: 13,
  ),
  Station(
    code: 'HL',
    name: 'Hamilton',
    shortName: 'Hamilton',
    line: 'Northeast Corridor',
    latitude: 40.255200,
    longitude: -74.725500,
    necOrder: 14,
  ),
  Station(
    code: 'TR',
    name: 'Trenton Transit Center',
    shortName: 'Trenton',
    line: 'Northeast Corridor',
    latitude: 40.218500,
    longitude: -74.754400,
    necOrder: 15,
  ),
  Station(
    code: 'HB',
    name: 'Hoboken Terminal',
    shortName: 'Hoboken',
    line: 'Main / Bergen / M&E',
    latitude: 40.734900,
    longitude: -74.027800,
    necOrder: 100,
  ),
  Station(
    code: 'NW',
    name: 'Newark Broad Street',
    shortName: 'Newark Broad',
    line: 'Morris & Essex',
    latitude: 40.747500,
    longitude: -74.171900,
    necOrder: 101,
  ),
  Station(
    code: 'WO',
    name: 'Woodbridge',
    shortName: 'Woodbridge',
    line: 'North Jersey Coast',
    latitude: 40.556700,
    longitude: -74.277500,
    necOrder: 201,
  ),
  Station(
    code: 'SA',
    name: 'South Amboy',
    shortName: 'South Amboy',
    line: 'North Jersey Coast',
    latitude: 40.484600,
    longitude: -74.281700,
    necOrder: 202,
  ),
];

Station getStationByCode(String code) {
  final upper = code.trim().toUpperCase();
  for (final s in kNjtStations) {
    if (s.code.toUpperCase() == upper) return s;
  }
  return kNjtStations.first;
}

Station? findStationByNameOrCode(String raw) {
  final clean = raw.trim().toLowerCase();
  if (clean.isEmpty) return null;
  for (final s in kNjtStations) {
    if (s.code.toLowerCase() == clean ||
        s.name.toLowerCase() == clean ||
        s.shortName.toLowerCase() == clean ||
        clean.contains(s.shortName.toLowerCase()) ||
        s.name.toLowerCase().contains(clean)) {
      return s;
    }
  }
  return null;
}
