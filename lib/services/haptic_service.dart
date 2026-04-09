import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HapticService {
  static const String _kHapticsEnabled = 'haptics_enabled';

  static Future<bool> _isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHapticsEnabled) ?? true;
  }

  static Future<void> selection() async {
    if (await _isEnabled()) {
      await HapticFeedback.selectionClick();
    }
  }

  static Future<void> light() async {
    if (await _isEnabled()) {
      await HapticFeedback.lightImpact();
    }
  }

  static Future<void> medium() async {
    if (await _isEnabled()) {
      await HapticFeedback.mediumImpact();
    }
  }
}
