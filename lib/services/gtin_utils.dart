/// Normalize a GTIN/UPC/EAN to a canonical 13-digit EAN-13 string for comparison.
/// Strips leading/trailing whitespace, pads UPC-A (12 digits) to EAN-13,
/// and strips leading zeros down to 13 digits for longer codes.
String normalizeGtin(String raw) {
  final stripped = raw.trim().replaceAll(RegExp(r'[^0-9]'), '');
  if (stripped.isEmpty) return '';
  // UPC-A (12 digits) → EAN-13 by prepending '0'
  if (stripped.length == 12) return '0$stripped';
  // UPC-E (8 digits) or EAN-8 — keep as-is (too short to pad reliably)
  if (stripped.length <= 8) return stripped;
  // EAN-13 or longer — take rightmost 13 digits (strip leading zeros)
  if (stripped.length > 13) return stripped.substring(stripped.length - 13);
  return stripped;
}
