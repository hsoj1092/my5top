import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'providers/backup_provider.dart';
import 'views/active_ride_screen.dart';
import 'views/home_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final ActiveRideRouteObserver activeRideRouteObserver =
    ActiveRideRouteObserver();

class ActiveRideRouteObserver extends NavigatorObserver {
  int _activeRideCount = 0;
  bool get isActiveRideInStack => _activeRideCount > 0;

  bool _isActiveRide(Route<dynamic>? route) =>
      route?.settings.name == ActiveRideScreen.routeName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (_isActiveRide(route)) _activeRideCount++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_isActiveRide(route) && _activeRideCount > 0) _activeRideCount--;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_isActiveRide(route) && _activeRideCount > 0) _activeRideCount--;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (_isActiveRide(oldRoute) && _activeRideCount > 0) _activeRideCount--;
    if (_isActiveRide(newRoute)) _activeRideCount++;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final packageInfo =
        await PackageInfo.fromPlatform().timeout(const Duration(seconds: 2));
    AppState.appVersion = packageInfo.version;
    AppState.appBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;
  } catch (e) {
    debugPrint('Error loading package version: $e');
  }
  runApp(const My5TopApp());
}

class My5TopApp extends StatelessWidget {
  final AppState? injectedAppState;

  const My5TopApp({super.key, this.injectedAppState});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        if (injectedAppState != null)
          ChangeNotifierProvider<AppState>.value(value: injectedAppState!)
        else
          ChangeNotifierProvider<AppState>(create: (_) => AppState()),
        ChangeNotifierProvider<BackupProvider>(create: (_) => BackupProvider()),
      ],
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          if (!appState.initialized) {
            return MaterialApp(
              scrollBehavior: MyCustomScrollBehavior(),
              debugShowCheckedModeBanner: false,
              home: const Scaffold(
                backgroundColor: Color(0xFF0B1120),
                body: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF38BDF8),
                  ),
                ),
              ),
            );
          }

          final pal = appState.palette;

          return MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [activeRideRouteObserver],
            scrollBehavior: MyCustomScrollBehavior(),
            title: 'my5top',
            debugShowCheckedModeBanner: false,
            theme: pal.toMaterialTheme(),
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(appState.textScaleFactor),
                ),
                child: ColoredBox(
                  color: pal.scaffoldBg,
                  child: SafeArea(
                    top: false,
                    left: false,
                    right: false,
                    bottom: true,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              );
            },
            initialRoute:
                appState.isRiding ? ActiveRideScreen.routeName : '/',
            onGenerateInitialRoutes: (initialRoute) {
              return <Route<dynamic>>[
                MaterialPageRoute(
                  settings: const RouteSettings(name: '/'),
                  builder: (_) => const HomeScreen(),
                ),
                if (initialRoute == ActiveRideScreen.routeName)
                  ActiveRideScreen.route(),
              ];
            },
            onGenerateRoute: (settings) {
              if (settings.name == ActiveRideScreen.routeName) {
                return ActiveRideScreen.route();
              }
              return MaterialPageRoute(
                settings: const RouteSettings(name: '/'),
                builder: (_) => const HomeScreen(),
              );
            },
          );
        },
      ),
    );
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}
