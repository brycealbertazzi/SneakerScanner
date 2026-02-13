class ScanData {
  final String? brand;
  final String? modelName;
  final String? colorway;
  final String? sku;
  final String? gtin;

  const ScanData({
    this.brand,
    this.modelName,
    this.colorway,
    this.sku,
    this.gtin,
  });

  bool get hasIdentifier => sku != null || gtin != null;

  String get displayName {
    final parts = <String>[];
    if (brand != null && brand!.isNotEmpty) parts.add(brand!);
    if (modelName != null && modelName!.isNotEmpty) {
      // Avoid duplicating the brand in the display name
      if (brand == null ||
          !modelName!.toLowerCase().startsWith(brand!.toLowerCase())) {
        parts.add(modelName!);
      } else {
        parts.add(modelName!);
        parts.clear();
        parts.add(modelName!);
      }
    }
    if (colorway != null && colorway!.isNotEmpty) parts.add(colorway!);
    if (parts.isEmpty) return sku ?? gtin ?? '';
    return parts.join(' ');
  }

  Map<String, dynamic> toFirebase() {
    return {
      if (brand != null) 'brand': brand,
      if (modelName != null) 'modelName': modelName,
      if (colorway != null) 'colorway': colorway,
      if (sku != null) 'sku': sku,
      if (gtin != null) 'gtin': gtin,
    };
  }

  factory ScanData.fromFirebase(Map<String, dynamic> data) {
    // Legacy support: old records use code/format/labelName
    final format = data['format'] as String?;
    final code = data['code'] as String?;
    final labelName = data['labelName'] as String?;

    if (data.containsKey('sku') || data.containsKey('gtin') ||
        data.containsKey('modelName')) {
      // New format
      return ScanData(
        brand: data['brand'] as String?,
        modelName: data['modelName'] as String?,
        colorway: data['colorway'] as String?,
        sku: data['sku'] as String?,
        gtin: data['gtin'] as String?,
      );
    }

    // Legacy mapping
    if (format == 'STYLE_CODE') {
      // For style code scans, code is the SKU (unless code == labelName,
      // meaning no real code was found)
      final hasRealCode = labelName == null || code != labelName;
      return ScanData(
        sku: hasRealCode ? code : null,
        modelName: labelName,
      );
    } else {
      // Barcode format → gtin
      return ScanData(
        gtin: code,
      );
    }
  }

  ScanData copyWith({
    String? brand,
    String? modelName,
    String? colorway,
    String? sku,
    String? gtin,
  }) {
    return ScanData(
      brand: brand ?? this.brand,
      modelName: modelName ?? this.modelName,
      colorway: colorway ?? this.colorway,
      sku: sku ?? this.sku,
      gtin: gtin ?? this.gtin,
    );
  }
}
