import 'dart:math' as math;

class Station {
  final String code;
  final String dvCode;
  final String name;
  final String shortName;
  final String line;
  final double latitude;
  final double longitude;
  final int necOrder; // Order along Northeast Corridor (0 = NY Penn -> 15 = Trenton)

  const Station({
    required this.code,
    String? dvCode,
    required this.name,
    required this.shortName,
    required this.line,
    required this.latitude,
    required this.longitude,
    required this.necOrder,
  }) : dvCode = dvCode ?? code;

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
        'dvCode': dvCode,
        'name': name,
        'shortName': shortName,
        'line': line,
        'latitude': latitude,
        'longitude': longitude,
        'necOrder': necOrder,
      };
}

/// Complete bundled NJ Transit Northeast Corridor & key commuter stations
/// with accurate platform GPS coordinates and official NJT 2-char station codes.
const List<Station> kNjtStations = [
  Station(
    code: 'NY',
    dvCode: 'NY',
    name: 'New York Penn Station',
    shortName: 'NY Penn',
    line: 'Northeast Corridor',
    latitude: 40.750568,
    longitude: -73.993519,
    necOrder: 0,
  ),
  Station(
    code: 'SE',
    dvCode: 'SE',
    name: 'Secaucus Junction',
    shortName: 'Secaucus',
    line: 'Northeast Corridor',
    latitude: 40.761250,
    longitude: -74.075820,
    necOrder: 1,
  ),
  Station(
    code: 'NP',
    dvCode: 'NP',
    name: 'Newark Penn Station',
    shortName: 'Newark Penn',
    line: 'Northeast Corridor',
    latitude: 40.734200,
    longitude: -74.164500,
    necOrder: 2,
  ),
  Station(
    code: 'NA',
    dvCode: 'NA',
    name: 'Newark Liberty Airport',
    shortName: 'Newark Airport',
    line: 'Northeast Corridor',
    latitude: 40.704440,
    longitude: -74.190690,
    necOrder: 3,
  ),
  Station(
    code: 'NE',
    dvCode: 'NZ',
    name: 'North Elizabeth',
    shortName: 'N. Elizabeth',
    line: 'Northeast Corridor',
    latitude: 40.680100,
    longitude: -74.205400,
    necOrder: 4,
  ),
  Station(
    code: 'EZ',
    dvCode: 'EZ',
    name: 'Elizabeth',
    shortName: 'Elizabeth',
    line: 'Northeast Corridor',
    latitude: 40.667700,
    longitude: -74.215000,
    necOrder: 5,
  ),
  Station(
    code: 'LI',
    dvCode: 'LI',
    name: 'Linden',
    shortName: 'Linden',
    line: 'Northeast Corridor',
    latitude: 40.629300,
    longitude: -74.251900,
    necOrder: 6,
  ),
  Station(
    code: 'RA',
    dvCode: 'RH',
    name: 'Rahway',
    shortName: 'Rahway',
    line: 'Northeast Corridor',
    latitude: 40.606400,
    longitude: -74.276800,
    necOrder: 7,
  ),
  Station(
    code: 'MP',
    dvCode: 'MP',
    name: 'Metropark',
    shortName: 'Metropark',
    line: 'Northeast Corridor',
    latitude: 40.568650,
    longitude: -74.329680,
    necOrder: 8,
  ),
  Station(
    code: 'MC',
    dvCode: 'MU',
    name: 'Metuchen',
    shortName: 'Metuchen',
    line: 'Northeast Corridor',
    latitude: 40.540700,
    longitude: -74.360600,
    necOrder: 9,
  ),
  Station(
    code: 'ED',
    dvCode: 'ED',
    name: 'Edison',
    shortName: 'Edison',
    line: 'Northeast Corridor',
    latitude: 40.518600,
    longitude: -74.412200,
    necOrder: 10,
  ),
  Station(
    code: 'NB',
    dvCode: 'NB',
    name: 'New Brunswick',
    shortName: 'New Brunswick',
    line: 'Northeast Corridor',
    latitude: 40.496600,
    longitude: -74.446000,
    necOrder: 11,
  ),
  Station(
    code: 'JA',
    dvCode: 'JA',
    name: 'Jersey Ave',
    shortName: 'Jersey Ave',
    line: 'Northeast Corridor',
    latitude: 40.476500,
    longitude: -74.467300,
    necOrder: 12,
  ),
  Station(
    code: 'PJ',
    dvCode: 'PJ',
    name: 'Princeton Junction',
    shortName: 'Princeton Jct',
    line: 'Northeast Corridor',
    latitude: 40.316800,
    longitude: -74.623100,
    necOrder: 13,
  ),
  Station(
    code: 'HL',
    dvCode: 'HL',
    name: 'Hamilton',
    shortName: 'Hamilton',
    line: 'Northeast Corridor',
    latitude: 40.255200,
    longitude: -74.725500,
    necOrder: 14,
  ),
  Station(
    code: 'TR',
    dvCode: 'TR',
    name: 'Trenton Transit Center',
    shortName: 'Trenton',
    line: 'Northeast Corridor',
    latitude: 40.218500,
    longitude: -74.754400,
    necOrder: 15,
  ),
  Station(
    code: 'HB',
    dvCode: 'HB',
    name: 'Hoboken Terminal',
    shortName: 'Hoboken',
    line: 'Main / Bergen / M&E',
    latitude: 40.734900,
    longitude: -74.027800,
    necOrder: 100,
  ),
  Station(
    code: 'NW',
    dvCode: 'ND',
    name: 'Newark Broad Street',
    shortName: 'Newark Broad',
    line: 'Morris & Essex',
    latitude: 40.747500,
    longitude: -74.171900,
    necOrder: 101,
  ),
  Station(
    code: 'WO',
    dvCode: 'WB',
    name: 'Woodbridge',
    shortName: 'Woodbridge',
    line: 'North Jersey Coast',
    latitude: 40.556700,
    longitude: -74.277500,
    necOrder: 201,
  ),
  Station(
    code: 'SA',
    dvCode: 'CH',
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
  for (final s in kNjtStations) {
    if (s.dvCode.toUpperCase() == upper) return s;
  }
  return kNjtStations.first;
}

const Map<String, String> _kStationNameAliases = {
  'new york penn station': 'NY',
  'new york penn': 'NY',
  'new york': 'NY',
  'ny penn station': 'NY',
  'ny penn': 'NY',
  'nyp': 'NY',
  'secaucus upper lvl': 'SE',
  'secaucus upper level': 'SE',
  'secaucus lower lvl': 'SE',
  'secaucus lower level': 'SE',
  'secaucus junction': 'SE',
  'secaucus jct': 'SE',
  'secaucus': 'SE',
  'newark penn station': 'NP',
  'newark penn': 'NP',
  'newark airport': 'NA',
  'newark liberty airport': 'NA',
  'newark intl airport': 'NA',
  'newark international airport': 'NA',
  'north elizabeth': 'NE',
  'n elizabeth': 'NE',
  'elizabeth': 'EZ',
  'linden': 'LI',
  'rahway': 'RA',
  'metropark': 'MP',
  'metuchen': 'MC',
  'edison': 'ED',
  'new brunswick': 'NB',
  'jersey avenue': 'JA',
  'jersey ave': 'JA',
  'princeton junction': 'PJ',
  'princeton jct': 'PJ',
  'hamilton': 'HL',
  'trenton transit center': 'TR',
  'trenton': 'TR',
  'hoboken terminal': 'HB',
  'hoboken': 'HB',
  'newark broad street': 'NW',
  'newark broad st': 'NW',
  'newark broad': 'NW',
  'woodbridge': 'WO',
  'south amboy': 'SA',
};

String _normalizeStationLookupKey(String raw) {
  return raw
      .replaceAll(RegExp(r'&#\d+;?'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+-SEC\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'-BH\b', caseSensitive: false), '')
      .replaceAll('.', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}

Station? findStationByNameOrCode(String raw) {
  final clean = _normalizeStationLookupKey(raw);
  if (clean.isEmpty) return null;

  // 1. Exact app code or NJT DepartureVision 2-char code match
  for (final s in kNjtStations) {
    if (s.code.toLowerCase() == clean || s.dvCode.toLowerCase() == clean) {
      return s;
    }
  }

  // 2. Explicit NJ Transit DepartureVision / RailData alias table
  final mappedCode = _kStationNameAliases[clean];
  if (mappedCode != null) {
    return getStationByCode(mappedCode);
  }

  // 3. Exact station name or shortName match
  for (final s in kNjtStations) {
    if (_normalizeStationLookupKey(s.name) == clean ||
        _normalizeStationLookupKey(s.shortName) == clean) {
      return s;
    }
  }

  // 4. Controlled fallback: check longest station names first so
  // "north elizabeth" never steals "elizabeth" and "newark penn" never steals "penn".
  final sortedByNameLen = List<Station>.from(kNjtStations)
    ..sort((a, b) => b.name.length.compareTo(a.name.length));
  for (final s in sortedByNameLen) {
    final normName = _normalizeStationLookupKey(s.name);
    final normShort = _normalizeStationLookupKey(s.shortName);
    if (clean.contains(normName) || clean.contains(normShort)) {
      return s;
    }
  }
  return null;
}
