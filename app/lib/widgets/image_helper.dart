import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class Base64ImageWidget extends StatefulWidget {
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
  State<Base64ImageWidget> createState() => _Base64ImageWidgetState();
}

class _Base64ImageWidgetState extends State<Base64ImageWidget> {
  Uint8List? _cachedBytes;
  String? _lastBase64Str;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(Base64ImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.base64Str != oldWidget.base64Str) {
      _decodeImage();
    }
  }

  void _decodeImage() {
    final str = widget.base64Str;
    if (str == null || str.trim().isEmpty || str.trim().length < 200) {
      _cachedBytes = null;
      _lastBase64Str = str;
      return;
    }

    if (str == _lastBase64Str && _cachedBytes != null) {
      return;
    }

    try {
      String cleanStr = str;
      if (cleanStr.contains(',')) {
        cleanStr = cleanStr.split(',')[1];
      }
      _cachedBytes = base64Decode(cleanStr.trim());
      _lastBase64Str = str;
    } catch (_) {
      _cachedBytes = null;
      _lastBase64Str = str;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedBytes == null) {
      return _buildFallback();
    }

    return Image.memory(
      _cachedBytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _buildFallback(),
    );
  }

  Widget _buildFallback() {
    return widget.fallback ??
        Container(
          width: widget.width,
          height: widget.height,
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
