import '../constants.dart';

/// Builds the CompsAPI search text for a shoe from its eBay listing title.
///
/// CompsAPI only returns sold listings whose title contains every word in the
/// query, so the query keeps only words other sellers are likely to write:
/// brand, model and color words, up to 7 words, e.g.
/// "Nike Dunk Low Retro Black White". Colors get their slots first (up to 3),
/// then brand + model words fill the rest. SKUs, size, quoted colorway
/// nicknames, gender and condition words are dropped.
///
/// [fallbackTitle] is used when there is no eBay title. Returns null when
/// there is nothing to search with.
String? buildEbaySalesQuery({String? ebayTitle, String? fallbackTitle}) {
  final title = (ebayTitle != null && ebayTitle.trim().isNotEmpty)
      ? ebayTitle
      : fallbackTitle;

  if (title == null || title.trim().isEmpty) return null;
  final brand = _findBrand(title);
  final colors = _colorWords(title).take(_maxColors).toList();
  final words = _modelWords(title, brand);
  // Brand + model words in title order, leaving room for the colors.
  final room = _maxWords - colors.length;
  final kept = <String>[];
  for (final w in words) {
    if (kept.length >= room) break;
    kept.add(w == _brandMarker ? brand!.text : w);
  }
  kept.addAll(colors);
  return kept.isEmpty ? null : kept.join(' ');
}

/// US size from a sold listing title ("Size 10.5", "Sz 10", "US10", "10M",
/// "~11"), as "10.5" / "10". Null when none is found.
String? parseUsSize(String title) {
  final t = title.toUpperCase();
  final patterns = [
    RegExp(
      r"\b(?:SIZE|SZ|US|MEN'?S|M|W|WMNS|WOMEN'?S)\s*[:#.]?\s*~?(\d{1,2}(?:\.5)?)(?![\d.])",
    ),
    RegExp(r'(?<![\d.])(\d{1,2}(?:\.5)?)\s*(?:M|W|US|Y)\b'),
    RegExp(r'~\s*(\d{1,2}(?:\.5)?)(?![\d.])'),
  ];
  for (final p in patterns) {
    for (final m in p.allMatches(t)) {
      final value = double.tryParse(m.group(1)!);
      if (value != null && value >= 1 && value <= 18) {
        return value == value.roundToDouble()
            ? value.toInt().toString()
            : value.toString();
      }
    }
  }
  return null;
}

// ── Internals ────────────────────────────────────────────────────────────────

final _hyphenSku = RegExp(r'^([A-Z0-9]{5,10})-([A-Z0-9]{2,4})$');
final _plainSku = RegExp(r'^[A-Z0-9]{6,10}$');
final _sizePrefix = RegExp(r'^(US|SZ|SIZE|UK|EU)\d');

bool _isSku(String token) {
  int digits(String s) => RegExp(r'\d').allMatches(s).length;
  final h = _hyphenSku.firstMatch(token);
  if (h != null) return digits(h.group(1)!) >= 3 && digits(h.group(2)!) >= 1;
  if (!_plainSku.hasMatch(token) || _sizePrefix.hasMatch(token)) return false;
  return RegExp(r'[A-Z]').hasMatch(token) && digits(token) >= 3;
}

/// Trims punctuation like quotes, commas and brackets from a token's ends.
String _stripEdges(String token) =>
    token.replaceAll(RegExp(r'''^[^A-Za-z0-9]+|[^A-Za-z0-9]+$'''), '');

class _BrandMatch {
  final String text; // as written in the title
  final int start;
  final int end;
  const _BrandMatch(this.text, this.start, this.end);
}

/// The earliest known brand in [title] (longest wins on ties), as written.
/// "On" only counts at the very start, since "Slip On" is common.
_BrandMatch? _findBrand(String title) {
  _BrandMatch? best;
  for (final brand in knownFootwearBrands) {
    final pattern = RegExp(
      '(?<![A-Za-z0-9])${RegExp.escape(brand)}(?![A-Za-z0-9])',
      caseSensitive: false,
    );
    final m = pattern.firstMatch(title);
    if (m == null) continue;
    if (brand == 'on' && m.start != 0) continue;
    final better =
        best == null ||
        m.start < best.start ||
        (m.start == best.start && m.end > best.end);
    if (better) best = _BrandMatch(m.group(0)!, m.start, m.end);
  }
  return best;
}

const _dropWords = {
  // condition / listing filler
  'new', 'brand', 'nwt', 'nwob', 'nib', 'nwb', 'bnib', 'ds', 'vnds', 'used',
  'pre-owned', 'preowned', 'worn', 'authentic', 'rare', 'box', 'no', 'lid',
  'with', 'w', 'and', 'the', 'free', 'shipping', 'fast', 'ship', 'sample',
  'lot', 'pair', 'read', 'description', 'great', 'condition', 'excellent',
  'good', 'mint', 'clean', 'og-box', 'replacement',
  // gender / age
  'men', 'mens', "men's", 'man', 'women', 'womens', "women's", 'wmns',
  'woman', 'gs', 'ps', 'td', 'youth', 'kids', 'kid', 'boys', 'girls',
  'grade', 'school', 'unisex', 'toddler', 'infant',
  // size words
  'size', 'sz', 'us', 'uk', 'eu', 'wide',
  // product type
  'shoes', 'shoe', 'sneakers', 'sneaker', 'trainers', 'trainer', 'running',
  'basketball', 'athletic', 'casual', 'lifestyle', 'top', 'skate',
  'walking', 'footwear',
  // color modifiers (the base color itself goes in the query)
  'multi', 'multicolor', 'royal', 'university', 'triple', 'metallic',
  'light', 'dark', 'cool', 'wolf', 'off', 'colorway',
};

/// Base colors that go in the query (see [_colorWords]).
const _colors = {
  'black',
  'white',
  'red',
  'blue',
  'green',
  'grey',
  'gray',
  'pink',
  'purple',
  'yellow',
  'orange',
  'brown',
  'tan',
  'beige',
  'cream',
  'navy',
  'olive',
  'silver',
  'gold',
  'sail',
  'bone',
  'volt',
  'smoke',
  'neutral',
  'khaki',
  'maroon',
  'burgundy',
  'teal',
};

const _maxColors = 3;

/// Base colors in [title], in order, without repeats: plain words ("Black
/// White") and slash colorways ("Red/White"). Quoted nicknames are skipped.
List<String> _colorWords(String title) {
  final text = title
      .replaceAll(RegExp(r'''["“”][^"“”]*["“”]'''), ' ')
      .replaceAll(RegExp(r"(?<![A-Za-z])'[^']+'(?![A-Za-z])"), ' ');
  final seen = <String>{};
  final colors = <String>[];
  for (final raw in text.split(RegExp(r'[\s/]+'))) {
    final word = _stripEdges(raw);
    final lower = word.toLowerCase();
    if (_colors.contains(lower) && seen.add(lower)) colors.add(word);
  }
  return colors;
}

const _brandMarker = 'BRANDMARKERX';
const _maxWords = 7;

/// Model words from [title], with the brand replaced by [_brandMarker]:
/// everything left after removing quoted
/// colorway names, bracketed text, sizes, SKUs, slash colors, years and
/// filler words.
List<String> _modelWords(String title, _BrandMatch? brand) {
  var text = brand == null
      ? title
      : '${title.substring(0, brand.start)} $_brandMarker '
            '${title.substring(brand.end)}';
  text = text
      .replaceAll(RegExp(r'''["“”][^"“”]*["“”]'''), ' ') // "Chicago"
      .replaceAll(RegExp(r"(?<![A-Za-z])'[^']+'(?![A-Za-z])"), ' ') // 'Panda'
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ') // (GS) [2023]
      .replaceAll(
        RegExp(
          r"\b(?:size|sz|us|uk|eu|men'?s|women'?s|wmns)\s*[:#.]?\s*~?\d{1,2}(?:\.5)?\b",
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'~\s*\d{1,2}(?:\.5)?'), ' ');

  final seen = <String>{};
  final words = <String>[];
  for (final raw in text.split(RegExp(r'\s+'))) {
    if (raw.contains('/')) continue; // Black/White
    final word = _stripEdges(raw);
    if (word.isEmpty) continue;
    if (word == _brandMarker) {
      words.add(word);
      continue;
    }
    final lower = word.toLowerCase();
    if (_dropWords.contains(lower) || _colors.contains(lower)) continue;
    if (_isSku(word.toUpperCase())) continue;
    if (RegExp(r'^(19|20)\d{2}$').hasMatch(word)) continue; // year
    if (RegExp(r'^\d{1,2}(\.5)?[MWY]$', caseSensitive: false).hasMatch(word)) {
      continue; // 10M
    }
    if (!seen.add(lower)) continue;
    words.add(word);
  }
  return words;
}
