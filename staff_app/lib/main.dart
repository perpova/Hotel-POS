import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/shift_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authProvider = AuthProvider();
  await authProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => ShiftProvider()),
      ],
      child: const StaffApp(),
    ),
  );
}

class StaffApp extends StatelessWidget {
  const StaffApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return MaterialApp(
      title: 'Hotel POS Staff Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: auth.isAuthenticated ? const HomeScreen() : const LoginScreen(),
    );
  }
}
