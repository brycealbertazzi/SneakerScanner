import 'package:mixpanel_flutter/mixpanel_flutter.dart';

class MixpanelService {
  MixpanelService._();
  static MixpanelService instance = MixpanelService._();

  static const String _token = '33ba28d27c13be16b7a9e4d8f07ec26c';

  late Mixpanel _mixpanel;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _mixpanel = await Mixpanel.init(_token, trackAutomaticEvents: true);
    _initialized = true;
  }

  void identify(String userId, {String? email, String? name}) {
    if (!_initialized) return;
    _mixpanel.identify(userId);
    if (email != null) _mixpanel.getPeople().set('\$email', email);
    if (name != null) _mixpanel.getPeople().set('\$name', name);
  }

  void reset() {
    if (!_initialized) return;
    _mixpanel.reset();
  }

  /// Attaches [properties] to every subsequent event. Used for the price A/B
  /// variant so the whole paywall funnel stays sliceable by it. Cleared by
  /// [reset], which the sign-out path already calls.
  void registerSuperProperties(Map<String, dynamic> properties) {
    if (!_initialized) return;
    _mixpanel.registerSuperProperties(properties);
  }

  void track(String eventName, {Map<String, dynamic>? properties}) {
    if (!_initialized) return;
    _mixpanel.track(eventName, properties: properties);
  }
}
