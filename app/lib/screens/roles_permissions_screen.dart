import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pages that can be assigned permissions
// ─────────────────────────────────────────────────────────────────────────────
const List<String> kAppPages = [
  'Dashboard', 'POS', 'POS: Dine-In Only', 'POS: Hide Cart View', 'Dining Tables', 'KDS', 'Order Queue',
  'Items', 'POS Orders', 'Pre Orders', 'Offers', 'Shifts & Cash', 'Reports & Logs',
  'Administrators', 'Delivery Boys', 'Customers', 'Employees', 'Waiters', 'Chefs', 'Short Eats Cabin',
  'Sales Report', 'Items Report', 'Credit Balance Report',
  'Raw Materials', 'POS Stock', 'Roles & Permissions', 'Settings',
];

const Set<String> kPagesWithActions = {
  'Items', 'Offers', 'Administrators', 'Delivery Boys',
  'Customers', 'Employees', 'Waiters', 'Chefs', 'Short Eats Cabin',
  'Raw Materials', 'POS Stock', 'Roles & Permissions',
  'Pre Orders',
};

// ─────────────────────────────────────────────────────────────────────────────
// Standalone screen wrapper (used from sidebar)
// ─────────────────────────────────────────────────────────────────────────────
class RolesPermissionsScreen extends StatelessWidget {
  const RolesPermissionsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.bgLight,
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: const RolesPermissionsContent(showHeader: true),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable content widget (can be embedded in settings page)
// ─────────────────────────────────────────────────────────────────────────────
class RolesPermissionsContent extends StatefulWidget {
  /// Set to false when embedded in the Settings page (header already provided)
  final bool showHeader;
  const RolesPermissionsContent({Key? key, this.showHeader = false}) : super(key: key);

  @override
  State<RolesPermissionsContent> createState() => _RolesPermissionsContentState();
}

class _RolesPermissionsContentState extends State<RolesPermissionsContent> {
  List<Map<String, dynamic>> _roles = [];
  bool _loading = true;

  Map<String, dynamic>? _selectedRole;
  List<Map<String, dynamic>> _permissions = [];
  bool _permLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    setState(() => _loading = true);
    try {
      final roles = await APIService.instance.getRoles();
      setState(() { _roles = roles; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openPermissions(Map<String, dynamic> role) async {
    setState(() { _selectedRole = role; _permLoading = true; });
    try {
      final raw = await APIService.instance.getRolePermissions(role['id']);
      final Map<String, Map<String, dynamic>> saved = { for (final p in raw) p['page'] as String: p };
      final isShortEatsCabin = role['name']?.toString().trim().toLowerCase() == 'short eats cabin';
      final perms = kAppPages.map((page) {
        final s = saved[page];
        bool canView = s?['can_view'] == 1 || s?['can_view'] == true;
        if (s == null && isShortEatsCabin) {
          if (page == 'POS' || page == 'POS: Dine-In Only' || page == 'POS: Hide Cart View' || page == 'Dining Tables') {
            canView = true;
          }
        }
        return {
          'page': page,
          'can_view':   canView,
          'can_create': s?['can_create'] == 1 || s?['can_create'] == true,
          'can_update': s?['can_update'] == 1 || s?['can_update'] == true,
          'can_delete': s?['can_delete'] == 1 || s?['can_delete'] == true,
        };
      }).toList();
      setState(() { _permissions = perms; _permLoading = false; });
    } catch (_) {
      setState(() => _permLoading = false);
    }
  }

  Future<void> _savePermissions() async {
    if (_selectedRole == null) return;
    try {
      await APIService.instance.saveRolePermissions(_selectedRole!['id'], _permissions);
      await APIService.instance.loadCurrentUserPermissions();
      if (mounted) {
        Provider.of<POSController>(context, listen: false).notifyListeners();
      }
      _snack('Permissions saved!');
    } catch (e) {
      _snack(e.toString(), isError: true);
    }
  }

  Future<void> _showRoleDialog({Map<String, dynamic>? role}) async {
    final ctrl = TextEditingController(text: role?['name'] ?? '');
    final isEdit = role != null;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.cardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 420,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Role', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                IconButton(icon: Icon(Icons.close, size: 18, color: AppTheme.textLightSecondary), onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 16),
              Text('NAME *', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              TextField(controller: ctrl, autofocus: true, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                  decoration: const InputDecoration(hintText: 'e.g. Manager')),
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textLightSecondary, side: BorderSide(color: AppTheme.borderLight)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final name = ctrl.text.trim();
                    if (name.isEmpty) return;
                    try {
                      if (isEdit) {
                        await APIService.instance.updateRole(role!['id'], name);
                      } else {
                        await APIService.instance.createRole(name);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _loadRoles();
                    } catch (e) {
                      _snack(e.toString(), isError: true);
                    }
                  },
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteRole(Map<String, dynamic> role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Delete Role', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        content: Text('Delete "${role['name']}"? This cannot be undone.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await APIService.instance.deleteRole(role['id']);
      if (_selectedRole?['id'] == role['id']) setState(() => _selectedRole = null);
      await _loadRoles();
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.danger : AppTheme.accent,
    ));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) =>
      _selectedRole == null ? _buildRoleList() : _buildPermissionsView();

  // ── Role list ───────────────────────────────────────────────────────────────
  Widget _buildRoleList() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.showHeader) ...[
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Role & Permissions', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
            const SizedBox(height: 2),
            Row(children: [
              Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
              Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
              Text('Role & Permissions', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
            ]),
          ])),
          _addRoleBtn(),
        ]),
        const SizedBox(height: 20),
      ] else ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Role & Permissions', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
          _addRoleBtn(),
        ]),
        const SizedBox(height: 4),
        Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 12),
      ],

      // Roles list card
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.cardLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _roles.isEmpty
                  ? Center(child: Text('No roles yet. Click "Add Role" to create one.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)))
                  : Column(children: [
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _roles.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.dividerColor),
                          itemBuilder: (ctx, i) => _buildRoleRow(_roles[i]),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Showing 1 to ${_roles.length} of ${_roles.length} entries',
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        ),
                      ),
                    ]),
        ),
      ),
    ]);
  }

  Widget _addRoleBtn() => ElevatedButton.icon(
    onPressed: () => _showRoleDialog(),
    icon: const Icon(Icons.add_circle_outline, size: 15),
    label: const Text('Add Role'),
    style: ElevatedButton.styleFrom(
      backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
  );

  Widget _buildRoleRow(Map<String, dynamic> role) {
    final memberCount = role['member_count'] ?? 0;
    final isSystem = ['Admin', 'Cashier', 'Waiter', 'Chef', 'Delivery Boy', 'Short Eats Cabin'].contains(role['name']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(role['name'] ?? '', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary)),
          const SizedBox(height: 2),
          Text('($memberCount) Members', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primary)),
        ])),
        _actionBtn('Permissions', Icons.shield_outlined, const Color(0xFFFF1B6B), () => _openPermissions(role)),
        const SizedBox(width: 6),
        _actionBtn('Edit', Icons.edit_outlined, const Color(0xFF10B981), () => _showRoleDialog(role: role)),
        if (!isSystem) ...[
          const SizedBox(width: 6),
          _actionBtn('Delete', Icons.delete_outline, AppTheme.danger, () => _deleteRole(role)),
        ],
      ]),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) =>
    OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 11),
      label: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

  // ── Permissions detail ──────────────────────────────────────────────────────
  Widget _buildPermissionsView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header row with back button
      Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 15, color: AppTheme.textLightPrimary),
          onPressed: () => setState(() => _selectedRole = null),
          style: IconButton.styleFrom(foregroundColor: AppTheme.primary),
          tooltip: 'Back to roles',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.outfit(fontSize: widget.showHeader ? 20 : 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
              children: [
                const TextSpan(text: 'Role & Permissions '),
                TextSpan(text: '(${_selectedRole!['name']})', style: TextStyle(color: AppTheme.primary)),
              ],
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _savePermissions,
          icon: const Icon(Icons.check_circle_outline, size: 15),
          label: const Text('Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ]),
      const SizedBox(height: 12),

      // Permissions table
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.cardLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: _permLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  // Header row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.dividerColor))),
                    child: Row(children: [
                      const SizedBox(width: 32),
                      Expanded(child: Text('PAGE', style: _hStyle())),
                      SizedBox(width: 72, child: Center(child: Text('CREATE', style: _hStyle()))),
                      SizedBox(width: 72, child: Center(child: Text('UPDATE', style: _hStyle()))),
                      SizedBox(width: 72, child: Center(child: Text('DELETE', style: _hStyle()))),
                      SizedBox(width: 72, child: Center(child: Text('VIEW', style: _hStyle()))),
                    ]),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _permissions.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.dividerColor),
                      itemBuilder: (ctx, i) => _buildPermRow(i),
                    ),
                  ),
                ]),
        ),
      ),
    ]);
  }

  Widget _buildPermRow(int i) {
    final perm = _permissions[i];
    final page = perm['page'] as String;
    final hasActions = kPagesWithActions.contains(page);
    final enabled = perm['can_view'] as bool;

    void toggleView(bool? v) => setState(() {
      _permissions[i]['can_view'] = v ?? false;
      if (!(v ?? false)) {
        _permissions[i]['can_create'] = false;
        _permissions[i]['can_update'] = false;
        _permissions[i]['can_delete'] = false;
      }
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: i % 2 == 0 ? AppTheme.cardLight : AppTheme.bgLight,
      child: Row(children: [
        SizedBox(width: 32, child: Checkbox(value: enabled, activeColor: AppTheme.primary, onChanged: toggleView)),
        Expanded(child: Text(page, style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: enabled ? FontWeight.w600 : FontWeight.normal,
          color: enabled ? AppTheme.primary : AppTheme.textLightPrimary,
        ))),
        SizedBox(width: 72, child: Center(child: hasActions ? Checkbox(
          value: perm['can_create'] as bool, activeColor: AppTheme.primary,
          onChanged: enabled ? (v) => setState(() => _permissions[i]['can_create'] = v ?? false) : null,
        ) : const SizedBox())),
        SizedBox(width: 72, child: Center(child: hasActions ? Checkbox(
          value: perm['can_update'] as bool, activeColor: AppTheme.primary,
          onChanged: enabled ? (v) => setState(() => _permissions[i]['can_update'] = v ?? false) : null,
        ) : const SizedBox())),
        SizedBox(width: 72, child: Center(child: hasActions ? Checkbox(
          value: perm['can_delete'] as bool, activeColor: AppTheme.primary,
          onChanged: enabled ? (v) => setState(() => _permissions[i]['can_delete'] = v ?? false) : null,
        ) : const SizedBox())),
        SizedBox(width: 72, child: Center(child: Checkbox(value: enabled, activeColor: AppTheme.primary, onChanged: toggleView))),
      ]),
    );
  }

  TextStyle _hStyle() => GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 0.8);
}
