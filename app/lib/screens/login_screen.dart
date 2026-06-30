import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../api_service.dart';
import '../theme.dart';
import '../controllers/app_settings_controller.dart';
import '../widgets/image_helper.dart';
import 'main_layout.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController(text: 'cashier');
  final _passwordController = TextEditingController(text: '123456');
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await APIService.instance.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    if (success) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainLayout()),
        );
      }
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = 'Invalid username, password, or inactive account.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;
    final appSettings = context.watch<AppSettingsController>();
    final companyName = appSettings.companyName;
    final hasLogo = appSettings.logoBase64 != null && appSettings.logoBase64!.isNotEmpty;
    final hasFavicon = appSettings.faviconBase64 != null && appSettings.faviconBase64!.isNotEmpty;

    final half = companyName.length > 4 ? companyName.length ~/ 2 : companyName.length;
    final part1 = companyName.substring(0, half);
    final part2 = companyName.substring(half);


    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient circles
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.secondary.withOpacity(0.1),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Container(
                width: isDesktop ? 450 : size.width * 0.9,
                margin: const EdgeInsets.symmetric(vertical: 24),
                child: Card(
                  elevation: 8,
                  shadowColor: Colors.black.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // App Logo
                          Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: hasLogo
                                  ? Base64ImageWidget(base64Str: appSettings.logoBase64, fit: BoxFit.cover)
                                  : hasFavicon
                                      ? Base64ImageWidget(base64Str: appSettings.faviconBase64, fit: BoxFit.cover)
                                      : Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primary.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.restaurant_menu,
                                            size: 40,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                text: part1,
                                style: GoogleFonts.outfit(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                                children: [
                                  TextSpan(
                                    text: part2,
                                    style: GoogleFonts.outfit(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFFFB300),
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' POS',
                                    style: GoogleFonts.outfit(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textLightPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Center(
                            child: Text(
                              'LAN-first + VPS Hybrid System',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppTheme.textLightSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          
                          // Username Field
                          Text(
                            'Username',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textLightPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              hintText: 'Enter your username',
                              prefixIcon: Icon(Icons.person_outline, size: 20),
                            ),
                            validator: (val) => val == null || val.isEmpty ? 'Username is required' : null,
                          ),
                          const SizedBox(height: 20),
                          
                          // Password Field
                          Text(
                            'Password',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textLightPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              hintText: 'Enter your password',
                              prefixIcon: Icon(Icons.lock_outline, size: 20),
                            ),
                            validator: (val) => val == null || val.isEmpty ? 'Password is required' : null,
                          ),
                          
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: AppTheme.danger,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: 32),
                          
                          // Login Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? const SpinKitThreeBounce(color: Colors.white, size: 20)
                                : Text(
                                    'Login',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              'Testing DB: Host: localhost | User: root',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.textLightSecondary.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
