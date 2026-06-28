import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../api_service.dart';
import 'roles_permissions_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _SettingsTab { editProfile, changePassword, rolesPermissions, connection }

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsTab _activeTab = _SettingsTab.editProfile;

  // Edit Profile controllers
  final _firstNameController = TextEditingController();
  final _lastNameController  = TextEditingController();
  final _emailController     = TextEditingController();
  final _phoneController     = TextEditingController();

  // Change Password controllers
  final _oldPasswordController     = TextEditingController();
  final _newPasswordController     = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Connection controller
  final _apiUrlController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _apiUrlController.text = APIService.instance.baseUrl;
    _loadUserData();
  }

  void _loadUserData() {
    final user = APIService.instance.currentUser;
    if (user != null) {
      final parts = user.name.split(' ');
      _firstNameController.text = parts.isNotEmpty ? parts[0] : '';
      _lastNameController.text  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      _emailController.text     = user.email ?? '';
      _phoneController.text     = user.phone ?? '';
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }

  // ─── Save Profile ────────────────────────────────────────────────────────────
  Future<void> _saveProfile() async {
    final firstName = _firstNameController.text.trim();
    final email     = _emailController.text.trim();
    if (firstName.isEmpty || email.isEmpty) {
      _snack('First Name and Email are required.', isError: true);
      return;
    }
    final lastName = _lastNameController.text.trim();
    final name     = lastName.isNotEmpty ? '$firstName $lastName' : firstName;
    final userId   = APIService.instance.currentUser?.id;
    if (userId == null) return;

    setState(() => _saving = true);
    try {
      await APIService.instance.updateProfile(userId, {
        'name': name, 'email': email, 'phone': _phoneController.text.trim(),
      });
      _snack('Profile updated successfully!');
    } catch (e) {
      _snack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Save Password ───────────────────────────────────────────────────────────
  Future<void> _savePassword() async {
    final newPass     = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();
    if (newPass.isEmpty || confirmPass.isEmpty) {
      _snack('Please fill in all password fields.', isError: true);
      return;
    }
    if (newPass != confirmPass) {
      _snack('New passwords do not match.', isError: true);
      return;
    }
    final userId = APIService.instance.currentUser?.id;
    if (userId == null) return;

    setState(() => _saving = true);
    try {
      await APIService.instance.updatePassword(userId, newPass);
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _snack('Password changed successfully!');
    } catch (e) {
      _snack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.danger : AppTheme.accent,
    ));
  }

  // ─── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Breadcrumb
          Row(children: [
            Text('Dashboard', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
            const Icon(Icons.chevron_right, size: 15, color: AppTheme.textLightSecondary),
            Text('Settings', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
            const Icon(Icons.chevron_right, size: 15, color: AppTheme.textLightSecondary),
            Text(_tabTitle(_activeTab),
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 20),

          // Two-panel layout
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Left Sidebar ──────────────────────────────────────────────
              Container(
                width: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _section('PROFILE'),
                      _item(Icons.person_outline,    'Edit Profile',       _SettingsTab.editProfile),
                      _item(Icons.lock_outline,      'Change Password',    _SettingsTab.changePassword),
                      const SizedBox(height: 4),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _section('USERS'),
                      _item(Icons.shield_outlined,   'Role & Permissions', _SettingsTab.rolesPermissions),
                      const SizedBox(height: 4),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _section('SYSTEM'),
                      _item(Icons.settings_ethernet, 'API Connection',     _SettingsTab.connection),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // ── Right Content ──────────────────────────────────────────────
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  padding: _activeTab == _SettingsTab.rolesPermissions
                      ? const EdgeInsets.all(20)
                      : const EdgeInsets.all(28),
                  child: _buildContent(),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ─── Sidebar helpers ─────────────────────────────────────────────────────────
  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold,
        color: const Color(0xFF94A3B8), letterSpacing: 0.8)),
  );

  Widget _item(IconData icon, String label, _SettingsTab tab) {
    final active = _activeTab == tab;
    return InkWell(
      onTap: () => setState(() => _activeTab = tab),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: active ? AppTheme.primary : const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? AppTheme.primary : const Color(0xFF334155),
          )),
        ]),
      ),
    );
  }

  String _tabTitle(_SettingsTab tab) => switch (tab) {
    _SettingsTab.editProfile      => 'Edit Profile',
    _SettingsTab.changePassword   => 'Change Password',
    _SettingsTab.rolesPermissions => 'Role & Permissions',
    _SettingsTab.connection       => 'API Connection',
  };

  // ─── Content panels ──────────────────────────────────────────────────────────
  Widget _buildContent() => switch (_activeTab) {
    _SettingsTab.editProfile      => _buildEditProfile(),
    _SettingsTab.changePassword   => _buildChangePassword(),
    _SettingsTab.rolesPermissions => const RolesPermissionsContent(showHeader: false),
    _SettingsTab.connection       => _buildConnection(),
  };

  // ── Edit Profile ─────────────────────────────────────────────────────────────
  Widget _buildEditProfile() {
    final user = APIService.instance.currentUser;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: Colors.teal.shade50,
            child: const Icon(Icons.face, color: Colors.teal, size: 40),
          ),
          const SizedBox(width: 20),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user?.name ?? '—', style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
              child: Text((user?.role ?? 'user').toUpperCase(),
                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            ),
          ]),
        ]),
        const SizedBox(height: 24),
        Text('Edit Profile', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        const SizedBox(height: 4),
        const Divider(color: Color(0xFFE2E8F0)),
        const SizedBox(height: 16),

        Row(children: [
          Expanded(child: _field('FIRST NAME *', _firstNameController)),
          const SizedBox(width: 16),
          Expanded(child: _field('LAST NAME', _lastNameController)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _field('EMAIL *', _emailController, keyboardType: TextInputType.emailAddress)),
          const SizedBox(width: 16),
          Expanded(child: _field('PHONE', _phoneController, keyboardType: TextInputType.phone)),
        ]),
        const SizedBox(height: 28),
        _saveButton('Save Profile', _saveProfile),
      ]),
    );
  }

  // ── Change Password ──────────────────────────────────────────────────────────
  Widget _buildChangePassword() => SingleChildScrollView(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Change Password', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
      const SizedBox(height: 4),
      const Divider(color: Color(0xFFE2E8F0)),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: _field('OLD PASSWORD *', _oldPasswordController, obscure: true)),
        const SizedBox(width: 16),
        Expanded(child: _field('NEW PASSWORD *', _newPasswordController, obscure: true)),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _field('CONFIRM PASSWORD *', _confirmPasswordController, obscure: true)),
        const SizedBox(width: 16),
        const Expanded(child: SizedBox()),
      ]),
      const SizedBox(height: 28),
      _saveButton('Change Password', _savePassword),
    ]),
  );

  // ── API Connection ───────────────────────────────────────────────────────────
  Widget _buildConnection() {
    final controller = Provider.of<POSController>(context);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('API / VPS Connection', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        const SizedBox(height: 4),
        const Divider(color: Color(0xFFE2E8F0)),
        const SizedBox(height: 8),
        Text('Change the base URL to switch from localhost testing to your remote VPS server.',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(labelText: 'Backend API Base URL', hintText: 'http://localhost:3000'),
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () async {
              final newUrl = _apiUrlController.text.trim();
              if (newUrl.isEmpty) return;
              await APIService.instance.setBaseUrl(newUrl);
              await controller.reloadEnvironment();
              if (mounted) _snack('API Base URL updated to: $newUrl');
            },
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Save & Reconnect'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            ),
          ),
        ]),
      ]),
    );
  }

  // ─── Shared widgets ───────────────────────────────────────────────────────────
  Widget _field(String label, TextEditingController ctrl,
      {bool obscure = false, TextInputType? keyboardType}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold,
          color: const Color(0xFF64748B), letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextField(controller: ctrl, obscureText: obscure, keyboardType: keyboardType,
          style: GoogleFonts.inter(fontSize: 13)),
    ]);

  Widget _saveButton(String label, VoidCallback onTap) => ElevatedButton.icon(
    onPressed: _saving ? null : onTap,
    icon: _saving
        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Icon(Icons.check_circle_outline, size: 16),
    label: Text(label),
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF1E293B), foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
    ),
  );
}
