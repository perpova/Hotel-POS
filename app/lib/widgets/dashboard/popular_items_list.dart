import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../controllers/pos_controller.dart';
import '../../models/models.dart';
import '../image_helper.dart';

class PopularItemsList extends StatelessWidget {
  const PopularItemsList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final posController = Provider.of<POSController>(context);
    final products = posController.products;

    // Fallback items if database is empty
    final fallbackItems = [
      _PopularItem('Mojito', 'Beverages', 2.00, null),
      _PopularItem('Baked Potato', 'Side Orders', 1.50, null),
      _PopularItem('French Fries', 'Side Orders', 1.00, null),
      _PopularItem('Homemade Mashed Potato', 'Side Orders', 1.50, null),
      _PopularItem('Vegan Hum-Burger With Cheese', 'Veggie & Plant Burgers', 2.50, null),
      _PopularItem('Szechuan Shrimp', 'Seafood Entrees', 4.00, null),
    ];

    final hasProducts = products.isNotEmpty;
    final itemCount = hasProducts ? (products.length > 6 ? 6 : products.length) : fallbackItems.length;

    String getCategoryName(int categoryId) {
      final cat = posController.categories.firstWhere(
        (c) => c.id == categoryId,
        orElse: () => CategoryModel(id: 0, name: 'General'),
      );
      return cat.name;
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFF1F5F9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Most Popular Items',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: itemCount,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final String name;
                final String category;
                final double price;
                final String? imageBase64;

                if (hasProducts) {
                  final p = products[index];
                  name = p.name;
                  category = getCategoryName(p.categoryId);
                  price = p.activePrice;
                  imageBase64 = p.imageBase64;
                } else {
                  final f = fallbackItems[index];
                  name = f.name;
                  category = f.category;
                  price = f.price;
                  imageBase64 = f.imageBase64;
                }

                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Row(
                    children: [
                      // Thumbnail image (Base64)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Base64ImageWidget(
                          base64Str: imageBase64,
                          width: 48,
                          height: 48,
                          fallback: Container(
                            width: 48,
                            height: 48,
                            color: const Color(0xFFEFF6FF), // Soft blue bg
                            child: const Center(
                              child: Icon(
                                Icons.fastfood_outlined,
                                color: Color(0xFF2563EB),
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Price
                      Text(
                        'LKR ${price.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularItem {
  final String name;
  final String category;
  final double price;
  final String? imageBase64;
  _PopularItem(this.name, this.category, this.price, this.imageBase64);
}
