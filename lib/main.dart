import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'providers/backup_provider.dart';
import 'views/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    AppState.appVersion = packageInfo.version;
    AppState.appBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;
  } catch (e) {
    debugPrint('Error loading package version: $e');
  }
  runApp(const My5TopApp());
}

class My5TopApp extends StatelessWidget {
  const My5TopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
            scrollBehavior: MyCustomScrollBehavior(),
            title: 'my5top',
            debugShowCheckedModeBanner: false,
            theme: pal.toMaterialTheme(),
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaleFactor: appState.textScaleFactor,
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
            home: const HomeScreen(),
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
