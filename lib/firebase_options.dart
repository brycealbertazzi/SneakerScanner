import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB_mVa2_1X6PO3P7UmITA_-q_issze40Ss',
    appId: '1:773179554972:ios:99da421aee480d633e0159',
    messagingSenderId: '773179554972',
    projectId: 'sneaker-scanner-f77aa',
    storageBucket: 'sneaker-scanner-f77aa.firebasestorage.app',
    iosBundleId: 'com.BryceAlbertazzi.SneakerScanner',
    iosClientId: '773179554972-l9jtvpf5ri7md0a2pbqtqhaj7dr2muon.apps.googleusercontent.com',
    databaseURL: 'https://sneaker-scanner-f77aa-default-rtdb.firebaseio.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBE0yHmfuN5LvLtK1w-M0nBUnA2WaMy25U',
    appId: '1:773179554972:android:c0a1af11e94628663e0159',
    messagingSenderId: '773179554972',
    projectId: 'sneaker-scanner-f77aa',
    storageBucket: 'sneaker-scanner-f77aa.firebasestorage.app',
    databaseURL: 'https://sneaker-scanner-f77aa-default-rtdb.firebaseio.com',
  );
}
