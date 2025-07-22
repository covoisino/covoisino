import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
import 'backend.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'definitions.dart';








final setupPageStageProvider = StateNotifierProvider<SetupPageStageNotifier, int>(
  (ref) => SetupPageStageNotifier(),
);
final homePageTabProvider = StateProvider<int>((ref) => 0);
final optionsPageTabProvider = StateProvider<int>((ref) => 0);
final localeProvider = StateProvider<Locale?>((ref) => const Locale('en'));
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);


final homePageSponsorsCountValueProvider = StreamProvider.autoDispose<int>((ref) {
  int? last;
  return getSponsorsCountStream().distinct((prev, next) {
    final isSame = prev == next;
    if (!isSame) last = next;
    return isSame;
  });
});
final driverLocationOnValueProvider = StreamProvider.autoDispose<bool>((ref) {
  bool? last;
  return getDriverLocationOnStream().distinct((prev, next) {
    final isSame = prev == next;
    if (!isSame) last = next;
    return isSame;
  });
});
final stopUpdatingLocationInProgressProvider = StateProvider<bool>((ref) => false);
final driverLocationOnListenerProvider = StateProvider<ProviderSubscription?>((ref) => null);
final usersCollectionProvider =
    StateNotifierProvider<UsersCollectionNotifier, UserModel?>(
  (ref) => UsersCollectionNotifier(),
);
final sendSponsorshipRequestLoadingProvider = StateProvider<Map<String,bool>>((ref) => {});
final acceptSponsorshipRequestLoadingProvider = StateProvider<Map<String,bool>>((ref) => {});
final declineSponsorshipRequestLoadingProvider = StateProvider<Map<String,bool>>((ref) => {});
final sendRideRequestLoadingProvider = StateProvider<Map<String,bool>>((ref) => {});
final acceptRideRequestLoadingProvider = StateProvider<Map<String,bool>>((ref) => {});
final declineRideRequestLoadingProvider = StateProvider<Map<String,bool>>((ref) => {});

final navKey = GlobalKey<NavigatorState>();
final referralLinkServiceProvider = Provider<ReferralLinkService>((ref) {
  return ReferralLinkService(navKey);
});
final homePageGenerateLinkLoadingProvider = StateProvider<bool>((ref) => false);
final sponsorPageAcceptInviteLoadingProvider = StateProvider<bool>((ref) => false);
final hasRequestedLocationPermissionProvider = StateProvider<bool>((ref) => false);
final mapControllerProvider = Provider<MapController>((ref) {
  return MapController();
});
final popupControllerProvider = Provider<PopupController>((ref) {
  return PopupController();
});







final signupPageEmailProvider = Provider.autoDispose((ref) => TextEditingController());
final signupPagePasswordProvider = Provider.autoDispose((ref) => TextEditingController());
final loginPageEmailProvider = Provider.autoDispose((ref) => TextEditingController());
final loginPagePasswordProvider = Provider.autoDispose((ref) => TextEditingController());
final forgotPasswordPageEmailProvider = Provider.autoDispose((ref) => TextEditingController());






final signupLoadingProvider = StateProvider<bool>((ref) => false);
final loginLoadingProvider = StateProvider<bool>((ref) => false);
final googleSignupLoadingProvider = StateProvider<bool>((ref) => false);
final googleLoginLoadingProvider = StateProvider<bool>((ref) => false);
final passwordResetLoadingProvider = StateProvider<bool>((ref) => false);
final resendVerificationLoadingProvider = StateProvider<bool>((ref) => false);
final continueToSetupLoadingProvider = StateProvider<bool>((ref) => false);
final restartSignupLoadingProvider = StateProvider<bool>((ref) => false);
final addPasswordLoadingProvider = StateProvider<bool>((ref) => false);
final deleteAccountLoadingProvider = StateProvider<bool>((ref) => false);
final logoutLoadingProvider = StateProvider<bool>((ref) => false);






final stage0DriverProvider = StateProvider<String?>((ref) => null);
final stage1CarModelProvider = Provider.autoDispose((ref) => TextEditingController());
final stage2PhoneNumberProvider = Provider.autoDispose((ref) => TextEditingController());
final stage3SMSCodeProvider = Provider.autoDispose((ref) => TextEditingController());
final stage4FirstNameProvider = Provider.autoDispose((ref) => TextEditingController());
final stage4LastNameProvider = Provider.autoDispose((ref) => TextEditingController());


final stage0ContinueLoadingProvider = StateProvider<bool>((ref) => false);
final stage1ContinueLoadingProvider = StateProvider<bool>((ref) => false);
final stage2ContinueLoadingProvider = StateProvider<bool>((ref) => false);
final stage3ContinueLoadingProvider = StateProvider<bool>((ref) => false);
final stage4ContinueLoadingProvider = StateProvider<bool>((ref) => false);

final setupPageCameFromProvider = StateProvider<String>((ref) => "");










class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LifecycleWatcher().initialize(
        getAutoDriveModeOnValue: () {
          final usersCollection = ref.read(usersCollectionProvider);
          return usersCollection?.autoDriveModeOn ?? false;
        },
      );
    });

    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      navigatorKey: navKey,
      home: SignupPage(),
      routes: {
        '/sponsor': (context) => SponsorPage(),
      },
    );
  }
}

class LifecycleWatcher with WidgetsBindingObserver {
  static final LifecycleWatcher _instance = LifecycleWatcher._internal();

  factory LifecycleWatcher() => _instance;

  LifecycleWatcher._internal();

  late bool Function() getAutoDriveModeOnValue;

  void initialize({required bool Function() getAutoDriveModeOnValue}) {
    this.getAutoDriveModeOnValue = getAutoDriveModeOnValue;
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final autoDriveModeOn = getAutoDriveModeOnValue();
    switch (state) {
      case AppLifecycleState.resumed:
        if (autoDriveModeOn) updateDriverLocationOn(true);
        break;
      case AppLifecycleState.paused:
        if (autoDriveModeOn) updateDriverLocationOn(false);
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.detached:
        if (autoDriveModeOn) updateDriverLocationOn(false);
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }
}


class SignupPage extends ConsumerWidget {
  final _formKey = GlobalKey<FormState>();


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(signupPageEmailProvider);
    final password = ref.watch(signupPagePasswordProvider);
    final signupLoading = ref.watch(signupLoadingProvider);
    final googleSignupLoading = ref.watch(googleSignupLoadingProvider);
    final notifier = ref.read(usersCollectionProvider.notifier);


    return Scaffold(
      appBar: AppBar(
        title: Text('Signup'),
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: email,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Email",
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) return "Email cannot be empty";
                  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                  return emailRegex.hasMatch(value) ? null : "Email is invalid";
                },
              ),
              TextFormField(
                controller: password,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Password",
                ),
                obscureText: true,
                validator: (value) => value != null && value.length >= 6 ? null : "Password must be at least 6 characters",
              ),
              ElevatedButton(
                child: signupLoading ? CircularProgressIndicator() : Text("Signup"),
                onPressed: () async {
                  if (_formKey.currentState?.validate() == true) {
                    ref.read(signupLoadingProvider.notifier).state = true;
                    String status = await signup(email.text,password.text);
                    if (status == "") {
                      status = await sendVerificationEmail();
                      ref.read(signupLoadingProvider.notifier).state = false;
                      if (status == "") {
                        Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => VerifyAccountPage()));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                      }
                    } else {
                      ref.read(signupLoadingProvider.notifier).state = false;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                    }
                  }
                },
              ),
              ElevatedButton(
                child: googleSignupLoading ? CircularProgressIndicator() : Text("Continue with Google"),
                onPressed: () async {
                  ref.read(googleSignupLoadingProvider.notifier).state = true;
                  String status = await continueWithGoogle();
                  ref.read(googleSignupLoadingProvider.notifier).state = false;
                  if (status == "") {
                    await notifier.loadUsersCollection();
                    Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => HomePage()));
                  } else if (status == "SetupPage") {
                    ref.read(setupPageStageProvider.notifier).setStage(0);
                    Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => SetupPage()));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                  }
                },
              ),
              TextButton(
                child: Text("Go to login"),
                onPressed: () {
                  Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => LoginPage()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class LoginPage extends ConsumerWidget {
  final _formKey = GlobalKey<FormState>();
 
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(loginPageEmailProvider);
    final password = ref.watch(loginPagePasswordProvider);
    final loginLoading = ref.watch(loginLoadingProvider);
    final googleLoginLoading = ref.watch(googleLoginLoadingProvider);
    final notifier = ref.read(usersCollectionProvider.notifier);


    return Scaffold(
      appBar: AppBar(
        title: Text('Login'),
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: email,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Email",
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) return "Email cannot be empty";
                  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                  return emailRegex.hasMatch(value) ? null : "Email is invalid";
                },
              ),
              TextFormField(
                controller: password,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Password",
                ),
                obscureText: true,
                validator: (value) => value != null && value.length >= 6 ? null : "Password must be at least 6 characters",
              ),
              ElevatedButton(
                child: loginLoading ? CircularProgressIndicator() : Text("Login"),
                onPressed: () async {
                  if (_formKey.currentState?.validate() == true) {
                    ref.read(loginLoadingProvider.notifier).state = true;
                    String status = await login(email.text,password.text);
                    ref.read(loginLoadingProvider.notifier).state = false;
                    if (status == "") {
                      await notifier.loadUsersCollection();
                      final usersCollection = ref.read(usersCollectionProvider);
                      final autoDriveModeOn = usersCollection?.autoDriveModeOn ?? false;
                      if (autoDriveModeOn) updateDriverLocationOn(true);
                      Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => HomePage()));
                    } else if (status == "SetupPage") {
                      ref.read(setupPageStageProvider.notifier).setStage(0);
                      Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => SetupPage()));
                    } else if (status == "VerifyAccountPage") {
                      Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => VerifyAccountPage()));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                    }
                  }
                },
              ),
              ElevatedButton(
                child: googleLoginLoading ? CircularProgressIndicator() : Text("Continue with Google"),
                onPressed: () async {
                  ref.read(googleLoginLoadingProvider.notifier).state = true;
                  String status = await continueWithGoogle();
                  ref.read(googleLoginLoadingProvider.notifier).state = false;
                  if (status == "") {
                    await notifier.loadUsersCollection();
                    final usersCollection = ref.read(usersCollectionProvider);
                    final autoDriveModeOn = usersCollection?.autoDriveModeOn ?? false;
                    if (autoDriveModeOn) updateDriverLocationOn(true);
                    Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => HomePage()));
                  } else if (status == "SetupPage") {
                    ref.read(setupPageStageProvider.notifier).setStage(0);
                    Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => SetupPage()));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                  }
                },
              ),
              TextButton(
                child: Text("Forgot password"),
                onPressed: () {
                  Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => ForgotPasswordPage()));
                },
              ),
              TextButton(
                child: Text("Go to signup"),
                onPressed: () {
                  Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => SignupPage()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class ForgotPasswordPage extends ConsumerWidget {
  final _formKey = GlobalKey<FormState>();


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(forgotPasswordPageEmailProvider);
    final passwordResetLoading = ref.watch(passwordResetLoadingProvider);


    return Scaffold(
      appBar: AppBar(
        title: Text('Reset password'),
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: email,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Email",
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) return "Email cannot be empty";
                  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                  return emailRegex.hasMatch(value) ? null : "Email is invalid";
                },
              ),
              ElevatedButton(
                child: passwordResetLoading ? CircularProgressIndicator() : Text("Send password reset email"),
                onPressed: () async {
                  if (_formKey.currentState?.validate() == true) {
                    ref.read(passwordResetLoadingProvider.notifier).state = true;
                    String status = await sendPasswordResetEmail(email.text);
                    ref.read(passwordResetLoadingProvider.notifier).state = false;
                    if (status == "") {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Password reset email sent")));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                    }
                  }
                },
              ),
              TextButton(
                child: Text("Back to login"),
                onPressed: () {
                  Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => LoginPage()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class VerifyAccountPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resendVerificationLoading = ref.watch(resendVerificationLoadingProvider);
    final continueToSetupLoading = ref.watch(continueToSetupLoadingProvider);
    final restartSignupLoading = ref.watch(restartSignupLoadingProvider);


    return Scaffold(
      appBar: AppBar(
        title: Text('Verify account'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            TextButton(
              child: resendVerificationLoading ? CircularProgressIndicator() : Text("Resend verification email"),
              onPressed: () async {
                ref.read(resendVerificationLoadingProvider.notifier).state = true;
                String status = await sendVerificationEmail();
                ref.read(resendVerificationLoadingProvider.notifier).state = false;
                if (status == "") {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Verification email resent")));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                }
              },
            ),
            ElevatedButton(
              child: continueToSetupLoading ? CircularProgressIndicator() : Text("Continue to setup"),
              onPressed: () async {
                ref.read(continueToSetupLoadingProvider.notifier).state = true;
                String status = await continueToSetup();
                ref.read(continueToSetupLoadingProvider.notifier).state = false;
                if (status == "") {
                  ref.read(setupPageStageProvider.notifier).setStage(0);
                  Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => SetupPage()));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                }
              },
            ),
            TextButton(
              child: restartSignupLoading ? CircularProgressIndicator() : Text("Restart signup"),
              onPressed: () async {
                ref.read(restartSignupLoadingProvider.notifier).state = true;
                String status = await deleteAccount();
                ref.read(restartSignupLoadingProvider.notifier).state = false;
                if (status == "") {
                  Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => SignupPage()));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                }
              },
            ),
            TextButton(
              child: Text("Back to login"),
              onPressed: () {
                Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => LoginPage()));
              },
            ),
          ],
        ),
      ),
    );
  }
}


class SetupPage extends ConsumerWidget {
  final _formKey2 = GlobalKey<FormState>();
  final _formKey3 = GlobalKey<FormState>();


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(setupPageStageProvider);
    final setupNotifier = ref.read(setupPageStageProvider.notifier);
    final driver = ref.watch(stage0DriverProvider);
    final usersCollection = ref.watch(usersCollectionProvider);
    final notifier = ref.read(usersCollectionProvider.notifier);

    Widget content;
    switch (stage) {
      case 0:
        final stage0ContinueLoading = ref.watch(stage0ContinueLoadingProvider);


        content = Column(
          children: [
            Text("Do you want to become a driver?"),
            RadioListTile(
              title: Text("Yes"),
              value: "Yes",
              groupValue: driver,
              onChanged: (value) {
                ref.read(stage0DriverProvider.notifier).state = value;
              },
            ),
            RadioListTile(
              title: Text("No"),
              value: "No",
              groupValue: driver,
              onChanged: (value) {
                ref.read(stage0DriverProvider.notifier).state = value;
              },
            ),
            ElevatedButton(
              child: stage0ContinueLoading ? CircularProgressIndicator() : Text("Continue"),
              onPressed: () async {
                if (driver == null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Please select Yes or No")));
                  return;
                }
                ref.read(stage0ContinueLoadingProvider.notifier).state = true;
                String status = await writeToUsersCollection({'driver':driver=="Yes"});
                ref.read(stage0ContinueLoadingProvider.notifier).state = false;
                if (status == "") {
                  notifier.updateDriver(driver=="Yes");
                  setupNotifier.setStage(driver=="Yes"?1:2);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                }
              },
            ),
          ],
        );
        break;
      case 1:
        final carModel = ref.watch(stage1CarModelProvider);
        final stage1ContinueLoading = ref.watch(stage1ContinueLoadingProvider);


        content = Column(
          children: [
            Text("Select your car model"),
            TextField(
              controller: carModel,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Car model",
              ),
            ),
            ElevatedButton(
              child: stage1ContinueLoading ? CircularProgressIndicator() : Text("Continue"),
              onPressed: () async {
                ref.read(stage1ContinueLoadingProvider.notifier).state = true;
                String status = await writeToUsersCollection({'carModel':carModel.text});
                ref.read(stage1ContinueLoadingProvider.notifier).state = false;
                if (status == "") {
                  notifier.updateCarModel(carModel.text);
                  final phoneNumber = getPhoneNumber() ?? "";
                  if (phoneNumber.trim().isEmpty) {
                    setupNotifier.setStage(2);
                  } else {
                    await notifier.loadUsersCollection();
                    Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => HomePage()));
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                }
              },
            ),
          ],
        );
        break;
      case 2:
        final phoneNumber = ref.watch(stage2PhoneNumberProvider);
        final stage2ContinueLoading = ref.watch(stage2ContinueLoadingProvider);


        content = Form(
          key: _formKey2,
          child: Column(
            children: [
              Text("Add your phone number"),
              TextFormField(
                controller: phoneNumber,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Phone number",
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) return "Phone number cannot be empty";
                  return null;
                },
              ),
              ElevatedButton(
                child: stage2ContinueLoading ? CircularProgressIndicator() : Text("Verify phone number"),
                onPressed: () async {
                  if (_formKey2.currentState?.validate() == true) {
                    ref.read(stage2ContinueLoadingProvider.notifier).state = true;
                    String status = await verifyPhoneNumber(phoneNumber.text);
                    ref.read(stage2ContinueLoadingProvider.notifier).state = false;
                    if (status == "") {
                      setupNotifier.setStage(3);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                    }
                  }
                },
              ),
              driver == "Yes" ? SizedBox.shrink() : TextButton(
                child: Text("Skip"),
                onPressed: () async {
                  final setupPageCameFrom = ref.read(setupPageCameFromProvider);
                  if (["driver","phoneNumber"].contains(setupPageCameFrom)) {
                    ref.read(setupPageCameFromProvider.notifier).state = "";
                    await notifier.loadUsersCollection();
                    Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => HomePage()));
                    if (setupPageCameFrom == "phoneNumber") {
                      Future.microtask(() {
                        Navigator.push(context,MaterialPageRoute(builder: (context) => OptionsPage()));
                      });
                    }
                  } else {
                    setupNotifier.setStage(4);
                  }
                },
              ),
            ],
          ),
        );
        break;
      case 3:
        final phoneNumber = ref.read(stage2PhoneNumberProvider);
        final smsCode = ref.watch(stage3SMSCodeProvider);
        final stage3ContinueLoading = ref.watch(stage3ContinueLoadingProvider);


        content = Form(
          key: _formKey3,
          child: Column(
            children: [
              Text("Verify your phone number"),
              TextFormField(
                controller: smsCode,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "SMS Code",
                ),
                validator: (value) => null,
              ),
              ElevatedButton(
                child: stage3ContinueLoading ? CircularProgressIndicator() : Text("Continue"),
                onPressed: () async {
                  if (_formKey3.currentState?.validate() == true) {
                    ref.read(stage3ContinueLoadingProvider.notifier).state = true;
                    String status = await verifySMSCode(smsCode.text);
                    ref.read(stage3ContinueLoadingProvider.notifier).state = false;
                    if (status == "") {
                      final setupPageCameFrom = ref.read(setupPageCameFromProvider);
                      if (ref.read(stage0DriverProvider.notifier).state == "Yes") await updateDriverLocationOn(false);
                      if (["driver","phoneNumber"].contains(setupPageCameFrom)) {
                        ref.read(setupPageCameFromProvider.notifier).state = "";
                        await notifier.loadUsersCollection();
                        Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => HomePage()));
                        if (setupPageCameFrom == "phoneNumber") {
                          Future.microtask(() {
                            Navigator.push(context,MaterialPageRoute(builder: (context) => OptionsPage()));
                          });
                        }
                      } else {
                        setupNotifier.setStage(4);
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                    }
                  }
                },
              ),
            ],
          ),
        );
        break;
      case 4:
        final firstName = ref.watch(stage4FirstNameProvider);
        final lastName = ref.watch(stage4LastNameProvider);
        final stage4ContinueLoading = ref.watch(stage4ContinueLoadingProvider);


        content = Column(
          children: [
            Text("Add your personal information"),
            TextField(
              controller: firstName,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: "First name",
              ),
            ),
            TextField(
              controller: lastName,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Last name",
              ),
            ),
            ElevatedButton(
              child: stage4ContinueLoading ? CircularProgressIndicator() : Text("Finish setup"),
              onPressed: () async {
                ref.read(stage4ContinueLoadingProvider.notifier).state = true;
                String status = await writeToUsersCollection({'firstName':firstName.text,'lastName':lastName.text});
                if (status == "") {
                  status = await writeToUsersCollection({'completedSetup':true});
                  ref.read(stage4ContinueLoadingProvider.notifier).state = false;
                  if (status == "") {
                    await notifier.loadUsersCollection();
                    Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => HomePage()));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                  }
                } else {
                  ref.read(stage4ContinueLoadingProvider.notifier).state = false;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                }
              },
            ),
          ],
        );
        break;
      default:
        content = SizedBox.shrink();
    }


    return Scaffold(
      appBar: AppBar(
        title: Text('Setup - Stage ${stage+1}'),
        leading: [
          null,
          IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {setupNotifier.setStage(0);},
          ),
          ref.read(setupPageCameFromProvider) == "phoneNumber" ? null : IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {setupNotifier.setStage(driver=="Yes"?1:0);},
          ),
          IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {setupNotifier.setStage(2);},
          ),
          IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {setupNotifier.setStage(2);},
          ),
        ][stage],
      ),
      body: SingleChildScrollView(child: content),
    );
  }
}










class HomePage extends ConsumerWidget {
  final locationUpdater = LocationUpdater();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homePageTabProvider);


    final tabs = [
      buildHomeTab(context, ref),
      buildRideTab(context, ref),
      buildDriveTab(context, ref),
    ];

    final sponsorsCountValue = ref.watch(homePageSponsorsCountValueProvider);

    ProviderSubscription subscription = ref.listenManual(driverLocationOnValueProvider, (previous, next) async {
      final driverLocationOn = next.value ?? false;

      if (driverLocationOn) {
        final hasRun = ref.read(hasRequestedLocationPermissionProvider);
        if (!hasRun) {
          ref.read(hasRequestedLocationPermissionProvider.notifier).state = true;
          await checkAndRequestLocationPermission();
        }

        if (!locationUpdater.isRunning) {
          locationUpdater.startUpdatingLocation();
        }
      } else {
        try {
          await locationUpdater.stopUpdatingLocation();
          ref.read(stopUpdatingLocationInProgressProvider.notifier).state = false;
        } catch (e) {
          print("STOP UPDATING LOCATION ERROR: $e");
        }
      }
    });

    return sponsorsCountValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (sponsorsCount) {
        if (sponsorsCount >= 2) {
          return Scaffold(
            appBar: AppBar(
              title: [Text("Home"),Text("Ride"),Text("Drive")][tab],
              actions: [
                IconButton(
                  icon: Icon(Icons.menu),
                  onPressed: () {
                    Navigator.push(context,MaterialPageRoute(builder: (context) => OptionsPage()));
                  },
                ),
              ],
            ),
            body: tabs[tab],
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: tab,
              onTap: (index) => ref.read(homePageTabProvider.notifier).state = index,
              items: [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Ride'),
                BottomNavigationBarItem(icon: Icon(Icons.directions_car_filled), label: 'Drive'),
              ],
            ),
          );
        }


        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                icon: Icon(Icons.menu),
                onPressed: () {
                  Navigator.push(context,MaterialPageRoute(builder: (context) => OptionsPage()));
                },
              ),
            ],
          ),
          body: buildUnsponsoredPage(ref, sponsorsCount),
        );
      },
    );
  }

  Widget buildHomeTab(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              ref.read(homePageGenerateLinkLoadingProvider.notifier).state = true;
              final link = await generateSponsorshipInviteLink();
              await Clipboard.setData(ClipboardData(text: link));
              ref.read(homePageGenerateLinkLoadingProvider.notifier).state = false;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('One-time link copied! Expires in 24 hours')),
              );
            },
            child: Consumer(
              builder: (context, ref, _) {
                final generateLinkLoading = ref.watch(homePageGenerateLinkLoadingProvider);
                return generateLinkLoading ? CircularProgressIndicator() : Text('Generate sponsorship invite link');
              }
            )
          ),
          Consumer(
            builder: (context, ref, _) {
              final usersCollection = ref.watch(usersCollectionProvider);
              final firstName = usersCollection?.firstName;
              final lastName = usersCollection?.lastName;
              final sponsorshipVisibility = usersCollection?.sponsorshipVisibility;
      
      
              return DropdownButton<bool>(
                value: sponsorshipVisibility,
                onChanged: (newValue) async {
                  if (newValue == null) return;
                  if (newValue == true && firstName!.trim().isEmpty && lastName!.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Please add a first or last name first")));
                    return;
                  }
                  final notifier = ref.read(usersCollectionProvider.notifier);
                  String status = await writeToUsersCollection({'sponsorshipVisibility': newValue});
                  if (status == "") {
                    notifier.updateSponsorshipVisibility(newValue);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                  }
                },
                items: const [
                  DropdownMenuItem(value: true, child: Text('Visible')),
                  DropdownMenuItem(value: false, child: Text('Hidden')),
                ],
                style: Theme.of(context).textTheme.bodyMedium,
              );
            }
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(homePageTabProvider.notifier).state = 1;
            },
            child: Text('I want to ride'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(homePageTabProvider.notifier).state = 2;
            },
            child: Text('I want to drive'),
          ),
          Text("Incoming sponsorship requests:"),
          StreamBuilder(
            stream: getSponsorshipRequestsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
      
      
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
      
      
              final sponsorshipRequests = snapshot.data!;
      
      
              return SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: sponsorshipRequests.length,
                  itemBuilder: (context, index) {
                    final sponsorshipRequest = sponsorshipRequests[index];
                    String? fullName = sponsorshipRequest['fromFullName'];
                    if (fullName!.trim().isEmpty) {
                      fullName = "Anonymous User";
                    }
             
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(fullName),
                        ElevatedButton(
                          onPressed: () async {
                            ref.read(acceptSponsorshipRequestLoadingProvider.notifier).update((state) {
                              return {...state, sponsorshipRequest['id']!: true};
                            });
                            String status = await updateSponsorshipRequestStatus(sponsorshipRequest['id']!,"accepted");
                            ref.read(acceptSponsorshipRequestLoadingProvider.notifier).update((state) {
                              return {...state, sponsorshipRequest['id']!: false};
                            });
                            if (status == "") {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sponsorship request accepted!")));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                            }
                          },
                          child: Consumer(
                            builder: (context, ref, _) {
                              final updateRequestLoading = ref.watch(acceptSponsorshipRequestLoadingProvider);
                              return updateRequestLoading[sponsorshipRequest['id']] == true ? CircularProgressIndicator() : Text('Accept');
                            }
                          )
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            ref.read(declineSponsorshipRequestLoadingProvider.notifier).update((state) {
                              return {...state, sponsorshipRequest['id']!: true};
                            });
                            String status = await updateSponsorshipRequestStatus(sponsorshipRequest['id']!,"declined");
                            ref.read(declineSponsorshipRequestLoadingProvider.notifier).update((state) {
                              return {...state, sponsorshipRequest['id']!: false};
                            });
                            if (status == "") {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sponsorship request declined")));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                            }
                          },
                          child: Consumer(
                            builder: (context, ref, _) {
                              final updateRequestLoading = ref.watch(declineSponsorshipRequestLoadingProvider);
                              return updateRequestLoading[sponsorshipRequest['id']] == true ? CircularProgressIndicator() : Text('Decline');
                            }
                          )
                        ),
                      ],
                    );
                  }
                ),
              );
            }
          ),
        ],
      ),
    );
  }


  Widget buildRideTab(BuildContext context, WidgetRef ref) {
    final mapController = ref.watch(mapControllerProvider);
    final popupController = ref.watch(popupControllerProvider);

    return Stack(
      children: [
        StreamBuilder(
          stream: getDriverMarkerInformationsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final driverMarkerInformations = snapshot.data ?? {};

            final driverMarkers = <Marker>[];
            for (final entry in driverMarkerInformations.entries) {
              final userId = entry.key;
              final driverMarkerInformation = entry.value;
              final ll = LatLng(driverMarkerInformation.latitude, driverMarkerInformation.longitude);

              late final Marker marker;
              marker = Marker(
                point: ll,
                width: 30,
                height: 30,
                key: ValueKey(userId),
                child: GestureDetector(
                  onTap: () => popupController.togglePopup(marker),
                  child: Icon(
                    Icons.directions_car_filled,
                    size: 40,
                    color: driverMarkerInformation.isYou ? Colors.blue : Colors.red,
                  ),
                ),
              );

              driverMarkers.add(marker);
            }

            return FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: LatLng(41.8781, -87.6298),
                initialZoom: 13.0,
                onTap: (_, __) => popupController.hideAllPopups(),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.covoisino',
                ),
                MarkerLayer(markers: driverMarkers),
                PopupMarkerLayerWidget(
                  options: PopupMarkerLayerOptions(
                    markers: driverMarkers,
                    popupController: popupController,
                    popupDisplayOptions: PopupDisplayOptions(
                      builder: (BuildContext context, Marker marker) {
                        final userId = (marker.key as ValueKey<String>).value;
                        final driverMarkerInformation = driverMarkerInformations[userId];
                        final isYou = driverMarkerInformation?.isYou;
                        final carModel = driverMarkerInformation?.carModel;
                        final phoneNumber = driverMarkerInformation?.phoneNumber;
                        final firstName = driverMarkerInformation?.firstName;
                        final lastName = driverMarkerInformation?.lastName;
                        return ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 200),
                          child: isYou ?? false ? Text("(You)") : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("$firstName $lastName"),
                              Text("Car Model: $carModel"),
                              Text("Phone Number: $phoneNumber"),
                              ElevatedButton(
                                onPressed: () async {
                                  ref.read(sendRideRequestLoadingProvider.notifier).update((state) {
                                    return {...state, userId: true};
                                  });
                                  String status = await sendRideRequest(userId);
                                  ref.read(sendRideRequestLoadingProvider.notifier).update((state) {
                                    return {...state, userId: false};
                                  });
                                  if (status == "") {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ride request sent")));
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                                  }
                                },
                                child: Consumer(
                                  builder: (context, ref, _) {
                                    final sendRequestLoading = ref.watch(sendRideRequestLoadingProvider);
                                    return sendRequestLoading[userId] == true ? CircularProgressIndicator() : Text('Send ride request');
                                  }
                                )
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        Positioned(
          child: Column(
            children: [
              ElevatedButton(
                onPressed: () {
                  scanQRCode();
                },
                child: Text('Scan QR Code'),
              ),
              ElevatedButton(
                onPressed: () {
                  makeEmergencyCall();
                },
                child: Text('Emergency Call'),
              ),
              ElevatedButton(
                onPressed: () {
                  shareLocation();
                },
                child: Text('Share location'),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget buildDriveTab(BuildContext context, WidgetRef ref) {
    final usersCollection = ref.read(usersCollectionProvider);
    final driver = usersCollection?.driver;

    final driverLocationOnValue = ref.watch(driverLocationOnValueProvider);

    if (driver ?? false) {
      return SingleChildScrollView(
        child: Column(
          children: [
            driverLocationOnValue.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (driverLocationOn) {
                return Consumer(
                  builder: (context, ref, _) {
                    final usersCollection = ref.watch(usersCollectionProvider);
                    final autoDriveModeOn = usersCollection?.autoDriveModeOn;                  
        
                    return DropdownButton<bool>(
                      value: driverLocationOn,
                      onChanged: autoDriveModeOn ?? false ? null : (newValue) async {
                        if (newValue == null) return;
                        String status = await updateDriverLocationOn(newValue);
                        if (status != "") {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                        }
                      },
                      items: const [
                        DropdownMenuItem(value: true, child: Text('Driver location is on')),
                        DropdownMenuItem(value: false, child: Text('Driver location is off')),
                      ],
                      style: Theme.of(context).textTheme.bodyMedium,
                    );
                  }
                );
              }
            ),
            Consumer(
              builder: (context, ref, _) {
                final usersCollection = ref.watch(usersCollectionProvider);
                final autoDriveModeOn = usersCollection?.autoDriveModeOn;
        
        
                return DropdownButton<bool>(
                  value: autoDriveModeOn,
                  onChanged: (newValue) async {
                    if (newValue == null) return;
                    final notifier = ref.read(usersCollectionProvider.notifier);
                    String status = await writeToUsersCollection({'autoDriveModeOn': newValue});
                    if (status == "") {
                      notifier.updateAutoDriveModeOn(newValue);
                      if (newValue == true) {
                        updateDriverLocationOn(true);
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Automatic drive mode is on')),
                    DropdownMenuItem(value: false, child: Text('Automatic drive mode is off')),
                  ],
                  style: Theme.of(context).textTheme.bodyMedium,
                );
              }
            ),
            ElevatedButton(
              onPressed: () {
                createQRCode();
              },
              child: Text('Create QR Code'),
            ),
            StreamBuilder(
              stream: getRideRequestsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
        
        
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
        
        
                final rideRequests = snapshot.data!;
        
        
                return SizedBox(
                  height: 200,
                  child: ListView.builder(
                    itemCount: rideRequests.length,
                    itemBuilder: (context, index) {
                      final rideRequest = rideRequests[index];
                      String? fullName = rideRequest['fromFullName'];
                      if (fullName!.trim().isEmpty) {
                        fullName = "Anonymous User";
                      }
              
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(fullName),
                          ElevatedButton(
                            onPressed: () async {
                              ref.read(acceptRideRequestLoadingProvider.notifier).update((state) {
                                return {...state, rideRequest['id']!: true};
                              });
                              String status = await updateRideRequestStatus(rideRequest['id']!,"accepted");
                              ref.read(acceptRideRequestLoadingProvider.notifier).update((state) {
                                return {...state, rideRequest['id']!: false};
                              });
                              if (status == "") {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ride request accepted!")));
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                              }
                            },
                            child: Consumer(
                              builder: (context, ref, _) {
                                final updateRequestLoading = ref.watch(acceptRideRequestLoadingProvider);
                                return updateRequestLoading[rideRequest['id']] == true ? CircularProgressIndicator() : Text('Accept');
                              }
                            )
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              ref.read(declineRideRequestLoadingProvider.notifier).update((state) {
                                return {...state, rideRequest['id']!: true};
                              });
                              String status = await updateRideRequestStatus(rideRequest['id']!,"declined");
                              ref.read(declineRideRequestLoadingProvider.notifier).update((state) {
                                return {...state, rideRequest['id']!: false};
                              });
                              if (status == "") {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ride request declined")));
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                              }
                            },
                            child: Consumer(
                              builder: (context, ref, _) {
                                final updateRequestLoading = ref.watch(declineRideRequestLoadingProvider);
                                return updateRequestLoading[rideRequest['id']] == true ? CircularProgressIndicator() : Text('Decline');
                              }
                            )
                          ),
                        ],
                      );
                    }
                  ),
                );
              }
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        ElevatedButton(
          child: Text("Become a driver"),
          onPressed: () {
            ref.read(setupPageCameFromProvider.notifier).state = "driver";
            ref.read(setupPageStageProvider.notifier).setStage(0);
            Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => SetupPage()));
          },
        ),
      ],
    );
  }


  Widget buildUnsponsoredPage(WidgetRef ref, sponsorsCount) {
    return Column(
      children: [
        Text("Visible sponsors:"),
        StreamBuilder(
          stream: getVisibleSponsorsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }


            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }


            final visibleSponsors = snapshot.data!;


            return SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: visibleSponsors.length,
                itemBuilder: (context, index) {
                  final sponsor = visibleSponsors[index];
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(sponsor['name']!),
                      ElevatedButton(
                        onPressed: () async {
                          ref.read(sendSponsorshipRequestLoadingProvider.notifier).update((state) {
                            return {...state, sponsor['uid']!: true};
                          });
                          String status = await sendSponsorshipRequest(sponsor['uid']!);
                          ref.read(sendSponsorshipRequestLoadingProvider.notifier).update((state) {
                            return {...state, sponsor['uid']!: false};
                          });
                          if (status == "") {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sponsorship request sent")));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                          }
                        },
                        child: Consumer(
                          builder: (context, ref, _) {
                            final sendRequestLoading = ref.watch(sendSponsorshipRequestLoadingProvider);
                            return sendRequestLoading[sponsor['uid']] == true ? CircularProgressIndicator() : Text('Send request');
                          }
                        )
                      ),
                    ],
                  );
                }
              ),
            );
          }
        ),
        Text("Sponsors count: ${sponsorsCount}/2"),
        Text("Sponsorship history:"),
        FutureBuilder(
          future: getSponsorshipHistory(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return const Center(child: Text("No history found"));
            }


            final sponsorshipHistory = snapshot.data!;
            return SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: sponsorshipHistory.length,
                itemBuilder: (context, index) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(sponsorshipHistory[index]),
                    ],
                  );
                }
              ),
            );
          }
        ),
      ],
    );
  }
}


class OptionsPage extends ConsumerWidget {
Future<void> waitForDriverLocationToStop(WidgetRef ref) async {
  final completer = Completer<void>();

  final sub = ref.listenManual<bool>(
    stopUpdatingLocationInProgressProvider,
    (prev, next) {
      if (next == false && !completer.isCompleted) {
        completer.complete();
      }
    },
  );

  Future.delayed(Duration(seconds: 10)).then((_) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });

  await completer.future;
  sub.close();
}

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(optionsPageTabProvider);


    final tabs = [
      buildProfileTab(context, ref),
      buildSettingsTab(context, ref),
      buildAccountTab(context, ref),
    ];


    return Scaffold(
      appBar: AppBar(
        title: Text('Options'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: tab,
            onDestinationSelected: (index) => ref.read(optionsPageTabProvider.notifier).state = index,
            labelType: NavigationRailLabelType.all,
            destinations: [
              NavigationRailDestination(
                icon: Icon(Icons.person),
                label: Text("Profile"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text("Settings"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.account_circle),
                label: Text("Account"),
              ),
            ],
          ),
          VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: tabs[tab],
          )
        ],
      )
    );
  }


  Widget buildProfileTab(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        Consumer(
          builder: (context, ref, _) {
            final usersCollection = ref.watch(usersCollectionProvider);
            final notifier = ref.read(usersCollectionProvider.notifier);
            final firstName = usersCollection!.firstName;
            final lastName = usersCollection!.lastName;
            final sponsorshipVisibility = usersCollection!.sponsorshipVisibility;

            return _buildEditableField(
              context: context,
              label: 'First Name',
              value: firstName,
              onSave: (newValue) async {
                if (sponsorshipVisibility == true && newValue.trim().isEmpty && lastName.trim().isEmpty) return;
                String status = await writeToUsersCollection({'firstName': newValue});
                if (status == "") {
                  notifier.updateFirstName(newValue);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                }
              }
            );
          }
        ),
        Consumer(
          builder: (context, ref, _) {
            final usersCollection = ref.watch(usersCollectionProvider);
            final notifier = ref.read(usersCollectionProvider.notifier);
            final firstName = usersCollection!.firstName;
            final lastName = usersCollection!.lastName;
            final sponsorshipVisibility = usersCollection!.sponsorshipVisibility;

            return _buildEditableField(
              context: context,
              label: 'Last Name',
              value: lastName,
              onSave: (newValue) async {
                if (sponsorshipVisibility == true && firstName.trim().isEmpty && newValue.trim().isEmpty) return;
                String status = await writeToUsersCollection({'lastName': newValue});
                if (status == "") {
                  notifier.updateFirstName(newValue);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                }
              }
            );
          }
        ),
        Consumer(
          builder: (context, ref, _) {
            final usersCollection = ref.watch(usersCollectionProvider);
            final notifier = ref.read(usersCollectionProvider.notifier);
            final driver = usersCollection?.driver;
            final carModel = usersCollection!.carModel;

            return driver ?? false ? _buildEditableField(
              context: context,
              label: 'Car Model',
              value: carModel,
              onSave: (newValue) async {
                String status = await writeToUsersCollection({'carModel': newValue});
                if (status == "") {
                  notifier.updateCarModel(newValue);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
                }
              }
            ) : Scaffold();
          }
        ),
        Consumer(
          builder: (context, ref, _) {
            final phoneNumber = getPhoneNumber();
            return Text("Phone number: $phoneNumber");
          }
        ),
        ElevatedButton(
          child: Text("Add/change phone number"),
          onPressed: () {
            ref.read(setupPageCameFromProvider.notifier).state = "phoneNumber";
            ref.read(setupPageStageProvider.notifier).setStage(2);
            Navigator.pop(context);
            Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => SetupPage()));
          },
        ),
      ]
    );
  }


  Widget buildSettingsTab(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        Text("Turn on/off dark mode:"),
        Consumer(
          builder: (context, ref, _) {
            final currentThemeMode = ref.read(themeModeProvider);

            return Switch(
              value: currentThemeMode == ThemeMode.dark,
              onChanged: (newValue) {
                if (newValue) {
                  ref.read(themeModeProvider.notifier).state = ThemeMode.dark;
                } else {
                  ref.read(themeModeProvider.notifier).state = ThemeMode.light;
                }
              },
            );
          }
        ),
        Text("Change language"),
        Consumer(
          builder: (context, ref, _) {
            final currentLocale = ref.read(localeProvider);

            return DropdownButton<Locale>(
              value: currentLocale,
              onChanged: (newValue) async {
                if (newValue == null) return;
                ref.read(localeProvider.notifier).state = newValue;
              },
              items: const [
                DropdownMenuItem(value: Locale('en'), child: Text('English')),
                DropdownMenuItem(value: Locale('fr'), child: Text('French')),
              ],
              style: Theme.of(context).textTheme.bodyMedium,
            );
          }
        ),
      ],
    );
  }


  Widget buildAccountTab(BuildContext context, WidgetRef ref) {
    final addPasswordLoading = ref.watch(addPasswordLoadingProvider);
    final deleteAccountLoading = ref.watch(deleteAccountLoadingProvider);
    final logoutLoading = ref.watch(logoutLoadingProvider);


    return ListView(
      children: [
        ElevatedButton(
          child: logoutLoading ? CircularProgressIndicator() : Text("Logout"),
          onPressed: () async {
            if (logoutLoading) return;
            ref.read(logoutLoadingProvider.notifier).state = true;
            final usersCollection = ref.read(usersCollectionProvider);
            final autoDriveModeOn = usersCollection?.autoDriveModeOn ?? false;
            if (autoDriveModeOn) {
              ref.read(stopUpdatingLocationInProgressProvider.notifier).state = true;
              updateDriverLocationOn(false);
              await waitForDriverLocationToStop(ref);
              ref.read(stopUpdatingLocationInProgressProvider.notifier).state = false;
            }
            ref.read(logoutLoadingProvider.notifier).state = false;
            ref.read(driverLocationOnListenerProvider.notifier).state?.close();
            ref.read(driverLocationOnListenerProvider.notifier).state = null;
            Navigator.pop(context);
            Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => LoginPage()));
            await Future.delayed(Duration(milliseconds: 500));
            String status = logout();
            if (status != "") {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
            }
          },
        ),
        TextButton(
          child: addPasswordLoading ? CircularProgressIndicator() : Text("Add or change password"),
          onPressed: () async {
            ref.read(addPasswordLoadingProvider.notifier).state = true;
            String status = await addOrChangePassword();
            ref.read(addPasswordLoadingProvider.notifier).state = false;
            if (status == "") {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Password reset email sent")));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
            }
          },
        ),
        ElevatedButton(
          child: deleteAccountLoading ? CircularProgressIndicator() : Text("Delete account"),
          onPressed: () async {
            ref.read(deleteAccountLoadingProvider.notifier).state = true;
            String status = await deleteAccount();
            ref.read(deleteAccountLoadingProvider.notifier).state = false;
            if (status == "") {
              Navigator.pop(context);
              Navigator.pushReplacement(context,MaterialPageRoute(builder: (context) => SignupPage()));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status)));
            }
          },
        ),
      ],
    );
  }
}


class SponsorPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ModalRoute.of(context)!.settings.arguments as String?;

    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            child: Consumer(
              builder: (context, ref, _) {
                final acceptInviteLoading = ref.watch(sponsorPageAcceptInviteLoadingProvider);
                return acceptInviteLoading ? CircularProgressIndicator() : Text("Accept sponsorship invite");
              }
            ),
            onPressed: () {
              ref.read(sponsorPageAcceptInviteLoadingProvider.notifier).state = true;
              acceptSponsorshipInvite(code);
              ref.read(sponsorPageAcceptInviteLoadingProvider.notifier).state = false;
              Navigator.pop(context);
            },
          ),
          TextButton(
            child: Text("Decline sponsorship invite"),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

Widget _buildEditableField({
  required BuildContext context,
  required String label,
  required String value,
  required Function(String) onSave,
}) {
  return GestureDetector(
    onTap: () => _showEditDialog(context, label, value, onSave),
    child: Text('$label: $value'),
  );
}

void _showEditDialog(
  BuildContext context,
  String label,
  String currentValue,
  Function(String) onSave,
) {
  final controller = TextEditingController(text: currentValue);

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Edit $label'),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final newValue = controller.text.trim();
            if (newValue != currentValue) {
              onSave(newValue);
            }
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}