import 'package:covoisino/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'frontend.dart';
import 'backend.dart';




void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final referralService = ReferralLinkService(navKey);
  runApp(
    ProviderScope(
      overrides: [
        referralLinkServiceProvider.overrideWithValue(referralService),
      ],
      child: MyApp()
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await referralService.init();
  });
}