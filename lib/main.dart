import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SneakerScannerApp());
}

class SneakerScannerApp extends StatelessWidget {
  const SneakerScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sneaker Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF646CFF),
        scaffoldBackgroundColor: const Color(0xFF242424),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF646CFF),
          secondary: Color(0xFF535BF2),
        ),
      ),
      home: const ScannerPage(),
    );
  }
}

class ScanResult {
  final String code;
  final String format;
  final String timestamp;

  ScanResult({
    required this.code,
    required this.format,
    required this.timestamp,
  });
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _isScanning = false;
  ScanResult? _lastScan;
  final List<ScanResult> _scanHistory = [];
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _controller?.stop();
        break;
      case AppLifecycleState.resumed:
        if (_isScanning) {
          _controller?.start();
        }
        break;
      default:
        break;
    }
  }

  Future<void> _startScanning() async {
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      autoStart: true,
    );
    setState(() {
      _isScanning = true;
    });
  }

  Future<void> _stopScanning() async {
    await _controller?.stop();
    await _controller?.dispose();
    _controller = null;
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final scanResult = ScanResult(
          code: barcode.rawValue!,
          format: barcode.format.name.toUpperCase(),
          timestamp: TimeOfDay.now().format(context),
        );

        setState(() {
          _lastScan = scanResult;
          _scanHistory.insert(0, scanResult);
          if (_scanHistory.length > 10) {
            _scanHistory.removeLast();
          }
        });

        _stopScanning();
        break;
      }
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    setState(() {
      _copied = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Header
              const Text(
                'Sneaker Scanner',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Scan barcodes from sneaker boxes',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 24),

              // Scanner Area
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: _isScanning
                      ? Border.all(color: const Color(0xFF646CFF), width: 2)
                      : null,
                ),
                clipBehavior: Clip.hardEdge,
                child: _isScanning && _controller != null
                    ? MobileScanner(
                        controller: _controller!,
                        onDetect: _onDetect,
                      )
                    : Center(
                        child: Icon(
                          Icons.qr_code_scanner,
                          size: 64,
                          color: Colors.grey[600],
                        ),
                      ),
              ),
              const SizedBox(height: 16),

              // Scan Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isScanning ? _stopScanning : _startScanning,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isScanning
                        ? const Color(0xFFFF4444)
                        : const Color(0xFF646CFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _isScanning ? 'Stop Scanning' : 'Start Scanning',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Last Scan Result
              if (_lastScan != null) ...[
                const Text(
                  'Last Scan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _lastScan!.code,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: Color(0xFF646CFF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF333333),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _lastScan!.format,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _lastScan!.timestamp,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _copyToClipboard(_lastScan!.code),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF646CFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(_copied ? 'Copied!' : 'Copy'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Scan History
              if (_scanHistory.isNotEmpty) ...[
                const Text(
                  'Scan History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: _scanHistory.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final scan = _scanHistory[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                scan.code,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${scan.format} - ${scan.timestamp}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
