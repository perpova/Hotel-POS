import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/stock_provider.dart';
import '../models/models.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({Key? key}) : super(key: key);

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stock = context.watch<StockProvider>();

    final filteredProducts = stock.products
        .where((p) =>
            _search.isEmpty ||
            p.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    final filteredIngredients = stock.ingredients
        .where((i) =>
            _search.isEmpty ||
            i.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: const Text('Stock Management'),
        actions: [
          if (stock.lowStockProducts.isNotEmpty ||
              stock.lowStockIngredients.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.errorGlow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.error.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.error, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${stock.lowStockProducts.length + stock.lowStockIngredients.length} Low Stock',
                      style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => stock.loadAll(),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Products'),
                  if (stock.lowStockProducts.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${stock.lowStockProducts.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Ingredients'),
                  if (stock.lowStockIngredients.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${stock.lowStockIngredients.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search products or ingredients...',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.textMuted, size: 20),
                suffixIcon: _search.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                        child: const Icon(Icons.close_rounded,
                            color: AppColors.textMuted, size: 18),
                      )
                    : null,
              ),
            ),
          ),

          // Tab content
          Expanded(
            child: stock.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary),
                  )
                : TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // Products tab
                      filteredProducts.isEmpty
                          ? _empty('No products found')
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                              itemCount: filteredProducts.length,
                              itemBuilder: (ctx, i) =>
                                  _ProductStockTile(
                                    product: filteredProducts[i],
                                    onAdjust: () => _showAdjustDialog(
                                        context, filteredProducts[i]),
                                  ).animate(delay: (i * 30).ms).fadeIn(),
                            ),

                      // Ingredients tab
                      filteredIngredients.isEmpty
                          ? _empty('No ingredients found')
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                              itemCount: filteredIngredients.length,
                              itemBuilder: (ctx, i) =>
                                  _IngredientStockTile(
                                    ingredient: filteredIngredients[i],
                                    onAdjust: () =>
                                        _showIngredientAdjustDialog(
                                            context, filteredIngredients[i]),
                                  ).animate(delay: (i * 30).ms).fadeIn(),
                            ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                color: AppColors.textMuted.withOpacity(0.4), size: 48),
            const SizedBox(height: 12),
            Text(msg,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );

  Future<void> _showAdjustDialog(
      BuildContext context, ProductModel product) async {
    final stock = context.read<StockProvider>();
    final qtyCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String type = 'purchase';
    bool loading = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Adjust Stock — ${product.name}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('Current: ',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  Text(
                    '${product.stockQty} units',
                    style: TextStyle(
                        color: product.isLowStock
                            ? AppColors.error
                            : AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Type selector
              const Text('Type',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: ['purchase', 'adjustment', 'wastage'].map((t) {
                  final sel = type == t;
                  Color c = t == 'purchase'
                      ? AppColors.success
                      : t == 'adjustment'
                          ? AppColors.info
                          : AppColors.error;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setModalState(() => type = t),
                      child: AnimatedContainer(
                        duration: 200.ms,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? c.withOpacity(0.15) : AppColors.bgCardAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: sel ? c : AppColors.border),
                        ),
                        child: Text(
                          t[0].toUpperCase() + t.substring(1),
                          style: TextStyle(
                              color: sel ? c : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: sel
                                  ? FontWeight.w600
                                  : FontWeight.w400),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Qty input
              TextField(
                controller: qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Qty Change (use negative for wastage)',
                  prefixIcon: Icon(Icons.add_circle_outline,
                      color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 12),
              // Reason input
              TextField(
                controller: reasonCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  prefixIcon:
                      Icon(Icons.notes_rounded, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final qty = int.tryParse(qtyCtrl.text);
                          if (qty == null || qty == 0) return;
                          setModalState(() => loading = true);
                          try {
                            await stock.adjustProductStock(
                              product.id,
                              qty,
                              type,
                              reasonCtrl.text.trim().isEmpty
                                  ? 'Admin adjustment'
                                  : reasonCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Stock updated: ${product.name}'),
                                  backgroundColor: AppColors.success,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() => loading = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Error: ${e.toString().replaceAll('Exception: ', '')}'),
                                  backgroundColor: AppColors.error,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Apply Adjustment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showIngredientAdjustDialog(
      BuildContext context, IngredientModel ingredient) async {
    final stock = context.read<StockProvider>();
    final qtyCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String type = 'purchase';
    bool loading = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text('Adjust — ${ingredient.name}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Current: ${ingredient.stockQty} ${ingredient.unit}',
                style: TextStyle(
                    color: ingredient.isLowStock
                        ? AppColors.error
                        : AppColors.success,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Row(
                children: ['purchase', 'adjustment', 'wastage'].map((t) {
                  final sel = type == t;
                  Color c = t == 'purchase'
                      ? AppColors.success
                      : t == 'adjustment'
                          ? AppColors.info
                          : AppColors.error;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setModalState(() => type = t),
                      child: AnimatedContainer(
                        duration: 200.ms,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? c.withOpacity(0.15) : AppColors.bgCardAlt,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: sel ? c : AppColors.border),
                        ),
                        child: Text(
                          t[0].toUpperCase() + t.substring(1),
                          style: TextStyle(
                              color: sel ? c : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: sel
                                  ? FontWeight.w600
                                  : FontWeight.w400),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Qty (${ingredient.unit})',
                  prefixIcon: const Icon(Icons.add_circle_outline,
                      color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  prefixIcon:
                      Icon(Icons.notes_rounded, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final qty = double.tryParse(qtyCtrl.text);
                          if (qty == null || qty == 0) return;
                          setModalState(() => loading = true);
                          try {
                            await stock.adjustIngredientStock(
                                ingredient.id,
                                qty,
                                type,
                                reasonCtrl.text.trim().isEmpty
                                    ? 'Admin adjustment'
                                    : reasonCtrl.text.trim());
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            setModalState(() => loading = false);
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductStockTile extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onAdjust;
  const _ProductStockTile({required this.product, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final isLow = product.isLowStock;
    final isOut = product.isOutOfStock;
    Color statusColor = isOut
        ? AppColors.error
        : isLow
            ? AppColors.warning
            : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isLow || isOut)
              ? statusColor.withOpacity(0.3)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isOut)
                      _badge('OUT', AppColors.error)
                    else if (isLow)
                      _badge('LOW', AppColors.warning),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${product.stockQty}',
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w800),
                    ),
                    Text(
                      ' / min ${product.minStockLevel} units',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: product.stockPercent,
                    backgroundColor: AppColors.bgCardAlt,
                    valueColor: AlwaysStoppedAnimation(statusColor),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onAdjust,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryGlow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tune_rounded,
                  color: AppColors.primary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w700)),
      );
}

class _IngredientStockTile extends StatelessWidget {
  final IngredientModel ingredient;
  final VoidCallback onAdjust;
  const _IngredientStockTile(
      {required this.ingredient, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final isLow = ingredient.isLowStock;
    final isOut = ingredient.isOutOfStock;
    Color statusColor = isOut
        ? AppColors.error
        : isLow
            ? AppColors.warning
            : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isLow || isOut)
              ? statusColor.withOpacity(0.3)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ingredient.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  '${ingredient.stockQty.toStringAsFixed(1)} ${ingredient.unit}  ·  min ${ingredient.minStockLevel.toStringAsFixed(1)}',
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onAdjust,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryGlow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tune_rounded,
                  color: AppColors.primary, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
