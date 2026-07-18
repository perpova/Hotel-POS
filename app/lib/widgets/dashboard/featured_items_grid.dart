import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../controllers/pos_controller.dart';
import '../../theme.dart';
import '../image_helper.dart';

class FeaturedItemsGrid extends StatelessWidget {
  const FeaturedItemsGrid({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;
    final posController = Provider.of<POSController>(context);
    final products = posController.products;

    // Fallback items if database is empty
    final fallbackItems = [
      _FoodItem('BBQ Chicken', null),
      _FoodItem('Vegan Hum-Burger With Cheese', null),
      _FoodItem('Fresh Tuna Salad', null),
      _FoodItem('Onion Rings', null),
      _FoodItem('Chicken Dumplings', null),
      _FoodItem('Chicken Noodles Soup', null),
      _FoodItem('Espresso', null),
      _FoodItem('Steak Sandwich', null),
    ];

    final hasProducts = products.isNotEmpty;
    final itemCount = hasProducts ? (products.length > 8 ? 8 : products.length) : fallbackItems.length;

    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Featured Items',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textLightPrimary,
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: itemCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isDesktop ? 4 : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.15,
              ),
              itemBuilder: (context, index) {
                final String name;
                final String? imageBase64;

                if (hasProducts) {
                  final p = products[index];
                  name = p.name;
                  imageBase64 = p.imageBase64;
                } else {
                  final f = fallbackItems[index];
                  name = f.name;
                  imageBase64 = f.imageBase64;
                }

                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderLight),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Food Image (Base64 or Fallback)
                        Expanded(
                          child: Base64ImageWidget(
                            base64Str: imageBase64,
                            width: double.infinity,
                            height: double.infinity,
                            fallback: Container(
                              color: const Color(0xFFFFECEF),
                              child: const Center(
                                child: Icon(
                                  Icons.restaurant_outlined,
                                  color: Color(0xFFFF1B6B),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Label Bar
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          color: AppTheme.cardLight,
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textLightPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _FoodItem {
  final String name;
  final String? imageBase64;
  _FoodItem(this.name, this.imageBase64);
}
