import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/realtime_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/stock_provider.dart';
import 'providers/live_pos_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authProvider = AuthProvider();
  await authProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => RealtimeProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => StockProvider()),
        ChangeNotifierProvider(create: (_) => LivePosProvider()),
      ],
      child: const HotelAdminApp(),
    ),
  );
}

class HotelAdminApp extends StatelessWidget {
  const HotelAdminApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return MaterialApp(
      title: 'Hotel POS Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: auth.isAuthenticated ? const MainShell() : const LoginScreen(),
    );
  }
}
