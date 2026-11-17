import 'package:flutter/material.dart';

class AnimeThemePalette {
  final String id; // 'mygo' or 'sakura'
  final String name;
  final String jpTitle;
  final String mascotName;
  final String mascotTitle;
  final bool isDark;
  final Color scaffoldBg;
  final Color cardBg;
  final Color cardBorder;
  final Color primaryAccent;
  final Color secondaryAccent;
  final Color trackBadgeBg;
  final Color trackBadgeText;
  final Color urgentColor;
  final Color successColor;
  final Color textPrimary;
  final Color textSecondary;

  const AnimeThemePalette({
    required this.id,
    required this.name,
    required this.jpTitle,
    required this.mascotName,
    required this.mascotTitle,
    required this.isDark,
    required this.scaffoldBg,
    required this.cardBg,
    required this.cardBorder,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.trackBadgeBg,
    required this.trackBadgeText,
    required this.urgentColor,
    required this.successColor,
    required this.textPrimary,
    required this.textSecondary,
  });

  static AnimeThemePalette resolve({
    required String themeStyle, // 'mygo' or 'sakura'
    required bool isDark,
    required bool isAmoled,
  }) {
    if (themeStyle == 'sakura') {
      if (isDark) {
        return AnimeThemePalette(
          id: 'sakura',
          name: 'Sakura Express (Night)',
          jpTitle: 'Sakura Express • Night',
          mascotName: 'Hana-chan',
          mascotTitle: 'Sakura Station Conductor',
          isDark: true,
          scaffoldBg: isAmoled ? const Color(0xFF000000) : const Color(0xFF1D1522),
          cardBg: isAmoled ? const Color(0xFF110C15) : const Color(0xFF2B1F31),
          cardBorder: const Color(0x33F472B6),
          primaryAccent: const Color(0xFFF472B6),
          secondaryAccent: const Color(0xFF60A5FA),
          trackBadgeBg: const Color(0xFFFDE047),
          trackBadgeText: const Color(0xFF1E1B4B),
          urgentColor: const Color(0xFFFB7185),
          successColor: const Color(0xFF34D399),
          textPrimary: const Color(0xFFFDF2F8),
          textSecondary: const Color(0xFFE9D5FF),
        );
      }
      return const AnimeThemePalette(
        id: 'sakura',
        name: 'Sakura Express Pastel',
        jpTitle: 'Sakura Express • Day',
        mascotName: 'Hana-chan',
        mascotTitle: 'Sakura Station Conductor',
        isDark: false,
        scaffoldBg: Color(0xFFFFF7FA),
        cardBg: Color(0xFFFFFFFF),
        cardBorder: Color(0xFFFBCFE8),
        primaryAccent: Color(0xFFEC4899),
        secondaryAccent: Color(0xFF0EA5E9),
        trackBadgeBg: Color(0xFFFEF08A),
        trackBadgeText: Color(0xFF854D0E),
        urgentColor: Color(0xFFE11D48),
        successColor: Color(0xFF059669),
        textPrimary: Color(0xFF331832),
        textSecondary: Color(0xFF704C6E),
      );
    }

    // Default: MyGO!!!!! Starry Rain
    if (!isDark) {
      return const AnimeThemePalette(
        id: 'mygo',
        name: 'MyGO!!!!! Starry Day',
        jpTitle: 'Starry Navigator',
        mascotName: 'Tomori-navi',
        mascotTitle: 'Starry Rail Navigator',
        isDark: false,
        scaffoldBg: Color(0xFFF1F5F9),
        cardBg: Color(0xFFFFFFFF),
        cardBorder: Color(0xFFCBD5E1),
        primaryAccent: Color(0xFF0284C7),
        secondaryAccent: Color(0xFF6366F1),
        trackBadgeBg: Color(0xFFFACC15),
        trackBadgeText: Color(0xFF0F172A),
        urgentColor: Color(0xFFE11D48),
        successColor: Color(0xFF10B981),
        textPrimary: Color(0xFF0F172A),
        textSecondary: Color(0xFF475569),
      );
    }

    return AnimeThemePalette(
      id: 'mygo',
      name: 'MyGO!!!!! Starry Rain',
      jpTitle: 'Starry Navigator',
      mascotName: 'Tomori-navi',
      mascotTitle: 'Starry Rail Navigator',
      isDark: true,
      scaffoldBg: isAmoled ? const Color(0xFF000000) : const Color(0xFF0B1120),
      cardBg: isAmoled ? const Color(0xFF090D16) : const Color(0xFF152036),
      cardBorder: const Color(0x2938BDF8),
      primaryAccent: const Color(0xFF38BDF8),
      secondaryAccent: const Color(0xFF818CF8),
      trackBadgeBg: const Color(0xFFFBBF24),
      trackBadgeText: const Color(0xFF0F172A),
      urgentColor: const Color(0xFFFB7185),
      successColor: const Color(0xFF34D399),
      textPrimary: const Color(0xFFF1F5F9),
      textSecondary: const Color(0xFF94A3B8),
    );
  }

  ThemeData toMaterialTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: primaryAccent,
              secondary: secondaryAccent,
              surface: cardBg,
              onPrimary: const Color(0xFF0F172A),
              onSecondary: Colors.white,
              onSurface: textPrimary,
            )
          : ColorScheme.light(
              primary: primaryAccent,
              secondary: secondaryAccent,
              surface: cardBg,
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onSurface: textPrimary,
            ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          side: BorderSide(color: cardBorder, width: 1.2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
    );
  }

  /// Generates cute anime mascot voice lines based on theme and commute status.
  String mascotLineForState({
    required bool isRiding,
    required String? watchedTrainId,
    required String? activeTrainId,
    required String originShort,
    required String destShort,
    required int stopsRemaining,
    required String? track,
  }) {
    final isSakura = id == 'sakura';
    if (isRiding) {
      if (stopsRemaining <= 0) {
        return isSakura
            ? '★ We arrived at $destShort!! Don\'t forget your umbrella & bag~ ♪'
            : '★ Arrived at $destShort. Even if we get lost, we made it home today.';
      }
      if (stopsRemaining == 1) {
        return isSakura
            ? '♪ Next stop is $destShort! Pack up your things & head to the doors~!'
            : '⚡ 1 stop left until $destShort! Time to pack up and stand by the doors.';
      }
      if (stopsRemaining == 2) {
        return isSakura
            ? '✿ Only 2 stops away from $destShort! Almost there, ganbatte~!'
            : '✦ 2 stops away from $destShort. Wrapping up the ride—get ready soon!';
      }
      return isSakura
          ? '♪ Chugging along on Train #$activeTrainId to $destShort ($stopsRemaining stops left)~'
          : '✦ Riding Train #$activeTrainId → $destShort • $stopsRemaining stops remaining. Rest your eyes, I\'ve got GPS + API watch.';
    }

    if (watchedTrainId != null) {
      if (track != null && track.isNotEmpty) {
        return isSakura
            ? '★ Track $track is posted for Train #$watchedTrainId! Let\'s board~!'
            : '⚡ Track $track announced for Train #$watchedTrainId! Head to the platform now!';
      }
      return isSakura
          ? '👀 Watching the big board for Train #$watchedTrainId\'s track at $originShort...'
          : '✦ Locking eyes on DepartureVision for Train #$watchedTrainId... I\'ll ping you the second the track drops.';
    }

    return isSakura
        ? 'Otsukaresama! Pick a train below to watch its track or hop aboard~'
        : 'Ready on the platform. Tap a train to watch its track or start your ride.';
  }
}
