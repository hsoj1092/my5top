import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/station.dart';
import '../providers/app_state.dart';
import '../services/njt_api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _njtUserCtrl;
  late TextEditingController _njtPassCtrl;
  late TextEditingController _githubRepoCtrl;
  bool _isTestingNjt = false;
  List<File> _localBackups = [];

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _njtUserCtrl = TextEditingController(text: appState.njtUsername);
    _njtPassCtrl = TextEditingController(text: appState.njtPassword);
    _githubRepoCtrl = TextEditingController(text: appState.githubRepoPath);
    _loadLocalBackups();
  }

  Future<void> _loadLocalBackups() async {
    final files = await context.read<AppState>().getLocalBackupFiles();
    if (mounted) {
      setState(() => _localBackups = files);
    }
  }

  @override
  void dispose() {
    _njtUserCtrl.dispose();
    _njtPassCtrl.dispose();
    _githubRepoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final pal = appState.palette;
        final rules = appState.notificationRules;

        return Scaffold(
          backgroundColor: pal.scaffoldBg,
          appBar: AppBar(
            title: const Text('Settings, Backups & Updates'),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
              children: [
                // 1. Anime Theme & Aesthetic Section
                _buildSectionHeader(
                  pal.primaryAccent,
                  Icons.auto_awesome_rounded,
                  'Anime Theme & Appearance',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Visual Style & Mascot',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: pal.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildThemeOptionCard(
                                context: context,
                                isSelected: appState.animeThemeStyle == 'mygo',
                                title: 'MyGO!!!!! Starry',
                                subtitle: 'Tomori-navi • Slate & Cyan',
                                icon: Icons.nightlight_round,
                                accent: const Color(0xFF38BDF8),
                                onTap: () => appState.setAnimeThemeStyle('mygo'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildThemeOptionCard(
                                context: context,
                                isSelected:
                                    appState.animeThemeStyle == 'sakura',
                                title: 'Sakura Express',
                                subtitle: 'Hana-chan • Pastel Pink',
                                icon: Icons.local_florist_rounded,
                                accent: const Color(0xFFF472B6),
                                onTap: () =>
                                    appState.setAnimeThemeStyle('sakura'),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Dark Mode',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Night commuter board palette',
                            style: TextStyle(
                              fontSize: 12,
                              color: pal.textSecondary,
                            ),
                          ),
                          value: appState.isDarkMode,
                          activeColor: pal.primaryAccent,
                          onChanged: (v) => appState.setDarkMode(v),
                        ),
                        if (appState.isDarkMode)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Pure Black AMOLED Mode',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: pal.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              'Saves battery on OLED screens during rides',
                              style: TextStyle(
                                fontSize: 12,
                                color: pal.textSecondary,
                              ),
                            ),
                            value: appState.isPureBlackDarkMode,
                            activeColor: pal.primaryAccent,
                            onChanged: (v) => appState.setPureBlackDarkMode(v),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Favorite Commute Stops (Work = NY Penn, Home = Metropark)
                _buildSectionHeader(
                  pal.primaryAccent,
                  Icons.star_rounded,
                  'Favorite Commute Stations',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildStationSelectorRow(
                          context: context,
                          label: '🏢 Work Station',
                          selected: appState.workStation,
                          onSelect: (code) => appState.setWorkStation(code),
                        ),
                        const Divider(height: 20),
                        _buildStationSelectorRow(
                          context: context,
                          label: '🏠 Home Station',
                          selected: appState.homeStation,
                          onSelect: (code) => appState.setHomeStation(code),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 3. Default Stop Notification Rules
                _buildSectionHeader(
                  pal.primaryAccent,
                  Icons.notifications_active_rounded,
                  'Commute Notification Rules',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start alerting me X stops before destination (${rules.startNotifyingStopsAway} ${rules.startNotifyingStopsAway == 1 ? "stop" : "stops"} away):',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: pal.textPrimary,
                          ),
                        ),
                        Slider(
                          value: rules.startNotifyingStopsAway.toDouble(),
                          min: 1,
                          max: 6,
                          divisions: 5,
                          label: '${rules.startNotifyingStopsAway} stops away',
                          activeColor: pal.primaryAccent,
                          onChanged: (val) {
                            appState.updateNotificationRules(
                              rules.copyWith(
                                startNotifyingStopsAway: val.round(),
                              ),
                            );
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Notify on Every Stop',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Send a status update as each intermediate stop is passed',
                            style: TextStyle(
                              fontSize: 12,
                              color: pal.textSecondary,
                            ),
                          ),
                          value: rules.notifyEveryStop,
                          activeColor: pal.primaryAccent,
                          onChanged: (v) => appState.updateNotificationRules(
                            rules.copyWith(notifyEveryStop: v),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Notify When Track Assignment Drops',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Instant alert when your watched train gets a track at NY Penn / Metropark',
                            style: TextStyle(
                              fontSize: 12,
                              color: pal.textSecondary,
                            ),
                          ),
                          value: rules.notifyOnTrackAssigned,
                          activeColor: pal.trackBadgeBg,
                          onChanged: (v) => appState.updateNotificationRules(
                            rules.copyWith(notifyOnTrackAssigned: v),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Final Wake-Up Arrival Alarm',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'High-priority sound + vibration when approaching destination',
                            style: TextStyle(
                              fontSize: 12,
                              color: pal.textSecondary,
                            ),
                          ),
                          value: rules.finalWakeUpAlarm,
                          activeColor: pal.urgentColor,
                          onChanged: (v) => appState.updateNotificationRules(
                            rules.copyWith(finalWakeUpAlarm: v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 4. Mihon-Style Backup & Restore (Google Drive / Folder File Picker)
                _buildSectionHeader(
                  pal.primaryAccent,
                  Icons.cloud_queue_rounded,
                  'Backup & Restore (.my5top.json)',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Save or restore your favorites, notification rules, and ride history as a portable JSON file in Google Drive or local storage.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: pal.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final res = await appState
                                      .createBackupViaFilePicker();
                                  await _loadLocalBackups();
                                  if (context.mounted &&
                                      res != null &&
                                      res['success'] == true) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Backup saved: ${res['displayName']}',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: pal.primaryAccent,
                                  foregroundColor: const Color(0xFF0F172A),
                                ),
                                icon: const Icon(Icons.upload_file_rounded),
                                label: const Text(
                                  'Create Backup',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final res = await appState
                                      .restoreBackupViaFilePicker();
                                  if (context.mounted &&
                                      res != null &&
                                      res['success'] == true) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Restored from ${res['displayName']}!',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.restore_page_rounded),
                                label: const Text('Restore File'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.folder_special_rounded,
                            color: pal.secondaryAccent,
                          ),
                          title: Text(
                            'Backup Location Folder (Google Drive / Local)',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: pal.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            appState.safBackupDirectoryLabel.isNotEmpty
                                ? appState.safBackupDirectoryLabel
                                : 'Tap to choose a Google Drive or device folder for automatic backups',
                            style: TextStyle(
                              fontSize: 12,
                              color: pal.textSecondary,
                            ),
                          ),
                          trailing: OutlinedButton(
                            onPressed: () async {
                              await appState.pickBackupDestinationFolder();
                            },
                            child: const Text('Choose'),
                          ),
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Automatic Backup Frequency',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: pal.textPrimary,
                              ),
                            ),
                            DropdownButton<String>(
                              value: appState.backupInterval,
                              dropdownColor: pal.cardBg,
                              items: const [
                                DropdownMenuItem(
                                  value: 'off',
                                  child: Text('Off'),
                                ),
                                DropdownMenuItem(
                                  value: '3_days',
                                  child: Text('Every 3 days'),
                                ),
                                DropdownMenuItem(
                                  value: '1_week',
                                  child: Text('Weekly'),
                                ),
                                DropdownMenuItem(
                                  value: '2_weeks',
                                  child: Text('Every 2 weeks'),
                                ),
                                DropdownMenuItem(
                                  value: '1_month',
                                  child: Text('Monthly'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  appState.setBackupInterval(val);
                                }
                              },
                            ),
                          ],
                        ),
                        if (appState.lastBackupTime != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Last backup: ${appState.lastBackupTime!.year}-${appState.lastBackupTime!.month.toString().padLeft(2, "0")}-${appState.lastBackupTime!.day.toString().padLeft(2, "0")} • ${NjtApiService.formatTime12h(appState.lastBackupTime!)}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: pal.successColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (_localBackups.isNotEmpty) ...[
                          const Divider(height: 22),
                          Text(
                            'Recent Local Backup Snapshots (${_localBackups.length})',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: pal.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._localBackups.take(3).map((file) {
                            final name =
                                file.path.split(RegExp(r'[/\\]')).last;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: pal.textPrimary,
                                ),
                              ),
                              trailing: TextButton(
                                onPressed: () async {
                                  await appState.restoreFromLocalBackupFile(
                                    file.path,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Restored $name!'),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Restore'),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 5. NJ Transit Data Source (Zero-Key + Optional Official RailData API)
                _buildSectionHeader(
                  pal.primaryAccent,
                  Icons.train_rounded,
                  'NJ Transit Live API (Optional)',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: pal.successColor.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                appState.hasActiveNjtToken
                                    ? '★ Official NJT Token Active'
                                    : '✓ Zero-Key Smart Schedule + GPS Active',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: pal.successColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'my5top works out-of-the-box for free with zero keys using bundled NEC schedules, DepartureVision lookups, and on-device GPS station geofencing. If you later register for a free NJ Transit Developer account, enter it below for direct RailData token polling:',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: pal.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _njtUserCtrl,
                          decoration: const InputDecoration(
                            labelText: 'NJT Developer Username / Email (Optional)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _njtPassCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'NJT Developer Password (Optional)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final uri = Uri.parse(
                                    'https://developer.njtransit.com/',
                                  );
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('Free NJT Portal'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isTestingNjt
                                    ? null
                                    : () async {
                                        setState(() => _isTestingNjt = true);
                                        final ok = await appState
                                            .saveAndTestNjtCredentials(
                                          _njtUserCtrl.text,
                                          _njtPassCtrl.text,
                                        );
                                        if (mounted) {
                                          setState(() => _isTestingNjt = false);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                ok
                                                    ? 'Connected to NJT RailData API!'
                                                    : (_njtUserCtrl.text
                                                            .trim()
                                                            .isEmpty
                                                        ? 'Using Zero-Key Smart Schedule + GPS mode.'
                                                        : 'Could not verify token; falling back to Zero-Key Smart mode.'),
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                child: Text(
                                  _isTestingNjt ? 'Testing...' : 'Save / Test',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 6. GitHub Releases APK Self-Updater
                _buildSectionHeader(
                  pal.primaryAccent,
                  Icons.system_update_rounded,
                  'GitHub APK Self-Updater',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Installed Version',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: pal.textPrimary,
                              ),
                            ),
                            Text(
                              'v${AppState.appVersion}+${AppState.appBuildNumber}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: pal.primaryAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _githubRepoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'GitHub Releases Repo (owner/repo)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (v) => appState.setGithubRepoPath(v),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await appState
                                  .setGithubRepoPath(_githubRepoCtrl.text);
                              if (context.mounted) {
                                await appState.checkForUpdates(
                                  context,
                                  showNoUpdateDialog: true,
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: pal.secondaryAccent,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text(
                              'Check GitHub for APK Updates',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(Color accent, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOptionCard({
    required BuildContext context,
    required bool isSelected,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final pal = context.read<AppState>().palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? accent.withOpacity(0.16) : pal.scaffoldBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accent : pal.cardBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check_circle, size: 16, color: accent),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: pal.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: pal.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationSelectorRow({
    required BuildContext context,
    required String label,
    required Station selected,
    required ValueChanged<String> onSelect,
  }) {
    final pal = context.read<AppState>().palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: pal.textPrimary,
                ),
              ),
              Text(
                '${selected.name} (${selected.code})',
                style: TextStyle(
                  fontSize: 12,
                  color: pal.textSecondary,
                ),
              ),
            ],
          ),
        ),
        DropdownButton<String>(
          value: selected.code,
          dropdownColor: pal.cardBg,
          items: kNjtStations.map((st) {
            return DropdownMenuItem(
              value: st.code,
              child: Text('${st.shortName} (${st.code})'),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) onSelect(val);
          },
        ),
      ],
    );
  }
}
