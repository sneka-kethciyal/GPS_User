// File generated for ebt-expense-geo-tracker
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA8_ExampleWebKeyPlaceholder_EbT1',
    appId: '1:100000000001:web:ebt99expense01',
    messagingSenderId: '100000000001',
    projectId: 'ebt-expense-geo-tracker',
    authDomain: 'ebt-expense-geo-tracker.firebaseapp.com',
    storageBucket: 'ebt-expense-geo-tracker.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD9wLW4SviHATSpmV4h1_h-j9W11e81nwg',
    appId: '1:940424517330:android:34f60c5ddff6045d507f0b',
    messagingSenderId: '940424517330',
    projectId: 'ebt-expense-geo-tracker',
    storageBucket: 'ebt-expense-geo-tracker.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA8_ExampleIosKeyPlaceholder_EbT3',
    appId: '1:100000000001:ios:ebt99expense03',
    messagingSenderId: '100000000001',
    projectId: 'ebt-expense-geo-tracker',
    storageBucket: 'ebt-expense-geo-tracker.firebasestorage.app',
    iosBundleId: 'com.ebtfusion.expenseTracker',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyA8_ExampleIosKeyPlaceholder_EbT3',
    appId: '1:100000000001:ios:ebt99expense03',
    messagingSenderId: '100000000001',
    projectId: 'ebt-expense-geo-tracker',
    storageBucket: 'ebt-expense-geo-tracker.firebasestorage.app',
    iosBundleId: 'com.ebtfusion.expenseTracker',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyA8_ExampleWebKeyPlaceholder_EbT1',
    appId: '1:100000000001:web:ebt99expense01',
    messagingSenderId: '100000000001',
    projectId: 'ebt-expense-geo-tracker',
    authDomain: 'ebt-expense-geo-tracker.firebaseapp.com',
    storageBucket: 'ebt-expense-geo-tracker.firebasestorage.app',
  );
}
