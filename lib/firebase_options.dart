// Firebase settings for project studyapp-28624-6558e.
// Android values come from android/app/google-services.json; web values from the
// "StudySync Web" app (Project settings → Your apps). They identify the project; not secrets.
// Access to data is controlled by Firebase Authentication + Firestore rules.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      _ => throw UnsupportedError('Firebase is only configured for Android.'),
    };
  }

  // Web app "StudySync Web" (Firebase console → Project settings → Your apps).
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDu7ZmRALSvdYenscyjWwucAw70U2U-EEs',
    appId: '1:81855985836:web:11c492bcacf11398d68709',
    messagingSenderId: '81855985836',
    projectId: 'studyapp-28624-6558e',
    authDomain: 'studyapp-28624-6558e.firebaseapp.com',
    storageBucket: 'studyapp-28624-6558e.firebasestorage.app',
    measurementId: 'G-CD3NJZKBRX',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDwFuL24Aj-ltJIHQkzZmsQXgGKR0938sM',
    appId: '1:81855985836:android:1158f3cd6c3d6038d68709',
    messagingSenderId: '81855985836',
    projectId: 'studyapp-28624-6558e',
    storageBucket: 'studyapp-28624-6558e.firebasestorage.app',
  );
}
