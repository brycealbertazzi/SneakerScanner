class ScanData {
  final String? brand;
  final String? sku;
  final String? gtin;
  final String? size;

  /// Raw normalized OCR text from the label scan. Not persisted to Firebase.
  final String? ocrText;

  /// User-entered title for title-based eBay search. Not persisted to Firebase.
  final String? titleSearch;

  const ScanData({
    this.brand,
    this.sku,
    this.gtin,
    this.size,
    this.ocrText,
    this.titleSearch,
  });

  bool get hasIdentifier => sku != null || gtin != null;

  String get displayName {
    if (brand != null && brand!.isNotEmpty) return brand!;
    return sku ?? '';
  }

  Map<String, dynamic> toFirebase() {
    return {
      if (brand != null) 'brand': brand,
      if (sku != null) 'sku': sku,
      if (gtin != null) 'gtin': gtin,
      if (size != null) 'size': size,
    };
  }

  factory ScanData.fromFirebase(Map<String, dynamic> data) {
    // Legacy support: old records use code/format/labelName
    final format = data['format'] as String?;
    final code = data['code'] as String?;
    final labelName = data['labelName'] as String?;

    if (data.containsKey('sku')) {
      // New format
      return ScanData(
        brand: data['brand'] as String?,
        sku: data['sku'] as String?,
        gtin: data['gtin'] as String?,
        size: data['size'] as String?,
      );
    }

    // Legacy mapping
    if (format == 'STYLE_CODE') {
      // For style code scans, code is the SKU (unless code == labelName,
      // meaning no real code was found)
      final hasRealCode = labelName == null || code != labelName;
      return ScanData(
        sku: hasRealCode ? code : null,
      );
    } else {
      // Legacy barcode format — treat as no SKU
      return ScanData();
    }
  }

  ScanData copyWith({
    String? brand,
    String? sku,
    String? gtin,
    String? size,
    String? ocrText,
    String? titleSearch,
  }) {
    return ScanData(
      brand: brand ?? this.brand,
      sku: sku ?? this.sku,
      gtin: gtin ?? this.gtin,
      size: size ?? this.size,
      ocrText: ocrText ?? this.ocrText,
      titleSearch: titleSearch ?? this.titleSearch,
    );
  }
}
