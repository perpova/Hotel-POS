import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../core/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({Key? key, required this.updateInfo}) : super(key: key);

  static Future<void> show(BuildContext context, UpdateInfo info) async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _dontRemind = false;
  bool _isLaunching = false;
  double _progress = 0.0;

  @override
  Widget build(BuildContext context) {
    final info = widget.updateInfo;
    final String ver = info.latestVersion.startsWith('v') ? info.latestVersion : 'V${info.latestVersion}';
    final List<String> changelogLines = (info.changelog ?? 'General performance improvements and bug fixes.')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xFF141926),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.borderLight, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withOpacity(0.15),
              blurRadius: 32,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header Graphic Banner with Rocket ─────────────────────
              Container(
                width: double.infinity,
                height: 160,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF1D4ED8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background Glow Orbs
                    Positioned(
                      top: -20,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF3B82F6).withOpacity(0.3),
                        ),
                      ),
                    ),
                    // Rocket Icon Badge
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2563EB),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3B82F6).withOpacity(0.5),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Content Body ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'New Update Available',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Version & Date Badge Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Version: ',
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                        ),
                        Text(
                          ver,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF3B82F6),
                          ),
                        ),
                      ],
                    ),
                    if (info.releaseDate != null && info.releaseDate!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Update time:  ${info.releaseDate}',
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Changelog Bullet Points List
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Scrollbar(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: changelogLines.length,
                          itemBuilder: (ctx, i) {
                            final line = changelogLines[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '• ',
                                    style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Expanded(
                                    child: Text(
                                      line,
                                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // "Don't remind me today" Checkbox
                    GestureDetector(
                      onTap: () async {
                        setState(() => _dontRemind = !_dontRemind);
                        final prefs = await SharedPreferences.getInstance();
                        final today = DateTime.now().toIso8601String().substring(0, 10);
                        if (_dontRemind) {
                          await prefs.setString('suppress_update_date', today);
                        } else {
                          await prefs.remove('suppress_update_date');
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: _dontRemind,
                              activeColor: const Color(0xFF2563EB),
                              onChanged: (v) async {
                                setState(() => _dontRemind = v ?? false);
                                final prefs = await SharedPreferences.getInstance();
                                final today = DateTime.now().toIso8601String().substring(0, 10);
                                if (_dontRemind) {
                                  await prefs.setString('suppress_update_date', today);
                                } else {
                                  await prefs.remove('suppress_update_date');
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Don't remind me today",
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_isLaunching) ...[
                      LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        backgroundColor: const Color(0xFF1E2D45),
                        color: const Color(0xFF2563EB),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Downloading update... ${(_progress * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      // Primary Button: "Update now"
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (info.downloadUrl != null && info.downloadUrl!.endsWith('.apk')) {
                              setState(() {
                                _isLaunching = true;
                                _progress = 0.0;
                              });
                              await UpdateService.instance.downloadAndInstallApk(
                                info.downloadUrl!,
                                onProgress: (p) {
                                  if (mounted) setState(() => _progress = p);
                                },
                                onError: (err) async {
                                  if (mounted) {
                                    setState(() => _isLaunching = false);
                                    await UpdateService.instance.launchUpdate(info);
                                  }
                                },
                              );
                            } else {
                              setState(() => _isLaunching = true);
                              final ok = await UpdateService.instance.launchUpdate(info);
                              if (mounted) {
                                setState(() => _isLaunching = false);
                                if (ok) {
                                  Navigator.pop(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Could not open update link: ${info.downloadUrl ?? ''}'),
                                      backgroundColor: AppColors.error,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            elevation: 6,
                            shadowColor: const Color(0xFF2563EB).withOpacity(0.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          child: Text(
                            'Update now',
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],

                    // Secondary Button: "Close"
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Close',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
