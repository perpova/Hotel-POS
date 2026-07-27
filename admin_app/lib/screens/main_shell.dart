import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/realtime_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/stock_provider.dart';
import '../providers/live_pos_provider.dart';
import '../providers/notification_provider.dart';
import '../widgets/notification_panel.dart';
import 'dashboard_screen.dart';
import 'live_pos_screen.dart';
import 'stock_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({Key? key}) : super(key: key);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _notifPanelOpen = false;

  // Periodic sync fallback when WS is disconnected (every 30s)
  Timer? _periodicSync;

  final List<Widget> _pages = [
    const DashboardScreen(),
    const LivePosScreen(),
    const StockScreen(),
    ReportsScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 1. Start WebSocket listener hub
    final realtime = context.read<RealtimeProvider>();
    realtime.init();

    // 2. Wire each provider to the realtime hub
    final dashboard = context.read<DashboardProvider>();
    final stock = context.read<StockProvider>();
    final livePos = context.read<LivePosProvider>();
    final notif = context.read<NotificationProvider>();

    realtime.on('*', dashboard.onRealtimeEvent);
    realtime.on('*', stock.onRealtimeEvent);
    realtime.on('*', livePos.onRealtimeEvent);
    realtime.on('*', notif.onRealtimeEvent);

    // 3. Initial data load (all in parallel)
    _loadAll();

    // 4. Start notification provider
    notif.init();

    // 5. Periodic fallback sync every 30 seconds
    _periodicSync = Timer.periodic(const Duration(seconds: 30), (_) {
      dashboard.load();
      livePos.load();
    });
  }

  void _loadAll() {
    context.read<DashboardProvider>().load();
    context.read<StockProvider>().loadAll();
    context.read<LivePosProvider>().load();
  }

  // Reload data when app comes back to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicSync?.cancel();
    super.dispose();
  }

  void _toggleNotifPanel() {
    setState(() => _notifPanelOpen = !_notifPanelOpen);
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<RealtimeProvider>().unreadNotifications;
    final notifUnread = context.watch<NotificationProvider>().unreadCount;
    final totalUnread = notifUnread; // Use our richer count

    return Scaffold(
      body: Stack(
        children: [
          // ── Main page content ──
          IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),

          // ── Notification panel overlay ──
          if (_notifPanelOpen) ...[
            // Tap-away backdrop
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleNotifPanel,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  color: Colors.black.withOpacity(0.45),
                ),
              ),
            ),
            // Sliding panel from top, below the safe area + appbar region
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                child: NotificationPanel(
                  onClose: _toggleNotifPanel,
                ),
              ),
            ),
          ],
        ],
      ),

      // ── AppBar injected via a custom top bar via extendBodyBehindAppBar ──
      appBar: _buildAppBar(context, totalUnread),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgPrimary,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) {
            setState(() {
              _currentIndex = i;
              _notifPanelOpen = false;
            });
            switch (i) {
              case 0:
                context.read<DashboardProvider>().load();
                break;
              case 1:
                context.read<LivePosProvider>().load();
                break;
              case 2:
                context.read<StockProvider>().loadAll();
                break;
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          selectedLabelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: _buildNavIcon(Icons.monitor_outlined, unread),
              activeIcon: _buildNavIcon(Icons.monitor_rounded, unread),
              label: 'Live POS',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2_rounded),
              label: 'Stock',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart_rounded),
              label: 'Reports',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, int totalUnread) {
    final titles = [
      'Dashboard',
      'Live POS',
      'Stock',
      'Reports',
      'Settings',
    ];

    return AppBar(
      title: Text(titles[_currentIndex]),
      actions: [
        // Notification bell with badge
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _NotificationBell(
            count: totalUnread,
            isOpen: _notifPanelOpen,
            onTap: _toggleNotifPanel,
          ),
        ),
      ],
    );
  }

  Widget _buildNavIcon(IconData icon, int badge) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (badge > 0)
          Positioned(
            right: -8,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                badge > 9 ? '9+' : '$badge',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Notification Bell ────────────────────────────────────────────────────────

class _NotificationBell extends StatefulWidget {
  final int count;
  final bool isOpen;
  final VoidCallback onTap;

  const _NotificationBell({
    required this.count,
    required this.isOpen,
    required this.onTap,
  });

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell>
    with SingleTickerProviderStateMixin {
  late AnimationController _shake;
  late Animation<double> _wobble;
  int _prevCount = 0;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _wobble = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shake, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(_NotificationBell old) {
    super.didUpdateWidget(old);
    if (widget.count > _prevCount) {
      _shake.forward(from: 0);
    }
    _prevCount = widget.count;
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _wobble,
        builder: (_, child) {
          final angle = (0.15 * _wobble.value * (1 - _wobble.value) * 4) *
              ((_wobble.value * 10).round().isEven ? 1 : -1);
          return Transform.rotate(angle: angle, child: child);
        },
        child: Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.only(top: 6, bottom: 6),
          decoration: BoxDecoration(
            color: widget.isOpen
                ? AppColors.primaryGlow
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: widget.isOpen
                ? Border.all(color: AppColors.primary.withOpacity(0.4))
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                widget.isOpen
                    ? Icons.notifications_rounded
                    : (widget.count > 0
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_outlined),
                color: widget.isOpen
                    ? AppColors.primary
                    : (widget.count > 0
                        ? AppColors.textPrimary
                        : AppColors.textMuted),
                size: 22,
              ),
              if (widget.count > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.count > 0 &&
                              widget.count ==
                                  context
                                      .read<NotificationProvider>()
                                      .notifications
                                      .where((n) =>
                                          n.type ==
                                              NotificationType.stockCritical ||
                                          n.type ==
                                              NotificationType.preOrderToday)
                                      .length
                          ? AppColors.error
                          : AppColors.warning,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(
                        minWidth: 16, minHeight: 14),
                    child: Text(
                      widget.count > 99 ? '99+' : '${widget.count}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
