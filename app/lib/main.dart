import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'api_service.dart';
import 'pos_controller.dart';
import 'controllers/dashboard_controller.dart';
import 'screens/login_screen.dart';
import 'screens/main_layout.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  final api = APIService.instance;
  await api.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => POSController()),
        ChangeNotifierProvider(create: (_) => DashboardController()),
      ],
      child: const HotelPOSApp(),
    ),
  );
}

class HotelPOSApp extends StatelessWidget {
  const HotelPOSApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final api = APIService.instance;

    return MaterialApp(
      title: 'FoodKing POS - LAN-first Restaurant POS System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Automatic initial route redirection based on Auth State
      home: api.isAuthenticated ? const MainLayout() : const LoginScreen(),
    );
  }
}
