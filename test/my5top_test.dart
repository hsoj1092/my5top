import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

    test('DepartureVision station codes and stop-name aliases resolve accurately',
        () {
      expect(getStationByCode('NE').dvCode, equals('NZ'));
      expect(getStationByCode('RA').dvCode, equals('RH'));
      expect(getStationByCode('MC').dvCode, equals('MU'));
      expect(getStationByCode('SE').dvCode, equals('SE'));

      expect(findStationByNameOrCode('Elizabeth')?.code, equals('EZ'));
      expect(findStationByNameOrCode('North Elizabeth')?.code, equals('NE'));
      expect(findStationByNameOrCode('Secaucus Upper Lvl')?.code, equals('SE'));
      expect(findStationByNameOrCode('Jersey Avenue')?.code, equals('JA'));
      expect(findStationByNameOrCode('Princeton Junction')?.code, equals('PJ'));
      expect(
        NjtApiService.cleanDestinationName('Trenton -SEC &#9992'),
        equals('Trenton'),
      );
      expect(
        NjtApiService.cleanDestinationName('New York -SEC &#9992'),
        equals('NY Penn Station'),
      );
    });

    test(
        'Bidirectional NEC GraphQL poll separates Southbound (Trenton) and Northbound (NYC) trains accurately',
        () async {
      NjtApiService.clearLiveCaches();
      // 11:37 AM EST = 16:37 UTC on Nov 16, 2026
      final refUtc = DateTime.utc(2026, 11, 16, 16, 37);

      final mockClient = MockClient((http.Request req) async {
        final body = json.decode(req.body) as Map<String, dynamic>;
        final query = (body['query'] ?? '').toString();

        if (query.contains('getTrainDepartureScreens')) {
          expect(query, contains('station: "NY"'));
          expect(query, contains('station: "MP"'));
          expect(query, contains('station: "TR"'));
          return http.Response(
            json.encode({
              'data': {
                'b_NY': {
                  'items': [
                    {
                      'trainID': '3839',
                      'departureDate': '11:37 AM',
                      'destination': 'Trenton -SEC &#9992',
                      'line': 'Northeast Corrdr',
                      'lineAbbreviation': 'NEC',
                      'status': 'BOARDING',
                      'track': '2',
                      'inlineMessage': '',
                    },
                    {
                      'trainID': '3841',
                      'departureDate': '12:01 PM',
                      'destination': 'Trenton -SEC &#9992',
                      'line': 'Northeast Corrdr',
                      'lineAbbreviation': 'NEC',
                      'status': '',
                      'track': '',
                      'inlineMessage': '',
                    },
                  ],
                },
                'b_MP': {
                  'items': [
                    {
                      'trainID': '3837',
                      'departureDate': '11:54 AM',
                      'destination': 'Trenton',
                      'line': 'Northeast Corrdr',
                      'lineAbbreviation': 'NEC',
                      'status': 'in 17 Min',
                      'track': '4',
                      'inlineMessage': '',
                    },
                    {
                      'trainID': '3840',
                      'departureDate': '12:11 PM',
                      'destination': 'New York -SEC &#9992',
                      'line': 'Northeast Corrdr',
                      'lineAbbreviation': 'NEC',
                      'status': '',
                      'track': '1',
                      'inlineMessage': '',
                    },
                    {
                      'trainID': '3839',
                      'departureDate': '12:20 PM',
                      'destination': 'Trenton',
                      'line': 'Northeast Corrdr',
                      'lineAbbreviation': 'NEC',
                      'status': '',
                      'track': '4',
                      'inlineMessage': '',
                    },
                  ],
                },
                'b_SE': {
                  'items': [
                    {
                      'trainID': '3838',
                      'departureDate': '11:48 AM',
                      'destination': 'New York -SEC &#9992',
                      'line': 'Northeast Corrdr',
                      'lineAbbreviation': 'NEC',
                      'status': 'in 11 Min',
                      'track': 'A',
                      'inlineMessage': '',
                    },
                  ],
                },
                'b_NP': {'items': []},
                'b_NB': {'items': []},
                'b_PJ': {'items': []},
                'b_TR': {'items': []},
              },
            }),
            200,
          );
        }

        // Step B: getTrainStopList batch response
        return http.Response(
          json.encode({
            'data': {
              't_3839': [
                {
                  'name': 'New York Penn Station',
                  'time': '11:37 AM',
                  'departed': true,
                  'status': 'BOARDING',
                },
                {
                  'name': 'Secaucus Upper Lvl',
                  'time': '11:45 AM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Newark Penn Station',
                  'time': '11:53 AM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Metropark',
                  'time': '12:20 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Trenton',
                  'time': '1:10 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
              ],
              't_3841': [
                {
                  'name': 'New York Penn Station',
                  'time': '12:01 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Secaucus Upper Lvl',
                  'time': '12:10 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Newark Penn Station',
                  'time': '12:19 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Elizabeth',
                  'time': '12:28 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Rahway',
                  'time': '12:38 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Metropark',
                  'time': '12:46 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Trenton',
                  'time': '1:38 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
              ],
              't_3837': [
                {
                  'name': 'New York Penn Station',
                  'time': '11:09 AM',
                  'departed': true,
                  'status': 'OnTime',
                },
                {
                  'name': 'Secaucus Upper Lvl',
                  'time': '11:18 AM',
                  'departed': true,
                  'status': 'OnTime',
                },
                {
                  'name': 'Newark Penn Station',
                  'time': '11:27 AM',
                  'departed': true,
                  'status': 'OnTime',
                },
                {
                  'name': 'Rahway',
                  'time': '11:46 AM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Metropark',
                  'time': '11:54 AM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Trenton',
                  'time': '12:44 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
              ],
              't_3840': [
                {
                  'name': 'Trenton',
                  'time': '11:24 AM',
                  'departed': true,
                  'status': 'OnTime',
                },
                {
                  'name': 'Princeton Junction',
                  'time': '11:37 AM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Metropark',
                  'time': '12:11 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Newark Penn Station',
                  'time': '12:36 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'Secaucus Upper Lvl',
                  'time': '12:45 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'New York Penn Station',
                  'time': '1:01 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
              ],
              't_3838': [
                {
                  'name': 'Trenton',
                  'time': '10:36 AM',
                  'departed': true,
                  'status': 'OnTime',
                },
                {
                  'name': 'Metropark',
                  'time': '11:18 AM',
                  'departed': true,
                  'status': 'OnTime',
                },
                {
                  'name': 'Newark Penn Station',
                  'time': '11:39 AM',
                  'departed': true,
                  'status': 'OnTime',
                },
                {
                  'name': 'Secaucus Upper Lvl',
                  'time': '11:48 AM',
                  'departed': false,
                  'status': 'OnTime',
                },
                {
                  'name': 'New York Penn Station',
                  'time': '12:01 PM',
                  'departed': false,
                  'status': 'OnTime',
                },
              ],
            },
          }),
          200,
        );
      });

      final nyToMp = await NjtApiService.fetchUpcomingTrains(
        originCode: 'NY',
        destinationCode: 'MP',
        forceRefresh: true,
        httpClient: mockClient,
        referenceNow: refUtc,
      );

      final southUpcoming =
          nyToMp.where((t) => !t.isRecentPastDeparture).toList();
      final southRecent =
          nyToMp.where((t) => t.isRecentPastDeparture).toList();

      expect(southUpcoming.map((t) => t.trainId).toList(), ['3839', '3841']);
      expect(southUpcoming.first.track, '2'); // NY Penn track, NOT MP's Track 4!
      expect(southUpcoming.first.status, 'Boarding');
      expect(southUpcoming.first.finalDestinationName, 'Trenton');
      expect(southUpcoming.last.track, isNull);
      expect(southRecent.map((t) => t.trainId).toList(), ['3837']);
      expect(southRecent.first.status, contains('Rahway'));

      // Flipping direction (MP -> NY) returns ONLY Northbound NYC trains, never inverted NY->MP!
      final mpToNy = await NjtApiService.fetchUpcomingTrains(
        originCode: 'MP',
        destinationCode: 'NY',
        forceRefresh: true,
        httpClient: mockClient,
        referenceNow: refUtc,
      );

      final northUpcoming =
          mpToNy.where((t) => !t.isRecentPastDeparture).toList();
      final northRecent =
          mpToNy.where((t) => t.isRecentPastDeparture).toList();

      expect(northUpcoming.map((t) => t.trainId).toList(), ['3840']);
      expect(northUpcoming.first.track, '1'); // Metropark Track 1
      expect(northUpcoming.first.departureTime, '12:11 PM');
      expect(northUpcoming.first.arrivalTime, '1:01 PM');
      expect(northUpcoming.first.finalDestinationName, 'NY Penn Station');
      expect(northRecent.map((t) => t.trainId).toList(), ['3838']);
      expect(northRecent.first.status, contains('Secaucus'));
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
      // Offline Northbound and Southbound schedules use distinct train IDs & departure times
      expect(toWorkTrips.first.trainId, isNot(equals(toHomeTrips.first.trainId)));
      expect(
        toWorkTrips.first.departureTime,
        isNot(equals(toHomeTrips.first.departureTime)),
      );
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
