import 'package:flutter/material.dart';

class ColorwayVariant {
  final String sku;
  final String colorCode;
  final String colorFamily;
  final Color displayColor;
  final double price;
  final String? slug;

  const ColorwayVariant({
    required this.sku,
    required this.colorCode,
    required this.colorFamily,
    required this.displayColor,
    required this.price,
    this.slug,
  });
}

/// Nike color families mapped from the second block of the SKU.
const _nikeColorFamilies = [
  (0, 49, 'Black', Colors.black),
  (100, 149, 'White', Colors.white),
  (200, 249, 'Brown', Colors.brown),
  (300, 349, 'Green', Colors.green),
  (400, 449, 'Blue', Colors.blue),
  (500, 549, 'Purple', Colors.purple),
  (600, 649, 'Red', Colors.red),
  (700, 749, 'Yellow', Colors.yellow),
  (800, 849, 'Orange', Colors.orange),
  (900, 999, 'Multi', Colors.grey),
];

/// Get the color family name and display color for a Nike colorway code.
(String, Color) nikeColorFamily(String colorCode) {
  final num = int.tryParse(colorCode);
  if (num == null) return ('Unknown', Colors.grey);

  for (final (low, high, name, color) in _nikeColorFamilies) {
    if (num >= low && num <= high) return (name, color);
  }
  return ('Unknown', Colors.grey);
}

/// Nike/Jordan SKU patterns: each has two capture groups (model, colorway).
final _nikeSkuPatterns = [
  RegExp(r'^([A-Z0-9]{6})-([0-9]{3})$'),
  RegExp(r'^([A-Z0-9]{6})([0-9]{3})$'),
  RegExp(r'^([A-Z0-9]{6})[\s./\-–_]+([0-9]{3})$'),
  RegExp(r'^([A-Z0-9]{6})-([0-9]{4})$'),
  RegExp(r'^([A-Z0-9]{6})([0-9]{4})$'),
  RegExp(r'^([A-Z0-9]{7})-([0-9]{3})$'),
  RegExp(r'^([A-Z0-9]{7})([0-9]{3})$'),
];

/// Extract the model block and colorway block from a Nike SKU.
/// Returns (modelBlock, colorwayBlock) or null if no pattern matches.
(String, String)? parseNikeSku(String sku) {
  final normalized = sku.trim().toUpperCase();
  for (final pattern in _nikeSkuPatterns) {
    final match = pattern.firstMatch(normalized);
    if (match != null) {
      return (match.group(1)!, match.group(2)!);
    }
  }
  return null;
}

/// Check if a brand string represents Nike or Jordan.
bool isNikeOrJordan(String? brand) {
  if (brand == null) return false;
  final lower = brand.toLowerCase().trim();
  return lower == 'nike' || lower == 'jordan' || lower.contains('nike') || lower.contains('jordan');
}
