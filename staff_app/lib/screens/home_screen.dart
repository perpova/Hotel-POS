import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/shift_provider.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _myActivity = [];
  bool _loadingActivity = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ShiftProvider>().load();
      _loadActivity();
      _checkWidgetLaunch();
    });
  }

  Future<void> _checkWidgetLaunch() async {
    try {
      final launchedUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (launchedUri != null) {
        _handleWidgetAction();
      }
      HomeWidget.widgetClicked.listen((_) => _handleWidgetAction());
    } catch (_) {}
  }

  Future<void> _handleWidgetAction() async {
    final shift = context.read<ShiftProvider>();
    if (shift.isClockedIn) {
      await shift.clockOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clocked Out via Widget!'), backgroundColor: AppColors.warning),
        );
      }
    } else {
      await shift.clockIn();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clocked In via Widget!'), backgroundColor: AppColors.success),
        );
      }
    }
  }

  Future<void> _loadActivity() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    setState(() => _loadingActivity = true);
    try {
      final act = await ApiService.instance.getMyActivity(auth.user!.role, auth.user!.id);
      if (mounted) setState(() { _myActivity = act; _loadingActivity = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingActivity = false);
    }
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'kitchen': return AppColors.info;
      case 'waiter': return const Color(0xFF8B5CF6);
      case 'cashier': return AppColors.success;
      case 'delivery': return AppColors.warning;
      default: return AppColors.primary;
    }
  }

  IconData _roleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'kitchen': return Icons.restaurant_rounded;
      case 'waiter': return Icons.room_service_rounded;
      case 'cashier': return Icons.point_of_sale_rounded;
      case 'delivery': return Icons.delivery_dining_rounded;
      default: return Icons.person_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final shift = context.watch<ShiftProvider>();
    final user = auth.user;
    final rColor = _roleColor(user?.role ?? '');

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: rColor.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: rColor.withOpacity(0.4)),
              ),
              child: Center(
                child: Text(
                  user?.name.substring(0, 1).toUpperCase() ?? 'U',
                  style: TextStyle(color: rColor, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.name ?? 'Staff Member',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Row(
                  children: [
                    Icon(_roleIcon(user?.role ?? ''), size: 10, color: rColor),
                    const SizedBox(width: 3),
                    Text(
                      user?.role.toUpperCase() ?? '',
                      style: TextStyle(fontSize: 9, color: rColor, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: AppColors.textSecondary),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.bgCard,
        onRefresh: () async {
          await shift.load();
          await _loadActivity();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── HERO CLOCK IN / OUT BUTTON ────────────────────────
            _buildClockHero(shift),
            const SizedBox(height: 20),

            // ── HOME WIDGET INSTRUCTION BANNER ────────────────────
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                try {
                  final isSupported = await HomeWidget.isRequestPinWidgetSupported();
                  if (isSupported == true) {
                    await HomeWidget.requestPinWidget(
                      name: 'StaffShiftWidgetProvider',
                      androidName: 'StaffShiftWidgetProvider',
                    );
                  } else {
                    if (mounted) {
                      _showWidgetInstructionsDialog(context);
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    _showWidgetInstructionsDialog(context);
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bgCardAlt.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.widgets_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Add Home Screen Widget',
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.touch_app_rounded, color: AppColors.primary, size: 14),
                            ],
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Tap here to pin Clock In / Out widget to your phone home screen!',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── MY ACTIVITY SECTION (ROLE AWARE) ──────────────────
            Row(
              children: [
                Text(
                  user?.role.toLowerCase() == 'kitchen' ? 'Prepared Items History' : 'My Orders History',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${_myActivity.length} items',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_loadingActivity)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.primary)))
            else if (_myActivity.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Center(
                  child: Text(
                    'No items logged for this period',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: _myActivity.take(20).toList().asMap().entries.map((e) {
                    final idx = e.key;
                    final item = e.value;
                    final isKitchen = user?.role.toLowerCase() == 'kitchen';
                    final title = isKitchen
                        ? (item['name'] ?? item['product_name'] ?? 'Dish')
                        : '#${item['order_number'] ?? ''}';
                    final sub = isKitchen
                        ? '${item['qty'] ?? item['quantity'] ?? 1} prepared'
                        : 'LKR ${item['total'] ?? 0} · ${item['order_type'] ?? ''}';
                    final dateRaw = item['created_at']?.toString();
                    String dateStr = '';
                    try {
                      if (dateRaw != null) dateStr = DateFormat('dd MMM  hh:mm a').format(DateTime.parse(dateRaw).toLocal());
                    } catch (_) {}

                    return Column(
                      children: [
                        if (idx > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: isKitchen ? AppColors.info.withOpacity(0.15) : AppColors.success.withOpacity(0.15),
                            radius: 14,
                            child: Icon(
                              isKitchen ? Icons.restaurant_rounded : Icons.receipt_rounded,
                              color: isKitchen ? AppColors.info : AppColors.success,
                              size: 14,
                            ),
                          ),
                          title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          trailing: Text(dateStr, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showWidgetInstructionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.widgets_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Add Home Screen Widget', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To add widget on your Android Phone:',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text('1. Go to your Phone Home Screen.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            SizedBox(height: 6),
            Text('2. Press & hold (Long Press) on any empty space on your home screen.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            SizedBox(height: 6),
            Text('3. Tap "Widgets".', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            SizedBox(height: 6),
            Text('4. Scroll to "Hotel Staff", tap it, and drag the Clock In/Out widget to your home screen!', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
            ),
            child: const Text('GOT IT'),
          ),
        ],
      ),
    );
  }

  Widget _buildClockHero(ShiftProvider shift) {
    final isIn = shift.isClockedIn;
    final color = isIn ? AppColors.error : AppColors.success;
    final bgGlow = isIn ? AppColors.error.withOpacity(0.15) : AppColors.successGlow;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bgGlow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scaleXY(begin: 1, end: 1.6, duration: 600.ms)
                    .then()
                    .scaleXY(begin: 1.6, end: 1, duration: 600.ms),
                const SizedBox(width: 6),
                Text(
                  isIn ? 'SHIFT IN PROGRESS' : 'READY FOR SHIFT',
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Digital Timer
          if (isIn) ...[
            Text(
              shift.liveDurationFormatted,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 44,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Clocked In at ${DateFormat('hh:mm a, dd MMM').format(shift.activeShift!.clockIn)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ] else ...[
            const Text(
              '00:00:00',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 44,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap button below to start your shift',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),

          // Giant Action Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: shift.isLoading
                  ? null
                  : () async {
                      if (isIn) {
                        final ok = await shift.clockOut();
                        if (ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Clocked Out successfully!'), backgroundColor: AppColors.warning),
                          );
                        }
                      } else {
                        final ok = await shift.clockIn();
                        if (ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Clocked In successfully!'), backgroundColor: AppColors.success),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: isIn ? Colors.white : Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: shift.isLoading
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isIn ? Icons.timer_off_rounded : Icons.play_arrow_rounded, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          isIn ? 'CLOCK OUT NOW' : 'CLOCK IN NOW',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
