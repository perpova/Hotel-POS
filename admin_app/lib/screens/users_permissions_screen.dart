import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../core/api_service.dart';
import '../models/models.dart';

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

class UsersPermissionsScreen extends StatefulWidget {
  const UsersPermissionsScreen({Key? key}) : super(key: key);

  @override
  State<UsersPermissionsScreen> createState() => _UsersPermissionsScreenState();
}

class _UsersPermissionsScreenState extends State<UsersPermissionsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription? _wsSub;

  // Users State
  List<UserModel> _users = [];
  bool _loadingUsers = true;
  String _searchQuery = '';
  String? _selectedRoleFilter;

  // Roles & Permissions State
  List<Map<String, dynamic>> _roles = [];
  bool _loadingRoles = true;
  Map<String, dynamic>? _selectedRole;
  List<Map<String, dynamic>> _permissions = [];
  bool _loadingPerms = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUsers();
    _loadRoles();

    // Listen for real-time WebSocket database changes
    _wsSub = ApiService.instance.eventStream.listen((event) {
      final type = event['type']?.toString();
      if (type == 'database_synchronized' || type == 'ws_reconnected' || type == 'user_updated') {
        _loadUsers();
        _loadRoles();
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  String _formatDisplayRole(String role) {
    final lower = role.trim().toLowerCase();
    if (lower == 'kitchen' || lower == 'chef') return 'Chef';
    if (lower == 'delivery' || lower == 'delivery boy') return 'Delivery Boy';
    if (lower == 'waiter' || lower == 'steward') return 'Waiter';
    if (lower == 'admin' || lower == 'administrator') return 'Admin';
    if (lower == 'cashier' || lower == 'employee') return 'Cashier';
    if (lower == 'owner') return 'Owner';
    if (lower == 'short eats cabin') return 'Short Eats Cabin';
    return role;
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final users = await ApiService.instance.getUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _loadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingUsers = false);
        _snack(e.toString(), isError: true);
      }
    }
  }

  Future<void> _loadRoles() async {
    setState(() => _loadingRoles = true);
    try {
      final roles = await ApiService.instance.getRoles();
      if (mounted) {
        setState(() {
          _roles = roles;
          _loadingRoles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingRoles = false);
        _snack(e.toString(), isError: true);
      }
    }
  }

  Future<void> _openRolePermissions(Map<String, dynamic> role) async {
    setState(() {
      _selectedRole = role;
      _loadingPerms = true;
    });
    try {
      final raw = await ApiService.instance.getRolePermissions(role['id']);
      final Map<String, Map<String, dynamic>> saved = {
        for (final p in raw) p['page'] as String: p
      };
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
          'can_view': canView,
          'can_create': s?['can_create'] == 1 || s?['can_create'] == true,
          'can_update': s?['can_update'] == 1 || s?['can_update'] == true,
          'can_delete': s?['can_delete'] == 1 || s?['can_delete'] == true,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _permissions = perms;
          _loadingPerms = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingPerms = false);
        _snack(e.toString(), isError: true);
      }
    }
  }

  Future<void> _saveRolePermissions() async {
    if (_selectedRole == null) return;
    try {
      await ApiService.instance.saveRolePermissions(_selectedRole!['id'], _permissions);
      _snack('Permissions saved for role "${_selectedRole!['name']}"!');
    } catch (e) {
      _snack(e.toString(), isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─── USER DIALOGS ────────────────────────────────────────────────────────
  Future<void> _showUserDialog({UserModel? user}) async {
    final isEdit = user != null;
    final nameCtrl = TextEditingController(text: user?.name ?? '');
    final usernameCtrl = TextEditingController(text: user?.username ?? '');
    final passwordCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: user?.email ?? '');
    final phoneCtrl = TextEditingController(text: user?.phone ?? '');
    String selectedRole = user?.role ?? (_roles.isNotEmpty ? _roles.first['name'] : 'cashier');
    String selectedStatus = user?.status ?? 'active';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isEdit ? 'Edit User' : 'Add New User',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full Name *', hintText: 'e.g. Perera Perera'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(labelText: 'Username *', hintText: 'e.g. cashier1'),
                  ),
                  if (!isEdit) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password *', hintText: 'Minimum 6 chars'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _roles.any((r) => r['name']?.toString().toLowerCase() == selectedRole.toLowerCase())
                              ? _roles.firstWhere((r) => r['name']?.toString().toLowerCase() == selectedRole.toLowerCase())['name']
                              : selectedRole,
                          dropdownColor: AppColors.bgCardAlt,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: _roles.map<DropdownMenuItem<String>>((r) {
                            final rName = r['name'].toString();
                            return DropdownMenuItem(value: rName, child: Text(rName, style: const TextStyle(color: AppColors.textPrimary)));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setDlgState(() => selectedRole = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedStatus,
                          dropdownColor: AppColors.bgCardAlt,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: 'active', child: Text('Active', style: TextStyle(color: AppColors.success))),
                            DropdownMenuItem(value: 'inactive', child: Text('Inactive', style: TextStyle(color: AppColors.error))),
                          ],
                          onChanged: (val) {
                            if (val != null) setDlgState(() => selectedStatus = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email (Optional)', hintText: 'user@hotel.com'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone (Optional)', hintText: '0771234567'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final username = usernameCtrl.text.trim();
                final password = passwordCtrl.text;
                if (name.isEmpty || username.isEmpty || (!isEdit && password.isEmpty)) {
                  _snack('Please fill in required fields (*)', isError: true);
                  return;
                }
                try {
                  if (isEdit) {
                    await ApiService.instance.updateUser(user.id, {
                      'name': name,
                      'username': username,
                      'role': selectedRole,
                      'status': selectedStatus,
                      'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    });
                    _snack('User updated successfully!');
                  } else {
                    await ApiService.instance.createUser({
                      'name': name,
                      'username': username,
                      'password': password,
                      'role': selectedRole,
                      'status': selectedStatus,
                      'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    });
                    _snack('User created successfully!');
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadUsers();
                  await _loadRoles();
                } catch (e) {
                  _snack(e.toString(), isError: true);
                }
              },
              child: Text(isEdit ? 'Save Changes' : 'Create User'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showResetPasswordDialog(UserModel user) async {
    final pwdCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reset Password for @${user.username}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: pwdCtrl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New Password *', hintText: 'Enter new password'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () async {
              final newPwd = pwdCtrl.text.trim();
              if (newPwd.isEmpty) return;
              try {
                await ApiService.instance.resetUserPassword(user.id, newPwd);
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('Password reset successfully for @${user.username}');
              } catch (e) {
                _snack(e.toString(), isError: true);
              }
            },
            child: const Text('Reset Password'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleUserStatus(UserModel user) async {
    final newStatus = user.status == 'active' ? 'inactive' : 'active';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('${newStatus == 'inactive' ? 'Deactivate' : 'Activate'} User', style: const TextStyle(color: AppColors.textPrimary)),
        content: Text('Are you sure you want to ${newStatus == 'inactive' ? 'deactivate' : 'activate'} user "${user.name}" (@${user.username})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: newStatus == 'inactive' ? AppColors.error : AppColors.success),
            child: Text(newStatus == 'inactive' ? 'Deactivate' : 'Activate', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (newStatus == 'inactive') {
          await ApiService.instance.deleteUser(user.id);
        } else {
          await ApiService.instance.updateUser(user.id, {'status': 'active'});
        }
        _snack('User ${user.username} is now $newStatus');
        await _loadUsers();
      } catch (e) {
        _snack(e.toString(), isError: true);
      }
    }
  }

  // ─── ROLE DIALOGS ────────────────────────────────────────────────────────
  Future<void> _showRoleDialog({Map<String, dynamic>? role}) async {
    final ctrl = TextEditingController(text: role?['name'] ?? '');
    final isEdit = role != null;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(isEdit ? 'Edit Role' : 'Add New Role', style: const TextStyle(color: AppColors.textPrimary)),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Role Name *', hintText: 'e.g. Supervisor'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              try {
                if (isEdit) {
                  await ApiService.instance.updateRole(role['id'], name);
                } else {
                  await ApiService.instance.createRole(name);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadRoles();
                _snack('Role saved successfully');
              } catch (e) {
                _snack(e.toString(), isError: true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRole(Map<String, dynamic> role) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Delete Role', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Are you sure you want to delete role "${role['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ApiService.instance.deleteRole(role['id']);
        if (_selectedRole?['id'] == role['id']) setState(() => _selectedRole = null);
        await _loadRoles();
        _snack('Role deleted');
      } catch (e) {
        _snack(e.toString(), isError: true);
      }
    }
  }

  // ─── BUILD SCREEN ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: const Text('Users & Permissions'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.people_alt_outlined), text: 'Users Management'),
            Tab(icon: Icon(Icons.admin_panel_settings_outlined), text: 'Roles & Permissions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsersTab(),
          _buildRolesTab(),
        ],
      ),
    );
  }

  // ─── TAB 1: USERS ────────────────────────────────────────────────────────
  Widget _buildUsersTab() {
    final filteredUsers = _users.where((u) {
      final matchesSearch = u.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          u.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (u.email?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      final matchesRole = _selectedRoleFilter == null ||
          u.role.toLowerCase() == _selectedRoleFilter!.toLowerCase();
      return matchesSearch && matchesRole;
    }).toList();

    return Column(
      children: [
        // Controls Row
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.bgPrimary,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 450;
              if (isNarrow) {
                return Column(
                  children: [
                    TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: const InputDecoration(
                        hintText: 'Search users...',
                        prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showUserDialog(),
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                        label: const Text('Add User'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: const InputDecoration(
                        hintText: 'Search users by name, username or email...',
                        prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showUserDialog(),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Add User'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // User list
        Expanded(
          child: _loadingUsers
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : filteredUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.people_outline, size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            _users.isEmpty ? 'No users created yet' : 'No users match criteria',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                      itemCount: filteredUsers.length,
                      itemBuilder: (ctx, i) {
                        final u = filteredUsers[i];
                        final isActive = u.status == 'active';
                        final displayRole = _formatDisplayRole(u.role);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: isActive ? AppColors.primaryGlow : AppColors.errorGlow,
                                      child: Text(
                                        u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
                                        style: TextStyle(
                                          color: isActive ? AppColors.primary : AppColors.error,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            u.name,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '@${u.username}',
                                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Action buttons
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.key_rounded, size: 18, color: AppColors.info),
                                          tooltip: 'Reset Password',
                                          onPressed: () => _showResetPasswordDialog(u),
                                        ),
                                        IconButton(
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                                          tooltip: 'Edit User',
                                          onPressed: () => _showUserDialog(user: u),
                                        ),
                                        IconButton(
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          padding: EdgeInsets.zero,
                                          icon: Icon(
                                            isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                            size: 18,
                                            color: isActive ? AppColors.error : AppColors.success,
                                          ),
                                          tooltip: isActive ? 'Deactivate User' : 'Activate User',
                                          onPressed: () => _toggleUserStatus(u),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryGlow,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                      ),
                                      child: Text(
                                        displayRole.toUpperCase(),
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isActive ? AppColors.successGlow : AppColors.errorGlow,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        u.status.toUpperCase(),
                                        style: TextStyle(
                                          color: isActive ? AppColors.success : AppColors.error,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    if (u.email != null && u.email!.isNotEmpty)
                                      Text(
                                        '• ${u.email}',
                                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                      ),
                                    if (u.phone != null && u.phone!.isNotEmpty)
                                      Text(
                                        '• ${u.phone}',
                                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ─── TAB 2: ROLES & PERMISSIONS ──────────────────────────────────────────
  Widget _buildRolesTab() {
    if (_selectedRole != null) {
      return _buildPermissionsMatrix();
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.bgPrimary,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'System Roles',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              ElevatedButton.icon(
                onPressed: () => _showRoleDialog(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Role'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingRoles
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _roles.isEmpty
                  ? const Center(child: Text('No roles defined', style: TextStyle(color: AppColors.textSecondary)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _roles.length,
                      itemBuilder: (ctx, i) {
                        final role = _roles[i];
                        final memberCount = role['member_count'] ?? 0;
                        final isSystemRole = ['Admin', 'Cashier', 'Waiter', 'Chef', 'Delivery Boy', 'Short Eats Cabin'].contains(role['name']);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.primaryGlow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                            ),
                            title: Text(
                              role['name'] ?? '',
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '$memberCount Member(s) assigned',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _openRolePermissions(role),
                                  icon: const Icon(Icons.tune_rounded, size: 14),
                                  label: const Text('Permissions', style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.primary),
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.info),
                                  onPressed: () => _showRoleDialog(role: role),
                                ),
                                if (!isSystemRole)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                                    onPressed: () => _deleteRole(role),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ─── PERMISSIONS MATRIX ──────────────────────────────────────────────────
  Widget _buildPermissionsMatrix() {
    return Column(
      children: [
        // Header with Back and Save Buttons
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.bgPrimary,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                onPressed: () => setState(() => _selectedRole = null),
                tooltip: 'Back to Roles List',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grant Permissions: ${_selectedRole!['name']}',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'Check features to allow/deny access for users with this role.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _saveRolePermissions,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Save Permissions'),
              ),
            ],
          ),
        ),

        // Matrix Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.bgCardAlt,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: const Row(
            children: [
              Expanded(child: Text('FEATURE / PAGE NAME', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold))),
              SizedBox(width: 60, child: Center(child: Text('VIEW', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)))),
              SizedBox(width: 60, child: Center(child: Text('CREATE', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)))),
              SizedBox(width: 60, child: Center(child: Text('UPDATE', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)))),
              SizedBox(width: 60, child: Center(child: Text('DELETE', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)))),
            ],
          ),
        ),

        // Matrix List
        Expanded(
          child: _loadingPerms
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : ListView.separated(
                  itemCount: _permissions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final perm = _permissions[i];
                    final page = perm['page'] as String;
                    final hasActions = kPagesWithActions.contains(page);
                    final canView = perm['can_view'] as bool;

                    void toggleView(bool? val) {
                      setState(() {
                        _permissions[i]['can_view'] = val ?? false;
                        if (!(val ?? false)) {
                          _permissions[i]['can_create'] = false;
                          _permissions[i]['can_update'] = false;
                          _permissions[i]['can_delete'] = false;
                        }
                      });
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      color: i % 2 == 0 ? AppColors.bgCard : AppColors.bgPrimary,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              page,
                              style: TextStyle(
                                color: canView ? AppColors.textPrimary : AppColors.textMuted,
                                fontWeight: canView ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: Center(
                              child: Checkbox(
                                value: canView,
                                activeColor: AppColors.primary,
                                checkColor: Colors.black,
                                onChanged: toggleView,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: Center(
                              child: hasActions
                                  ? Checkbox(
                                      value: perm['can_create'] as bool,
                                      activeColor: AppColors.primary,
                                      checkColor: Colors.black,
                                      onChanged: canView ? (v) => setState(() => _permissions[i]['can_create'] = v ?? false) : null,
                                    )
                                  : const SizedBox(),
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: Center(
                              child: hasActions
                                  ? Checkbox(
                                      value: perm['can_update'] as bool,
                                      activeColor: AppColors.primary,
                                      checkColor: Colors.black,
                                      onChanged: canView ? (v) => setState(() => _permissions[i]['can_update'] = v ?? false) : null,
                                    )
                                  : const SizedBox(),
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: Center(
                              child: hasActions
                                  ? Checkbox(
                                      value: perm['can_delete'] as bool,
                                      activeColor: AppColors.primary,
                                      checkColor: Colors.black,
                                      onChanged: canView ? (v) => setState(() => _permissions[i]['can_delete'] = v ?? false) : null,
                                    )
                                  : const SizedBox(),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
