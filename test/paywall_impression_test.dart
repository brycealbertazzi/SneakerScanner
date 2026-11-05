import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import 'package:sneakscan/services/paywall_impression.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('purchases_flutter');
  final calls = <MethodCall>[];

  /// Stands in for the native SDK. [onCall] lets a test make it fail.
  void mockChannel({Object? Function(MethodCall)? onCall}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return onCall?.call(call);
        });
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('paywallIdFor', () {
    test('names the variant the user is actually looking at', () {
      expect(paywallIdFor(trialEligible: true), 'main_trial');
      expect(paywallIdFor(trialEligible: false), 'main_lapsed');
    });
  });

  group('trackPaywallImpression', () {
    test('reports the view to RevenueCat exactly once', () async {
      mockChannel();

      await trackPaywallImpression(paywallId: 'main_trial');

      expect(calls.map((c) => c.method), ['trackCustomPaywallImpression']);
      expect((calls.single.arguments as Map)['paywallId'], 'main_trial');
    });

    test('carries the offering id that ties a view to an experiment arm', () {
      // Built from RevenueCat's own model so the payload shape is the real one.
      const offering = rc.Offering(
        'price_test_b',
        'Price experiment, arm B',
        <String, Object>{},
        <rc.Package>[],
      );

      mockChannel();

      return trackPaywallImpression(
        paywallId: 'main_lapsed',
        offering: offering,
      ).then((_) {
        final args = calls.single.arguments as Map;
        expect(args['paywallId'], 'main_lapsed');
        expect(args['offeringId'], 'price_test_b');
      });
    });

    test('omits offering data when the session fell back', () async {
      mockChannel();

      await trackPaywallImpression(paywallId: 'main_trial');

      expect(
        (calls.single.arguments as Map).containsKey('offeringId'),
        isFalse,
      );
    });

    test(
      'swallows a failing channel rather than taking the paywall down',
      () async {
        mockChannel(onCall: (_) => throw PlatformException(code: 'RC_DOWN'));

        // The assertion is that this completes at all — analytics must never be
        // able to throw into the paywall's initState.
        await expectLater(
          trackPaywallImpression(paywallId: 'main_trial'),
          completes,
        );
      },
    );
  });
}
