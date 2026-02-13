import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class SimilarResultsSection extends StatelessWidget {
  final List<Map<String, dynamic>> candidates;
  final bool isLoading;
  final bool searchDone;

  const SimilarResultsSection({
    super.key,
    required this.candidates,
    required this.isLoading,
    required this.searchDone,
  });

  Future<void> _openProductUrl(Map<String, dynamic> candidate) async {
    final stockXSlug = candidate['stockXSlug'] as String?;
    final goatSlug = candidate['goatSlug'] as String?;
    final sku = candidate['sku'] as String?;
    final title = candidate['title'] as String?;

    Uri? uri;
    if (stockXSlug != null && stockXSlug.isNotEmpty) {
      uri = Uri.parse('https://stockx.com/$stockXSlug');
    } else if (goatSlug != null && goatSlug.isNotEmpty) {
      uri = Uri.parse('https://www.goat.com/sneakers/$goatSlug');
    } else if (sku != null && sku.isNotEmpty) {
      uri = Uri.parse(
        'https://stockx.com/search?s=${Uri.encodeComponent(sku)}',
      );
    } else if (title != null && title.isNotEmpty) {
      uri = Uri.parse(
        'https://stockx.com/search?s=${Uri.encodeComponent(title)}',
      );
    }

    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildLoading();
    }
    if (candidates.isNotEmpty) {
      return _buildList();
    }
    if (searchDone) {
      return _buildEmpty();
    }
    return _buildLoading();
  }

  Widget _buildEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: const Color(0xFF646CFF),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Similar Results',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No similar results found',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: const Color(0xFF646CFF),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Similar Results',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CircularProgressIndicator(
                color: Color(0xFF646CFF),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Searching for similar results...',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: const Color(0xFF646CFF),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Similar Results',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Products similar to your scan:',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 12),
          ...candidates.map((candidate) {
            final title = (candidate['title'] ?? '').toString();
            final brand = (candidate['brand'] ?? '').toString();
            final image = (candidate['image'] ?? '').toString();
            final retailPrice = candidate['retailPrice'] as double?;
            final emv = candidate['estimatedMarketValue'] as double?;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => _openProductUrl(candidate),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252525),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF333333), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: image.isNotEmpty
                            ? Image.network(
                                image,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (_, e, s) => Container(
                                  width: 60,
                                  height: 60,
                                  color: const Color(0xFF333333),
                                  child: Icon(
                                    Icons.image_not_supported,
                                    color: Colors.grey[600],
                                    size: 24,
                                  ),
                                ),
                              )
                            : Container(
                                width: 60,
                                height: 60,
                                color: const Color(0xFF333333),
                                child: Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey[600],
                                  size: 24,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              brand,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (retailPrice != null) ...[
                                  Text(
                                    'Retail: \$${retailPrice.toStringAsFixed(0)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.green[400],
                                    ),
                                  ),
                                ],
                                if (retailPrice != null && emv != null)
                                  const SizedBox(width: 12),
                                if (emv != null) ...[
                                  Text(
                                    'Est: \$${emv.toStringAsFixed(0)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.blue[300],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Icon(
                          Icons.chevron_right,
                          color: Colors.grey[600],
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
