import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Brand / format data ───────────────────────────────────────────────────────

class _BrandFormat {
  final String brand;
  final String example;
  final String hint;
  const _BrandFormat({
    required this.brand,
    required this.example,
    required this.hint,
  });
}

const _kBrands = [
  _BrandFormat(
    brand: 'Nike / Jordan',
    example: 'DZ5485 612',
    hint: '6 chars · 3 digits',
  ),
  _BrandFormat(
    brand: 'Adidas',
    example: 'HQ4234',
    hint: '2 letters · 4 digits, or 6 alphanumeric',
  ),
  _BrandFormat(
    brand: 'Asics',
    example: '1011B548 001',
    hint: '8 alphanumeric · 3 digits',
  ),
  _BrandFormat(
    brand: 'New Balance',
    example: 'M990GL6',
    hint: 'M/W/U prefix · 4 digits · color code',
  ),
  _BrandFormat(
    brand: 'Vans',
    example: 'VN0A4U39',
    hint: 'Starts with VN · 6–8 alphanumeric',
  ),
  _BrandFormat(
    brand: 'Puma',
    example: '384857 01',
    hint: '6 digits · 2–3 digits',
  ),
  _BrandFormat(
    brand: 'Reebok',
    example: 'AR2626',
    hint: '2 letters · 4 digits',
  ),
  _BrandFormat(
    brand: 'Converse',
    example: 'A02851C',
    hint: '1 letter · 5 digits · 1 letter',
  ),
  _BrandFormat(
    brand: 'Skechers',
    example: '232001 BBK',
    hint: '5–6 digits · color code',
  ),
];

// ── Public entry point ────────────────────────────────────────────────────────

void showSkuFormatsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SkuFormatsSheet(),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _SkuFormatsSheet extends StatelessWidget {
  const _SkuFormatsSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SKU Formats by Brand',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.grey[500],
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'The SKU is on the side label of the shoe box.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[500]),
              ),
            ),

            const SizedBox(height: 20),

            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),

            // Brand list
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _kBrands.length,
                separatorBuilder: (_, i) => Divider(
                  color: Colors.white.withValues(alpha: 0.06),
                  height: 1,
                  indent: 24,
                  endIndent: 24,
                ),
                itemBuilder: (_, i) => _BrandRow(brand: _kBrands[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Brand row ─────────────────────────────────────────────────────────────────

class _BrandRow extends StatelessWidget {
  final _BrandFormat brand;
  const _BrandRow({required this.brand});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brand.brand,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  brand.hint,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Text(
              brand.example,
              style: GoogleFonts.robotoMono(
                fontSize: 13,
                color: const Color(0xFF646CFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
