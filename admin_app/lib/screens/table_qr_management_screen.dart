import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_service.dart';
import '../core/theme.dart';

class TableQRManagementScreen extends StatefulWidget {
  const TableQRManagementScreen({Key? key}) : super(key: key);

  @override
  State<TableQRManagementScreen> createState() => _TableQRManagementScreenState();
}

class _TableQRManagementScreenState extends State<TableQRManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _api = ApiService.instance;

  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;

  final TextEditingController _baseUrlController = TextEditingController();
  String _effectiveBaseUrl = 'http://192.168.1.100:3000';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBaseUrlAndData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadBaseUrlAndData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final savedBase = prefs.getString('customer_order_base_url');
    if (savedBase != null && savedBase.isNotEmpty) {
      _effectiveBaseUrl = savedBase;
    } else {
      _effectiveBaseUrl = _api.baseUrl;
    }
    _baseUrlController.text = _effectiveBaseUrl;

    await _fetchData();
  }

  Future<void> _saveBaseUrl() async {
    final newUrl = _baseUrlController.text.trim();
    if (newUrl.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customer_order_base_url', newUrl);
    setState(() {
      _effectiveBaseUrl = newUrl;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer Ordering Base URL updated successfully!'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _fetchData() async {
    try {
      final fetchedTables = await _api.getTables();
      final fetchedReviews = await _api.getCustomerReviews();

      if (mounted) {
        setState(() {
          _tables = fetchedTables.where((t) => (t['active_status'] ?? 'active') == 'active').toList();
          _reviews = fetchedReviews;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading table data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _buildQrUrl(String tableNumber) {
    var base = _effectiveBaseUrl.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final encodedTable = Uri.encodeComponent(tableNumber);
    return '$base/order?table=$encodedTable';
  }

  void _showAddTableDialog() {
    final numberCtrl = TextEditingController();
    final capCtrl = TextEditingController(text: '4');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add New Dining Table', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: numberCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Table Number / Name (e.g. Table 7)',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: capCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Seating Capacity',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final numText = numberCtrl.text.trim();
              final capVal = int.tryParse(capCtrl.text) ?? 4;
              if (numText.isEmpty) return;

              Navigator.pop(ctx);
              try {
                await _api.createTable(numText, capVal);
                _fetchData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to add table: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Create Table'),
          ),
        ],
      ),
    );
  }

  void _showQrCodeModal(Map<String, dynamic> table) {
    final tableNumber = table['table_number'] ?? 'Table';
    final qrData = _buildQrUrl(tableNumber);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Text(
                  tableNumber.toUpperCase(),
                  style: GoogleFonts.outfit(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Scan to View Digital Menu & Order',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, spreadRadius: 2),
                  ],
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(
                qrData,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.check),
                label: const Text('Close Preview'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          'Dine-In QR Codes & Reviews',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.white54,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_2), text: 'Table QR Generator'),
            Tab(icon: Icon(Icons.rate_review), text: 'Customer Reviews'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: _showAddTableDialog,
        icon: const Icon(Icons.add),
        label: Text('Add Table', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTablesQrTab(),
                _buildCustomerReviewsTab(),
              ],
            ),
    );
  }

  Widget _buildTablesQrTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Base URL Config Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.link, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Customer Web Order Base URL',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Set the Local IP address or Domain for phone QR code scanning (e.g. http://192.168.1.100:3000)',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _baseUrlController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'http://192.168.1.100:3000',
                          hintStyle: const TextStyle(color: Colors.white24),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: _saveBaseUrl,
                      child: const Text('Save URL'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Dining Tables (${_tables.length})',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),

          _tables.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(30),
                  width: double.infinity,
                  alignment: Alignment.center,
                  child: Text('No tables configured yet. Click "Add Table" to start.', style: GoogleFonts.outfit(color: Colors.white54)),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 220,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _tables.length,
                  itemBuilder: (ctx, idx) {
                    final t = _tables[idx];
                    final tableNumber = t['table_number'] ?? 'Table ${t['id']}';
                    final cap = t['capacity'] ?? 4;
                    final qrUrl = _buildQrUrl(tableNumber);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  tableNumber,
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('$cap Seats', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => _showQrCodeModal(t),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: QrImageView(
                                data: qrUrl,
                                version: QrVersions.auto,
                                size: 90.0,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary.withOpacity(0.2),
                              foregroundColor: AppColors.primary,
                              elevation: 0,
                              minimumSize: const Size(double.infinity, 36),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _showQrCodeModal(t),
                            icon: const Icon(Icons.qr_code, size: 16),
                            label: const Text('View / Print QR'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildCustomerReviewsTab() {
    if (_reviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.rate_review_outlined, size: 60, color: Colors.white24),
            const SizedBox(height: 16),
            Text('No customer reviews received yet.', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 15)),
          ],
        ),
      );
    }

    double avgRating = 0.0;
    if (_reviews.isNotEmpty) {
      final totalStars = _reviews.fold<int>(0, (sum, r) => sum + (int.tryParse(r['rating']?.toString() ?? '5') ?? 5));
      avgRating = totalStars / _reviews.length;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Average Rating Header Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.indigo.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      avgRating.toStringAsFixed(1),
                      style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < avgRating.round() ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Based on ${_reviews.length} customer reviews',
                      style: GoogleFonts.outfit(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text('Recent Reviews', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 14),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _reviews.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final r = _reviews[idx];
              final tableNum = r['table_number'] ?? 'Table';
              final customerName = r['customer_name'] ?? 'Anonymous';
              final rating = int.tryParse(r['rating']?.toString() ?? '5') ?? 5;
              final comment = r['comment'] ?? '';
              final dateStr = r['created_at'] != null ? r['created_at'].toString().split('T')[0] : '';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(customerName, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(tableNum, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              i < rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 16,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(dateStr, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '"$comment"',
                        style: GoogleFonts.outfit(color: Colors.white.withOpacity(0.87), fontStyle: FontStyle.italic, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
