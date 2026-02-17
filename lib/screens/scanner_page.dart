import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/scan_data.dart';
import '../services/gtin_utils.dart';
import 'scan_detail/scan_detail_page.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  bool _isProcessing = false;

  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final ImagePicker _imagePicker = ImagePicker();
  final MobileScannerController _previewController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _previewController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _previewController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _previewController.start();
    }
  }

  ScanData _parseLabelInfo(String text) {
    // Normalize: collapse whitespace, uppercase
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

    // sep = flexible separator: dash, space, slash, dot, or nothing
    const sep = r'[-\s/.]*';

    // --- Code extraction ---
    String? code;

    // --- Pass 1: Look for labeled codes ---
    final styleLabeled = RegExp(
      'STYLE[#:\\s]+([A-Z0-9][A-Z0-9\\-\\s/.]+[A-Z0-9])',
    ).firstMatch(normalized);
    if (styleLabeled != null) {
      final raw = styleLabeled.group(1)!.trim();
      code = raw.replaceAll(RegExp(r'[\s/.]+'), '-');
    }
    if (code == null) {
      final skuLabeled = RegExp(
        'SKU[#:\\s]+([A-Z0-9][A-Z0-9\\-\\s/.]+[A-Z0-9])',
      ).firstMatch(normalized);
      if (skuLabeled != null) {
        final raw = skuLabeled.group(1)!.trim();
        code = raw.replaceAll(RegExp(r'[\s/.]+'), '-');
      }
    }
    if (code == null) {
      final itemLabeled = RegExp(
        'ITEM[#:\\s]+([A-Z0-9][A-Z0-9\\-\\s/.]+[A-Z0-9])',
      ).firstMatch(normalized);
      if (itemLabeled != null) {
        final raw = itemLabeled.group(1)!.trim();
        code = raw.replaceAll(RegExp(r'[\s/.]+'), '-');
      }
    }
    if (code == null) {
      final dpciLabeled = RegExp(
        'DPCI[:\\s]+(\\d{3})$sep(\\d{2})$sep(\\d{4})',
      ).firstMatch(normalized);
      if (dpciLabeled != null) {
        code =
            '${dpciLabeled.group(1)}-${dpciLabeled.group(2)}-${dpciLabeled.group(3)}';
      }
    }

    // --- Pass 2: Pattern-match common style code formats ---
    if (code == null) {
      final patterns = <(RegExp, String Function(String))>[
        // Nike/Jordan: DD1391-100, CT8012 170, FB8896/100, CW1590.100, DH9765002
        (
          RegExp('\\b([A-Z]{2,3}\\d{4})$sep(\\d{3})\\b'),
          (m) {
            final match = RegExp(
              '\\b([A-Z]{2,3}\\d{4})$sep(\\d{3})\\b',
            ).firstMatch(m)!;
            return '${match.group(1)}-${match.group(2)}';
          },
        ),
        // Jordan/UA 6-digit: 555088-134, 555088 134, 3026175-001
        (
          RegExp('\\b(\\d{6,7})$sep(\\d{3})\\b'),
          (m) {
            final match = RegExp('\\b(\\d{6,7})$sep(\\d{3})\\b').firstMatch(m)!;
            return '${match.group(1)}-${match.group(2)}';
          },
        ),
        // Puma: 374915-01, 374915 01
        (
          RegExp('\\b(\\d{6})$sep(\\d{2})\\b'),
          (m) {
            final match = RegExp('\\b(\\d{6})$sep(\\d{2})\\b').firstMatch(m)!;
            return '${match.group(1)}-${match.group(2)}';
          },
        ),
        // Adidas: GW2871, HP5582, IF1477 (2 letters + 4 digits)
        (RegExp(r'\b[A-Z]{2}\d{4}\b'), (m) => m),
        // New Balance: M990GL6, ML574EVG, M1080B12
        (RegExp(r'\bM[A-Z]?\d{3,4}[A-Z]{1,3}\d{0,2}\b'), (m) => m),
        // Converse: 162050C
        (RegExp(r'\b\d{6}C\b'), (m) => m),
      ];

      for (final (pattern, normalize) in patterns) {
        final match = pattern.firstMatch(normalized);
        if (match != null) {
          code = normalize(match.group(0)!);
          break;
        }
      }
    }

    // --- Brand extraction ---
    const knownBrands = [
      'GOODFELLOW',
      'CAT & JACK',
      'ALL IN MOTION',
      'A NEW DAY',
      'UNIVERSAL THREAD',
      'WILD FABLE',
      'ART CLASS',
      'SHADE & SHORE',
      'NIKE',
      'ADIDAS',
      'JORDAN',
      'NEW BALANCE',
      'PUMA',
      'REEBOK',
      'CONVERSE',
      'VANS',
      'ASICS',
      'SAUCONY',
      'UNDER ARMOUR',
      'HOKA',
      'ON RUNNING',
      'BROOKS',
      'FILA',
      'SKETCHERS',
      'SKECHERS',
      'CROCS',
      'BIRKENSTOCK',
      'DR. MARTENS',
      'TIMBERLAND',
      'CHAMPION',
      'LEVI\'S',
      'WRANGLER',
      'DICKIES',
    ];

    String? foundBrand;
    final brandLabelMatch = RegExp(
      r'BRAND[:\s]+([A-Z][A-Z&\s]+)',
    ).firstMatch(normalized);
    if (brandLabelMatch != null) {
      foundBrand = brandLabelMatch.group(1)!.trim();
    }

    if (foundBrand == null) {
      for (final brand in knownBrands) {
        if (normalized.contains(brand)) {
          foundBrand = brand;
          break;
        }
      }
    }

    // --- Product name extraction ---
    final lines = text.split(RegExp(r'[\n\r]+'));
    String? productName;
    final labelFieldPattern = RegExp(
      r'^(DPCI|STYLE|SKU|ITEM|BRAND|COLOR|SIZE|UPC|TCIN|BARCODE)[#:\s]',
      caseSensitive: false,
    );
    final codePattern = RegExp(
      r'^\d{3}-\d{2}-\d{4}$|^[A-Z]{2,3}\d{4}-\d{3}$|^\d{6,}$|^\d{12,13}$',
    );

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.length < 3) continue;
      if (labelFieldPattern.hasMatch(trimmed)) continue;
      if (codePattern.hasMatch(trimmed.toUpperCase())) continue;
      final alphaCount = trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
      if (alphaCount < trimmed.length * 0.5) continue;
      final words = trimmed.split(RegExp(r'\s+'));
      if (words.length < 2) continue;
      if (foundBrand != null && trimmed.toUpperCase().trim() == foundBrand) {
        continue;
      }
      productName = trimmed;
      break;
    }

    // --- Colorway extraction ---
    String? colorway;
    // Look for COLOR: or COLORWAY: labeled field
    final colorLabelMatch = RegExp(
      r'COLOU?R(?:WAY)?[:\s]+([A-Z][A-Z /\-]+)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (colorLabelMatch != null) {
      colorway = _titleCase(colorLabelMatch.group(1)!.trim());
    }
    // Fallback: slash-separated color patterns like BLACK/WHITE-FIRE RED
    if (colorway == null) {
      final slashColorMatch = RegExp(
        r'\b([A-Z]{3,}(?:\s+[A-Z]+)*(?:/[A-Z]+(?:\s+[A-Z]+)*){1,4})\b',
      ).firstMatch(normalized);
      if (slashColorMatch != null) {
        final candidate = slashColorMatch.group(1)!;
        // Only treat as colorway if it looks like colors (has a slash)
        if (candidate.contains('/')) {
          colorway = _titleCase(candidate);
        }
      }
    }

    // --- Assemble model name ---
    String? modelName;
    if (foundBrand != null || productName != null) {
      String titleCase(String s) => s
          .split(' ')
          .map(
            (w) => w.isEmpty
                ? w
                : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
          )
          .join(' ');

      final parts = <String>[];
      if (foundBrand != null) {
        final brandTitle = titleCase(foundBrand);
        parts.add(brandTitle);
        if (productName != null &&
            !productName.toUpperCase().startsWith(foundBrand)) {
          parts.add(productName);
        } else if (productName != null) {
          parts.add(productName);
          parts.clear();
          parts.add(productName);
        }
      } else if (productName != null) {
        parts.add(productName);
      }
      final assembled = parts.join(' ').trim();
      if (assembled.isNotEmpty) {
        modelName = assembled;
      }
    }

    // Validate extracted code against known SKU patterns
    if (code != null && !_isValidSku(code)) {
      debugPrint('SKU rejected (no pattern match): "$code"');
      code = null;
    }

    // --- Size extraction ---
    String? size;
    final sizeMatch = RegExp(
      r'(?:SIZE|US|UK|EU)[:\s]*(\d{1,2}(?:\.\d)?)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (sizeMatch != null) {
      final parsed = double.tryParse(sizeMatch.group(1)!);
      if (parsed != null && parsed >= 1 && parsed <= 20) {
        size = sizeMatch.group(1)!;
      }
    }

    // Title-case the brand for storage
    String? brandForStorage;
    if (foundBrand != null) {
      brandForStorage = _titleCase(foundBrand);
    }

    return ScanData(
      brand: brandForStorage,
      modelName: modelName,
      colorway: colorway,
      sku: code,
      size: size,
    );
  }

  String _titleCase(String s) => s
      .split(' ')
      .map(
        (w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
      )
      .join(' ');

  static final _skuPatterns = [
    RegExp(r'^\d{6}-\d{3}$'),           // Nike (e.g. 555088-134)
    RegExp(r'^\d{9}$'),                  // Nike OCR variant (e.g. 555088134)
    RegExp(r'^[A-Z]{1,2}\d{4,5}$'),     // Adidas (e.g. GW2871, HP5582)
    RegExp(r'^\d{4}[A-Z]\d{3}-\d{3}$'), // ASICS
    RegExp(r'^[A-Z]\d{3,4}[A-Z0-9]{1,3}$'), // New Balance (e.g. M990GL6)
    RegExp(r'^\d{6}-\d{2}$'),           // Puma (e.g. 374915-01)
    RegExp(r'^[A-Z]{2,3}\d{4}-\d{3}$'), // Nike/Jordan alpha prefix (e.g. DD1391-100)
  ];

  bool _isValidSku(String code) {
    final normalized = code.replaceAll(' ', '-').toUpperCase();
    return _skuPatterns.any((p) => p.hasMatch(normalized));
  }

  Future<void> _captureAndProcess() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) return;

      setState(() => _isProcessing = true);

      final inputImage = InputImage.fromFilePath(photo.path);

      // Run OCR on the captured image
      final textRecognizer = TextRecognizer();

      try {
        final recognizedText = await textRecognizer.processImage(inputImage);

        final fullText = recognizedText.text;
        debugPrint('OCR text: $fullText');

        // Parse OCR text into ScanData
        final scanData = _parseLabelInfo(fullText);

        debugPrint('═══ SCAN RESULT ═══');
        if (scanData.sku != null) {
          debugPrint('SKU found: ${scanData.sku}');
        } else {
          debugPrint('SKU: not found');
        }
        debugPrint('Brand: ${scanData.brand ?? 'n/a'}, '
            'Model: ${scanData.modelName ?? 'n/a'}, '
            'Colorway: ${scanData.colorway ?? 'n/a'}, '
            'Size: ${scanData.size ?? 'n/a'}');
        debugPrint('═══════════════════');

        if (scanData.sku != null) {
          // SKU found — go directly to detail page
          final scanId = await _saveScan(scanData);
          if (mounted) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ScanDetailPage(
                  scanId: scanId ?? '',
                  scanData: scanData,
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                ),
              ),
            );
          }
        } else {
          // No SKU — show dialog with option to enter manually or proceed without
          if (mounted) {
            _showManualSkuDialog(fullText, scanData);
          }
        }
      } finally {
        textRecognizer.close();
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to process image: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _scanBarcode(String ocrText, ScanData currentScanData) async {
    final gtin = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const _BarcodeScannerPage(),
      ),
    );

    if (!mounted) return;

    if (gtin != null) {
      debugPrint('═══ BARCODE SCAN ═══');
      debugPrint('GTIN found: $gtin');
      debugPrint('═══════════════════');

      final data = currentScanData.copyWith(gtin: gtin);
      final scanId = await _saveScan(data);
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ScanDetailPage(
              scanId: scanId ?? '',
              scanData: data,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        );
      }
    } else {
      // User cancelled or no barcode found — return to modal
      _showManualSkuDialog(ocrText, currentScanData);
    }
  }

  void _showManualSkuDialog(String ocrText, ScanData currentScanData) {
    final controller = TextEditingController();
    final hasModel = currentScanData.modelName != null;
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF333333), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ocrText.isEmpty ? 'Enter SKU' : 'No SKU Found',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ocrText.isEmpty
                    ? 'Type the SKU from the shoe label or box.'
                    : hasModel
                        ? 'We couldn\'t detect a SKU. Enter it manually or proceed without one.'
                        : 'We couldn\'t automatically detect a SKU. You can enter it manually.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[400]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: GoogleFonts.robotoMono(
                  fontSize: 16,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. DD1391-100',
                  hintStyle: GoogleFonts.robotoMono(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  filled: true,
                  fillColor: const Color(0xFF252525),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF646CFF),
                      width: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[400],
                        side: BorderSide(color: Colors.grey[600]!),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final sku = controller.text.trim().toUpperCase();
                        if (sku.isEmpty) return;
                        Navigator.of(dialogContext).pop();
                        final data = currentScanData.copyWith(sku: sku);
                        final scanId = await _saveScan(data);
                        if (mounted) {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ScanDetailPage(
                                scanId: scanId ?? '',
                                scanData: data,
                                timestamp:
                                    DateTime.now().millisecondsSinceEpoch,
                              ),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF646CFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Look Up'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _scanBarcode(ocrText, currentScanData);
                  },
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan Barcode'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey[600]!),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (hasModel) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      final scanId = await _saveScan(currentScanData);
                      if (mounted) {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ScanDetailPage(
                              scanId: scanId ?? '',
                              scanData: currentScanData,
                              timestamp:
                                  DateTime.now().millisecondsSinceEpoch,
                            ),
                          ),
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF646CFF),
                      side: const BorderSide(color: Color(0xFF646CFF)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Continue without SKU'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _saveScan(ScanData scanData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final scanRef = _database.child('scans').child(user.uid).push();
    await scanRef.set({
      ...scanData.toFirebase(),
      // Legacy fields for backward compatibility with history display
      'code': scanData.sku ?? scanData.displayName,
      'format': 'STYLE_CODE',
      'timestamp': ServerValue.timestamp,
      'productTitle': null,
      'productImage': null,
      'retailPrice': null,
      'ebayPrice': null,
      'stockxPrice': null,
      'goatPrice': null,
      'labelName': scanData.modelName,
    });

    return scanRef.key;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Sneaker Scanner',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Take a photo of a shoe label or box',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),

            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _previewController,
                      onDetect: (_) {},
                    ),
                    if (_isProcessing)
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(
                                color: Color(0xFF646CFF),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Reading label...',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _captureAndProcess,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Scan Label'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF646CFF),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(
                    0xFF646CFF,
                  ).withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _showManualSkuDialog('', const ScanData()),
                icon: const Icon(Icons.keyboard, size: 18),
                label: const Text('Enter SKU Manually'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF646CFF),
                  side: const BorderSide(color: Color(0xFF646CFF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen live barcode scanner that auto-detects barcodes.
/// Returns the normalized GTIN string via Navigator.pop, or null if cancelled.
class _BarcodeScannerPage extends StatefulWidget {
  const _BarcodeScannerPage();

  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _hasPopped = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasPopped) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        final normalized = normalizeGtin(raw);
        if (normalized.length >= 8) {
          _hasPopped = true;
          Navigator.of(context).pop(normalized);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'Scan Barcode',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Scan overlay
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF646CFF), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Instruction text
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Text(
              'Point camera at the barcode',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
