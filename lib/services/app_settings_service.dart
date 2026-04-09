import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
//  Keys
// ─────────────────────────────────────────────
const _kAlwaysOn = 'always_on_tracking';
const _kInterval = 'tracking_interval_seconds'; // 0 = continuous
const _kHapticsEnabled = 'haptics_enabled';

// ─────────────────────────────────────────────
//  Interval presets
// ─────────────────────────────────────────────
class TrackingInterval {
  final String label;
  final int seconds; // 0 = continuous stream

  const TrackingInterval({required this.label, required this.seconds});
}

const kTrackingIntervals = [
  TrackingInterval(label: 'Continuous (best accuracy)', seconds: 0),
  TrackingInterval(label: 'Every 5 minutes', seconds: 300),
  TrackingInterval(label: 'Every 15 minutes', seconds: 900),
  TrackingInterval(label: 'Every 30 minutes', seconds: 1800),
];

// ─────────────────────────────────────────────
//  Service
// ─────────────────────────────────────────────
class AppSettingsService {
  AppSettingsService(this._prefs);
  final SharedPreferences _prefs;

  bool get alwaysOnTracking => _prefs.getBool(_kAlwaysOn) ?? false;

  Future<void> setAlwaysOnTracking(bool value) =>
      _prefs.setBool(_kAlwaysOn, value);

  int get trackingIntervalSeconds => _prefs.getInt(_kInterval) ?? 0;

  Future<void> setTrackingIntervalSeconds(int seconds) =>
      _prefs.setInt(_kInterval, seconds);

    bool get hapticsEnabled => _prefs.getBool(_kHapticsEnabled) ?? true;

    Future<void> setHapticsEnabled(bool value) =>
      _prefs.setBool(_kHapticsEnabled, value);

  TrackingInterval get currentInterval => kTrackingIntervals.firstWhere(
    (i) => i.seconds == trackingIntervalSeconds,
    orElse: () => kTrackingIntervals.first,
  );
}

// ─────────────────────────────────────────────
//  Providers
// ─────────────────────────────────────────────

/// AsyncValue of the shared preferences instance
final _sharedPrefsProvider = FutureProvider<SharedPreferences>(
  (_) => SharedPreferences.getInstance(),
);

/// Sync AppSettingsService (available once prefs are loaded)
final appSettingsServiceProvider = Provider<AppSettingsService?>((ref) {
  final prefsAsync = ref.watch(_sharedPrefsProvider);
  return prefsAsync.whenOrNull(data: (prefs) => AppSettingsService(prefs));
});

/// Reactive always-on state (true/false)
final alwaysOnTrackingProvider = StateNotifierProvider<_AlwaysOnNotifier, bool>(
  (ref) => _AlwaysOnNotifier(ref),
);

class _AlwaysOnNotifier extends StateNotifier<bool> {
  _AlwaysOnNotifier(this._ref) : super(false) {
    _ref.listen<AsyncValue<SharedPreferences>>(_sharedPrefsProvider, (_, next) {
      next.whenData((prefs) {
        state = prefs.getBool(_kAlwaysOn) ?? false;
      });
    });
  }
  final Ref _ref;

  Future<void> set(bool value) async {
    final prefs = await _ref.read(_sharedPrefsProvider.future);
    await prefs.setBool(_kAlwaysOn, value);
    state = value;
  }
}

/// Reactive interval seconds
final trackingIntervalProvider =
    StateNotifierProvider<_IntervalNotifier, int>((ref) => _IntervalNotifier(ref));

class _IntervalNotifier extends StateNotifier<int> {
  _IntervalNotifier(this._ref) : super(0) {
    _ref.listen<AsyncValue<SharedPreferences>>(_sharedPrefsProvider, (_, next) {
      next.whenData((prefs) {
        state = prefs.getInt(_kInterval) ?? 0;
      });
    });
  }
  final Ref _ref;

  Future<void> set(int seconds) async {
    final prefs = await _ref.read(_sharedPrefsProvider.future);
    await prefs.setInt(_kInterval, seconds);
    state = seconds;
  }
}

/// Reactive haptic feedback toggle
final hapticsEnabledProvider =
    StateNotifierProvider<_HapticsNotifier, bool>((ref) => _HapticsNotifier(ref));

class _HapticsNotifier extends StateNotifier<bool> {
  _HapticsNotifier(this._ref) : super(true) {
    _ref.listen<AsyncValue<SharedPreferences>>(_sharedPrefsProvider, (_, next) {
      next.whenData((prefs) {
        state = prefs.getBool(_kHapticsEnabled) ?? true;
      });
    });
  }

  final Ref _ref;

  Future<void> set(bool value) async {
    final prefs = await _ref.read(_sharedPrefsProvider.future);
    await prefs.setBool(_kHapticsEnabled, value);
    state = value;
  }
}
