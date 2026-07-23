import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'api_service.dart';
import 'pos_controller.dart';
import 'controllers/dashboard_controller.dart';
import 'controllers/app_settings_controller.dart';
import 'screens/login_screen.dart';
import 'screens/main_layout.dart';
import 'screens/order_queue_screen.dart';

import 'package:flutter/foundation.dart';
import 'package:video_player_win/video_player_win_plugin.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'services/window_helper.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load app version from pubspec/binary config dynamically
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    POSController.appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
  } catch (e) {
    print('Failed to load package info version: \$e');
  }

  // Register Windows Video Player platform implementation
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    try {
      WindowsVideoPlayer.registerWith();
    } catch (e) {
      print('WindowsVideoPlayer registration error: $e');
    }
  }

  // Initialize services
  final api = APIService.instance;
  await api.init();

  // Initialize app-wide settings (company name, logo, theme color, branches)
  final appSettings = AppSettingsController();
  await appSettings.init();

  final isQueueScreenMode = args.contains('--queue-screen');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => POSController()),
        ChangeNotifierProvider(create: (_) => DashboardController()),
        ChangeNotifierProvider<AppSettingsController>.value(value: appSettings),
      ],
      child: HotelPOSApp(isQueueScreenMode: isQueueScreenMode),
    ),
  );

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows && !isQueueScreenMode) {
    Future.delayed(const Duration(milliseconds: 300), () {
      WindowHelper.enableFullScreen();
    });
  }
}

class HotelPOSApp extends StatelessWidget {
  final bool isQueueScreenMode;
  const HotelPOSApp({Key? key, this.isQueueScreenMode = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final api = APIService.instance;
    // Watch settings to trigger a rebuild of MaterialApp when color or other settings change.
    final settings = context.watch<AppSettingsController>();

    // Queue screen doesn't change theme (always light)
    if (isQueueScreenMode) {
      AppTheme.isDarkMode = false;
    } else {
      AppTheme.isDarkMode = settings.themeMode == ThemeMode.dark ||
          (settings.themeMode == ThemeMode.system &&
              MediaQuery.of(context).platformBrightness == Brightness.dark);
    }

    return MaterialApp(
      title: 'Hotel POS System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isQueueScreenMode ? ThemeMode.light : settings.themeMode,
      // Automatic initial route redirection based on Auth State
      home: isQueueScreenMode
          ? const OrderQueueScreen(isSeparateWindow: true)
          : (api.isAuthenticated ? const MainLayout() : const LoginScreen()),
    );
  }
}


