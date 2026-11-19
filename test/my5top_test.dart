import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my5top/main.dart';
import 'package:my5top/models/notification_rules.dart';
import 'package:my5top/models/station.dart';
import 'package:my5top/models/train_trip.dart';
import 'package:my5top/providers/app_state.dart';
import 'package:my5top/services/arrival_eta_engine.dart';
import 'package:my5top/services/njt_api_service.dart';
import 'package:my5top/theme/anime_theme.dart';
import 'package:my5top/views/active_ride_screen.dart';
import 'package:my5top/views/home_screen.dart';
import 'package:my5top/widgets/animated_train_timeline.dart';

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

    test(
        'Tracked train arrival staleness enforces 20-minute reopen threshold including midnight crossover',
        () {
      final refDay = DateTime(2026, 11, 16, 12, 30);
      final afternoonTrip = TrainTrip(
        trainId: '3843',
        line: 'Northeast Corridor',
        lineBadge: 'NEC',
        originCode: 'NY',
        destinationCode: 'MP',
        finalDestinationName: 'Trenton',
        departureTime: '12:35 PM',
        arrivalTime: '1:21 PM',
        departureDateTime: DateTime(2026, 11, 16, 12, 35),
        durationMinutes: 46,
        status: 'En Route → Newark Penn',
        isExpress: false,
        isRecentPastDeparture: true,
        dataSource: 'NJT DepartureVision Live',
        stops: const [],
      );

      final arrEast = AppState.computeTripArrivalEastern(
        afternoonTrip,
        referenceEasternNow: refDay,
      );
      expect(arrEast, DateTime(2026, 11, 16, 13, 21));

      // Still en route (1:05 PM) -> NOT stale
      expect(
        AppState.isTripArrivalStale(
          arrivalEastern: arrEast,
          nowEastern: DateTime(2026, 11, 16, 13, 5),
        ),
        isFalse,
      );

      // 19 minutes after arrival (1:40 PM) -> NOT stale (reopens to tracked train screen)
      expect(
        AppState.isTripArrivalStale(
          arrivalEastern: arrEast,
          nowEastern: DateTime(2026, 11, 16, 13, 40, 59),
        ),
        isFalse,
      );

      // Exactly 20 minutes after arrival (1:41 PM) -> STALE (opens to main train table)
      expect(
        AppState.isTripArrivalStale(
          arrivalEastern: arrEast,
          nowEastern: DateTime(2026, 11, 16, 13, 41, 0),
        ),
        isTrue,
      );

      // Late-night midnight crossover trip (11:45 PM -> 12:28 AM next day)
      final lateRef = DateTime(2026, 11, 16, 23, 40);
      final midnightTrip = afternoonTrip.copyWith(
        departureTime: '11:45 PM',
        arrivalTime: '12:28 AM',
        departureDateTime: DateTime(2026, 11, 16, 23, 45),
      );
      final midnightArr = AppState.computeTripArrivalEastern(
        midnightTrip,
        referenceEasternNow: lateRef,
      );
      expect(midnightArr, DateTime(2026, 11, 17, 0, 28));
      expect(
        AppState.isTripArrivalStale(
          arrivalEastern: midnightArr,
          nowEastern: DateTime(2026, 11, 17, 0, 40),
        ),
        isFalse,
      );
      expect(
        AppState.isTripArrivalStale(
          arrivalEastern: midnightArr,
          nowEastern: DateTime(2026, 11, 17, 0, 48),
        ),
        isTrue,
      );
    });

    testWidgets(
        'AnimatedTrainTimeline renders all 5 check-in streetscape variations and progresses cleanly from 0% to 100%',
        (WidgetTester tester) async {
      final trips = NjtApiService.generateSmartSchedule(
        originCode: 'NY',
        destinationCode: 'MP',
        now: DateTime(2026, 11, 16, 17, 30),
      );
      final stops = trips.first.commuteStops;
      final pal = AnimeThemePalette.resolve(
        themeStyle: 'mygo',
        isDark: true,
        isAmoled: false,
      );

      for (int variation = 0; variation < 5; variation++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AnimatedTrainTimeline(
                  palette: pal,
                  stops: stops,
                  currentStopIndex: variation.clamp(0, stops.length - 1),
                  segmentProgress: variation / 5.0,
                  alertStopsAwayThreshold: 2,
                  trainId: '3843',
                  track: '9',
                  sceneSeed: 1000 + variation * 337,
                  variationIndex: variation,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });

    test('TrainTrip minutesUntilDeparture and formatCountdownLabel compute crisp commuter tags',
        () {
      final refNow = DateTime(2026, 11, 17, 17, 15, 0);
      final upcomingTrip = TrainTrip(
        trainId: '3865',
        line: 'Northeast Corridor',
        lineBadge: 'NEC',
        originCode: 'NY',
        destinationCode: 'MP',
        finalDestinationName: 'Trenton',
        departureTime: '5:23 PM',
        arrivalTime: '6:01 PM',
        departureDateTime: DateTime(2026, 11, 17, 17, 23, 0),
        durationMinutes: 38,
        status: 'On Time',
        isExpress: true,
        isRecentPastDeparture: false,
        dataSource: 'NJT DepartureVision Live',
        stops: const [],
      );

      expect(upcomingTrip.minutesUntilDeparture(refNow), equals(8));
      expect(TrainTrip.formatCountdownLabel(8), equals('in 8m'));
      expect(TrainTrip.formatCountdownLabel(0), equals('Now'));
      expect(TrainTrip.formatCountdownLabel(60), equals('in 1h'));
      expect(TrainTrip.formatCountdownLabel(74), equals('in 1h 14m'));

      // Recent past departure returns null countdown
      final departedTrip = upcomingTrip.copyWith(isRecentPastDeparture: true);
      expect(departedTrip.minutesUntilDeparture(refNow), isNull);
    });

    testWidgets(
        'HomeScreen renders compact mascot strip, unified route bar, 2-row cards, Load More, and collapsible En Route accordion without overflow',
        (WidgetTester tester) async {
      late Directory tempDir;
      late AppState appState;

      final rawSchedule = NjtApiService.generateSmartSchedule(
        originCode: 'NY',
        destinationCode: 'MP',
        now: DateTime(2026, 11, 16, 12, 55),
      );
      final upcoming =
          rawSchedule.where((t) => !t.isRecentPastDeparture).toList();
      final departed =
          rawSchedule.where((t) => t.isRecentPastDeparture).toList();
      expect(upcoming.length, equals(6));
      expect(departed.isNotEmpty, isTrue);

      // Reproduce exact screenshot case (#3843, 12:35 PM -> 1:21 PM, 46 min, En Route -> Newark Penn)
      final testTrains = <TrainTrip>[
        ...upcoming,
        departed.first.copyWith(
          trainId: '3843',
          departureTime: '12:35 PM',
          arrivalTime: '1:21 PM',
          durationMinutes: 46,
          status: 'En Route → Newark Penn',
          isRecentPastDeparture: true,
        ),
        ...departed.skip(1),
      ];

      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('my5top_home_test_');
        Hive.init(tempDir.path);
        final box = await Hive.openBox('my5top_test_home');
        await box.put('origin_station_code', 'NY');
        await box.put('destination_station_code', 'MP');
        await box.put('backup_interval', 'off');
        await box.put('text_scale_factor', 1.12);
        appState = await AppState.createForTesting(
          settingsBox: box,
          initialTrains: testTrains,
        );
      });

      addTearDown(() async {
        await tester.runAsync(() async {
          await Hive.close();
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      // Narrow 360px phone viewport to guard against horizontal RenderFlex overflow
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(My5TopApp(injectedAppState: appState));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Slim Unified Route Bar controls render cleanly without old 3-chip clutter
      expect(find.text('To Home'), findsOneWidget);
      expect(find.text('To Work'), findsOneWidget);
      expect(find.text('≤2 stops'), findsOneWidget);
      expect(find.text('Every Stop: OFF'), findsNothing);

      // Initially only the first 3 upcoming trains are shown; trains 4..6 are hidden behind Load More
      expect(find.text('#${upcoming[0].trainId}'), findsOneWidget);
      expect(find.text('#${upcoming[2].trainId}'), findsOneWidget);
      expect(find.text('#${upcoming[3].trainId}'), findsNothing);
      expect(find.text('Load More Trains (3 more)'), findsOneWidget);

      // En Route accordion starts collapsed by default to keep Home screen clean
      expect(find.textContaining('Already on board?'), findsOneWidget);
      expect(find.text('EN ROUTE'), findsOneWidget);
      expect(find.text('En Route → Newark Penn'), findsNothing);

      // Tap En Route accordion -> expands departed trains cleanly without overflow
      await tester.tap(find.text('EN ROUTE'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('12:35 PM'), findsOneWidget);
      expect(find.text('En Route → Newark Penn'), findsOneWidget);

      // Tap Load More -> reveals remaining 3 trains and offers Show Fewer Trains
      await tester.tap(find.text('Load More Trains (3 more)'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('#${upcoming[3].trainId}'), findsOneWidget);
      expect(find.text('#${upcoming[5].trainId}'), findsOneWidget);
      expect(find.text('Show Fewer Trains'), findsOneWidget);

      // Tap Quick Alert pill -> opens Quick Commute Alert Settings sheet
      await tester.tap(find.text('≤2 stops'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      expect(find.text('Quick Commute Alert Settings'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'Reopening app restores ActiveRideScreen when fresh and opens HomeScreen when >= 20 min past arrival',
        (WidgetTester tester) async {
      late Directory tempDir;
      late AppState freshState;
      late AppState staleState;
      late Box staleBox;

      final trips = NjtApiService.generateSmartSchedule(
        originCode: 'NY',
        destinationCode: 'MP',
        now: DateTime(2026, 11, 16, 17, 30),
      );
      final trackedTrip = trips.first;
      final nowEast = NjtApiService.easternNow();

      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('my5top_reopen_test_');
        Hive.init(tempDir.path);

        // Case 1: Active ride arriving in 12 minutes (not stale) -> boots straight to ActiveRideScreen
        final freshBox = await Hive.openBox('my5top_fresh_reopen');
        await freshBox.put('backup_interval', 'off');
        await freshBox.put('active_ride_state', {
          'trip': trackedTrip.toJson(),
          'arrivalEasternIso':
              nowEast.add(const Duration(minutes: 12)).toIso8601String(),
          'boardedAtIso': DateTime.now()
              .subtract(const Duration(minutes: 15))
              .toIso8601String(),
          'currentStopIndex': 1,
          'segmentProgress': 0.45,
          'notifiedStopIndices': <int>[],
          'hasFiredWakeUpAlarm': false,
          'lastTrackingSignalSource': 'Resumed Active Ride',
          'rideSceneSeed': 4242,
          'rideVariationIndex': 2,
        });

        freshState = await AppState.createForTesting(
          settingsBox: freshBox,
          initialTrains: trips,
        );

        // Case 2: Active ride whose arrival was 25 minutes ago (>= 20m stale) -> expires & opens HomeScreen
        staleBox = await Hive.openBox('my5top_stale_reopen');
        await staleBox.put('backup_interval', 'off');
        await staleBox.put('active_ride_state', {
          'trip': trackedTrip.toJson(),
          'arrivalEasternIso':
              nowEast.subtract(const Duration(minutes: 25)).toIso8601String(),
          'boardedAtIso': DateTime.now()
              .subtract(const Duration(minutes: 70))
              .toIso8601String(),
          'currentStopIndex': 2,
          'segmentProgress': 0.8,
          'notifiedStopIndices': <int>[],
          'hasFiredWakeUpAlarm': false,
          'lastTrackingSignalSource': 'Resumed Active Ride',
          'rideSceneSeed': 777,
          'rideVariationIndex': 4,
        });

        staleState = await AppState.createForTesting(
          settingsBox: staleBox,
          initialTrains: trips,
        );
      });

      addTearDown(() async {
        await tester.runAsync(() async {
          await Hive.close();
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      expect(freshState.isRiding, isTrue);
      expect(freshState.rideSceneSeed, equals(4242));
      expect(freshState.rideVariationIndex, equals(2));

      await tester.pumpWidget(My5TopApp(injectedAppState: freshState));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.byType(ActiveRideScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());

      expect(staleState.isRiding, isFalse);
      expect(staleBox.get('active_ride_state'), isNull);
      expect(staleState.rideLogs.length, equals(1));

      await tester.pumpWidget(
        My5TopApp(key: UniqueKey(), injectedAppState: staleState),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.byType(ActiveRideScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('NotificationRules headphoneAudioBypass serializes and defaults safely',
        () {
      const defaults = NotificationRules();
      expect(defaults.headphoneAudioBypass, isTrue);

      final disabled = defaults.copyWith(headphoneAudioBypass: false);
      final encoded = disabled.toJson();
      expect(encoded['headphoneAudioBypass'], isFalse);

      final roundTripped = NotificationRules.fromJson(encoded);
      expect(roundTripped.headphoneAudioBypass, isFalse);

      // Legacy backups missing the field should default to true
      final legacy = NotificationRules.fromJson({
        'notifyEveryStop': true,
        'startNotifyingStopsAway': 3,
      });
      expect(legacy.headphoneAudioBypass, isTrue);
    });

    test('easternWallClockToEpochMs round-trips accurately across EST and EDT',
        () {
      // Winter (EST, UTC-5): Jan 15, 2026 08:30:00 Eastern -> 13:30:00 UTC
      final winterWall = DateTime(2026, 1, 15, 8, 30, 0);
      final winterEpochMs = NjtApiService.easternWallClockToEpochMs(winterWall);
      final winterUtc =
          DateTime.fromMillisecondsSinceEpoch(winterEpochMs, isUtc: true);
      expect(winterUtc, equals(DateTime.utc(2026, 1, 15, 13, 30, 0)));

      // Summer (EDT, UTC-4): Jul 15, 2026 17:45:00 Eastern -> 21:45:00 UTC
      final summerWall = DateTime(2026, 7, 15, 17, 45, 0);
      final summerEpochMs = NjtApiService.easternWallClockToEpochMs(summerWall);
      final summerUtc =
          DateTime.fromMillisecondsSinceEpoch(summerEpochMs, isUtc: true);
      expect(summerUtc, equals(DateTime.utc(2026, 7, 15, 21, 45, 0)));
    });

    test('pollSingleTrainTrackFast parses track drop, TBA, and HTTP 429 backoff',
        () async {
      final trackDropClient = MockClient((req) async {
        final decodedBody = json.decode(req.body) as Map<String, dynamic>;
        expect(
          decodedBody['query'],
          contains('getTrainDepartureScreens(station: "NY")'),
        );
        return http.Response(
          json.encode({
            'data': {
              'board': {
                'items': [
                  {
                    'trainID': '3855',
                    'status': 'Boarding',
                    'track': '11',
                    'inlineMessage': '',
                  },
                  {
                    'trainID': '3857',
                    'status': 'On Time',
                    'track': '',
                    'inlineMessage': '',
                  },
                ],
              },
            },
          }),
          200,
        );
      });

      final posted = await NjtApiService.pollSingleTrainTrackFast(
        originCode: 'NY',
        trainId: '3855',
        httpClient: trackDropClient,
      );
      expect(posted, isNotNull);
      expect(posted!.foundOnBoard, isTrue);
      expect(posted.hasTrack, isTrue);
      expect(posted.track, equals('11'));
      expect(posted.rateLimited, isFalse);

      final tba = await NjtApiService.pollSingleTrainTrackFast(
        originCode: 'NY',
        trainId: '3857',
        httpClient: trackDropClient,
      );
      expect(tba, isNotNull);
      expect(tba!.foundOnBoard, isTrue);
      expect(tba.hasTrack, isFalse);

      final rateLimitClient = MockClient(
        (_) async => http.Response('Too Many Requests', 429),
      );
      final limited = await NjtApiService.pollSingleTrainTrackFast(
        originCode: 'NY',
        trainId: '3855',
        httpClient: rateLimitClient,
      );
      expect(limited, isNotNull);
      expect(limited!.rateLimited, isTrue);
      expect(limited.hasTrack, isFalse);
    });

    test(
        'Watch Track 1s fast polling respects 11m-9m window, delay exception, and safety caps',
        () {
      final dep = DateTime(2026, 11, 16, 18, 0, 0);
      TrainTrip makeTrip({String status = 'On Time', String? track}) =>
          TrainTrip(
            trainId: '3861',
            line: 'Northeast Corridor',
            lineBadge: 'NEC',
            originCode: 'NY',
            destinationCode: 'MP',
            finalDestinationName: 'Trenton',
            departureTime: '6:00 PM',
            arrivalTime: '6:42 PM',
            departureDateTime: dep,
            durationMinutes: 42,
            status: status,
            track: track,
            isExpress: true,
            dataSource: 'Live NJT DepartureVision',
            stops: const [],
          );

      // 12 min before departure (> 11m): stay on normal 5s schedule poll
      expect(
        AppState.shouldUseFastTrackWatchPolling(
          watchedTrip: makeTrip(),
          nowEastern: dep.subtract(const Duration(minutes: 12)),
        ),
        isFalse,
      );

      // 11 min before departure (exact start of burst): enable 1s fast polling
      expect(
        AppState.shouldUseFastTrackWatchPolling(
          watchedTrip: makeTrip(),
          nowEastern: dep.subtract(const Duration(minutes: 11)),
        ),
        isTrue,
      );

      // 10 min before departure (typical NJT track drop window): enable 1s fast polling
      expect(
        AppState.shouldUseFastTrackWatchPolling(
          watchedTrip: makeTrip(),
          nowEastern: dep.subtract(const Duration(minutes: 10)),
        ),
        isTrue,
      );

      // 8 min before departure (< 9m guardrail) while On Time: stop 1s fast polling
      expect(
        AppState.shouldUseFastTrackWatchPolling(
          watchedTrip: makeTrip(status: 'On Time'),
          nowEastern: dep.subtract(const Duration(minutes: 8)),
        ),
        isFalse,
      );

      // 8 min before departure while Delayed (non-routine condition): extend 1s polling past 9m
      expect(
        AppState.shouldUseFastTrackWatchPolling(
          watchedTrip: makeTrip(status: 'Delayed 8 min'),
          nowEastern: dep.subtract(const Duration(minutes: 8)),
          fastBurstStartedAt: dep.subtract(const Duration(minutes: 11)),
        ),
        isTrue,
      );

      // Delayed train that has exceeded the 8m continuous burst safety cap: stop 1s burst
      expect(
        AppState.shouldUseFastTrackWatchPolling(
          watchedTrip: makeTrip(status: 'Delayed 15 min'),
          nowEastern: dep.subtract(const Duration(minutes: 2)),
          fastBurstStartedAt: dep.subtract(const Duration(minutes: 11)),
        ),
        isFalse,
      );

      // Track already assigned: stop 1s polling immediately
      expect(
        AppState.shouldUseFastTrackWatchPolling(
          watchedTrip: makeTrip(track: '9'),
          nowEastern: dep.subtract(const Duration(minutes: 10)),
        ),
        isFalse,
      );

      // Cancelled train: stop 1s polling
      expect(
        AppState.shouldUseFastTrackWatchPolling(
          watchedTrip: makeTrip(status: 'Cancelled'),
          nowEastern: dep.subtract(const Duration(minutes: 10)),
        ),
        isFalse,
      );

      // Rate-limit backoff active: pause 1s polling
      final nowAt10m = dep.subtract(const Duration(minutes: 10));
      expect(
        AppState.shouldUseFastTrackWatchPolling(
          watchedTrip: makeTrip(),
          nowEastern: nowAt10m,
          rateLimitBackoffUntil: nowAt10m.add(const Duration(seconds: 20)),
        ),
        isFalse,
      );
    });

    test(
        'AppState recovers gracefully from corrupt/null Hive values and closed boxes without hanging startup',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('my5top_corrupt_startup_');
      try {
        Hive.init(tempDir.path);
        final box = await Hive.openBox('my5top_corrupt_box');
        await box.put('anime_theme_style', null);
        await box.put('is_dark_mode', 'bad_bool');
        await box.put('pure_black_dark_mode', 123);
        await box.put('text_scale_factor', 'oops');
        await box.put('dev_test_mode', 'nope');
        await box.put('work_station_code', '');
        await box.put('home_station_code', 42);
        await box.put('starred_station_codes', [null, '', '  ']);
        await box.put('origin_station_code', 99);
        await box.put('destination_station_code', null);
        await box.put('njt_username', 1234);
        await box.put('cached_njt_token_time', 999);
        await box.put('notification_rules', {
          'startNotifyingStopsAway': 'bad_int',
        });
        await box.put('ride_logs', ['corrupt_entry', 12345]);
        await box.put('active_ride_state', {'trip': 'corrupt_trip'});
        await box.put('backup_interval', '');
        await box.put('github_token', 555);

        final state = await AppState.createForTesting(settingsBox: box);

        expect(state.initialized, isTrue);
        expect(state.animeThemeStyle, equals('mygo'));
        expect(state.isDarkMode, isTrue);
        expect(state.isPureBlackDarkMode, isFalse);
        expect(state.textScaleFactor, equals(1.0));
        expect(state.devTestMode, isFalse);
        expect(state.workStationCode, equals('NY'));
        expect(state.homeStationCode, equals('MP'));
        expect(state.starredStationCodes, isNotEmpty);
        expect(state.njtUsername, equals(''));
        expect(state.notificationRules.startNotifyingStopsAway, equals(2));
        expect(state.rideLogs, isEmpty);
        expect(state.isRiding, isFalse);
        expect(state.backupInterval, equals('off'));
        expect(state.githubToken, equals(''));
        expect(box.get('active_ride_state'), isNull);

        // Even if the Hive box closes unexpectedly, getters/setters remain safe
        await box.close();
        expect(state.backupInterval, equals('off'));
        expect(state.githubToken, equals(''));
        await state.setDarkMode(false);
        expect(state.isDarkMode, isFalse);
      } finally {
        await Hive.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });

  group('ArrivalEtaEngine 2-Part Final Arrival Precision Tests', () {
    const double destLat = 40.5681; // Metropark
    const double destLng = -74.3296;
    const double metersPerDegLat = 111132.0;

    test('Kinematic braking model outperforms naive distance/speed ETA', () {
      // 70 mph (~31.29 m/s) at 1,240m out: naive d/v = 39.6s (20s too late!),
      // whereas braking kinematics gives ~60s (triggers Approaching on time).
      final kin60 = ArrivalEtaEngine.computeKinematicBrakingSeconds(
        distanceMeters: 1240.0,
        speedMps: 31.29,
      );
      expect(kin60, greaterThan(56.0));
      expect(kin60, lessThan(63.0));

      // Inside braking zone: 150m out at 20 m/s (~45 mph) -> ~10.5s
      final kin10 = ArrivalEtaEngine.computeKinematicBrakingSeconds(
        distanceMeters: 150.0,
        speedMps: 20.0,
      );
      expect(kin10, greaterThan(8.5));
      expect(kin10, lessThan(12.5));

      expect(ArrivalEtaEngine.parseApiDelaySeconds('Delayed 7 min'), equals(420));
      expect(ArrivalEtaEngine.parseApiDelaySeconds('4 min late'), equals(240));
      expect(ArrivalEtaEngine.parseApiDelaySeconds('On Time'), equals(0));
      expect(ArrivalEtaEngine.formatCountdown(58), equals('58s'));
      expect(ArrivalEtaEngine.formatCountdown(125), equals('2m 05s'));
      expect(ArrivalEtaEngine.formatCountdown(0), equals('Now'));
    });

    test(
        'High-speed 67 mph 1Hz GPS approach fires Approaching (~1m) then Arriving (~10-19s) strictly BEFORE stop',
        () {
      final engine = ArrivalEtaEngine();
      final startMs = DateTime.utc(2026, 11, 16, 22, 0, 0).millisecondsSinceEpoch;
      engine.reset(
        initialRouteDistanceMeters: 30000.0,
        rideStartedEpochMs: startMs - 900000,
      );

      // Simulate train cruising at 30 m/s (67 mph) from 2,500m out, then braking at 0.72 m/s²
      const double vCruise = 30.0;
      const double decel = 0.72;
      const double dBrake = (vCruise * vCruise) / (2.0 * decel); // 625m
      double dist = 2500.0;
      double speed = vCruise;
      int tSec = 0;

      bool hasFiredApproaching = false;
      bool hasFiredArriving = false;
      int? approachingTick;
      int? arrivingTick;
      int? platformMarkedTick;
      int approachingCount = 0;
      int arrivingCount = 0;

      while (dist > 1.0 && tSec < 200) {
        final nowMs = startMs + tSec * 1000;
        final lat = destLat + (dist / metersPerDegLat);
        engine.recordGpsFix(
          GpsTelemetrySample(
            latitude: lat,
            longitude: destLng,
            speedMps: speed,
            accuracyMeters: 6.0,
            timestampEpochMs: nowMs,
          ),
          destLat: destLat,
          destLng: destLng,
          stopsRemaining: 1,
        );

        final est = engine.evaluate(
          nowEpochMs: nowMs,
          scheduledArrivalEpochMs: startMs + 140 * 1000, // Slightly off schedule
          stopsRemaining: 1,
          apiStatus: 'On Time',
          finalWakeUpAlarmEnabled: true,
          hasFiredApproaching: hasFiredApproaching,
          hasFiredArriving: hasFiredArriving,
        );

        if (est.shouldFireApproaching) {
          hasFiredApproaching = true;
          approachingTick = tSec;
          approachingCount++;
        }
        if (est.shouldFireArriving) {
          hasFiredArriving = true;
          arrivingTick = tSec;
          arrivingCount++;
        }
        if (est.shouldMarkPlatformArrived && platformMarkedTick == null) {
          platformMarkedTick = tSec;
          expect(dist, lessThanOrEqualTo(125.0));
        }

        // Advance physics by 1 second
        if (dist > dBrake) {
          dist -= vCruise;
          speed = vCruise;
        } else {
          speed = (speed - decel).clamp(0.0, vCruise);
          dist = (dist - (speed + 0.5 * decel)).clamp(0.0, 2500.0);
          if (speed <= 0.1) break;
        }
        tSec++;
      }

      final totalStopSec = tSec;
      expect(approachingCount, equals(1));
      expect(arrivingCount, equals(1));
      expect(approachingTick, isNotNull);
      expect(arrivingTick, isNotNull);
      expect(approachingTick!, lessThan(arrivingTick!));

      final secsBeforeStopApproaching = totalStopSec - approachingTick!;
      final secsBeforeStopArriving = totalStopSec - arrivingTick!;
      expect(secsBeforeStopApproaching, inInclusiveRange(50, 72));
      expect(secsBeforeStopArriving, inInclusiveRange(8, 22));
      expect(platformMarkedTick, isNotNull);
      expect(platformMarkedTick!, greaterThanOrEqualTo(arrivingTick!));
    });

    test(
        'Low-speed 35 mph local approach still fires Approaching (~1m) and Arriving before stop',
        () {
      final engine = ArrivalEtaEngine();
      final startMs = DateTime.utc(2026, 11, 16, 22, 0, 0).millisecondsSinceEpoch;
      engine.reset(
        initialRouteDistanceMeters: 15000.0,
        rideStartedEpochMs: startMs - 600000,
      );

      const double vCruise = 15.6; // ~35 mph
      const double decel = 0.72;
      const double dBrake = (vCruise * vCruise) / (2.0 * decel); // ~169m
      double dist = 1400.0;
      double speed = vCruise;
      int tSec = 0;

      bool hasFiredApproaching = false;
      bool hasFiredArriving = false;
      int? approachingTick;
      int? arrivingTick;

      while (dist > 1.0 && tSec < 200) {
        final nowMs = startMs + tSec * 1000;
        engine.recordGpsFix(
          GpsTelemetrySample(
            latitude: destLat + (dist / metersPerDegLat),
            longitude: destLng,
            speedMps: speed,
            accuracyMeters: 8.0,
            timestampEpochMs: nowMs,
          ),
          destLat: destLat,
          destLng: destLng,
          stopsRemaining: 1,
        );

        final est = engine.evaluate(
          nowEpochMs: nowMs,
          scheduledArrivalEpochMs: startMs + 130 * 1000,
          stopsRemaining: 1,
          apiStatus: 'On Time',
          finalWakeUpAlarmEnabled: true,
          hasFiredApproaching: hasFiredApproaching,
          hasFiredArriving: hasFiredArriving,
        );

        if (est.shouldFireApproaching) {
          hasFiredApproaching = true;
          approachingTick = tSec;
        }
        if (est.shouldFireArriving) {
          hasFiredArriving = true;
          arrivingTick = tSec;
        }

        if (dist > dBrake) {
          dist -= vCruise;
          speed = vCruise;
        } else {
          speed = (speed - decel).clamp(0.0, vCruise);
          dist = (dist - (speed + 0.5 * decel)).clamp(0.0, 1400.0);
          if (speed <= 0.1) break;
        }
        tSec++;
      }

      final totalStopSec = tSec;
      expect(approachingTick, isNotNull);
      expect(arrivingTick, isNotNull);
      expect(totalStopSec - approachingTick!, inInclusiveRange(50, 72));
      expect(totalStopSec - arrivingTick!, inInclusiveRange(8, 22));
    });

    test('Signal-hold detection suppresses false alerts while stopped 650m out',
        () {
      final engine = ArrivalEtaEngine();
      final baseMs = DateTime.utc(2026, 11, 16, 22, 0, 0).millisecondsSinceEpoch;
      engine.reset(
        initialRouteDistanceMeters: 20000.0,
        rideStartedEpochMs: baseMs - 600000,
      );

      final holdLat = destLat + (650.0 / metersPerDegLat);
      for (int s = 0; s < 10; s++) {
        engine.recordGpsFix(
          GpsTelemetrySample(
            latitude: holdLat,
            longitude: destLng,
            speedMps: 0.0,
            accuracyMeters: 8.0,
            timestampEpochMs: baseMs + s * 1000,
          ),
          destLat: destLat,
          destLng: destLng,
          stopsRemaining: 1,
        );
      }

      final est = engine.evaluate(
        nowEpochMs: baseMs + 10000,
        scheduledArrivalEpochMs: baseMs + 15000, // Timetable thinks we're arriving!
        stopsRemaining: 1,
        apiStatus: 'On Time',
        finalWakeUpAlarmEnabled: true,
        hasFiredApproaching: false,
        hasFiredArriving: false,
      );

      expect(est.isHoldingAtSignal, isTrue);
      expect(est.shouldFireApproaching, isFalse);
      expect(est.shouldFireArriving, isFalse);
      expect(est.sourceLabel, contains('Holding'));
    });

    test(
        'Hudson River Tunnel GPS-blackout uses Secaucus stop-pass delay calibration accurately',
        () {
      final engine = ArrivalEtaEngine();
      final secaucusSchedMs =
          DateTime.utc(2026, 11, 16, 13, 0, 0).millisecondsSinceEpoch;
      final nyPennSchedMs =
          secaucusSchedMs + 10 * 60 * 1000; // Scheduled 10m after Secaucus

      engine.reset(
        initialRouteDistanceMeters: 35000.0,
        rideStartedEpochMs: secaucusSchedMs - 1800000,
      );

      // Train passes Secaucus exactly 3 minutes (180s) late, then loses GPS in tunnel
      engine.recordStopPassed(
        actualEpochMs: secaucusSchedMs + 180 * 1000,
        scheduledStopEpochMs: secaucusSchedMs,
      );
      expect(engine.hasObservedStopAnchor, isTrue);
      expect(engine.observedDelaySeconds, equals(180));

      // Real expected NY Penn arrival is nyPennSchedMs + 180s.
      // At nyPennSchedMs - 50s (still 230s away in reality!), must NOT fire prematurely:
      final tooEarly = engine.evaluate(
        nowEpochMs: nyPennSchedMs - 50 * 1000,
        scheduledArrivalEpochMs: nyPennSchedMs,
        stopsRemaining: 1,
        apiStatus: 'On Time',
        finalWakeUpAlarmEnabled: true,
        hasFiredApproaching: false,
        hasFiredArriving: false,
      );
      expect(tooEarly.shouldFireApproaching, isFalse);
      expect(tooEarly.shouldFireArriving, isFalse);
      expect(tooEarly.estimatedSeconds, closeTo(230.0, 2.0));
      expect(tooEarly.sourceLabel, contains('Delay-Calibrated'));

      // At 60s before calibrated real arrival: Part 1 Approaching fires!
      final at60s = engine.evaluate(
        nowEpochMs: nyPennSchedMs + 120 * 1000,
        scheduledArrivalEpochMs: nyPennSchedMs,
        stopsRemaining: 1,
        apiStatus: 'On Time',
        finalWakeUpAlarmEnabled: true,
        hasFiredApproaching: false,
        hasFiredArriving: false,
      );
      expect(at60s.shouldFireApproaching, isTrue);
      expect(at60s.shouldFireArriving, isFalse);

      // At 10s before calibrated real arrival: Part 2 Arriving fires!
      final at10s = engine.evaluate(
        nowEpochMs: nyPennSchedMs + 170 * 1000,
        scheduledArrivalEpochMs: nyPennSchedMs,
        stopsRemaining: 1,
        apiStatus: 'On Time',
        finalWakeUpAlarmEnabled: true,
        hasFiredApproaching: true,
        hasFiredArriving: false,
      );
      expect(at10s.shouldFireApproaching, isFalse);
      expect(at10s.shouldFireArriving, isTrue);
    });

    test(
        'Physical lower-bound sanity check prevents false triggers when GPS proves train is still 3km away',
        () {
      final engine = ArrivalEtaEngine();
      final baseMs = DateTime.utc(2026, 11, 16, 22, 0, 0).millisecondsSinceEpoch;
      engine.reset(
        initialRouteDistanceMeters: 30000.0,
        rideStartedEpochMs: baseMs - 1200000,
      );

      // Train is moving at 25 m/s ~3,000m from destination (~135s away physically),
      // even though static schedule claims arrival is in 20s!
      engine.recordGpsFix(
        GpsTelemetrySample(
          latitude: destLat + (3025.0 / metersPerDegLat),
          longitude: destLng,
          speedMps: 25.0,
          accuracyMeters: 6.0,
          timestampEpochMs: baseMs,
        ),
        destLat: destLat,
        destLng: destLng,
        stopsRemaining: 1,
      );
      engine.recordGpsFix(
        GpsTelemetrySample(
          latitude: destLat + (3000.0 / metersPerDegLat),
          longitude: destLng,
          speedMps: 25.0,
          accuracyMeters: 6.0,
          timestampEpochMs: baseMs + 1000,
        ),
        destLat: destLat,
        destLng: destLng,
        stopsRemaining: 1,
      );

      final est = engine.evaluate(
        nowEpochMs: baseMs + 1000,
        scheduledArrivalEpochMs: baseMs + 21000, // Stale timetable says 20s left
        stopsRemaining: 1,
        apiStatus: 'On Time',
        finalWakeUpAlarmEnabled: true,
        hasFiredApproaching: false,
        hasFiredArriving: false,
      );

      expect(est.estimatedSeconds, greaterThan(100.0));
      expect(est.shouldFireApproaching, isFalse);
      expect(est.shouldFireArriving, isFalse);
    });
  });
}


