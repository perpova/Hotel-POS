import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/realtime_provider.dart';
import '../screens/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl = TextEditingController();
  bool _isConnected = false;
  bool _testingConn = false;
  List<Map<String, dynamic>> _notifications = [];
  bool _loadingNotifs = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = ApiService.instance.baseUrl;
    _loadNotifications();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() => _testingConn = true);
    final ok = await ApiService.instance.checkConnectivity();
    setState(() { _isConnected = ok; _testingConn = false; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? '✓ Server connected!' : '✗ Cannot reach server'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _saveUrl() async {
    final auth = context.read<AuthProvider>();
    await auth.setBaseUrl(_urlCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Server URL saved'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _loadNotifications() async {
    setState(() => _loadingNotifs = true);
    try {
      final data = await ApiService.instance.getNotifications();
      setState(() { _notifications = data; _loadingNotifs = false; });
    } catch (_) {
      setState(() => _loadingNotifs = false);
    }
  }

  Future<void> _markAllRead() async {
    final realtime = context.read<RealtimeProvider>();
    try {
      await ApiService.instance.markAllNotificationsRead();
      realtime.clearUnreadNotifications();
      await _loadNotifications();
    } catch (_) {}
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final unread = context.watch<RealtimeProvider>().unreadNotifications;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          // ── User card ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1400), Color(0xFF0D1120)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 2),
                  ),
                  child: Center(
                    child: Text(
                      (user?.name.isNotEmpty == true)
                          ? user!.name[0].toUpperCase()
                          : 'A',
                      style: const TextStyle(
                          color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? 'Admin',
                          style: const TextStyle(color: AppColors.textPrimary,
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text('@${user?.username ?? ''}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGlow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          (user?.role ?? 'admin').toUpperCase(),
                          style: const TextStyle(color: AppColors.primary,
                              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),

          const SizedBox(height: 24),

          // ── Server config ─────────────────────────────────────────
          _sectionLabel('SERVER CONNECTION'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.x:3000',
                    prefixIcon: Icon(Icons.dns_rounded, color: AppColors.textMuted, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testingConn ? null : _testConnection,
                        icon: _testingConn
                            ? const SizedBox(width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info))
                            : const Icon(Icons.wifi_rounded, size: 16, color: AppColors.info),
                        label: Text(_testingConn ? 'Testing...' : 'Test Connection',
                            style: const TextStyle(color: AppColors.info, fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.info),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveUrl,
                        icon: const Icon(Icons.save_rounded, size: 16),
                        label: const Text('Save URL', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 80.ms),

          const SizedBox(height: 24),

          // ── Notifications ─────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionLabel('NOTIFICATIONS ${unread > 0 ? '($unread unread)' : ''}'),
              if (_notifications.any((n) => n['is_read'] == false || n['is_read'] == 0))
                TextButton(
                  onPressed: _markAllRead,
                  child: const Text('Mark all read',
                      style: TextStyle(color: AppColors.primary, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _loadingNotifs
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)))
              : _notifications.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Center(
                        child: Text('No notifications',
                            style: TextStyle(color: AppColors.textMuted)),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: _notifications.take(10).toList().asMap().entries.map((e) {
                          final i = e.key;
                          final n = e.value;
                          final isRead = n['is_read'] == true || n['is_read'] == 1;
                          final isLowStock = n['type'] == 'low_stock';
                          return Column(
                            children: [
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isLowStock
                                        ? AppColors.errorGlow
                                        : AppColors.infoGlow,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isLowStock
                                        ? Icons.warning_amber_rounded
                                        : Icons.notifications_rounded,
                                    color: isLowStock ? AppColors.error : AppColors.info,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  n['title']?.toString() ?? '',
                                  style: TextStyle(
                                    color: isRead ? AppColors.textSecondary : AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  n['message']?.toString() ?? '',
                                  style: const TextStyle(
                                      color: AppColors.textMuted, fontSize: 11),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: isRead
                                    ? null
                                    : Container(
                                        width: 8, height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                onTap: () async {
                                  if (!isRead) {
                                    await ApiService.instance
                                        .markNotificationRead(n['id']);
                                    _loadNotifications();
                                  }
                                },
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 120.ms),

          const SizedBox(height: 24),

          // ── App info ──────────────────────────────────────────────
          _sectionLabel('APP'),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _infoTile(Icons.info_outline_rounded, 'Version', 'Hotel POS Admin v1.0'),
                const Divider(height: 1),
                _infoTile(Icons.business_rounded, 'Developer', 'Perpova Developers'),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.errorGlow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
                  ),
                  title: const Text('Sign Out',
                      style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                  onTap: _logout,
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 160.ms),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8),
      );

  Widget _infoTile(IconData icon, String label, String value) => ListTile(
        leading: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.bgCardAlt,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 18),
        ),
        title: Text(label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        trailing: Text(value,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
      );
}
