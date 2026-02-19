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
  (0, 99, 'Black', Colors.black),
  (100, 199, 'White', Colors.white),
  (200, 299, 'Brown', Colors.brown),
  (300, 399, 'Green', Colors.green),
  (400, 499, 'Blue', Colors.blue),
  (500, 599, 'Purple', Colors.purple),
  (600, 699, 'Red', Colors.red),
  (700, 799, 'Yellow', Colors.yellow),
  (800, 899, 'Orange', Colors.orange),
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
  return lower == 'nike' ||
      lower == 'jordan' ||
      lower.contains('nike') ||
      lower.contains('jordan');
}

// ─────────────────────────────────────────────────────────────────────────────
// New Balance utilities
// ─────────────────────────────────────────────────────────────────────────────

/// New Balance color codes for display (dot color + family name).
/// Falls back to (colorCode, grey) for unmapped codes.
const _nbColorDisplay = <String, (String, Color)>{
  'GRY': ('Grey', Color(0xFF9E9E9E)),
  'GY': ('Grey', Color(0xFF9E9E9E)),
  'BLK': ('Black', Color(0xFF212121)),
  'BK': ('Black', Color(0xFF212121)),
  'WHT': ('White', Color(0xFFFAFAFA)),
  'WT': ('White', Color(0xFFFAFAFA)),
  'RED': ('Red', Color(0xFFF44336)),
  'RD': ('Red', Color(0xFFF44336)),
  'BLU': ('Blue', Color(0xFF2196F3)),
  'NVY': ('Navy', Color(0xFF1A237E)),
  'NAV': ('Navy', Color(0xFF1A237E)),
  'GRN': ('Green', Color(0xFF4CAF50)),
  'GN': ('Green', Color(0xFF4CAF50)),
  'YLW': ('Yellow', Color(0xFFFFEB3B)),
  'YEL': ('Yellow', Color(0xFFFFEB3B)),
  'ORG': ('Orange', Color(0xFFFF9800)),
  'OR': ('Orange', Color(0xFFFF9800)),
  'PNK': ('Pink', Color(0xFFE91E63)),
  'PK': ('Pink', Color(0xFFE91E63)),
  'PUR': ('Purple', Color(0xFF9C27B0)),
  'BRN': ('Brown', Color(0xFF795548)),
  'TAN': ('Tan', Color(0xFFD2B48C)),
  'BEG': ('Beige', Color(0xFFF5F5DC)),
  'BGE': ('Beige', Color(0xFFF5F5DC)),
  'CRM': ('Cream', Color(0xFFFFFDD0)),
  'IVY': ('White', Color(0xFFFAFAFA)),
  'MLT': ('Multi', Color(0xFF9E9E9E)),
  'MUL': ('Multi', Color(0xFF9E9E9E)),
};

/// New Balance SKU patterns.
/// Pattern 1 includes the gender prefix (M/W/U) in the model block so that
/// same-gender-only matching works (M990 ≠ W990).
final _nbSkuPatterns = [
  RegExp(r'^([MWU][0-9]{4}[A-Z]?)([A-Z]{2,6})$'),
  RegExp(r'^([A-Z]{2}[0-9]{3})([A-Z0-9]{2,6})$'),
];

/// Extract the model block and colorway block from a New Balance SKU.
/// Returns (modelBlock, colorCode) or null if no pattern matches.
(String, String)? parseNewBalanceSku(String sku) {
  final normalized = sku.trim().toUpperCase();
  for (final pattern in _nbSkuPatterns) {
    final match = pattern.firstMatch(normalized);
    if (match != null) {
      return (match.group(1)!, match.group(2)!);
    }
  }
  return null;
}

/// Get the color family name and display color for a New Balance color code.
/// Returns (colorCode, grey) for unmapped codes.
(String, Color) nbColorFamily(String colorCode) {
  final upper = colorCode.toUpperCase();
  final entry = _nbColorDisplay[upper];
  if (entry != null) return entry;
  return (colorCode, const Color(0xFF9E9E9E));
}

/// Check if a brand string represents New Balance.
bool isNewBalance(String? brand) {
  if (brand == null) return false;
  final lower = brand.toLowerCase().trim();
  return lower == 'new balance' || lower.contains('new balance');
}

// ─────────────────────────────────────────────────────────────────────────────
// Asics utilities
// ─────────────────────────────────────────────────────────────────────────────

/// Asics SKU patterns: 8-char model block + 2-3 digit colorway.
final _asicsSkuPatterns = [
  RegExp(r'^([0-9]{4}[A-Z][0-9]{3})-([0-9]{2,3})$'),
  RegExp(r'^([A-Z0-9]{8})-([0-9]{2,3})$'),
  RegExp(r'^([A-Z0-9]{8})[\s./\-–_]+([0-9]{2,3})$'),
  RegExp(r'^([A-Z0-9]{8})([0-9]{2,3})$'),
];

/// Extract the model block and colorway block from an Asics SKU.
/// Returns (modelBlock, colorCode) or null if no pattern matches.
(String, String)? parseAsicsSku(String sku) {
  final normalized = sku.trim().toUpperCase();
  for (final pattern in _asicsSkuPatterns) {
    final match = pattern.firstMatch(normalized);
    if (match != null) {
      return (match.group(1)!, match.group(2)!);
    }
  }
  return null;
}

/// Asics colorways are not mapped to colors — always returns a generic entry.
(String, Color) asicsColorFamily(String colorCode) {
  return ('Other Color', const Color(0xFF9E9E9E));
}

/// Check if a brand string represents Asics.
bool isAsics(String? brand) {
  if (brand == null) return false;
  final lower = brand.toLowerCase().trim();
  return lower == 'asics' || lower.contains('asics');
}

// ─────────────────────────────────────────────────────────────────────────────
// Puma utilities
// ─────────────────────────────────────────────────────────────────────────────

/// Puma SKU patterns: 6-digit model block + 2-3 digit colorway.
/// The no-separator pattern is included as a fallback for API responses.
final _pumaSkuPatterns = [
  RegExp(r'^([0-9]{6})-([0-9]{2,3})$'),
  RegExp(r'^([0-9]{6})[\s./\-–_]+([0-9]{2,3})$'),
  RegExp(r'^([0-9]{6})([0-9]{2,3})$'),
];

/// Extract the model block and colorway block from a Puma SKU.
/// Returns (modelBlock, colorCode) or null if no pattern matches.
(String, String)? parsePumaSku(String sku) {
  final normalized = sku.trim().toUpperCase();
  for (final pattern in _pumaSkuPatterns) {
    final match = pattern.firstMatch(normalized);
    if (match != null) {
      return (match.group(1)!, match.group(2)!);
    }
  }
  return null;
}

/// Puma colorways are not mapped to colors — always returns a generic entry.
(String, Color) pumaColorFamily(String colorCode) {
  return ('Other Color', const Color(0xFF9E9E9E));
}

/// Check if a brand string represents Puma.
bool isPuma(String? brand) {
  if (brand == null) return false;
  final lower = brand.toLowerCase().trim();
  return lower == 'puma' || lower.contains('puma');
}
