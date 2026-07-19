import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/realtime_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/stock_provider.dart';
import '../providers/live_pos_provider.dart';
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

  // Periodic sync fallback when WS is disconnected (every 30s)
  Timer? _periodicSync;

  final List<Widget> _pages = const [
    DashboardScreen(),
    LivePosScreen(),
    StockScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 1. Start WebSocket listener hub
    final realtime = context.read<RealtimeProvider>();
    realtime.init();

    // 2. Wire each provider to the realtime hub
    //    Each provider's onRealtimeEvent has its own event filter + debounce logic
    final dashboard = context.read<DashboardProvider>();
    final stock = context.read<StockProvider>();
    final livePos = context.read<LivePosProvider>();

    realtime.on('*', dashboard.onRealtimeEvent);
    realtime.on('*', stock.onRealtimeEvent);
    realtime.on('*', livePos.onRealtimeEvent);

    // 3. Initial data load (all in parallel)
    _loadAll();

    // 4. Periodic fallback sync every 30 seconds
    //    Handles periods where WS is briefly disconnected
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

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<RealtimeProvider>().unreadNotifications;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgPrimary,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) {
            setState(() => _currentIndex = i);
            // Reload data for the tapped tab immediately for freshness
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
          selectedLabelStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600),
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
