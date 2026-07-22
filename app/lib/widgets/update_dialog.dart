import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

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
  bool _isDownloading = false;
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
          border: Border.all(color: const Color(0xFF263552), width: 1.2),
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
              // ── Rocket Header Graphic ──────────────────────────────────
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

              // ── Body Content ──────────────────────────────────────────
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

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Version: ', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8))),
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
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Changelog Container
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF1E2D45)),
                      ),
                      child: Scrollbar(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: changelogLines.length,
                          itemBuilder: (ctx, i) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• ', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 13)),
                                  Expanded(
                                    child: Text(
                                      changelogLines[i],
                                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), height: 1.4),
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

                    // Checkbox
                    GestureDetector(
                      onTap: () async {
                        setState(() => _dontRemind = !_dontRemind);
                        final prefs = await SharedPreferences.getInstance();
                        final today = DateTime.now().toIso8601String().substring(0, 10);
                        if (_dontRemind) {
                          await prefs.setString('suppress_pos_update_date', today);
                        } else {
                          await prefs.remove('suppress_pos_update_date');
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
                                  await prefs.setString('suppress_pos_update_date', today);
                                } else {
                                  await prefs.remove('suppress_pos_update_date');
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Don't remind me today",
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_isDownloading) ...[
                      LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        backgroundColor: const Color(0xFF1E2D45),
                        color: const Color(0xFF2563EB),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Downloading update... ${(_progress * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      // Primary Button: "Update now"
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (info.isDirectDownload && info.downloadUrl != null) {
                              setState(() => _isDownloading = true);
                              await UpdateService().startWindowsUpdate(
                                info.downloadUrl!,
                                onProgress: (p) => setState(() => _progress = p),
                                onError: (err) {
                                  if (mounted) {
                                    setState(() => _isDownloading = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Update failed: $err'), backgroundColor: Colors.red),
                                    );
                                  }
                                },
                                onComplete: () {},
                              );
                            } else if (info.downloadUrl != null) {
                              final uri = Uri.parse(info.downloadUrl!);
                              bool launched = false;
                              try {
                                launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } catch (_) {}
                              if (!launched) {
                                try {
                                  launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
                                } catch (_) {}
                              }
                              if (mounted) {
                                if (launched) {
                                  Navigator.pop(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Could not open update URL: ${info.downloadUrl}'), backgroundColor: Colors.red),
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

                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Close',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
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
