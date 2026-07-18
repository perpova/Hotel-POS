import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../theme.dart';
import '../api_service.dart';
import '../pos_controller.dart';
import '../controllers/app_settings_controller.dart';
import '../widgets/image_helper.dart';
import 'roles_permissions_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _SettingsTab { company, theme, branches, editProfile, changePassword, rolesPermissions, connection, externalDisplay, kotSound }

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsTab _activeTab = _SettingsTab.company;
  bool _saving = false;

  // ── Edit Profile controllers ──────────────────────────────────────────────
  final _firstNameController = TextEditingController();
  final _lastNameController  = TextEditingController();
  final _emailController     = TextEditingController();
  final _phoneController     = TextEditingController();
  final _oldPasswordController     = TextEditingController();
  final _newPasswordController     = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _apiUrlController = TextEditingController();
  final _queueVideoUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiUrlController.text = APIService.instance.baseUrl;
    _loadUserData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appSettings = Provider.of<AppSettingsController>(context, listen: false);
      _queueVideoUrlController.text = appSettings.queueBgVideoUrl ?? '';
    });
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
    _queueVideoUrlController.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.danger : AppTheme.accent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Breadcrumb ───────────────────────────────────────────────────
          Row(children: [
            Text('Dashboard', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
            Icon(Icons.chevron_right, size: 15, color: AppTheme.textLightSecondary),
            Text('Settings', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
            Icon(Icons.chevron_right, size: 15, color: AppTheme.textLightSecondary),
            Text(_tabTitle(_activeTab),
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 20),

          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Left Sidebar ─────────────────────────────────────────────
              Container(
                width: 220,
                decoration: BoxDecoration(
                  color: AppTheme.cardLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _section('COMPANY'),
                      _item(Icons.business_outlined,     'Company',          _SettingsTab.company),
                      _item(Icons.palette_outlined,      'Theme',            _SettingsTab.theme),
                      _item(Icons.store_outlined,        'Branches',         _SettingsTab.branches),
                      Divider(height: 1, color: AppTheme.isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                      _section('PROFILE'),
                      _item(Icons.person_outline,        'Edit Profile',     _SettingsTab.editProfile),
                      _item(Icons.lock_outline,          'Change Password',  _SettingsTab.changePassword),
                      Divider(height: 1, color: AppTheme.isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                      _section('USERS'),
                      _item(Icons.shield_outlined,       'Roles & Permissions', _SettingsTab.rolesPermissions),
                      Divider(height: 1, color: AppTheme.isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                      _section('SYSTEM'),
                      _item(Icons.settings_ethernet,     'API Connection',   _SettingsTab.connection),
                      _item(Icons.monitor,               'External Display', _SettingsTab.externalDisplay),
                      _item(Icons.volume_up_outlined,    'KOT Sound',        _SettingsTab.kotSound),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // ── Right Content ─────────────────────────────────────────────
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.cardLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
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

  // ── Sidebar helpers ────────────────────────────────────────────────────────
  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(label, style: GoogleFonts.inter(
        fontSize: 10, fontWeight: FontWeight.bold,
        color: AppTheme.textLightSecondary, letterSpacing: 0.8)),
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
          Icon(icon, size: 16, color: active ? AppTheme.primary : AppTheme.textLightSecondary),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? AppTheme.primary : AppTheme.textLightPrimary,
          )),
        ]),
      ),
    );
  }

  String _tabTitle(_SettingsTab tab) => switch (tab) {
    _SettingsTab.company          => 'Company',
    _SettingsTab.theme            => 'Theme',
    _SettingsTab.branches         => 'Branches',
    _SettingsTab.editProfile      => 'Edit Profile',
    _SettingsTab.changePassword   => 'Change Password',
    _SettingsTab.rolesPermissions => 'Roles & Permissions',
    _SettingsTab.connection       => 'API Connection',
    _SettingsTab.externalDisplay  => 'External Display',
    _SettingsTab.kotSound         => 'KOT Sound Settings',
  };

  Widget _buildContent() => switch (_activeTab) {
    _SettingsTab.company          => const _CompanyTab(),
    _SettingsTab.theme            => const _ThemeTab(),
    _SettingsTab.branches         => const _BranchesTab(),
    _SettingsTab.editProfile      => _buildEditProfile(),
    _SettingsTab.changePassword   => _buildChangePassword(),
    _SettingsTab.rolesPermissions => const RolesPermissionsContent(showHeader: false),
    _SettingsTab.connection       => _buildConnection(),
    _SettingsTab.externalDisplay  => _buildExternalDisplay(),
    _SettingsTab.kotSound         => const _KotSoundTab(),
  };

  // ── Edit Profile ─────────────────────────────────────────────────────────
  Widget _buildEditProfile() {
    final user = APIService.instance.currentUser;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 38, backgroundColor: Colors.teal.shade50,
            child: const Icon(Icons.face, color: Colors.teal, size: 40)),
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
        Divider(color: AppTheme.dividerColor),
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
        _saveButton('Save Profile', () async {
          final firstName = _firstNameController.text.trim();
          final email     = _emailController.text.trim();
          if (firstName.isEmpty || email.isEmpty) { _snack('First Name and Email are required.', isError: true); return; }
          final lastName = _lastNameController.text.trim();
          final name     = lastName.isNotEmpty ? '$firstName $lastName' : firstName;
          final userId   = APIService.instance.currentUser?.id;
          if (userId == null) return;
          setState(() => _saving = true);
          try {
            await APIService.instance.updateProfile(userId, {'name': name, 'email': email, 'phone': _phoneController.text.trim()});
            _snack('Profile updated successfully!');
          } catch (e) { _snack(e.toString(), isError: true); }
          finally { if (mounted) setState(() => _saving = false); }
        }),
      ]),
    );
  }

  // ── Change Password ──────────────────────────────────────────────────────
  Widget _buildChangePassword() => SingleChildScrollView(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Change Password', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
      Divider(color: AppTheme.dividerColor),
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
      _saveButton('Change Password', () async {
        final newPass     = _newPasswordController.text.trim();
        final confirmPass = _confirmPasswordController.text.trim();
        if (newPass.isEmpty || confirmPass.isEmpty) { _snack('Please fill in all password fields.', isError: true); return; }
        if (newPass != confirmPass) { _snack('New passwords do not match.', isError: true); return; }
        final userId = APIService.instance.currentUser?.id;
        if (userId == null) return;
        setState(() => _saving = true);
        try {
          await APIService.instance.updatePassword(userId, newPass);
          _oldPasswordController.clear(); _newPasswordController.clear(); _confirmPasswordController.clear();
          _snack('Password changed successfully!');
        } catch (e) { _snack(e.toString(), isError: true); }
        finally { if (mounted) setState(() => _saving = false); }
      }),
    ]),
  );

  // ── API Connection ────────────────────────────────────────────────────────
  Widget _buildConnection() {
    final controller = Provider.of<POSController>(context);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('API / VPS Connection', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 8),
        Text('Change the base URL to switch between localhost and your remote VPS server.',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: TextField(
            controller: _apiUrlController,
            decoration: const InputDecoration(labelText: 'Backend API Base URL', hintText: 'http://localhost:3000'),
          )),
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

  // ── Shared ────────────────────────────────────────────────────────────────
  Widget _field(String label, TextEditingController ctrl,
      {bool obscure = false, TextInputType? keyboardType}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold,
          color: AppTheme.textLightSecondary, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextField(controller: ctrl, obscureText: obscure, keyboardType: keyboardType,
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary)),
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

  Widget _buildExternalDisplay() {
    final appSettings = context.watch<AppSettingsController>();
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('External Display & Queue Window', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 8),
        Text('Configure the Order Queue display on a secondary customer monitor (connected via HDMI).',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
        const SizedBox(height: 24),

        // Auto launch option
        Row(children: [
          Text('Open Queue in Separate Window:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary)),
          const SizedBox(width: 16),
          Switch(
            value: appSettings.extendQueueScreen,
            activeColor: AppTheme.primary,
            onChanged: (val) async {
              await appSettings.toggleExtendQueueScreen();
            },
          ),
          const SizedBox(width: 8),
          Text(
            appSettings.extendQueueScreen ? 'Separate Window Mode Enabled' : 'Disabled (Shows inside main window)',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
          ),
        ]),
        const SizedBox(height: 12),
        Text('When enabled, the Order Queue screen will automatically open as a separate independent window when the system starts.',
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),

        const SizedBox(height: 32),
        Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 20),

        // Queue Screen Background Media
        Text('Queue Screen Background Media', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        const SizedBox(height: 8),
        Text('Upload a background image or paste a video/YouTube link to display behind the Order Queue status boards.',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
        const SizedBox(height: 20),

        // Dropdown selection
        Row(
          children: [
            Text('Background Type: ', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary)),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.borderLight),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: appSettings.queueBgType,
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('None (Default Dark)')),
                    DropdownMenuItem(value: 'image', child: Text('Custom Image (Upload)')),
                    DropdownMenuItem(value: 'video', child: Text('Video / YouTube Link')),
                  ],
                  onChanged: (val) async {
                    if (val != null) {
                      await appSettings.saveQueueBackground(type: val);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Conditional display based on selected background type
        if (appSettings.queueBgType == 'image') ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
                      withData: true,
                    );
                    if (result != null && result.files.single.path != null) {
                      final fileBytes = await File(result.files.single.path!).readAsBytes();
                      final base64Str = base64Encode(fileBytes);
                      await appSettings.saveQueueBackground(
                        type: 'image',
                        imageBase64: base64Str,
                      );
                      _snack('Background image uploaded successfully!');
                    }
                  } catch (e) {
                    _snack('Failed to upload image: $e', isError: true);
                  }
                },
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Upload Background Image'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(width: 16),
              if (appSettings.queueBgImageBase64 != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 120,
                    height: 80,
                    color: Colors.grey.shade100,
                    child: Base64ImageWidget(
                      base64Str: appSettings.queueBgImageBase64,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
            ],
          ),
        ] else if (appSettings.queueBgType == 'video') ...[
          // Video Source Selector
          Row(
            children: [
              Text('Video Source: ', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary)),
              const SizedBox(width: 16),
              ChoiceChip(
                label: const Text('Paste Video / YouTube Link'),
                selected: appSettings.queueBgVideoSource == 'link',
                selectedColor: AppTheme.primary.withOpacity(0.15),
                onSelected: (selected) async {
                  if (selected) {
                    await appSettings.saveQueueBackground(type: 'video', videoSource: 'link');
                  }
                },
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('Upload Local Video File'),
                selected: appSettings.queueBgVideoSource == 'file',
                selectedColor: AppTheme.primary.withOpacity(0.15),
                onSelected: (selected) async {
                  if (selected) {
                    await appSettings.saveQueueBackground(type: 'video', videoSource: 'file');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (appSettings.queueBgVideoSource == 'link') ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: TextField(
                      controller: _queueVideoUrlController,
                    decoration: InputDecoration(
                        hintText: 'Enter YouTube URL or Video Link (e.g. https://youtu.be/...)',
                        labelText: 'Video URL',
                        labelStyle: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                        hintStyle: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.borderLight)),
                        prefixIcon: const Icon(Icons.link, size: 20),
                      ),
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    final val = _queueVideoUrlController.text.trim();
                    await appSettings.saveQueueBackground(type: 'video', videoUrl: val);
                    _snack('Video / YouTube link saved!');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  child: const Text('Save Link'),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.open_in_browser_rounded, color: AppTheme.accent),
                  tooltip: 'Test URL in browser',
                  onPressed: () async {
                    final url = _queueVideoUrlController.text.trim();
                    if (url.isNotEmpty) {
                      try {
                        await Process.run('cmd', ['/c', 'start', '', url]);
                      } catch (_) {}
                    } else {
                      _snack('Please enter a video URL first!', isError: true);
                    }
                  },
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'webm'],
                        withData: false,
                      );
                      if (result != null && result.files.single.path != null) {
                        final pickedPath = result.files.single.path!;
                        final extension = pickedPath.substring(pickedPath.lastIndexOf('.'));
                        final tempDir = Directory.systemTemp;
                        final savedFile = File('${tempDir.path}${Platform.pathSeparator}queue_background_video$extension');
                        
                        if (await savedFile.exists()) {
                          try {
                            await savedFile.delete();
                          } catch (_) {}
                        }
                        
                        await File(pickedPath).copy(savedFile.path);
                        
                        await appSettings.saveQueueBackground(
                          type: 'video',
                          videoSource: 'file',
                          videoPath: savedFile.path,
                        );
                        _snack('Background video uploaded successfully!');
                      }
                    } catch (e) {
                      _snack('Failed to copy video: $e', isError: true);
                    }
                  },
                  icon: const Icon(Icons.video_call_outlined),
                  label: const Text('Upload Video File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
                if (appSettings.queueBgVideoPath != null) ...[
                  const Icon(Icons.check_circle, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'File: ${appSettings.queueBgVideoPath!.split(Platform.pathSeparator).last}',
                      style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textLightSecondary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_browser_rounded, color: AppTheme.accent),
                    tooltip: 'Test local video playback',
                    onPressed: () async {
                      if (await File(appSettings.queueBgVideoPath!).exists()) {
                        try {
                          await Process.run('cmd', ['/c', 'start', '', appSettings.queueBgVideoPath!]);
                        } catch (_) {}
                      } else {
                        _snack('Uploaded file does not exist on disk!', isError: true);
                      }
                    },
                  ),
                ],
              ],
            ),
          ],
        ],

        if (appSettings.queueBgType != 'none') ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Overlay Opacity: ${(appSettings.queueBgOpacity * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary)),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 350),
                  child: Slider(
                    value: appSettings.queueBgOpacity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    activeColor: AppTheme.primary,
                    inactiveColor: AppTheme.borderLight,
                    onChanged: (val) async {
                      await appSettings.saveQueueBackground(type: appSettings.queueBgType, opacity: val);
                    },
                  ),
                ),
              ),
            ],
          ),
          Text('Higher opacity makes the overlay darker, making order tokens more readable.',
              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
        ],

        const SizedBox(height: 32),
        Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 20),

        // Manual open button
        Text('Manual Window Controls', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        const SizedBox(height: 8),
        Text('Click below to launch the separate Order Queue window immediately. You can drag it to your external HDMI monitor.',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
        const SizedBox(height: 20),
        
        ElevatedButton.icon(
          onPressed: () async {
            try {
              final executable = Platform.resolvedExecutable;
              await Process.start(executable, ['--queue-screen']);
              _snack('Queue Window launched successfully!');
            } catch (e) {
              _snack('Failed to launch window: $e', isError: true);
            }
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Launch Queue Window Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// COMPANY TAB
// ════════════════════════════════════════════════════════════════════════════
class _CompanyTab extends StatefulWidget {
  const _CompanyTab();
  @override
  State<_CompanyTab> createState() => _CompanyTabState();
}

class _CompanyTabState extends State<_CompanyTab> {
  final _nameCtrl        = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _websiteCtrl     = TextEditingController();
  final _cityCtrl        = TextEditingController();
  final _stateCtrl       = TextEditingController();
  final _countryCtrl     = TextEditingController();
  final _zipCtrl         = TextEditingController();
  final _addressCtrl     = TextEditingController();
  bool _saving = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only populate once so user edits aren't overwritten on rebuild
    if (_initialized) return;
    _initialized = true;
    final s = context.read<AppSettingsController>();
    _nameCtrl.text    = s.companyName;
    _emailCtrl.text   = s.companyEmail;
    _phoneCtrl.text   = s.companyPhone;
    _websiteCtrl.text = s.companyWebsite;
    _cityCtrl.text    = s.companyCity;
    _stateCtrl.text   = s.companyState;
    _countryCtrl.text = s.companyCountryCode;
    _zipCtrl.text     = s.companyZipCode;
    _addressCtrl.text = s.companyAddress;
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl,_emailCtrl,_phoneCtrl,_websiteCtrl,_cityCtrl,_stateCtrl,_countryCtrl,_zipCtrl,_addressCtrl]) c.dispose();
    super.dispose();
  }

  Widget _lbl(String t) => Text(t, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold,
      color: AppTheme.textLightSecondary, letterSpacing: 0.5));

  Widget _tf(TextEditingController c, {int maxLines = 1, TextInputType? kt}) =>
    TextField(controller: c, maxLines: maxLines, keyboardType: kt,
        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary));

  Widget _row(List<Widget> children) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children.expand((w) => [Expanded(child: w), const SizedBox(width: 16)]).toList()..removeLast(),
  );

  Widget _fld(String label, TextEditingController c, {int maxLines = 1, TextInputType? kt}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_lbl(label), const SizedBox(height: 6), _tf(c, maxLines: maxLines, kt: kt)]);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Company', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 16),

        _row([_fld('NAME *', _nameCtrl), _fld('EMAIL', _emailCtrl, kt: TextInputType.emailAddress)]),
        const SizedBox(height: 14),
        _row([_fld('PHONE', _phoneCtrl, kt: TextInputType.phone), _fld('WEBSITE', _websiteCtrl, kt: TextInputType.url)]),
        const SizedBox(height: 14),
        _row([_fld('CITY', _cityCtrl), _fld('STATE', _stateCtrl)]),
        const SizedBox(height: 14),
        _row([_fld('COUNTRY CODE', _countryCtrl), _fld('ZIP CODE', _zipCtrl)]),
        const SizedBox(height: 14),
        _fld('ADDRESS', _addressCtrl, maxLines: 4),
        const SizedBox(height: 28),

        ElevatedButton.icon(
          onPressed: _saving ? null : () async {
            setState(() => _saving = true);
            await context.read<AppSettingsController>().saveCompany(
              name:        _nameCtrl.text,
              email:       _emailCtrl.text,
              phone:       _phoneCtrl.text,
              website:     _websiteCtrl.text,
              city:        _cityCtrl.text,
              state:       _stateCtrl.text,
              countryCode: _countryCtrl.text,
              zipCode:     _zipCtrl.text,
              address:     _addressCtrl.text,
            );
            setState(() => _saving = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Company settings saved!'),
                backgroundColor: AppTheme.accent,
              ));
            }
          },
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined, size: 16),
          label: const Text('Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// THEME TAB
// ════════════════════════════════════════════════════════════════════════════
class _ThemeTab extends StatefulWidget {
  const _ThemeTab();
  @override
  State<_ThemeTab> createState() => _ThemeTabState();
}

class _ThemeTabState extends State<_ThemeTab> {
  bool _saving = false;
  bool _initialized = false;
  Color? _pickedColor;
  String? _logoBase64;
  String? _faviconBase64;
  String? _footerLogoBase64;

  static const _presets = [
    Color(0xFFFF1B6B),
    Color(0xFFFF6B35),
    Color(0xFFFFB800),
    Color(0xFF10B981),
    Color(0xFF0EA5E9),
    Color(0xFF6366F1),
    Color(0xFF8B5CF6),
    Color(0xFF1E293B),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only populate once so in-progress picks aren't overwritten on rebuild
    if (_initialized) return;
    _initialized = true;
    final s = context.read<AppSettingsController>();
    _pickedColor      = s.primaryColor;
    _logoBase64       = s.logoBase64;
    _faviconBase64    = s.faviconBase64;
    _footerLogoBase64 = s.footerLogoBase64;
  }

  Future<String?> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      return base64Encode(result.files.single.bytes!);
    }
    return null;
  }

  Widget _imagePickerCard({
    required String label,
    required String hint,
    required String? base64Value,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold,
          color: AppTheme.textLightSecondary, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      Text(hint, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textLightSecondary)),
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.upload_file, size: 14),
          label: const Text('Choose File'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textLightPrimary,
            side: BorderSide(color: AppTheme.borderLight),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: GoogleFonts.inter(fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        Text(base64Value != null ? 'Image selected' : 'No file chosen',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
        if (base64Value != null) ...[ const SizedBox(width: 8),
          GestureDetector(onTap: onClear,
            child: const Icon(Icons.close, size: 16, color: AppTheme.danger)),
        ],
      ]),
      const SizedBox(height: 10),
      if (base64Value != null && base64Value.isNotEmpty)
        Container(
          width: 120, height: 80,
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.borderLight),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Base64ImageWidget(base64Str: base64Value, fit: BoxFit.contain,
            fallback: const Center(child: Icon(Icons.image_not_supported, color: Color(0xFFCBD5E1)))),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Theme', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        const Divider(color: Color(0xFFE2E8F0)),
        const SizedBox(height: 20),

        // ── Logo uploads ──────────────────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _imagePickerCard(
            label: 'LOGO (sidebar / header)',
            hint: 'Recommended: 128px × 43px',
            base64Value: _logoBase64,
            onPick: () async { final b = await _pickImage(); if (b != null) setState(() => _logoBase64 = b); },
            onClear: () => setState(() => _logoBase64 = null),
          )),
          const SizedBox(width: 24),
          Expanded(child: _imagePickerCard(
            label: 'FAV ICON / NEAR ICON (120px × 120px)',
            hint: 'Square image shown next to the company name',
            base64Value: _faviconBase64,
            onPick: () async { final b = await _pickImage(); if (b != null) setState(() => _faviconBase64 = b); },
            onClear: () => setState(() => _faviconBase64 = null),
          )),
        ]),

        const SizedBox(height: 20),

        _imagePickerCard(
          label: 'FOOTER LOGO (144px × 48px)',
          hint: 'Logo displayed at the bottom of receipts',
          base64Value: _footerLogoBase64,
          onPick: () async { final b = await _pickImage(); if (b != null) setState(() => _footerLogoBase64 = b); },
          onClear: () => setState(() => _footerLogoBase64 = null),
        ),

        const SizedBox(height: 24),

        // ── Save logos button ─────────────────────────────────────────────
        ElevatedButton.icon(
          onPressed: _saving ? null : () async {
            setState(() => _saving = true);
            await context.read<AppSettingsController>().saveTheme(
              logoBase64:       _logoBase64,
              faviconBase64:    _faviconBase64,
              footerLogoBase64: _footerLogoBase64,
            );
            setState(() => _saving = false);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Logos saved!'), backgroundColor: AppTheme.accent));
          },
          icon: const Icon(Icons.save_outlined, size: 16),
          label: const Text('Save Logos'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          ),
        ),

        const SizedBox(height: 32),
        Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 20),

        // ── Primary Color ─────────────────────────────────────────────────
        Text('Primary Color', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        const SizedBox(height: 12),

        // Current color display
        Row(children: [
          GestureDetector(
            onTap: () => _showColorDialog(),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _pickedColor ?? AppTheme.primary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderLight, width: 2),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _showColorDialog(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.borderLight),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#${(_pickedColor ?? AppTheme.primary).value.toRadixString(16).toUpperCase().substring(2)}',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary),
              ),
            ),
          ),
        ]),

        const SizedBox(height: 16),
        Text('PRESETS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold,
            color: AppTheme.textLightSecondary, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: _presets.map((c) {
          final selected = c.value == (_pickedColor ?? AppTheme.primary).value;
          return GestureDetector(
            onTap: () => setState(() => _pickedColor = c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Colors.white : Colors.transparent,
                  width: 3,
                ),
                boxShadow: selected ? [BoxShadow(color: c.withOpacity(0.5), blurRadius: 8, spreadRadius: 1)] : [],
              ),
            ),
          );
        }).toList()),

        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _saving ? null : () async {
            setState(() => _saving = true);
            await context.read<AppSettingsController>().saveTheme(primaryColor: _pickedColor);
            setState(() => _saving = false);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Theme color saved!'), backgroundColor: AppTheme.accent));
          },
          icon: const Icon(Icons.palette_outlined, size: 16),
          label: const Text('Save Color'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _pickedColor ?? AppTheme.primary, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          ),
        ),

        const SizedBox(height: 32),
        Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 20),

        // ── POS Layout Toggle ──
        Text('POS Layout Configuration', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        const SizedBox(height: 8),
        Text('Change the position of the Cart panel in the POS screen (Left side vs Right side).',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
        const SizedBox(height: 16),
        Row(children: [
          Text('Cart Position:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary)),
          const SizedBox(width: 16),
          Switch(
            value: context.watch<AppSettingsController>().cartOnLeft,
            activeColor: AppTheme.primary,
            onChanged: (val) async {
              await context.read<AppSettingsController>().toggleCartPosition();
            },
          ),
          const SizedBox(width: 8),
          Text(
            context.watch<AppSettingsController>().cartOnLeft ? 'Left Hand Side' : 'Right Hand Side (Default)',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
          ),
        ]),

        const SizedBox(height: 32),
        Divider(color: AppTheme.dividerColor),
        const SizedBox(height: 20),

        // ── Theme Mode ──
        Text('App Theme Mode', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        const SizedBox(height: 8),
        Text('Choose how the application theme is displayed on this device.',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
        const SizedBox(height: 16),
        Row(children: [
          ChoiceChip(
            label: const Text('Light Mode'),
            selected: context.watch<AppSettingsController>().themeMode == ThemeMode.light,
            selectedColor: AppTheme.primary.withOpacity(0.15),
            onSelected: (selected) async {
              if (selected) {
                await context.read<AppSettingsController>().saveThemeMode(ThemeMode.light);
              }
            },
          ),
          const SizedBox(width: 12),
          ChoiceChip(
            label: const Text('Dark Mode'),
            selected: context.watch<AppSettingsController>().themeMode == ThemeMode.dark,
            selectedColor: AppTheme.primary.withOpacity(0.15),
            onSelected: (selected) async {
              if (selected) {
                await context.read<AppSettingsController>().saveThemeMode(ThemeMode.dark);
              }
            },
          ),
          const SizedBox(width: 12),
          ChoiceChip(
            label: const Text('System Default'),
            selected: context.watch<AppSettingsController>().themeMode == ThemeMode.system,
            selectedColor: AppTheme.primary.withOpacity(0.15),
            onSelected: (selected) async {
              if (selected) {
                await context.read<AppSettingsController>().saveThemeMode(ThemeMode.system);
              }
            },
          ),
        ]),
      ]),
    );
  }

  void _showColorDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _ColorPickerDialog(
        initial: _pickedColor ?? AppTheme.primary,
        onPicked: (c) => setState(() => _pickedColor = c),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// COLOR PICKER DIALOG
// ════════════════════════════════════════════════════════════════════════════
class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onPicked;
  const _ColorPickerDialog({required this.initial, required this.onPicked});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _current;
  final _hexCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _hexCtrl.text = _toHex(_current);
  }

  String _toHex(Color c) => '#${c.value.toRadixString(16).toUpperCase().substring(2)}';

  @override
  Widget build(BuildContext context) {
    final hslColor = HSLColor.fromColor(_current);
    return AlertDialog(
      title: Text('Pick a Color', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: 60, decoration: BoxDecoration(
            color: _current, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: _current.withOpacity(0.4), blurRadius: 12)],
          )),
          const SizedBox(height: 16),
          Text('Hue', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
          Slider(
            value: hslColor.hue,
            min: 0, max: 360,
            onChanged: (v) {
              setState(() { _current = hslColor.withHue(v).toColor(); _hexCtrl.text = _toHex(_current); });
            },
            activeColor: _current,
          ),
          Text('Saturation', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
          Slider(
            value: hslColor.saturation,
            onChanged: (v) {
              setState(() { _current = hslColor.withSaturation(v).toColor(); _hexCtrl.text = _toHex(_current); });
            },
            activeColor: _current,
          ),
          Text('Lightness', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
          Slider(
            value: hslColor.lightness,
            onChanged: (v) {
              setState(() { _current = hslColor.withLightness(v).toColor(); _hexCtrl.text = _toHex(_current); });
            },
            activeColor: _current,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _hexCtrl,
            decoration: InputDecoration(
              labelText: 'Hex code (e.g. #FF1B6B)',
              labelStyle: GoogleFonts.inter(fontSize: 12),
            ),
            onSubmitted: (v) {
              final clean = v.replaceAll('#', '');
              if (clean.length == 6) {
                try {
                  final parsed = Color(int.parse('FF$clean', radix: 16));
                  setState(() => _current = parsed);
                } catch (_) {}
              }
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () { widget.onPicked(_current); Navigator.pop(context); },
          style: ElevatedButton.styleFrom(backgroundColor: _current),
          child: const Text('Select', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BRANCHES TAB
// ════════════════════════════════════════════════════════════════════════════
class _BranchesTab extends StatefulWidget {
  const _BranchesTab();
  @override
  State<_BranchesTab> createState() => _BranchesTabState();
}

class _BranchesTabState extends State<_BranchesTab> {

  void _openBranchDialog({BranchItem? editing}) {
    showDialog(
      context: context,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: context.read<AppSettingsController>(),
        child: _BranchDialog(editing: editing),
      ),
    );
  }

  void _confirmDelete(BranchItem branch) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Branch', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${branch.name}"?\nThis action cannot be undone.',
            style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () {
              context.read<AppSettingsController>().deleteBranch(branch.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('"${branch.name}" deleted.'),
                backgroundColor: AppTheme.danger,
              ));
            },
            icon: const Icon(Icons.delete_outline, size: 14),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branches = context.watch<AppSettingsController>().branches;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header ────────────────────────────────────────────────────────────
      Row(children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Branches', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
            const SizedBox(height: 4),
            Text('Configure physical locations and branch details.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
          ],
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => _openBranchDialog(),
          icon: const Icon(Icons.add_circle_outline, size: 16, color: Colors.white),
          label: const Text('Add Branch'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Divider(color: AppTheme.dividerColor),
      const SizedBox(height: 16),

      // ── Branch Cards Grid ─────────────────────────────────────────────────
      Expanded(
        child: branches.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.store_outlined, size: 48, color: AppTheme.primary),
                ),
                const SizedBox(height: 16),
                Text('No branches added yet', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                const SizedBox(height: 6),
                Text('Add branches to configure different physical locations.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
              ]))
            : GridView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 380,
                  mainAxisExtent: 330,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                ),
                itemCount: branches.length,
                itemBuilder: (ctx, i) {
                  final b = branches[i];
                  final isActive = b.status == 'Active';
                  return Container(
                    decoration: BoxDecoration(
                      color: AppTheme.cardLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderLight),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card Cover Image / Gradient
                        Stack(
                          children: [
                            if (b.imageBase64 != null && b.imageBase64!.isNotEmpty)
                              SizedBox(
                                height: 130,
                                width: double.infinity,
                                child: Base64ImageWidget(base64Str: b.imageBase64, fit: BoxFit.cover),
                              )
                            else
                              Container(
                                height: 130,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.primary.withOpacity(0.85),
                                      AppTheme.primary.withOpacity(0.5),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(Icons.store, size: 44, color: Colors.white),
                                ),
                              ),
                            // Status Badge
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                    )
                                  ]
                                ),
                                child: Text(
                                  b.status.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Card Info
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textLightPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 10),
                                // Location Row
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF94A3B8)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        b.address.isNotEmpty
                                            ? b.address
                                            : '${b.city}, ${b.state}',
                                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // Phone Row
                                Row(
                                  children: [
                                    const Icon(Icons.phone_outlined, size: 14, color: Color(0xFF94A3B8)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        b.phone.isNotEmpty ? b.phone : 'No Phone Number',
                                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // Email Row
                                Row(
                                  children: [
                                    const Icon(Icons.mail_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        b.email.isNotEmpty ? b.email : 'No Email Address',
                                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                // Actions Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // Edit Button
                                    TextButton.icon(
                                      onPressed: () => _openBranchDialog(editing: b),
                                      icon: const Icon(Icons.edit_outlined, size: 14),
                                      label: const Text('Edit'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppTheme.primary,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Delete Button
                                    TextButton.icon(
                                      onPressed: () => _confirmDelete(b),
                                      icon: const Icon(Icons.delete_outline, size: 14),
                                      label: const Text('Delete'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppTheme.danger,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      const SizedBox(height: 8),
      Consumer<AppSettingsController>(builder: (_, s, __) =>
        Text('Showing 1 to ${s.branches.length} of ${s.branches.length} entries',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
      ),
    ]);
  }
}


// ════════════════════════════════════════════════════════════════════════════
// BRANCH ADD / EDIT DIALOG
// ════════════════════════════════════════════════════════════════════════════
class _BranchDialog extends StatefulWidget {
  final BranchItem? editing;
  const _BranchDialog({this.editing});

  @override
  State<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<_BranchDialog> {
  final _nameCtrl   = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  final _cityCtrl   = TextEditingController();
  final _stateCtrl  = TextEditingController();
  final _zipCtrl    = TextEditingController();
  final _addrCtrl   = TextEditingController();
  String _status = 'Active';
  String? _imageBase64;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.editing;
    if (b != null) {
      _nameCtrl.text  = b.name;
      _emailCtrl.text = b.email;
      _phoneCtrl.text = b.phone;
      _cityCtrl.text  = b.city;
      _stateCtrl.text = b.state;
      _zipCtrl.text   = b.zipCode;
      _addrCtrl.text  = b.address;
      _status         = b.status;
      _imageBase64    = b.imageBase64;
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl,_emailCtrl,_phoneCtrl,_cityCtrl,_stateCtrl,_zipCtrl,_addrCtrl]) c.dispose();
    super.dispose();
  }

  Widget _fld(String label, TextEditingController c, {int maxLines = 1, TextInputType? kt}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold,
          color: const Color(0xFF64748B), letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextField(controller: c, maxLines: maxLines, keyboardType: kt,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.borderLight)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.borderLight)),
          )),
    ]);

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result != null && result.files.single.bytes != null) {
      setState(() => _imageBase64 = base64Encode(result.files.single.bytes!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editing != null;
    return Dialog(
      backgroundColor: AppTheme.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              // Title
              Row(children: [
                Text(isEdit ? 'Edit Branch' : 'Add Branch',
                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20)),
              ]),
              Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 16),

              // Name + Status row
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _fld('NAME *', _nameCtrl)),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('STATUS *', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold,
                      color: const Color(0xFF64748B), letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Radio<String>(value: 'Active',   groupValue: _status, onChanged: (v) => setState(() => _status = v!), activeColor: AppTheme.accent),
                    const Text('Active'),
                    const SizedBox(width: 8),
                    Radio<String>(value: 'Inactive', groupValue: _status, onChanged: (v) => setState(() => _status = v!), activeColor: AppTheme.danger),
                    const Text('Inactive'),
                  ]),
                ]),
              ]),
              const SizedBox(height: 14),

              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _fld('EMAIL', _emailCtrl, kt: TextInputType.emailAddress)),
                const SizedBox(width: 16),
                Expanded(child: _fld('PHONE', _phoneCtrl, kt: TextInputType.phone)),
              ]),
              const SizedBox(height: 14),

              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _fld('CITY *', _cityCtrl)),
                const SizedBox(width: 16),
                Expanded(child: _fld('STATE *', _stateCtrl)),
              ]),
              const SizedBox(height: 14),

              _fld('ZIP CODE', _zipCtrl),
              const SizedBox(height: 14),

              _fld('ADDRESS *', _addrCtrl, maxLines: 3),
              const SizedBox(height: 16),

              // Branch image
              Text('BRANCH IMAGE', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold,
                  color: const Color(0xFF64748B), letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.upload_file, size: 14),
                  label: const Text('Choose Image'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textLightPrimary,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: GoogleFonts.inter(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                if (_imageBase64 != null) ...[ 
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.borderLight),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Base64ImageWidget(base64Str: _imageBase64, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _imageBase64 = null),
                    child: const Icon(Icons.close, size: 16, color: AppTheme.danger),
                  ),
                ] else
                  Text('No image chosen', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
              ]),

              const SizedBox(height: 24),

              // Buttons
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textLightSecondary,
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _saving ? null : () async {
                    if (_nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Branch name is required.'), backgroundColor: AppTheme.danger));
                      return;
                    }
                    setState(() => _saving = true);
                    final settings = context.read<AppSettingsController>();
                    final branch = BranchItem(
                      id:          widget.editing?.id ?? 0,
                      name:        _nameCtrl.text.trim(),
                      email:       _emailCtrl.text.trim(),
                      phone:       _phoneCtrl.text.trim(),
                      city:        _cityCtrl.text.trim(),
                      state:       _stateCtrl.text.trim(),
                      zipCode:     _zipCtrl.text.trim(),
                      address:     _addrCtrl.text.trim(),
                      status:      _status,
                      imageBase64: _imageBase64,
                    );
                    if (isEdit) {
                      await settings.updateBranch(branch);
                    } else {
                      await settings.addBranch(branch);
                    }
                    if (mounted) Navigator.pop(context);
                  },
                  icon: _saving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 14),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// KOT SOUND TAB
// ════════════════════════════════════════════════════════════════════════════
class _KotSoundTab extends StatefulWidget {
  const _KotSoundTab({Key? key}) : super(key: key);

  @override
  State<_KotSoundTab> createState() => _KotSoundTabState();
}

class _KotSoundTabState extends State<_KotSoundTab> {
  Future<void> _pickSoundFile(int categoryId, POSController controller) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'wma', 'flac'],
        withData: true,
      );
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final filename = result.files.single.name;
        final fileBytes = await File(filePath).readAsBytes();
        final base64Str = base64Encode(fileBytes);
        await controller.saveKotSoundSetting(categoryId, 'custom', soundBase64: base64Str, filename: filename);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Custom sound uploaded for ${result.files.single.name} successfully!'),
            backgroundColor: AppTheme.accent,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to pick sound file: $e'),
          backgroundColor: AppTheme.danger,
        ));
      }
    }
  }

  void _showRecordDialog(int categoryId, String categoryName, POSController controller) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RecordSoundDialog(
        categoryId: categoryId,
        categoryName: categoryName,
        controller: controller,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<POSController>();
    final categories = controller.categories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Text(
          'KOT Category Sound Configuration',
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.textLightPrimary,
          ),
        ),
        const Divider(color: Color(0xFFE2E8F0)),
        const SizedBox(height: 8),
        Text(
          'Map custom voice alerts or audio sound files to specific product categories. Custom sounds override the default text-to-speech engine when items from mapped categories are added to kitchen orders.',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppTheme.textLightSecondary,
          ),
        ),
        const SizedBox(height: 24),

        // List of Categories
        Expanded(
          child: categories.isEmpty
              ? Center(
                  child: Text(
                    'No categories found. Please pull catalog from API.',
                    style: GoogleFonts.inter(color: AppTheme.textLightSecondary),
                  ),
                )
              : ListView.separated(
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final soundSetting = controller.categorySounds[cat.id];
                    final isCustom = soundSetting != null && soundSetting['soundType'] == 'custom';
                    final filename = soundSetting?['filename']?.toString();

                    return Container(
                      decoration: BoxDecoration(
                        color: AppTheme.cardLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderLight),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.01),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          // Category Image or Icon
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: cat.imageBase64 != null && cat.imageBase64!.isNotEmpty
                                ? Base64ImageWidget(
                                    base64Str: cat.imageBase64!,
                                    fit: BoxFit.cover,
                                  )
                                : Icon(
                                    Icons.restaurant_menu_outlined,
                                    color: AppTheme.primary,
                                    size: 22,
                                  ),
                          ),
                          const SizedBox(width: 16),

                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cat.name,
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textLightPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isCustom
                                            ? (soundSetting['soundBase64'] != null
                                                ? AppTheme.accent
                                                : Colors.orange)
                                            : Colors.grey.shade400,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isCustom
                                          ? (soundSetting['soundBase64'] != null
                                              ? 'Custom Audio Sound Mapped'
                                              : 'Custom Sound (No file selected)')
                                          : 'Default Speech (Sinhala TTS)',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: isCustom
                                            ? (soundSetting['soundBase64'] != null
                                                ? AppTheme.accent
                                                : Colors.orange.shade700)
                                            : AppTheme.textLightSecondary,
                                        fontWeight: isCustom
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isCustom) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    filename != null
                                        ? 'File: $filename'
                                        : 'Click upload or mic icon to add sound',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: const Color(0xFF64748B),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Controls / Settings Toggle
                          Row(
                            children: [
                              // Playback preview if custom sound exists
                              if (isCustom && soundSetting['soundBase64'] != null) ...[
                                IconButton(
                                  icon: const Icon(
                                    Icons.play_circle_outline_rounded,
                                    color: AppTheme.accent,
                                    size: 26,
                                  ),
                                  tooltip: 'Preview Sound',
                                  onPressed: () => controller.playCustomSoundForCategory(cat.id),
                                ),
                                const SizedBox(width: 4),
                              ],

                              // Dropdown choice
                              DropdownButtonHideUnderline(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppTheme.borderLight),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: DropdownButton<String>(
                                    value: isCustom ? 'custom' : 'default',
                                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightPrimary),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'default',
                                        child: Text('Default Voice'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'custom',
                                        child: Text('Custom Sound'),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val == 'default') {
                                        controller.removeKotSoundSetting(cat.id);
                                      } else {
                                        controller.saveKotSoundSetting(cat.id, 'custom');
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Quick upload/record action buttons when custom sound is enabled
                              if (isCustom) ...[
                                IconButton(
                                  icon: const Icon(
                                    Icons.upload_file_outlined,
                                    color: Color(0xFF64748B),
                                    size: 20,
                                  ),
                                  tooltip: 'Upload Sound File',
                                  onPressed: () => _pickSoundFile(cat.id, controller),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.mic_outlined,
                                    color: Color(0xFF64748B),
                                    size: 20,
                                  ),
                                  tooltip: 'Record Sound',
                                  onPressed: () => _showRecordDialog(cat.id, cat.name, controller),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppTheme.danger,
                                    size: 20,
                                  ),
                                  tooltip: 'Reset to Default',
                                  onPressed: () => controller.removeKotSoundSetting(cat.id),
                                ),
                              ],
                            ],
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

// ════════════════════════════════════════════════════════════════════════════
// RECORD SOUND DIALOG
// ════════════════════════════════════════════════════════════════════════════
class _RecordSoundDialog extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  final POSController controller;

  const _RecordSoundDialog({
    Key? key,
    required this.categoryId,
    required this.categoryName,
    required this.controller,
  }) : super(key: key);

  @override
  State<_RecordSoundDialog> createState() => _RecordSoundDialogState();
}

class _RecordSoundDialogState extends State<_RecordSoundDialog> {
  bool _recording = false;
  int _seconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) {
      widget.controller.stopRecording();
    }
    super.dispose();
  }

  void _start() async {
    setState(() {
      _recording = true;
      _seconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _seconds++;
      });
    });
    await widget.controller.startRecording();
  }

  void _stop() async {
    _timer?.cancel();
    setState(() {
      _recording = false;
    });
    final base64Str = await widget.controller.stopRecording();
    if (base64Str != null) {
      final nowStr = DateTime.now().toString().substring(0, 19).replaceAll(':', '-');
      final filename = 'recording_$nowStr.wav';
      await widget.controller.saveKotSoundSetting(
        widget.categoryId,
        'custom',
        soundBase64: base64Str,
        filename: filename,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Voice recording saved successfully!'),
          backgroundColor: AppTheme.accent,
        ));
        Navigator.pop(context);
        widget.controller.playCustomSoundForCategory(widget.categoryId);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to record audio.'),
          backgroundColor: AppTheme.danger,
        ));
        Navigator.pop(context);
      }
    }
  }

  void _cancel() async {
    _timer?.cancel();
    setState(() {
      _recording = false;
    });
    await widget.controller.stopRecording();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Record Voice Alert',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'Category: ${widget.categoryName}',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
            ),
            const SizedBox(height: 32),
            
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: _recording ? AppTheme.danger.withOpacity(0.08) : AppTheme.bgLight,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _recording ? AppTheme.danger : AppTheme.borderLight,
                  width: 2,
                ),
              ),
              child: Icon(
                _recording ? Icons.mic : Icons.mic_none,
                size: 44,
                color: _recording ? AppTheme.danger : AppTheme.textLightSecondary,
              ),
            ),
            const SizedBox(height: 20),
            
            // Timer
            Text(
              _recording
                  ? 'Recording: ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'
                  : 'Ready to record',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _recording ? AppTheme.danger : AppTheme.textLightPrimary,
              ),
            ),
            const SizedBox(height: 32),
            
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_recording) ...[
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.circle, color: Colors.white, size: 12),
                    label: const Text('Start Recording'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ] else ...[
                  OutlinedButton(
                    onPressed: _cancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Stop & Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
