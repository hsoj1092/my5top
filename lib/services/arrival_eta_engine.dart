import 'dart:math' as math;

class GpsTelemetrySample {
  final double latitude;
  final double longitude;
  final double speedMps;
  final double accuracyMeters;
  final int timestampEpochMs;

  const GpsTelemetrySample({
    required this.latitude,
    required this.longitude,
    required this.speedMps,
    required this.accuracyMeters,
    required this.timestampEpochMs,
  });
}

class ArrivalEtaEstimate {
  final double? estimatedSeconds;
  final double? distanceMeters;
  final double? closingSpeedMps;
  final double? speedMph;
  final int delayOffsetSeconds;
  final int? liveArrivalEpochMs;
  final bool isGpsFresh;
  final bool isHoldingAtSignal;
  final bool isPrecisionMode;
  final String sourceLabel;
  final bool shouldFireApproaching;
  final bool shouldFireArriving;
  final bool shouldMarkPlatformArrived;

  const ArrivalEtaEstimate({
    required this.estimatedSeconds,
    required this.distanceMeters,
    required this.closingSpeedMps,
    required this.speedMph,
    required this.delayOffsetSeconds,
    required this.liveArrivalEpochMs,
    required this.isGpsFresh,
    required this.isHoldingAtSignal,
    required this.isPrecisionMode,
    required this.sourceLabel,
    required this.shouldFireApproaching,
    required this.shouldFireArriving,
    required this.shouldMarkPlatformArrived,
  });

  int? get roundedSeconds =>
      estimatedSeconds == null ? null : estimatedSeconds!.round().clamp(0, 86400);
}

/// Multi-signal commuter rail arrival estimator combining:
/// 1. High-frequency GPS radial closing velocity + Doppler speed,
/// 2. NJ Transit commuter rail service braking kinematics (~0.72 m/s²),
/// 3. Live stop-pass delay calibration (essential for underground tunnels like
///    the Hudson River Tunnels into NY Penn where GPS drops out completely),
/// 4. Signal-hold detection (prevents false "Arriving" while stopped at red signals),
/// 5. 2-part final arrival triggers:
///    - Part 1 ("Approaching"): ~60s before platform stop
///    - Part 2 ("Arriving"):    ~10s before platform stop (12s threshold w/ audio latency buffer)
class ArrivalEtaEngine {
  static const double serviceBrakingDecelMps2 = 0.72; // ~1.6 mph/s NJT service braking
  static const double maxNecSpeedMps = 38.0; // ~85 mph sanity cap
  static const double platformLeadMeters = 45.0; // Train length / platform-entry lead
  static const double approachingThresholdSeconds = 62.0; // Targets ~1 min before stop
  static const double arrivingThresholdSeconds = 12.0; // Targets ~10s before stop (+2s audio buffer)
  static const double gpsFreshMaxAgeSeconds = 14.0;
  static const double gpsDeadReckoningMaxAgeSeconds = 45.0;
  static const double platformArrivalRadiusMeters = 135.0;
  static const double platformArrivedMarkRadiusMeters = 115.0;
  static const double intermediateStopDwellSeconds = 55.0;

  GpsTelemetrySample? _lastGpsFix;
  double? _lastGpsDistMeters;
  double? _smoothedClosingSpeedMps;
  double? _smoothedDisplaySpeedMps;
  int _observedDelaySeconds = 0;
  bool _hasObservedStopAnchor = false;
  double? _initialRouteDistanceMeters;
  int _rideStartedEpochMs = 0;

  int get observedDelaySeconds => _observedDelaySeconds;
  bool get hasObservedStopAnchor => _hasObservedStopAnchor;
  double? get smoothedClosingSpeedMps => _smoothedClosingSpeedMps;
  double? get smoothedDisplaySpeedMps => _smoothedDisplaySpeedMps;

  void reset({
    double? initialRouteDistanceMeters,
    int? rideStartedEpochMs,
    int observedDelaySeconds = 0,
    bool hasObservedStopAnchor = false,
  }) {
    _lastGpsFix = null;
    _lastGpsDistMeters = null;
    _smoothedClosingSpeedMps = null;
    _smoothedDisplaySpeedMps = null;
    _initialRouteDistanceMeters = initialRouteDistanceMeters;
    _rideStartedEpochMs =
        rideStartedEpochMs ?? DateTime.now().millisecondsSinceEpoch;
    _observedDelaySeconds = observedDelaySeconds.clamp(-600, 3600);
    _hasObservedStopAnchor = hasObservedStopAnchor;
  }

  /// Records the exact moment the train passed/cleared an intermediate stop to
  /// calibrate live schedule drift for tunnel / GPS-blackout fallback.
  void recordStopPassed({
    required int actualEpochMs,
    int? scheduledStopEpochMs,
  }) {
    if (scheduledStopEpochMs == null || scheduledStopEpochMs <= 0) return;
    final rawDelaySec = ((actualEpochMs - scheduledStopEpochMs) / 1000.0)
        .round()
        .clamp(-600, 3600);
    if (!_hasObservedStopAnchor) {
      _observedDelaySeconds = rawDelaySec;
      _hasObservedStopAnchor = true;
    } else {
      _observedDelaySeconds =
          (0.75 * rawDelaySec + 0.25 * _observedDelaySeconds).round();
    }
  }

  /// Syncs observed delay offset from the native background guard service.
  void applySyncedDelayOffset(int delaySeconds, {required bool hasAnchor}) {
    if (hasAnchor) {
      _observedDelaySeconds = delaySeconds.clamp(-600, 3600);
      _hasObservedStopAnchor = true;
    }
  }

  /// Ingests a new GPS fix and updates radial closing speed + display speed EMA.
  void recordGpsFix(
    GpsTelemetrySample fix, {
    required double destLat,
    required double destLng,
    int stopsRemaining = 1,
  }) {
    // Reject extremely coarse network fixes when we already have a recent accurate fix
    if (fix.accuracyMeters > 200.0 && _lastGpsFix != null) {
      final ageSinceGood =
          (fix.timestampEpochMs - _lastGpsFix!.timestampEpochMs) / 1000.0;
      if (ageSinceGood >= 0 && ageSinceGood < 25.0) {
        return;
      }
    }

    final distNow = haversineMeters(
      fix.latitude,
      fix.longitude,
      destLat,
      destLng,
    );

    final validDoppler =
        fix.speedMps.isFinite && fix.speedMps >= 0.0 && fix.speedMps <= maxNecSpeedMps;
    if (validDoppler) {
      _smoothedDisplaySpeedMps = _smoothedDisplaySpeedMps == null
          ? fix.speedMps
          : (0.45 * fix.speedMps + 0.55 * _smoothedDisplaySpeedMps!);
    }

    if (_lastGpsFix != null && _lastGpsDistMeters != null) {
      final dtSec =
          (fix.timestampEpochMs - _lastGpsFix!.timestampEpochMs) / 1000.0;
      if (dtSec >= 0.4 && dtSec <= 35.0) {
        final rawClosing = (_lastGpsDistMeters! - distNow) / dtSec;
        if (rawClosing > 0.5) {
          final clampedClosing = rawClosing.clamp(0.0, maxNecSpeedMps);
          final double measuredSpeed;
          if (validDoppler && fix.speedMps >= 1.5) {
            // Radial closing velocity cancels out moderate track curvature; blend
            // 65% radial closing + 35% Doppler speed (capped to closing*1.25).
            measuredSpeed = 0.65 * clampedClosing +
                0.35 * math.min(fix.speedMps, clampedClosing * 1.25);
          } else {
            measuredSpeed = clampedClosing;
          }
          final alpha = distNow <= 3500.0 ? 0.48 : 0.32;
          _smoothedClosingSpeedMps = _smoothedClosingSpeedMps == null
              ? measuredSpeed
              : (alpha * measuredSpeed +
                  (1.0 - alpha) * _smoothedClosingSpeedMps!);
          if (!validDoppler) {
            _smoothedDisplaySpeedMps = _smoothedClosingSpeedMps;
          }
        } else if (rawClosing <= 0.5 && (!validDoppler || fix.speedMps < 1.5)) {
          // Train is stopped / holding at signal or intermediate station: decay rapidly
          final prev = _smoothedClosingSpeedMps ?? 0.0;
          _smoothedClosingSpeedMps = (0.35 * prev).clamp(0.0, maxNecSpeedMps);
          if (_smoothedClosingSpeedMps! < 0.4) {
            _smoothedClosingSpeedMps = 0.0;
          }
          if (!validDoppler) {
            _smoothedDisplaySpeedMps = _smoothedClosingSpeedMps;
          }
        }
      }
    } else if (validDoppler && fix.speedMps >= 2.0) {
      // First GPS fix of the ride: conservatively seed closing speed if already en route
      final movedEnough = stopsRemaining <= 1 ||
          (_initialRouteDistanceMeters != null &&
              distNow < _initialRouteDistanceMeters! * 0.9);
      if (movedEnough) {
        _smoothedClosingSpeedMps = fix.speedMps * 0.88;
      }
    }

    _lastGpsFix = fix;
    _lastGpsDistMeters = distNow;
  }

  /// Evaluates current fused ETA and determines whether Stage 1 (Approaching ~60s)
  /// or Stage 2 (Arriving ~10s) alerts should trigger right now.
  ArrivalEtaEstimate evaluate({
    required int nowEpochMs,
    required int? scheduledArrivalEpochMs,
    required int stopsRemaining,
    required String apiStatus,
    required bool finalWakeUpAlarmEnabled,
    required bool hasFiredApproaching,
    required bool hasFiredArriving,
    double? fallbackDistanceMeters,
  }) {
    final apiDelaySec = parseApiDelaySeconds(apiStatus);
    final delaySec = _hasObservedStopAnchor ? _observedDelaySeconds : apiDelaySec;

    double? schedEtaSec;
    if (scheduledArrivalEpochMs != null && scheduledArrivalEpochMs > 0) {
      schedEtaSec =
          ((scheduledArrivalEpochMs + delaySec * 1000) - nowEpochMs) / 1000.0;
    }

    final gpsAgeSec = _lastGpsFix != null
        ? (nowEpochMs - _lastGpsFix!.timestampEpochMs) / 1000.0
        : null;
    final gpsFresh = gpsAgeSec != null &&
        gpsAgeSec >= -2.0 &&
        gpsAgeSec <= gpsFreshMaxAgeSeconds &&
        _lastGpsDistMeters != null;

    final clampedGpsAge = gpsAgeSec == null ? 0.0 : math.max(0.0, gpsAgeSec);
    final closingV = _smoothedClosingSpeedMps ?? 0.0;
    final dopplerV = _lastGpsFix?.speedMps ?? 0.0;

    final gpsDeadReckoning = !gpsFresh &&
        gpsAgeSec != null &&
        gpsAgeSec > gpsFreshMaxAgeSeconds &&
        gpsAgeSec <= gpsDeadReckoningMaxAgeSeconds &&
        _lastGpsDistMeters != null &&
        _lastGpsDistMeters! <= 3500.0 &&
        closingV >= 4.0;

    double? extrapDist = fallbackDistanceMeters;
    if (gpsFresh) {
      extrapDist = math.max(0.0, _lastGpsDistMeters! - (closingV * clampedGpsAge));
    } else if (gpsDeadReckoning) {
      extrapDist = math.max(
        0.0,
        _lastGpsDistMeters! - (closingV * clampedGpsAge * 0.85),
      );
    }

    // Physical sanity bound: if live GPS proves we are still far away (> 1.8km),
    // the train cannot physically arrive faster than max NEC speed + braking!
    if (gpsFresh && extrapDist != null && extrapDist > 1800.0 && schedEtaSec != null) {
      final minPhysicalEta = computeKinematicBrakingSeconds(
        distanceMeters: extrapDist,
        speedMps: math.max(closingV, 28.0).clamp(15.0, maxNecSpeedMps),
      );
      if (schedEtaSec < minPhysicalEta) {
        schedEtaSec = minPhysicalEta;
      }
    }

    final isHolding = gpsFresh &&
        extrapDist != null &&
        extrapDist > platformArrivalRadiusMeters &&
        closingV < 1.5 &&
        dopplerV < 1.5;

    double? fusedEtaSec;
    String sourceLabel;

    if (stopsRemaining == 0) {
      fusedEtaSec = 0.0;
      sourceLabel = 'Arrived at Platform';
    } else if (gpsFresh && extrapDist != null) {
      if (extrapDist <= platformArrivalRadiusMeters) {
        fusedEtaSec = closingV >= 1.8
            ? computeKinematicBrakingSeconds(
                distanceMeters: extrapDist,
                speedMps: closingV,
              ).clamp(0.0, 10.0)
            : 0.0;
        sourceLabel = 'GPS Platform Entry (${extrapDist.round()}m)';
      } else if (isHolding) {
        final holdingFloor = extrapDist / 14.0;
        fusedEtaSec = schedEtaSec != null
            ? math.max(schedEtaSec, holdingFloor)
            : holdingFloor;
        sourceLabel = 'GPS Holding • ${extrapDist.round()}m out';
      } else if (closingV >= 1.8) {
        final intermediateDwell = (stopsRemaining > 1 && extrapDist > 2200.0)
            ? (stopsRemaining - 1) * intermediateStopDwellSeconds
            : 0.0;
        final gpsKinematicEta = computeKinematicBrakingSeconds(
              distanceMeters: extrapDist,
              speedMps: closingV,
            ) +
            intermediateDwell;
        final dBrake = (closingV * closingV) / (2.0 * serviceBrakingDecelMps2);
        final inBrakingZone =
            math.max(0.0, extrapDist - platformLeadMeters) <= dBrake;
        final mph = ((_smoothedDisplaySpeedMps ?? closingV) * 2.23694).round();

        if (extrapDist <= 3800.0 || stopsRemaining <= 1) {
          fusedEtaSec = gpsKinematicEta;
        } else if (extrapDist <= 7500.0 && schedEtaSec != null && schedEtaSec > 0) {
          fusedEtaSec = 0.65 * gpsKinematicEta + 0.35 * schedEtaSec;
        } else if (schedEtaSec != null && schedEtaSec > 0) {
          fusedEtaSec = 0.35 * gpsKinematicEta + 0.65 * schedEtaSec;
        } else {
          fusedEtaSec = gpsKinematicEta;
        }

        sourceLabel = inBrakingZone
            ? 'GPS Braking • $mph mph'
            : 'GPS Physics • $mph mph';
      } else {
        // Low velocity or first fix before closing speed converges
        fusedEtaSec = schedEtaSec ?? (extrapDist / 18.0);
        sourceLabel = 'GPS + Schedule Sync';
      }
    } else if (gpsDeadReckoning && extrapDist != null) {
      final drEta = computeKinematicBrakingSeconds(
        distanceMeters: extrapDist,
        speedMps: closingV,
      );
      fusedEtaSec = (schedEtaSec != null && schedEtaSec > 0)
          ? (0.55 * drEta + 0.45 * schedEtaSec)
          : drEta;
      sourceLabel = 'Dead-Reckoning (Brief GPS Gap)';
    } else {
      fusedEtaSec = schedEtaSec;
      if (_hasObservedStopAnchor && delaySec.abs() >= 30) {
        final mins = (delaySec / 60.0).round();
        final sign = mins >= 0 ? '+' : '';
        sourceLabel = 'Delay-Calibrated ETA ($sign${mins}m)';
      } else if (apiDelaySec > 0) {
        final mins = (apiDelaySec / 60.0).round();
        sourceLabel = 'Delay-Calibrated ETA (+${mins}m)';
      } else {
        sourceLabel = 'Schedule + API ETA';
      }
    }

    final isPrecisionMode = stopsRemaining <= 1 ||
        (extrapDist != null && extrapDist <= 5000.0) ||
        (fusedEtaSec != null && fusedEtaSec <= 360.0);

    // Guardrail: avoid firing immediately on boarding before train leaves origin
    final elapsedSinceStartMs = nowEpochMs - _rideStartedEpochMs;
    final movedFromOrigin = _initialRouteDistanceMeters == null ||
        extrapDist == null ||
        extrapDist < (_initialRouteDistanceMeters! * 0.80);
    final pastOriginGuard = stopsRemaining <= 1 ||
        movedFromOrigin ||
        elapsedSinceStartMs >= 45000;

    // Part 2: "Arriving" (~10s before platform stop — GET UP NOW!)
    bool shouldFireArriving = false;
    if (finalWakeUpAlarmEnabled && !hasFiredArriving && pastOriginGuard) {
      if (stopsRemaining == 0) {
        shouldFireArriving = true;
      } else if (gpsFresh && extrapDist != null) {
        final withinKinematic10s = !isHolding &&
            fusedEtaSec != null &&
            fusedEtaSec <= arrivingThresholdSeconds &&
            extrapDist <= 520.0;
        final atPlatformEdge = extrapDist <= platformArrivalRadiusMeters;
        if (withinKinematic10s || atPlatformEdge) {
          shouldFireArriving = true;
        }
      } else if (stopsRemaining <= 1 &&
          fusedEtaSec != null &&
          fusedEtaSec <= arrivingThresholdSeconds &&
          fusedEtaSec >= -25.0) {
        // Tunnel / GPS-blackout fallback (e.g. Hudson River Tunnel into NY Penn)
        shouldFireArriving = true;
      }
    }

    // Part 1: "Approaching" (~1 min before platform stop — Pack up & get ready!)
    bool shouldFireApproaching = false;
    if (finalWakeUpAlarmEnabled &&
        !hasFiredApproaching &&
        !hasFiredArriving &&
        !shouldFireArriving &&
        pastOriginGuard &&
        stopsRemaining > 0 &&
        !isHolding &&
        fusedEtaSec != null &&
        fusedEtaSec <= approachingThresholdSeconds &&
        fusedEtaSec > arrivingThresholdSeconds) {
      if (gpsFresh && extrapDist != null) {
        // Allow GPS approaching trigger even if previous stop API flag lagged!
        if (extrapDist <= 3400.0) {
          shouldFireApproaching = true;
        }
      } else if (stopsRemaining <= 1) {
        // Tunnel / no-GPS schedule fallback
        shouldFireApproaching = true;
      }
    }

    // Only advance GPS directly to destination stop (stopsRemaining == 0) once
    // physically at/on the platform (<= 115m), NOT 550m away!
    final shouldMarkPlatformArrived = stopsRemaining > 0 &&
        pastOriginGuard &&
        gpsFresh &&
        extrapDist != null &&
        extrapDist <= platformArrivedMarkRadiusMeters;

    final int? liveArrivalEpochMs = fusedEtaSec != null
        ? nowEpochMs + (math.max(0.0, fusedEtaSec) * 1000.0).round()
        : scheduledArrivalEpochMs;

    final double? displayMph = gpsFresh && _smoothedDisplaySpeedMps != null
        ? (_smoothedDisplaySpeedMps! * 2.23694)
        : null;

    return ArrivalEtaEstimate(
      estimatedSeconds: fusedEtaSec,
      distanceMeters: extrapDist,
      closingSpeedMps: gpsFresh ? closingV : null,
      speedMph: displayMph,
      delayOffsetSeconds: delaySec,
      liveArrivalEpochMs: liveArrivalEpochMs,
      isGpsFresh: gpsFresh,
      isHoldingAtSignal: isHolding,
      isPrecisionMode: isPrecisionMode,
      sourceLabel: sourceLabel,
      shouldFireApproaching: shouldFireApproaching,
      shouldFireArriving: shouldFireArriving,
      shouldMarkPlatformArrived: shouldMarkPlatformArrived,
    );
  }

  /// Rail kinematic ETA accounting for constant service braking deceleration
  /// down to 0 m/s at the destination platform.
  static double computeKinematicBrakingSeconds({
    required double distanceMeters,
    required double speedMps,
    double decelMps2 = serviceBrakingDecelMps2,
    double platformLeadMeters = platformLeadMeters,
  }) {
    final dEff = math.max(0.0, distanceMeters - platformLeadMeters);
    if (dEff <= 0.0) return 0.0;
    final v = speedMps.clamp(0.5, maxNecSpeedMps);
    final dBrake = (v * v) / (2.0 * decelMps2);
    if (dEff <= dBrake) {
      // Already inside the braking zone: average speed from v down to 0 is v/2
      return (2.0 * dEff) / v;
    }
    final cruiseDist = dEff - dBrake;
    return (cruiseDist / v) + (v / decelMps2);
  }

  /// Parses NJ Transit status delay minutes (e.g. "Delayed 7 min", "Late 4m",
  /// "5 min late") into seconds.
  static int parseApiDelaySeconds(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty || s == 'on time' || s == 'ontime') return 0;
    final m1 = RegExp(r'(?:delayed?|late)\s*(?:by\s*)?(\d+)\s*(?:min|m\b)')
        .firstMatch(s);
    if (m1 != null) {
      final mins = int.tryParse(m1.group(1) ?? '') ?? 0;
      return (mins * 60).clamp(0, 3600);
    }
    final m2 = RegExp(r'(\d+)\s*(?:min|m)\s*(?:late|delay)').firstMatch(s);
    if (m2 != null) {
      final mins = int.tryParse(m2.group(1) ?? '') ?? 0;
      return (mins * 60).clamp(0, 3600);
    }
    return 0;
  }

  /// Formats remaining seconds into a crisp commuter countdown label.
  static String formatCountdown(int seconds) {
    if (seconds <= 0) return 'Now';
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final remSec = seconds % 60;
    if (mins >= 10) return '${(seconds / 60.0).ceil()}m';
    return '${mins}m ${remSec.toString().padLeft(2, '0')}s';
  }

  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000.0;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}
