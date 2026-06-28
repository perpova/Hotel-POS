import 'dart:convert';
import 'package:flutter/material.dart';

class Base64ImageWidget extends StatelessWidget {
  final String? base64Str;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallback;

  const Base64ImageWidget({
    Key? key,
    this.base64Str,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Treat base64 strings shorter than 200 characters as placeholders and show fallback.
    if (base64Str == null || base64Str!.trim().isEmpty || base64Str!.trim().length < 200) {
      return _buildFallback();
    }

    try {
      String cleanStr = base64Str!;
      if (cleanStr.contains(',')) {
        cleanStr = cleanStr.split(',')[1];
      }

      return Image.memory(
        base64Decode(cleanStr.trim()),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    } catch (e) {
      return _buildFallback();
    }
  }

  Widget _buildFallback() {
    return fallback ??
        Container(
          width: width,
          height: height,
          color: const Color(0xFFFFF0F5), // FoodKing light pink background
          child: const Center(
            child: Icon(
              Icons.restaurant_menu,
              color: Color(0xFFFF1B6B), // FoodKing primary pink
              size: 28,
            ),
          ),
        );
  }
}
