import 'package:flutter_test/flutter_test.dart';
import 'package:my5top/models/notification_rules.dart';
import 'package:my5top/models/station.dart';
import 'package:my5top/services/njt_api_service.dart';
import 'package:my5top/theme/anime_theme.dart';

void main() {
  group('my5top Commute Engine & Models Tests', () {
    test('NY Penn (NY) and Metropark (MP) exist with accurate coordinates', () {
      final ny = getStationByCode('NY');
      final mp = getStationByCode('MP');

      expect(ny.name, contains('Penn'));
      expect(mp.name, equals('Metropark'));
      expect(ny.necOrder, lessThan(mp.necOrder));

      final distMeters = ny.distanceMetersTo(mp.latitude, mp.longitude);
      // NY Penn to Metropark is ~34 km straight-line distance
      expect(distMeters, greaterThan(25000));
      expect(distMeters, lessThan(45000));
    });

    test('Smart NEC Schedule generates valid NY -> MP and MP -> NY trips', () {
      final now = DateTime(2026, 11, 13, 17, 30);
      final toHomeTrips = NjtApiService.generateSmartSchedule(
        originCode: 'NY',
        destinationCode: 'MP',
        now: now,
      );

      expect(toHomeTrips, isNotEmpty);
      final upcoming =
          toHomeTrips.where((t) => !t.isRecentPastDeparture).toList();
      final recentPast =
          toHomeTrips.where((t) => t.isRecentPastDeparture).toList();
      expect(upcoming.length, equals(6));
      expect(recentPast.length, equals(3));

      final first = upcoming.first;
      expect(first.originCode, 'NY');
      expect(first.destinationCode, 'MP');
      expect(first.commuteStops.first.stationCode, 'NY');
      expect(first.commuteStops.last.stationCode, 'MP');
      expect(first.totalStopCount, equals(3));
      expect(first.isFourOrLessStops, isTrue);
      expect(first.hasDepartedOrigin(now), isFalse);
      expect(recentPast.first.hasDepartedOrigin(now), isTrue);

      final toWorkTrips = NjtApiService.generateSmartSchedule(
        originCode: 'MP',
        destinationCode: 'NY',
        now: now,
      );
      expect(toWorkTrips.first.commuteStops.first.stationCode, 'MP');
      expect(toWorkTrips.first.commuteStops.last.stationCode, 'NY');
    });

    test('NotificationRules JSON round-trip preserves custom thresholds', () {
      const rules = NotificationRules(
        notifyEveryStop: true,
        startNotifyingStopsAway: 3,
        notifyOnTrackAssigned: true,
        finalWakeUpAlarm: false,
        mascotPersonality: 'sakura',
      );

      final json = rules.toJson();
      final restored = NotificationRules.fromJson(json);

      expect(restored.notifyEveryStop, isTrue);
      expect(restored.startNotifyingStopsAway, equals(3));
      expect(restored.finalWakeUpAlarm, isFalse);
      expect(restored.mascotPersonality, equals('sakura'));
    });

    test('Both MyGO Starry Rain and Sakura Express themes resolve cleanly', () {
      final mygo = AnimeThemePalette.resolve(
        themeStyle: 'mygo',
        isDark: true,
        isAmoled: false,
      );
      final sakura = AnimeThemePalette.resolve(
        themeStyle: 'sakura',
        isDark: false,
        isAmoled: false,
      );

      expect(mygo.mascotName, 'Tomori-navi');
      expect(sakura.mascotName, 'Hana-chan');
    });
  });
}
