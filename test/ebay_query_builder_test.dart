import 'package:flutter_test/flutter_test.dart';
import 'package:sneakscan/services/ebay_query_builder.dart';

void main() {
  group('buildEbaySalesQuery', () {
    test('drops SKUs from the query', () {
      expect(
        buildEbaySalesQuery(
          ebayTitle:
              'NEW Nike Dunk Low Retro Panda Black White Sz 10 DD1391-100',
        ),
        'Nike Dunk Low Retro Panda Black White',
      );
      expect(
        buildEbaySalesQuery(
          ebayTitle: 'adidas Yeezy Boost 350 V2 HQ6316 Size 10',
        ),
        'adidas Yeezy Boost 350 V2',
      );
    });
    test('brand + model when no SKU', () {
      expect(
        buildEbaySalesQuery(
          ebayTitle:
              "Air Jordan 1 Retro High OG 'Chicago' Men's Size 10.5 Red/White",
        ),
        'Air Jordan 1 Retro High Red White',
      );
      expect(
        buildEbaySalesQuery(
          ebayTitle:
              'Skechers GOrun Arch Fit Shoes Mens Size 11.5 White Running Sneakers',
        ),
        'Skechers GOrun Arch Fit White',
      );
      expect(
        buildEbaySalesQuery(
          ebayTitle: 'Nike Air Force 1 Low Triple White (GS) Sz 6Y',
        ),
        'Nike Air Force 1 Low White',
      );
    });
    test('falls back to product title', () {
      expect(
        buildEbaySalesQuery(fallbackTitle: 'Hoka Clifton 9 Black White'),
        'Hoka Clifton 9 Black White',
      );
    });
  });

  test('colors take priority within 7 words', () {
    expect(
      buildEbaySalesQuery(
        ebayTitle:
            'Nike Air Max 90 Essential Premium Retro Black Red Grey Pink Sz 10',
      ),
      'Nike Air Max 90 Black Red Grey',
    );
  });

  group('parseUsSize', () {
    test('common formats', () {
      expect(
        parseUsSize('Skechers GOrun Arch Fit Mens Size 11.5 White'),
        '11.5',
      );
      expect(parseUsSize('Nike Dunk Low Panda Sz 10'), '10');
      expect(parseUsSize('Jordan 4 Retro US10 Black Cat'), '10');
      expect(parseUsSize('SKECHERS GORUN PURE 3 ARCH FIT SHOES~14M'), '14');
      expect(parseUsSize('Air Max 90 10.5M'), '10.5');
      expect(parseUsSize('Nike Dunk Low Panda DD1391-100'), isNull);
    });
  });
}
