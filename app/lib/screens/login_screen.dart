import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import '../services/window_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
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
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
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

  void _showServerConfigDialog() {
    final urlController = TextEditingController(text: APIService.instance.displayUrl);
    bool testing = false;
    String? testResult;
    bool isSuccess = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.wifi_tethering, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Text('Server / LAN Connection', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect this app/terminal to your Main POS Computer IP or Cloud/VPS Server.',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                    ),
                    const SizedBox(height: 16),
                    Text('Backend Server API URL', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: urlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        hintText: 'e.g. https://abc1.com or http://192.168.1.100:3000',
                        prefixIcon: const Icon(Icons.dns_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Quick Presets:', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.cloud_done_outlined, size: 14, color: Colors.blue),
                          label: const Text('Default (https://abc1.com)', style: TextStyle(fontSize: 11)),
                          onPressed: () => setDialogState(() => urlController.text = 'https://abc1.com'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.bug_report_outlined, size: 14, color: Colors.orange),
                          label: const Text('Testing (https://abc2.com)', style: TextStyle(fontSize: 11)),
                          onPressed: () => setDialogState(() => urlController.text = 'https://abc2.com'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.computer_outlined, size: 14, color: Colors.green),
                          label: const Text('Localhost (http://localhost:3000)', style: TextStyle(fontSize: 11)),
                          onPressed: () => setDialogState(() => urlController.text = 'http://localhost:3000'),
                        ),
                        ActionChip(
                          label: const Text('http://192.168.1.100:3000', style: TextStyle(fontSize: 11)),
                          onPressed: () => setDialogState(() => urlController.text = 'http://192.168.1.100:3000'),
                        ),
                      ],
                    ),
                    if (testResult != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSuccess ? Colors.green : Colors.red),
                        ),
                        child: Row(
                          children: [
                            Icon(isSuccess ? Icons.check_circle : Icons.error_outline,
                                color: isSuccess ? Colors.green : Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                testResult!,
                                style: TextStyle(color: isSuccess ? Colors.green.shade900 : Colors.red.shade900, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: testing ? null : () async {
                    var targetUrl = urlController.text.trim();
                    if (targetUrl.isEmpty) return;
                    if (targetUrl == 'https://abc1.com' || targetUrl == 'abc1.com') targetUrl = 'https://pos0001.perpova.com';
                    if (targetUrl == 'https://abc2.com' || targetUrl == 'abc2.com') targetUrl = 'https://pos0001.perpova.dev';
                    setDialogState(() {
                      testing = true;
                      testResult = null;
                    });
                    try {
                      final res = await http.get(Uri.parse('$targetUrl/api/categories')).timeout(const Duration(seconds: 4));
                      if (res.statusCode == 200 || res.statusCode == 401) {
                        setDialogState(() {
                          testResult = 'Success! Connected to server.';
                          isSuccess = true;
                        });
                      } else {
                        setDialogState(() {
                          testResult = 'Server responded with code ${res.statusCode}';
                          isSuccess = false;
                        });
                      }
                    } catch (e) {
                      setDialogState(() {
                        testResult = 'Cannot reach server at $targetUrl. Ensure phone is on same Wi-Fi.';
                        isSuccess = false;
                      });
                    } finally {
                      setDialogState(() => testing = false);
                    }
                  },
                  child: testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Test Connection'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  onPressed: () async {
                    final newUrl = urlController.text.trim();
                    if (newUrl.isNotEmpty) {
                      await APIService.instance.setBaseUrl(newUrl);
                      if (mounted) setState(() {});
                    }
                    Navigator.pop(context);
                  },
                  child: const Text('Save Server URL', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
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
                          // App Logo & Settings Button
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
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
                              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  child: IconButton(
                                    icon: Icon(
                                      WindowHelper.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                      color: AppTheme.primary,
                                    ),
                                    tooltip: WindowHelper.isFullScreen ? 'Exit Full Screen' : 'Enter Full Screen (Hide Title Bar)',
                                    onPressed: () {
                                      setState(() {
                                        WindowHelper.toggleFullScreen();
                                      });
                                    },
                                  ),
                                ),
                              if (!kIsWeb)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IconButton(
                                    icon: Icon(Icons.settings_ethernet, color: AppTheme.primary),
                                    tooltip: 'Server Connection IP Settings',
                                    onPressed: _showServerConfigDialog,
                                  ),
                                ),
                            ],
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
                          
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: AppTheme.danger,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          
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
                          if (!kIsWeb)
                            Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: InkWell(
                                onTap: _showServerConfigDialog,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.wifi_tethering, size: 14, color: AppTheme.primary),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Server: ${APIService.instance.displayUrl}',
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '(Change IP)',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppTheme.textLightSecondary,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
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
