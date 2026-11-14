class NotificationRules {
  final bool notifyEveryStop;
  final int startNotifyingStopsAway; // e.g., 2 stops away
  final bool notifyOnTrackAssigned;
  final bool finalWakeUpAlarm;
  final double gpsStationRadiusMeters; // e.g., 550m geofence radius
  final bool vibrateOnAlerts;
  final String mascotPersonality; // 'mygo' (cool/band), 'sakura' (genki conductor)

  const NotificationRules({
    this.notifyEveryStop = false,
    this.startNotifyingStopsAway = 2,
    this.notifyOnTrackAssigned = true,
    this.finalWakeUpAlarm = true,
    this.gpsStationRadiusMeters = 550.0,
    this.vibrateOnAlerts = true,
    this.mascotPersonality = 'mygo',
  });

  NotificationRules copyWith({
    bool? notifyEveryStop,
    int? startNotifyingStopsAway,
    bool? notifyOnTrackAssigned,
    bool? finalWakeUpAlarm,
    double? gpsStationRadiusMeters,
    bool? vibrateOnAlerts,
    String? mascotPersonality,
  }) {
    return NotificationRules(
      notifyEveryStop: notifyEveryStop ?? this.notifyEveryStop,
      startNotifyingStopsAway:
          startNotifyingStopsAway ?? this.startNotifyingStopsAway,
      notifyOnTrackAssigned:
          notifyOnTrackAssigned ?? this.notifyOnTrackAssigned,
      finalWakeUpAlarm: finalWakeUpAlarm ?? this.finalWakeUpAlarm,
      gpsStationRadiusMeters:
          gpsStationRadiusMeters ?? this.gpsStationRadiusMeters,
      vibrateOnAlerts: vibrateOnAlerts ?? this.vibrateOnAlerts,
      mascotPersonality: mascotPersonality ?? this.mascotPersonality,
    );
  }

  Map<String, dynamic> toJson() => {
        'notifyEveryStop': notifyEveryStop,
        'startNotifyingStopsAway': startNotifyingStopsAway,
        'notifyOnTrackAssigned': notifyOnTrackAssigned,
        'finalWakeUpAlarm': finalWakeUpAlarm,
        'gpsStationRadiusMeters': gpsStationRadiusMeters,
        'vibrateOnAlerts': vibrateOnAlerts,
        'mascotPersonality': mascotPersonality,
      };

  factory NotificationRules.fromJson(Map<String, dynamic> json) {
    return NotificationRules(
      notifyEveryStop: json['notifyEveryStop'] == true,
      startNotifyingStopsAway:
          (json['startNotifyingStopsAway'] as num?)?.toInt().clamp(1, 10) ?? 2,
      notifyOnTrackAssigned: json['notifyOnTrackAssigned'] != false,
      finalWakeUpAlarm: json['finalWakeUpAlarm'] != false,
      gpsStationRadiusMeters:
          (json['gpsStationRadiusMeters'] as num?)?.toDouble() ?? 550.0,
      vibrateOnAlerts: json['vibrateOnAlerts'] != false,
      mascotPersonality: (json['mascotPersonality'] ?? 'mygo').toString(),
    );
  }
}
