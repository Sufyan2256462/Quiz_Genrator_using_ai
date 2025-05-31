import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAypP7a5ruCowouS20wjLKuSTqiksFi5E4',
    authDomain: 'firstproject-92080.firebaseapp.com',
    projectId: 'firstproject-92080',
    storageBucket: 'firstproject-92080.firebasestorage.app',
    messagingSenderId: '1077199970233',
    appId: '1:1077199970233:web:fb59b8734ddbe612196068',
    measurementId: 'G-72FTD8TMPD',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'firstproject-92080',
    storageBucket: 'firstproject-92080.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'firstproject-92080',
    storageBucket: 'firstproject-92080.firebasestorage.app',
    iosBundleId: 'YOUR_IOS_BUNDLE_ID',
    iosClientId: 'YOUR_IOS_CLIENT_ID',
    androidClientId: 'YOUR_ANDROID_CLIENT_ID',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: 'YOUR_MACOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'firstproject-92080',
    storageBucket: 'firstproject-92080.firebasestorage.app',
    iosBundleId: 'YOUR_MACOS_BUNDLE_ID',
    iosClientId: 'YOUR_MACOS_CLIENT_ID',
    androidClientId: 'YOUR_ANDROID_CLIENT_ID',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'YOUR_WINDOWS_API_KEY',
    appId: 'YOUR_WINDOWS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'firstproject-92080',
    storageBucket: 'firstproject-92080.firebasestorage.app',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'YOUR_LINUX_API_KEY',
    appId: 'YOUR_LINUX_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'firstproject-92080',
    storageBucket: 'firstproject-92080.firebasestorage.app',
  );
}
