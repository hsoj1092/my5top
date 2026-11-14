import 'package:flutter/material.dart';
import 'app_state.dart';

class BackupProvider extends ChangeNotifier {
  bool _isBusy = false;
  String _statusMessage = '';
  String? _errorMessage;

  bool get isBusy => _isBusy;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;

  Future<void> checkAndRunAutoBackup(AppState appState) async {
    final interval = appState.backupInterval;
    if (interval == 'off' || _isBusy) return;

    final lastBackup = appState.lastBackupTime;
    final now = DateTime.now();

    bool shouldBackup = false;
    if (lastBackup == null) {
      shouldBackup = true;
    } else {
      final difference = now.difference(lastBackup);
      if (interval == '3_days' && difference.inDays >= 3) {
        shouldBackup = true;
      } else if (interval == '1_week' && difference.inDays >= 7) {
        shouldBackup = true;
      } else if (interval == '2_weeks' && difference.inDays >= 14) {
        shouldBackup = true;
      } else if (interval == '1_month' && difference.inDays >= 30) {
        shouldBackup = true;
      }
    }

    if (!shouldBackup) return;

    _isBusy = true;
    _errorMessage = null;
    _statusMessage = 'Running automatic JSON backup...';
    notifyListeners();

    try {
      await appState.exportLocalBackupFile();
      _isBusy = false;
      _statusMessage = 'Automatic backup completed.';
      notifyListeners();
    } catch (e) {
      _isBusy = false;
      _errorMessage = 'Automatic backup failed: $e';
      _statusMessage = '';
      notifyListeners();
    }
  }
}
