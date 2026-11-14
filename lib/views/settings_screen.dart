import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/station.dart';
import '../providers/app_state.dart';
import '../providers/backup_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, int>? _storageStats;
  bool _loadingStorage = false;

  @override
  void initState() {
    super.initState();
    _refreshStorageStats();
  }

  Future<void> _refreshStorageStats() async {
    if (!mounted) return;
    setState(() => _loadingStorage = true);
    final stats = await context.read<AppState>().getStorageStats();
    if (!mounted) return;
    setState(() {
      _storageStats = stats;
      _loadingStorage = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    final kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(2)} MB';
  }

  String _formatIntervalLabel(String interval) {
    switch (interval) {
      case 'daily':
        return 'Every day';
      case 'weekly':
        return 'Every week';
      default:
        return 'Off';
    }
  }

  String _formatShortDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = months[(dt.month - 1).clamp(0, 11)];
    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final minStr = dt.minute.toString().padLeft(2, '0');
    return '$m ${dt.day}, $hour12:$minStr $amPm';
  }

  Widget _buildCategoryHeader(BuildContext context, String title) {
    final pal = context.read<AppState>().palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: pal.primaryAccent,
        ),
      ),
    );
  }

  Widget _buildPreferenceTile({
    required BuildContext context,
    IconData? icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    final pal = context.read<AppState>().palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 23,
                color: iconColor ?? pal.primaryAccent.withOpacity(0.9),
              ),
              const SizedBox(width: 18),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: pal.textPrimary,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: pal.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionDivider(BuildContext context) {
    final pal = context.read<AppState>().palette;
    return Divider(
      height: 12,
      thickness: 0.6,
      color: pal.cardBorder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppState, BackupProvider>(
      builder: (context, appState, backupProv, _) {
        final pal = appState.palette;
        final rules = appState.notificationRules;

        final lastBackupStr = appState.lastBackupTime != null
            ? _formatShortDate(appState.lastBackupTime!.toLocal())
            : 'Never';
        final lastCheckStr = appState.lastUpdateCheckTime != null
            ? _formatShortDate(appState.lastUpdateCheckTime!.toLocal())
            : 'Automatic on app launch';

        return Scaffold(
          backgroundColor: pal.scaffoldBg,
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.only(
                bottom: 36 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                // ==========================================
                // 1. APPEARANCE & ANIME THEME
                // ==========================================
                _buildCategoryHeader(context, 'Appearance'),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Theme Mode',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: pal.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            icon: Icon(Icons.wb_sunny_outlined, size: 18),
                            label: Text('Light'),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            icon: Icon(Icons.dark_mode_outlined, size: 18),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {appState.isDarkMode},
                        onSelectionChanged: (sel) {
                          appState.setDarkMode(sel.first);
                        },
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Anime Visual Theme & Mascot',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: pal.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildThemeOptionCard(
                              selected: appState.animeThemeStyle == 'mygo',
                              title: 'MyGO!!!!! Starry',
                              subtitle: 'Tomori-navi • Starry Rain',
                              accent: const Color(0xFF38BDF8),
                              icon: Icons.nightlight_round,
                              onTap: () => appState.setAnimeThemeStyle('mygo'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildThemeOptionCard(
                              selected: appState.animeThemeStyle == 'sakura',
                              title: 'Sakura Express',
                              subtitle: 'Hana-chan • Pastel Pink',
                              accent: const Color(0xFFF472B6),
                              icon: Icons.local_florist_rounded,
                              onTap: () =>
                                  appState.setAnimeThemeStyle('sakura'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (appState.isDarkMode)
                  _buildPreferenceTile(
                    context: context,
                    icon: Icons.contrast_rounded,
                    title: 'Pure black dark mode',
                    subtitle: 'AMOLED #000000 background for night train rides',
                    trailing: Switch(
                      value: appState.isPureBlackDarkMode,
                      activeColor: pal.primaryAccent,
                      onChanged: (v) => appState.setPureBlackDarkMode(v),
                    ),
                    onTap: () => appState
                        .setPureBlackDarkMode(!appState.isPureBlackDarkMode),
                  ),

                _buildSectionDivider(context),

                // ==========================================
                // 2. FAVORITE COMMUTE STATIONS
                // ==========================================
                _buildCategoryHeader(context, 'Favorite Commute Stations'),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.work_outline_rounded,
                  title: 'Work Station',
                  subtitle:
                      '${appState.workStation.name} (${appState.workStation.code})',
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: appState.workStationCode,
                      dropdownColor: pal.cardBg,
                      items: kNjtStations
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.code,
                              child: Text('${s.shortName} (${s.code})'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) appState.setWorkStation(val);
                      },
                    ),
                  ),
                ),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.home_outlined,
                  title: 'Home Station',
                  subtitle:
                      '${appState.homeStation.name} (${appState.homeStation.code})',
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: appState.homeStationCode,
                      dropdownColor: pal.cardBg,
                      items: kNjtStations
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.code,
                              child: Text('${s.shortName} (${s.code})'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) appState.setHomeStation(val);
                      },
                    ),
                  ),
                ),

                _buildSectionDivider(context),

                // ==========================================
                // 3. COMMUTE NOTIFICATIONS & GPS ALERTS
                // ==========================================
                _buildCategoryHeader(context, 'Notifications & Stop Alerts'),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Start alerting me X stops away',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                              color: pal.textPrimary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: pal.primaryAccent.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${rules.startNotifyingStopsAway} ${rules.startNotifyingStopsAway == 1 ? "stop" : "stops"} away',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: pal.primaryAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Numbered Dots Selector with Numbers Printed Underneath Each Dot
                      Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          Positioned(
                            top: 17,
                            left: 24,
                            right: 24,
                            child: Container(
                              height: 2.5,
                              color: pal.cardBorder,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [1, 2, 3, 4, 5, 6].map((count) {
                              final selected =
                                  rules.startNotifyingStopsAway == count;
                              final isActiveOrBefore =
                                  count <= rules.startNotifyingStopsAway;
                              return InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  appState.updateNotificationRules(
                                    rules.copyWith(
                                      startNotifyingStopsAway: count,
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: selected
                                              ? pal.primaryAccent
                                              : isActiveOrBefore
                                                  ? pal.cardBg
                                                  : pal.scaffoldBg,
                                          border: Border.all(
                                            color: selected || isActiveOrBefore
                                                ? pal.primaryAccent
                                                : pal.cardBorder,
                                            width: selected ? 2.4 : 1.6,
                                          ),
                                          boxShadow: selected
                                              ? [
                                                  BoxShadow(
                                                    color: pal.primaryAccent
                                                        .withOpacity(0.4),
                                                    blurRadius: 8,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          selected
                                              ? Icons.notifications_active
                                              : Icons.circle,
                                          size: selected ? 15 : 8,
                                          color: selected
                                              ? const Color(0xFF0F172A)
                                              : isActiveOrBefore
                                                  ? pal.primaryAccent
                                                  : pal.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '$count',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w900
                                              : FontWeight.w600,
                                          color: selected
                                              ? pal.primaryAccent
                                              : pal.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.linear_scale_rounded,
                  title: 'Notify on every stop',
                  subtitle: 'Send a progress ping at every station on the route',
                  trailing: Switch(
                    value: rules.notifyEveryStop,
                    activeColor: pal.primaryAccent,
                    onChanged: (v) => appState.updateNotificationRules(
                      rules.copyWith(notifyEveryStop: v),
                    ),
                  ),
                  onTap: () => appState.updateNotificationRules(
                    rules.copyWith(notifyEveryStop: !rules.notifyEveryStop),
                  ),
                ),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.campaign_outlined,
                  title: 'Notify when track assignment drops',
                  subtitle:
                      'Instant alert when your watched train gets a track at NY Penn / Metropark',
                  trailing: Switch(
                    value: rules.notifyOnTrackAssigned,
                    activeColor: pal.trackBadgeBg,
                    onChanged: (v) => appState.updateNotificationRules(
                      rules.copyWith(notifyOnTrackAssigned: v),
                    ),
                  ),
                  onTap: () => appState.updateNotificationRules(
                    rules.copyWith(
                      notifyOnTrackAssigned: !rules.notifyOnTrackAssigned,
                    ),
                  ),
                ),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.alarm_rounded,
                  title: 'Final wake-up arrival alarm',
                  subtitle:
                      'High-priority sound + vibration when approaching destination',
                  trailing: Switch(
                    value: rules.finalWakeUpAlarm,
                    activeColor: pal.urgentColor,
                    onChanged: (v) => appState.updateNotificationRules(
                      rules.copyWith(finalWakeUpAlarm: v),
                    ),
                  ),
                  onTap: () => appState.updateNotificationRules(
                    rules.copyWith(finalWakeUpAlarm: !rules.finalWakeUpAlarm),
                  ),
                ),

                _buildSectionDivider(context),

                // ==========================================
                // 4. DATA & STORAGE (Replicating current mygo2)
                // ==========================================
                _buildCategoryHeader(context, 'Data & Storage'),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.upload_file_outlined,
                  title: 'Create backup',
                  subtitle:
                      'Save to Google Drive or local storage via file picker',
                  onTap: () async {
                    final res = await appState.createBackupViaFilePicker();
                    if (res != null && res['cancelled'] == true) return;
                    if (res != null && res['success'] == true && mounted) {
                      await _refreshStorageStats();
                      if (!context.mounted) return;
                      final displayName =
                          res['displayName'] ?? 'my5top_backup.json';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Backup saved: $displayName')),
                      );
                    }
                  },
                ),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.settings_backup_restore_rounded,
                  title: 'Restore backup',
                  subtitle:
                      'Import from Google Drive / local file or recent snapshot',
                  onTap: () => _openRestoreLocalBackupSheet(context, appState),
                ),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.folder_outlined,
                  title: 'Backup location',
                  subtitle: appState.safBackupDirectoryLabel.isNotEmpty
                      ? appState.safBackupDirectoryLabel
                      : 'Tap to choose a folder for automatic backups',
                  onTap: () async {
                    final res = await appState.pickBackupDestinationFolder();
                    if (res != null && res['success'] == true && mounted) {
                      await _refreshStorageStats();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Backup location set: ${res['displayName']}',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.schedule_outlined,
                  title: 'Automatic backup',
                  subtitle:
                      '${_formatIntervalLabel(appState.backupInterval)} • Last: $lastBackupStr',
                  onTap: () =>
                      _openAutoBackupSheet(context, appState, backupProv),
                ),

                _buildSectionDivider(context),

                // ==========================================
                // 5. DEVELOPER & TESTING
                // ==========================================
                _buildCategoryHeader(context, 'Developer & Testing'),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.science_outlined,
                  title: 'Dev Test Mode',
                  subtitle:
                      'Show Sim Track and Ride & Alert Simulator buttons for testing',
                  trailing: Switch(
                    value: appState.devTestMode,
                    activeColor: pal.secondaryAccent,
                    onChanged: (v) => appState.setDevTestMode(v),
                  ),
                  onTap: () => appState.setDevTestMode(!appState.devTestMode),
                ),

                _buildSectionDivider(context),

                // ==========================================
                // 6. ABOUT & UPDATES (Replicating current mygo2)
                // ==========================================
                _buildCategoryHeader(context, 'About & Updates'),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.update_rounded,
                  title: 'Check for updates',
                  subtitle: 'Last checked: $lastCheckStr',
                  onTap: () async {
                    await appState.setLastUpdateCheckTime(DateTime.now());
                    if (context.mounted) {
                      await appState.checkForUpdates(
                        context,
                        showNoUpdateDialog: true,
                      );
                    }
                  },
                ),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.new_releases_outlined,
                  title: 'What\'s new',
                  subtitle: 'View release notes for v${AppState.appVersion}',
                  onTap: () => appState.showWhatsNew(context),
                ),
                _buildPreferenceTile(
                  context: context,
                  icon: Icons.info_outline_rounded,
                  title: 'Version',
                  subtitle:
                      'Stable v${AppState.appVersion} (Build ${AppState.appBuildNumber})',
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            'my5top v${AppState.appVersion}+${AppState.appBuildNumber}',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Version info copied to clipboard'),
                      ),
                    );
                  },
                ),
                if (appState.rideLogs.isNotEmpty)
                  _buildPreferenceTile(
                    context: context,
                    icon: Icons.history_rounded,
                    title: 'Recent Commute History',
                    subtitle:
                        '${appState.rideLogs.length} completed ${appState.rideLogs.length == 1 ? "ride" : "rides"} logged',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Opens the Automatic Backup frequency & storage modal matching mygo2.
  Future<void> _openAutoBackupSheet(
    BuildContext context,
    AppState appState,
    BackupProvider backupProv,
  ) async {
    await _refreshStorageStats();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: appState.palette.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final pal = appState.palette;
        final stats = _storageStats ?? const {};
        final backupFiles = stats['backupFiles'] ?? 0;
        final backupBytes = stats['backupBytes'] ?? 0;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Automatic backup',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: pal.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Automatically writes a JSON backup snapshot to your selected Backup location folder when the app opens.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: pal.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                for (final entry in const [
                  ('off', 'Off'),
                  ('daily', 'Every day'),
                  ('weekly', 'Every week'),
                ])
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: entry.$1,
                    groupValue: appState.backupInterval,
                    activeColor: pal.primaryAccent,
                    title: Text(entry.$2),
                    onChanged: (val) async {
                      if (val != null) {
                        await appState.setBackupInterval(val);
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
                  ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: backupProv.isBackingUp
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                final path =
                                    await backupProv.createBackupNow(appState);
                                if (path != null && context.mounted) {
                                  await _refreshStorageStats();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Local backup created: $path',
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.save_alt, size: 18),
                        label: const Text('Create Backup Now'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: pal.scaffoldBg.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: pal.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: pal.primaryAccent.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'TOTAL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: pal.primaryAccent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Backup Storage Used',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: pal.textPrimary,
                              ),
                            ),
                            Text(
                              appState.safBackupDirectoryLabel.isNotEmpty
                                  ? appState.safBackupDirectoryLabel
                                  : 'Internal backup snapshots',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: pal.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_loadingStorage)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Text(
                          '${_formatBytes(backupBytes)} ($backupFiles ${backupFiles == 1 ? 'file' : 'files'})',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: pal.primaryAccent,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Opens the Restore Backup modal sheet matching mygo2 (File picker + Recent Local Snapshots).
  Future<void> _openRestoreLocalBackupSheet(
    BuildContext context,
    AppState appState,
  ) async {
    final files = await appState.getLocalBackupFiles();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: appState.palette.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final pal = appState.palette;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Restore Backup',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: pal.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pick any .json backup file from Google Drive or device storage, or choose a recent local snapshot below:',
                  style: TextStyle(
                    fontSize: 12,
                    color: pal.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        final res = await appState.restoreBackupViaFilePicker();
                        if (res == null || res['cancelled'] == true) return;
                        if (res['success'] == true && context.mounted) {
                          await _refreshStorageStats();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Restored ${res['displayName']} (${res['rideLogs'] ?? 0} commute logs)!',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Restore failed: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text(
                      'Choose Backup File (Drive / Local)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pal.primaryAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (files.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'RECENT LOCAL SNAPSHOTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: pal.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: files.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (c, i) {
                        final f = files[i];
                        final name = f.path.split(Platform.pathSeparator).last;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.description_outlined,
                            color: pal.primaryAccent,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await appState.restoreFromLocalBackupFile(f.path);
                              if (context.mounted) {
                                await _refreshStorageStats();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Restored $name!')),
                                );
                              }
                            },
                            child: const Text('Restore'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemeOptionCard({
    required bool selected,
    required String title,
    required String subtitle,
    required Color accent,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final pal = context.read<AppState>().palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withOpacity(0.18)
              : pal.scaffoldBg.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : pal.cardBorder,
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: accent),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 16, color: accent),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: pal.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10.5,
                color: pal.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
