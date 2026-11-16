import 'station.dart';

class TrainStop {
  final String stationCode;
  final String stationName;
  final String scheduledTime;
  final String estimatedTime;
  final bool departed;
  final String stopStatus;
  final double latitude;
  final double longitude;

  const TrainStop({
    required this.stationCode,
    required this.stationName,
    required this.scheduledTime,
    required this.estimatedTime,
    required this.departed,
    this.stopStatus = 'On Time',
    required this.latitude,
    required this.longitude,
  });

  TrainStop copyWith({
    String? stationCode,
    String? stationName,
    String? scheduledTime,
    String? estimatedTime,
    bool? departed,
    String? stopStatus,
    double? latitude,
    double? longitude,
  }) {
    return TrainStop(
      stationCode: stationCode ?? this.stationCode,
      stationName: stationName ?? this.stationName,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      departed: departed ?? this.departed,
      stopStatus: stopStatus ?? this.stopStatus,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, dynamic> toJson() => {
        'stationCode': stationCode,
        'stationName': stationName,
        'scheduledTime': scheduledTime,
        'estimatedTime': estimatedTime,
        'departed': departed,
        'stopStatus': stopStatus,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory TrainStop.fromJson(Map<String, dynamic> json) {
    final code = (json['stationCode'] ?? 'NY').toString();
    final fallbackStation = getStationByCode(code);
    return TrainStop(
      stationCode: code,
      stationName: (json['stationName'] ?? fallbackStation.name).toString(),
      scheduledTime: (json['scheduledTime'] ?? '').toString(),
      estimatedTime: (json['estimatedTime'] ?? json['scheduledTime'] ?? '').toString(),
      departed: json['departed'] == true,
      stopStatus: (json['stopStatus'] ?? 'On Time').toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? fallbackStation.latitude,
      longitude: (json['longitude'] as num?)?.toDouble() ?? fallbackStation.longitude,
    );
  }
}

class TrainTrip {
  final String trainId;
  final String line;
  final String lineBadge;
  final String originCode;
  final String destinationCode;
  final String finalDestinationName;
  final String departureTime;
  final String arrivalTime;
  final DateTime? departureDateTime;
  final int durationMinutes;
  final String status;
  final String? track;
  final bool isExpress;
  final bool isRecentPastDeparture;
  final String dataSource;
  final List<TrainStop> stops;

  const TrainTrip({
    required this.trainId,
    required this.line,
    required this.lineBadge,
    required this.originCode,
    required this.destinationCode,
    required this.finalDestinationName,
    required this.departureTime,
    required this.arrivalTime,
    this.departureDateTime,
    required this.durationMinutes,
    required this.status,
    this.track,
    required this.isExpress,
    this.isRecentPastDeparture = false,
    required this.dataSource,
    required this.stops,
  });

  bool get hasTrack => track != null && track!.trim().isNotEmpty;

  /// Returns only the stops between [originCode] and [destinationCode] (inclusive).
  List<TrainStop> get commuteStops {
    int startIdx = stops.indexWhere(
      (s) => s.stationCode.toUpperCase() == originCode.toUpperCase(),
    );
    int endIdx = stops.indexWhere(
      (s) => s.stationCode.toUpperCase() == destinationCode.toUpperCase(),
    );
    if (startIdx == -1) startIdx = 0;
    if (endIdx == -1 || endIdx < startIdx) endIdx = stops.length - 1;
    return stops.sublist(startIdx, endIdx + 1);
  }

  /// Total stops after origin up to and including destination.
  int get totalStopCount {
    final slice = commuteStops;
    return slice.length > 1 ? slice.length - 1 : 1;
  }

  /// True when total stops to destination is 4 or fewer (Express).
  bool get isFourOrLessStops => totalStopCount <= 4;

  /// Checks whether this train has already departed the origin station.
  bool hasDepartedOrigin(DateTime now) {
    if (isRecentPastDeparture) return true;
    if (commuteStops.isNotEmpty && commuteStops.first.departed) return true;
    final srcLower = dataSource.toLowerCase();
    final isLiveFeed =
        srcLower.contains('live') || srcLower.contains('raildata');
    if (!isLiveFeed && departureDateTime != null) {
      return now.isAfter(departureDateTime!.add(const Duration(minutes: 1)));
    }
    return false;
  }

  TrainTrip copyWith({
    String? trainId,
    String? line,
    String? lineBadge,
    String? originCode,
    String? destinationCode,
    String? finalDestinationName,
    String? departureTime,
    String? arrivalTime,
    DateTime? departureDateTime,
    int? durationMinutes,
    String? status,
    String? track,
    bool? isExpress,
    bool? isRecentPastDeparture,
    String? dataSource,
    List<TrainStop>? stops,
  }) {
    return TrainTrip(
      trainId: trainId ?? this.trainId,
      line: line ?? this.line,
      lineBadge: lineBadge ?? this.lineBadge,
      originCode: originCode ?? this.originCode,
      destinationCode: destinationCode ?? this.destinationCode,
      finalDestinationName: finalDestinationName ?? this.finalDestinationName,
      departureTime: departureTime ?? this.departureTime,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      departureDateTime: departureDateTime ?? this.departureDateTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      status: status ?? this.status,
      track: track ?? this.track,
      isExpress: isExpress ?? this.isExpress,
      isRecentPastDeparture:
          isRecentPastDeparture ?? this.isRecentPastDeparture,
      dataSource: dataSource ?? this.dataSource,
      stops: stops ?? this.stops,
    );
  }

  Map<String, dynamic> toJson() => {
        'trainId': trainId,
        'line': line,
        'lineBadge': lineBadge,
        'originCode': originCode,
        'destinationCode': destinationCode,
        'finalDestinationName': finalDestinationName,
        'departureTime': departureTime,
        'arrivalTime': arrivalTime,
        'departureDateTime': departureDateTime?.toIso8601String(),
        'durationMinutes': durationMinutes,
        'status': status,
        'track': track,
        'isExpress': isExpress,
        'isRecentPastDeparture': isRecentPastDeparture,
        'dataSource': dataSource,
        'stops': stops.map((s) => s.toJson()).toList(),
      };

  factory TrainTrip.fromJson(Map<String, dynamic> json) {
    final rawStops = (json['stops'] as List?) ?? const [];
    return TrainTrip(
      trainId: (json['trainId'] ?? '3800').toString(),
      line: (json['line'] ?? 'Northeast Corridor').toString(),
      lineBadge: (json['lineBadge'] ?? 'NEC').toString(),
      originCode: (json['originCode'] ?? 'NY').toString(),
      destinationCode: (json['destinationCode'] ?? 'MP').toString(),
      finalDestinationName: (json['finalDestinationName'] ?? 'Trenton').toString(),
      departureTime: (json['departureTime'] ?? '').toString(),
      arrivalTime: (json['arrivalTime'] ?? '').toString(),
      departureDateTime: json['departureDateTime'] != null
          ? DateTime.tryParse(json['departureDateTime'].toString())
          : null,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 38,
      status: (json['status'] ?? 'On Time').toString(),
      track: json['track']?.toString(),
      isExpress: json['isExpress'] == true,
      isRecentPastDeparture: json['isRecentPastDeparture'] == true,
      dataSource: (json['dataSource'] ?? 'NEC Smart Schedule').toString(),
      stops: rawStops
          .map((e) => TrainStop.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
