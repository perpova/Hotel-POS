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
    if (base64Str == null || base64Str!.isEmpty) {
      return _buildFallback();
    }

    try {
      String cleanStr = base64Str!;
      // Handle "data:image/png;base64," prefix if it exists
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
          color: const Color(0xFFF1F5F9),
          child: const Center(
            child: Icon(
              Icons.restaurant_outlined,
              color: Color(0xFF94A3B8),
              size: 24,
            ),
          ),
        );
  }
}
