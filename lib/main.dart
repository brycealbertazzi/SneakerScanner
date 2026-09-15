import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/gomarketme_service.dart';
import 'services/mixpanel_service.dart';
import 'services/review_access.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await MixpanelService.instance.initialize();
  // Affiliate attribution. Deliberately not awaited — it does a network round
  // trip and nothing on the launch path reads its result, so blocking here
  // would only stall the splash screen.
  unawaited(GoMarketMeService.instance.initialize());
  // Entitlement getters read this synchronously, so it has to be resolved
  // before the splash screen makes its first routing decision.
  await ReviewAccess.instance.load();
  runApp(const SneakerScannerApp());
}

class SneakerScannerApp extends StatelessWidget {
  const SneakerScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SneakScan',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorObservers: [routeObserver],
      home: const SplashScreen(),
    );
  }
}
