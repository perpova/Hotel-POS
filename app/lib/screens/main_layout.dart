import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../pos_controller.dart';
import '../controllers/dashboard_controller.dart';
import '../theme.dart';
import '../api_service.dart';
import '../widgets/image_helper.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'pos_screen.dart';
import 'table_management_screen.dart';
import 'kds_screen.dart';
import 'order_queue_screen.dart';
import 'shift_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({Key? key}) : super(key: key);

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<String> _titles = [
    'Dashboard',
    'POS System',
    'Dining Tables',
    'Kitchen Display (KDS)',
    'Order Queue Screen',
    'Shifts & Drawer',
    'Reports & Logs',
    'Settings & Stock',
  ];

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const POSScreen();
      case 2:
        return const TableManagementScreen();
      case 3:
        return const KDSScreen();
      case 4:
        return const OrderQueueScreen();
      case 5:
        return const ShiftScreen();
      case 6:
        return const ReportsScreen();
      case 7:
        return const SettingsScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = Provider.of<POSController>(context, listen: false);
      controller.reloadEnvironment();
      controller.setupEventSubscription();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;
    final posController = Provider.of<POSController>(context);
    final dashController = Provider.of<DashboardController>(context);

    // Sidebar items structure categorized like FoodKing
    final categories = [
      _SidebarCategory(
        null,
        [
          _SidebarItem(Icons.dashboard_outlined, 'Dashboard', 0),
          _SidebarItem(Icons.table_restaurant_outlined, 'Dining Tables', 2),
        ],
      ),
      _SidebarCategory(
        'POS & ORDERS',
        [
          _SidebarItem(Icons.point_of_sale_outlined, 'POS System', 1),
          _SidebarItem(Icons.queue_play_next_outlined, 'Queue Screen', 4),
          _SidebarItem(Icons.kitchen_outlined, 'K.D.S (Kitchen)', 3),
        ],
      ),
      _SidebarCategory(
        'REPORTS & SHIFTS',
        [
          _SidebarItem(Icons.monetization_on_outlined, 'Shifts & Cash', 5),
          _SidebarItem(Icons.analytics_outlined, 'Reports & Logs', 6),
        ],
      ),
      _SidebarCategory(
        'SYSTEM',
        [
          _SidebarItem(Icons.settings_outlined, 'Settings & Stock', 7),
        ],
      ),
    ];

    Widget buildSidebarContent() {
      return Container(
        color: Colors.white,
        child: Column(
          children: [
            // Logo area styled exactly like FoodKing
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.restaurant_menu, color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 8),
                  RichText(
                    text: TextSpan(
                      text: 'Food',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                      children: [
                        TextSpan(
                          text: 'King',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFFFB300), // Amber yellow
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // Navigation Links grouped by categories
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: categories.length,
                itemBuilder: (context, catIdx) {
                  final cat = categories[catIdx];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (cat.title != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 16, bottom: 8),
                          child: Text(
                            cat.title!,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF94A3B8), // Slate header text
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                      ...cat.items.map((item) {
                        final isSelected = _selectedIndex == item.screenIndex;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: ListTile(
                            selected: isSelected,
                            selectedTileColor: const Color(0xFFFFF0F5), // Light pink tile bg
                            hoverColor: Colors.pink.withOpacity(0.02),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            leading: Icon(
                              item.icon,
                              color: isSelected ? AppTheme.primary : const Color(0xFF7A869A),
                              size: 18,
                            ),
                            title: Text(
                              item.title,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? AppTheme.primary : const Color(0xFF7A869A),
                              ),
                            ),
                            onTap: () {
                              setState(() {
                                _selectedIndex = item.screenIndex;
                              });
                              if (!isDesktop) {
                                Navigator.pop(context);
                              }
                            },
                            dense: true,
                          ),
                        );
                      }).toList(),
                    ],
                  );
                },
              ),
            ),

            // User Profile Section & Logout
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.primary.withOpacity(0.1),
                        radius: 18,
                        child: APIService.instance.currentUser?.imageBase64 != null && APIService.instance.currentUser!.imageBase64!.isNotEmpty
                            ? ClipOval(
                                child: Base64ImageWidget(
                                  base64Str: APIService.instance.currentUser!.imageBase64,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Text(
                                (APIService.instance.currentUser?.name ?? 'C')[0].toUpperCase(),
                                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              APIService.instance.currentUser?.name ?? 'Guest User',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textLightPrimary,
                              ),
                            ),
                            Text(
                              (APIService.instance.currentUser?.role ?? 'cashier').toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textLightSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () async {
                      await APIService.instance.logout();
                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                        );
                      }
                    },
                    icon: const Icon(Icons.logout, size: 14),
                    label: const Text('Logout'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      minimumSize: const Size.fromHeight(36),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: !isDesktop ? Drawer(child: buildSidebarContent()) : null,
      body: Row(
        children: [
          // Sidebar on Desktop
          if (isDesktop)
            SizedBox(
              width: 240,
              child: buildSidebarContent(),
            ),
          if (isDesktop)
            const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),

          // Main Body Area
          Expanded(
            child: Column(
              children: [
                // Top Header Bar
                Container(
                  height: 70,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      if (!isDesktop)
                        IconButton(
                          icon: const Icon(Icons.menu),
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                        ),

                      Text(
                        _titles[_selectedIndex],
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textLightPrimary,
                        ),
                      ),

                      const Spacer(),

                      // Sync indicator
                      GestureDetector(
                        onTap: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Triggering sync...')),
                          );
                          await posController.reloadEnvironment();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  posController.isOnline
                                      ? 'System Online. Data synchronized successfully.'
                                      : 'System Offline. Offline data remains cached.'
                                ),
                                backgroundColor: posController.isOnline ? AppTheme.accent : AppTheme.warning,
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: posController.isOnline
                                ? AppTheme.accent.withOpacity(0.08)
                                : AppTheme.warning.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: posController.isOnline ? AppTheme.accent : AppTheme.warning,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: posController.isOnline ? AppTheme.accent : AppTheme.warning,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                posController.isOnline ? 'Online' : 'Offline',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: posController.isOnline ? AppTheme.accent : AppTheme.warning,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.sync,
                                size: 12,
                                color: posController.isOnline ? AppTheme.accent : AppTheme.warning,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Shift Badge (simplified)
                      if (isDesktop && posController.activeShift != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.secondary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.secondary, width: 1),
                          ),
                          child: Text(
                            'SHIFT OPEN',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],

                      // Branch selection dropdown
                      if (isDesktop) ...[
                        Row(
                          children: [
                            const Icon(Icons.storefront_outlined, color: AppTheme.primary, size: 18),
                            const SizedBox(width: 6),
                            DropdownButton<String>(
                              value: dashController.selectedBranch,
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B), size: 18),
                              underline: const SizedBox(),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                              items: <String>['Mirpur-1 (Main)', 'Mirpur-2', 'Dhanmondi']
                                  .map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  dashController.setBranch(newValue);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                      ],

                      // Language selection dropdown
                      if (isDesktop) ...[
                        Row(
                          children: [
                            const Icon(Icons.language_outlined, color: Colors.blue, size: 18),
                            const SizedBox(width: 6),
                            DropdownButton<String>(
                              value: dashController.selectedLanguage,
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B), size: 18),
                              underline: const SizedBox(),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                              items: <String>['English', 'Sinhala', 'Spanish']
                                  .map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  dashController.setLanguage(newValue);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                      ],

                      // Notification Bell with indicator badge
                      IconButton(
                        icon: const Badge(
                          label: Text('1', style: TextStyle(fontSize: 8)),
                          backgroundColor: Colors.red,
                          child: Icon(Icons.notifications_none_outlined, color: Color(0xFF64748B), size: 20),
                        ),
                        onPressed: () {},
                      ),

                      const SizedBox(width: 8),

                      // Profile Display
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.teal.shade100,
                            child: APIService.instance.currentUser?.imageBase64 != null && APIService.instance.currentUser!.imageBase64!.isNotEmpty
                                ? ClipOval(
                                    child: Base64ImageWidget(
                                      base64Str: APIService.instance.currentUser!.imageBase64,
                                      width: 32,
                                      height: 32,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(Icons.face, color: Colors.teal, size: 20),
                          ),
                          if (isDesktop) ...[
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Hello',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    color: const Color(0xFF94A3B8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  APIService.instance.currentUser?.name ?? 'John Doe',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF1E293B),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),

                // Screen Content
                Expanded(
                  child: posController.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: AppTheme.primary),
                        )
                      : _getScreen(_selectedIndex),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String title;
  final int screenIndex;
  _SidebarItem(this.icon, this.title, this.screenIndex);
}

class _SidebarCategory {
  final String? title;
  final List<_SidebarItem> items;
  _SidebarCategory(this.title, this.items);
}
