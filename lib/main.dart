import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'services/background_location_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    if (_isOfflineSupabaseRefreshError(details.exception)) {
      debugPrint('Ignored transient Supabase refresh error while offline.');
      return;
    }
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (_isOfflineSupabaseRefreshError(error)) {
      debugPrint('Ignored transient Supabase refresh error while offline.');
      return true;
    }
    return false;
  };

  runApp(const ProviderScope(child: _BootstrapApp()));
}

bool _isOfflineSupabaseRefreshError(Object error) {
  final message = error.toString();
  return message.contains('AuthRetryableFetchException') &&
      message.contains('Failed host lookup');
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  Future<void> _initialize() async {
    // 1. Initialise Supabase
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    ).timeout(const Duration(seconds: 12));

    // 2. Configure the background service (registers channels & handlers).
    //    Must happen every launch so the service handler is registered.
    await BackgroundLocationService.configure();

    // 3. Auto-resume background tracking if the user had it enabled before.
    final prefs = await SharedPreferences.getInstance();
    final alwaysOn = prefs.getBool('always_on_tracking') ?? false;
    final interval = prefs.getInt('tracking_interval_seconds') ?? 0;
    if (alwaysOn) {
      final isRunning = await BackgroundLocationService.isRunning;
      if (!isRunning) {
        await BackgroundLocationService.start();
      }
      BackgroundLocationService.updateInterval(interval);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Initialization failed. Please restart the app.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ),
          );
        }

        return const TravelSyncApp();
      },
    );
  }
}

class TravelSyncApp extends ConsumerWidget {
  const TravelSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'TrailSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
