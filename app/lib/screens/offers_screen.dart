import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../pos_controller.dart';
import '../widgets/image_helper.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({Key? key}) : super(key: key);

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  List<OfferModel> _offers = [];
  List<Map<String, dynamic>> _happyHours = [];
  bool _isLoading = false;
  String _errorMessage = '';

  // Search & Filters
  String _searchQuery = '';
  String _statusFilter = 'All'; // 'All', 'active', 'inactive'

  // Drawer / Form State
  bool _isDrawerOpen = false;
  bool _isHappyHourForm = false; // true = Happy Hour form, false = Promo Banner form
  OfferModel? _editingOffer; // null means adding new offer (Promo Banner only)

  // Form Fields Keys
  final _promoFormKey = GlobalKey<FormState>();
  final _happyHourFormKey = GlobalKey<FormState>();

  // Promo Banner Controllers
  final _nameController = TextEditingController();
  final _discountController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  String? _imageName;
  String? _imageBase64;
  String _statusVal = 'active'; // 'active', 'inactive'

  // Happy Hour Controllers
  ProductModel? _selectedPromoProduct;
  final _promoPriceController = TextEditingController();
  final _startTimeController = TextEditingController(text: '17:00:00');
  final _endTimeController = TextEditingController(text: '19:00:00');
  String _selectedDays = '1,2,3,4,5'; // Monday to Friday

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadOffers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _discountController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _promoPriceController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  Future<void> _loadOffers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final ords = await APIService.instance.getOffers();
      final promos = await APIService.instance.getHappyHours();
      if (mounted) {
        setState(() {
          _offers = ords;
          _happyHours = promos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load offers: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Open Promo Drawer (Add/Edit)
  void _openPromoDrawer([OfferModel? offer]) {
    setState(() {
      _isHappyHourForm = false;
      _editingOffer = offer;
      _isDrawerOpen = true;

      if (offer != null) {
        _nameController.text = offer.name;
        _discountController.text = offer.discountPercentage.toStringAsFixed(0);
        _startDateController.text = offer.startDate;
        _endDateController.text = offer.endDate;
        _imageBase64 = offer.imageBase64;
        _imageName = offer.imageBase64 != null ? 'Existing Image' : null;
        _statusVal = offer.status;
      } else {
        _nameController.clear();
        _discountController.clear();
        _startDateController.clear();
        _endDateController.clear();
        _imageName = null;
        _imageBase64 = null;
        _statusVal = 'active';
      }
    });
  }

  // Open Happy Hour Drawer (Add only)
  void _openHappyHourDrawer() {
    setState(() {
      _isHappyHourForm = true;
      _editingOffer = null;
      _isDrawerOpen = true;

      _selectedPromoProduct = null;
      _promoPriceController.clear();
      _startTimeController.text = '17:00:00';
      _endTimeController.text = '19:00:00';
      _selectedDays = '1,2,3,4,5';
    });
  }

  // Close Drawer
  void _closeDrawer() {
    setState(() {
      _isDrawerOpen = false;
      _editingOffer = null;
    });
  }

  // Pick Image File
  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        setState(() {
          _imageName = result.files.single.name;
          _imageBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  // Show Date Picker
  Future<void> _selectDate(TextEditingController controller) async {
    DateTime initial = DateTime.now();
    if (controller.text.isNotEmpty) {
      initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // Save Promo (POST or PUT)
  Future<void> _savePromo() async {
    if (!_promoFormKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    final payload = {
      'name': _nameController.text.trim(),
      'discount_percentage': double.tryParse(_discountController.text) ?? 0.0,
      'start_date': _startDateController.text.trim(),
      'end_date': _endDateController.text.trim(),
      'image_base64': _imageBase64,
      'status': _statusVal,
    };

    try {
      if (_editingOffer == null) {
        await APIService.instance.createOffer(payload);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offer created successfully.'), backgroundColor: AppTheme.accent),
        );
      } else {
        await APIService.instance.updateOffer(_editingOffer!.id!, payload);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offer updated successfully.'), backgroundColor: AppTheme.accent),
        );
      }
      _closeDrawer();
      await _loadOffers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save offer: $e'), backgroundColor: AppTheme.danger),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  // Save Happy Hour (POST)
  Future<void> _saveHappyHour(POSController posController) async {
    if (!_happyHourFormKey.currentState!.validate()) return;
    if (_selectedPromoProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final price = double.tryParse(_promoPriceController.text) ?? 0.00;
    final start = _startTimeController.text.trim();
    final end = _endTimeController.text.trim();

    try {
      await APIService.instance.configureHappyHour(_selectedPromoProduct!.id, price, start, end, _selectedDays);
      _closeDrawer();
      await _loadOffers();
      await posController.reloadEnvironment();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Happy Hour promotion saved successfully.'), backgroundColor: AppTheme.accent),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e'), backgroundColor: AppTheme.danger),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  // Delete Offer Banner
  Future<void> _deleteOffer(OfferModel offer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Offer', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${offer.name}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await APIService.instance.deleteOffer(offer.id!);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offer deleted successfully.'), backgroundColor: AppTheme.accent),
        );
        await _loadOffers();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Deactivate Happy Hour
  Future<void> _deactivateHappyHour(int id, POSController posController) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Deactivate Happy Hour', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to deactivate this Happy Hour promotion?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await APIService.instance.deleteHappyHour(id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Happy Hour promotion deactivated successfully.'), backgroundColor: AppTheme.accent),
        );
        await _loadOffers();
        await posController.reloadEnvironment();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to deactivate: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Filtered Banner Offers list
  List<OfferModel> get _filteredOffers {
    return _offers.where((o) {
      final matchSearch = o.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchStatus = _statusFilter == 'All' || o.status == _statusFilter;
      return matchSearch && matchStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final posController = Provider.of<POSController>(context);
    final filtered = _filteredOffers;

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Row(
        children: [
          // Main Panel
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Title & Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Offers & Happy Hour',
                            style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                              const Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                              Text('Offers', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(icon: const Icon(Icons.refresh, color: AppTheme.primary), onPressed: _loadOffers),
                          const SizedBox(width: 8),
                          _buildOutlineIconButton(icon: Icons.filter_alt_outlined, label: 'Filter', onTap: _showFilterDialog),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _openHappyHourDrawer,
                            icon: const Icon(Icons.celebration_outlined, size: 16),
                            label: const Text('Add Happy Hour'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.secondary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () => _openPromoDrawer(),
                            icon: const Icon(Icons.add_circle_outline, size: 16),
                            label: const Text('Add Promo Banner'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Search Bar
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: Color(0xFF94A3B8), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                onChanged: (val) => setState(() => _searchQuery = val),
                                decoration: const InputDecoration(
                                  hintText: 'Search by promo name...',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                                style: GoogleFonts.inter(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tables list scrollable
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                        : _errorMessage.isNotEmpty
                            ? Center(child: Text(_errorMessage, style: GoogleFonts.inter(color: Colors.red)))
                            : SingleChildScrollView(
                                child: Column(
                                  children: [
                                    // SECTION 1: Banner Offers
                                    Card(
                                      elevation: 0,
                                      color: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      child: Padding(
                                        padding: const EdgeInsets.all(20.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Promotional Banners',
                                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                            ),
                                            const SizedBox(height: 16),
                                            filtered.isEmpty
                                                ? SizedBox(height: 200, child: _buildEmptyState())
                                                : _buildOffersTable(filtered),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    // SECTION 2: Happy Hour Offers
                                    Card(
                                      elevation: 0,
                                      color: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      child: Padding(
                                        padding: const EdgeInsets.all(20.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Happy Hour Offers',
                                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                            ),
                                            const SizedBox(height: 16),
                                            _happyHours.isEmpty
                                                ? Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 40.0),
                                                    child: Center(
                                                      child: Text(
                                                        'No active happy hour offers.',
                                                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary),
                                                      ),
                                                    ),
                                                  )
                                                : _buildHappyHoursTable(posController),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),

          // Slide-out Drawer Panel on Right
          if (_isDrawerOpen) _buildDrawerForm(posController),
        ],
      ),
    );
  }

  // Outline action button
  Widget _buildOutlineIconButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: AppTheme.primary),
      label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppTheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }

  // Filter Dialog
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String tempStatus = _statusFilter;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Filter Offers', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filter by Status:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: tempStatus == 'All',
                        onSelected: (_) => setDialogState(() => tempStatus = 'All'),
                      ),
                      ChoiceChip(
                        label: const Text('Active'),
                        selected: tempStatus == 'active',
                        onSelected: (_) => setDialogState(() => tempStatus = 'active'),
                      ),
                      ChoiceChip(
                        label: const Text('Inactive'),
                        selected: tempStatus == 'inactive',
                        onSelected: (_) => setDialogState(() => tempStatus == 'inactive'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _statusFilter = tempStatus;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Sad Illustration
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 140,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF0F5), Color(0xFFFFE4E6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Column(
                children: [
                  const Icon(Icons.folder_open, size: 54, color: Color(0xFFFDA4AF)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFFE11D48), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFFE11D48), shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 12,
                    height: 2,
                    color: const Color(0xFFE11D48),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'No data available.',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  // Offers Table list
  Widget _buildOffersTable(List<OfferModel> offers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          child: Row(
            children: [
              Expanded(flex: 3, child: _buildTableHeaderText('NAME')),
              Expanded(flex: 2, child: _buildTableHeaderText('AMOUNT (%)')),
              Expanded(flex: 3, child: _buildTableHeaderText('START DATE')),
              Expanded(flex: 3, child: _buildTableHeaderText('END DATE')),
              Expanded(flex: 2, child: _buildTableHeaderText('STATUS')),
              Expanded(flex: 2, child: _buildTableHeaderText('ACTION')),
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: offers.length,
          separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
          itemBuilder: (context, index) {
            final offer = offers[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        if (offer.imageBase64 != null && offer.imageBase64!.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: 36,
                              height: 36,
                              color: const Color(0xFFF1F5F9),
                              child: Base64ImageWidget(base64Str: offer.imageBase64, fit: BoxFit.cover),
                            ),
                          )
                        else
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: const Color(0xFFFFF0F5), borderRadius: BorderRadius.circular(6)),
                            child: const Icon(Icons.local_offer_outlined, color: AppTheme.primary, size: 18),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            offer.name,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${offer.discountPercentage.toStringAsFixed(0)}%',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      offer.startDate,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      offer.endDate,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildStatusBadge(offer.status),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _openPromoDrawer(offer),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: const Color(0xFFFFF0F5), borderRadius: BorderRadius.circular(6)),
                            child: const Icon(Icons.edit, color: AppTheme.primary, size: 14),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _deleteOffer(offer),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(6)),
                            child: const Icon(Icons.delete, color: AppTheme.danger, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // Happy Hours table list
  Widget _buildHappyHoursTable(POSController posController) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          child: Row(
            children: [
              Expanded(flex: 3, child: _buildTableHeaderText('PRODUCT NAME')),
              Expanded(flex: 2, child: _buildTableHeaderText('PROMO PRICE')),
              Expanded(flex: 2, child: _buildTableHeaderText('ORIGINAL PRICE')),
              Expanded(flex: 3, child: _buildTableHeaderText('TIME RANGE')),
              Expanded(flex: 3, child: _buildTableHeaderText('PROMO DAYS')),
              Expanded(flex: 2, child: _buildTableHeaderText('ACTION')),
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _happyHours.length,
          separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
          itemBuilder: (context, index) {
            final promo = _happyHours[index];
            final id = promo['id'] as int;
            final prodName = promo['product_name'] ?? '';
            final promoPrice = promo['promo_price'];
            final originalPrice = promo['original_price'];
            final start = promo['start_time'].toString().substring(0, 5);
            final end = promo['end_time'].toString().substring(0, 5);
            final daysStr = promo['days_of_week'] ?? '1,2,3,4,5,6,7';

            String daysDesc = 'Every Day';
            if (daysStr == '1,2,3,4,5') {
              daysDesc = 'Weekdays';
            } else if (daysStr == '6,7') {
              daysDesc = 'Weekends';
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      prodName,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'LKR $promoPrice',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accent),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'LKR $originalPrice',
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8), decoration: TextDecoration.lineThrough),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '$start - $end',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      daysDesc,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () => _deactivateHappyHour(id, posController),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.cancel_outlined, color: AppTheme.danger, size: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTableHeaderText(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF475569), letterSpacing: 0.5),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE6F4EA) : const Color(0xFFFCE8E6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? const Color(0xFF137333) : const Color(0xFFC5221F)),
      ),
    );
  }

  // Main drawer builder switching by type
  Widget _buildDrawerForm(POSController posController) {
    return Container(
      width: 420,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(-4, 0)),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: _isHappyHourForm 
          ? _buildHappyHourDrawerForm(posController)
          : _buildPromoBannerDrawerForm(),
    );
  }

  // Form 1: Add/Edit Promo Banner
  Widget _buildPromoBannerDrawerForm() {
    return Form(
      key: _promoFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _editingOffer == null ? 'Add Promo Banner' : 'Edit Promo Banner',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
              ),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _closeDrawer),
            ],
          ),
          const Divider(height: 24, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('NAME *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nameController,
                    validator: (val) => val == null || val.isEmpty ? 'Please enter a name' : null,
                    decoration: const InputDecoration(hintText: 'Enter offer name'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('DISCOUNT PERCENTAGE *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _discountController,
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Please enter discount percentage';
                      final numVal = double.tryParse(val);
                      if (numVal == null || numVal < 0 || numVal > 100) return 'Enter a number between 0 and 100';
                      return null;
                    },
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Enter discount %'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('START DATE *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _startDateController,
                    readOnly: true,
                    onTap: () => _selectDate(_startDateController),
                    validator: (val) => val == null || val.isEmpty ? 'Select a start date' : null,
                    decoration: const InputDecoration(
                      hintText: 'yyyy-mm-dd',
                      suffixIcon: Icon(Icons.calendar_today, size: 16, color: Color(0xFF64748B)),
                    ),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('END DATE *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _endDateController,
                    readOnly: true,
                    onTap: () => _selectDate(_endDateController),
                    validator: (val) => val == null || val.isEmpty ? 'Select an end date' : null,
                    decoration: const InputDecoration(
                      hintText: 'yyyy-mm-dd',
                      suffixIcon: Icon(Icons.calendar_today, size: 16, color: Color(0xFF64748B)),
                    ),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('IMAGE (548PX, 140PX)'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _pickImage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF1F5F9),
                          foregroundColor: const Color(0xFF475569),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Text('Choose File', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _imageName ?? 'No file chosen',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('STATUS'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Radio<String>(
                        value: 'active',
                        groupValue: _statusVal,
                        activeColor: AppTheme.primary,
                        onChanged: (val) => setState(() => _statusVal = val!),
                      ),
                      Text('Active', style: GoogleFonts.inter(fontSize: 13)),
                      const SizedBox(width: 20),
                      Radio<String>(
                        value: 'inactive',
                        groupValue: _statusVal,
                        activeColor: AppTheme.primary,
                        onChanged: (val) => setState(() => _statusVal = val!),
                      ),
                      Text('Inactive', style: GoogleFonts.inter(fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _savePromo,
                  icon: _isSaving 
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _closeDrawer,
                  icon: const Icon(Icons.close, size: 16, color: Color(0xFF475569)),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    foregroundColor: const Color(0xFF475569),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Form 2: Configure Happy Hour Promo
  Widget _buildHappyHourDrawerForm(POSController posController) {
    return Form(
      key: _happyHourFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Configure Happy Hour',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
              ),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _closeDrawer),
            ],
          ),
          const Divider(height: 24, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('SELECT PROMO PRODUCT *'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<ProductModel>(
                    value: _selectedPromoProduct,
                    decoration: const InputDecoration(hintText: 'Select product'),
                    items: [
                      ...posController.products.map((p) => DropdownMenuItem(
                            value: p,
                            child: Text('${p.name} (LKR ${p.price.toStringAsFixed(0)})', style: const TextStyle(fontSize: 12)),
                          )),
                    ],
                    onChanged: (p) => setState(() => _selectedPromoProduct = p),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('PROMO PRICE (LKR) *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _promoPriceController,
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Please enter promotional price';
                      final numVal = double.tryParse(val);
                      if (numVal == null || numVal <= 0) return 'Enter a valid price';
                      return null;
                    },
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Enter promotional price'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('START TIME *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _startTimeController,
                    validator: (val) => val == null || val.isEmpty ? 'Enter start time' : null,
                    decoration: const InputDecoration(hintText: 'HH:MM:SS (e.g. 17:00:00)'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('END TIME *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _endTimeController,
                    validator: (val) => val == null || val.isEmpty ? 'Enter end time' : null,
                    decoration: const InputDecoration(hintText: 'HH:MM:SS (e.g. 19:00:00)'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  _buildFieldLabel('PROMOTION DAYS'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _selectedDays,
                    items: const [
                      DropdownMenuItem(value: '1,2,3,4,5', child: Text('Weekdays (Mon-Fri)')),
                      DropdownMenuItem(value: '6,7', child: Text('Weekends (Sat-Sun)')),
                      DropdownMenuItem(value: '1,2,3,4,5,6,7', child: Text('Every Day')),
                    ],
                    onChanged: (val) => setState(() => _selectedDays = val!),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : () => _saveHappyHour(posController),
                  icon: _isSaving 
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _closeDrawer,
                  icon: const Icon(Icons.close, size: 16, color: Color(0xFF475569)),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    foregroundColor: const Color(0xFF475569),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
    );
  }
}
