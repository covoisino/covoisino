import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class ReferralService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static const _uuid = Uuid();

  // Generate a one-time referral link
  static Future<String> generateReferralLink() async {
    final user = _auth.currentUser!;
    const duration = Duration(hours: 24);
    
    final code = _uuid.v4().substring(0, 8);
    await _db.collection('referralLinks').doc(code).set({
      'creator': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(duration)),
      'used': false,
      'usedBy': null,
    });

    return 'https://covoisino.github.io/referral.html?code=$code';
  }

  // Validate and claim a referral code
  static Future<String?> claimReferralCode(String code) async {
    return _db.runTransaction<String?>((transaction) async {
      final ref = _db.collection('referralLinks').doc(code);
      final doc = await transaction.get(ref);

      if (!doc.exists || doc['used'] || doc['expiresAt'].toDate().isBefore(DateTime.now())) {
        return null;
      }

      transaction.update(ref, {
        'used': true,
        'usedBy': _auth.currentUser!.uid,
        'usedAt': FieldValue.serverTimestamp(),
      });

      return doc['creator'];
    });
  }

  // Get current user's sponsor count
  static Stream<int> getSponsorCount() {
    return _db.collection('users').doc(_auth.currentUser!.uid)
        .snapshots()
        .map((snap) => snap.data()?['sponsorsCount'] ?? 0);
  }

  // Get sponsor history
  static Stream<List<Map<String, dynamic>>> getSponsorHistory() {
    final user = _auth.currentUser!;
    return _db.collection('users').doc(user.uid)
        .collection('sponsorsHistory')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => doc.data())
            .toList());
  }

  // Increment sponsor count
  static Future<void> incrementSponsorCount(String referrerId, {String? targetUid}) async {
    final userRef = _db.collection('users').doc(targetUid ?? _auth.currentUser!.uid);
    final historyRef = userRef.collection('sponsorsHistory');

    await _db.runTransaction((transaction) async {
      final docSnapshot = await transaction.get(userRef);

      int currentCount = (docSnapshot.data()?['sponsorsCount'] as int?) ?? 0;

      if (currentCount >= 2) {
        throw StateError('Maximum of 2 sponsors already reached');
      }

      final historyQuery = await historyRef
          .where('uid', isEqualTo: referrerId)
          .limit(1)
          .get();

      if (historyQuery.docs.isNotEmpty) {
        throw StateError('This sponsor has already sponsored this user.');
      }

      transaction.update(userRef, {
        'sponsorsCount': FieldValue.increment(1),
      });

      transaction.set(
        userRef.collection('sponsorsHistory').doc(),
        {
          'uid': referrerId,
          'timestamp': FieldValue.serverTimestamp(),
        }
      );
    });
  }

  /// 1a. Send a sponsorship request
  static Future<void> sendSponsorRequest({
    required String toUid,
    String message = '',
  }) async {
    final fromUid = FirebaseAuth.instance.currentUser!.uid;
    final col     = FirebaseFirestore.instance.collection('sponsorRequests');

    // Check if there's already a non‑declined request
    final dup = await col
        .where('fromUid', isEqualTo: fromUid)
        .where('toUid',   isEqualTo: toUid)
        .where('status',  whereIn: ['pending', 'accepted'])
        .get();

    if (dup.docs.isNotEmpty) {
      throw Exception('You have already invited this user.');
    }

    // Otherwise add a fresh request
    await col.add({
      'fromUid':   fromUid,
      'toUid':     toUid,
      'message':   message,
      'status':    'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// 1b. Stream all pending requests TO the current user
  static Stream<QuerySnapshot> incomingSponsorRequests() {
    final uid = _auth.currentUser!.uid;
    return _db
      .collection('sponsorRequests')
      .where('toUid', isEqualTo: uid)
      .where('status', isEqualTo: 'pending')
      .orderBy('timestamp', descending: true)
      .snapshots();
  }

  /// 1c. Accept or decline a request
  static Future<void> updateSponsorRequestStatus({
    required String requestId,
    required String status, // "accepted" or "declined"
  }) async {
    final db     = FirebaseFirestore.instance;
    final meUid  = FirebaseAuth.instance.currentUser!.uid;
    final reqRef = db.collection('sponsorRequests').doc(requestId);

    // Step 1: Update the request status
    await reqRef.update({'status': status});

    // Step 2: If accepted, increment the sponsor count of the request sender (fromUid)
    if (status == 'accepted') {
      // Re-read the request doc to get the fromUid (sponsoree)
      final reqSnap = await reqRef.get();
      final fromUid = reqSnap.data()?['fromUid'] as String?;

      if (fromUid != null) {
        // meUid is the sponsor accepting the request
        await incrementSponsorCount(meUid, targetUid: fromUid);
      } else {
        throw StateError('Missing fromUid in sponsor request.');
      }
    }
  }
}

class ReferralLinkService {
  static const _chan = MethodChannel('referral_link');
  final GlobalKey<NavigatorState> navKey;

  ReferralLinkService(this.navKey) {
    _chan.setMethodCallHandler((call) async {
      if (call.method == 'onLinkReceived') {
        _handleLink(call.arguments as String);
      }
    });
  }

  Future<void> init() async {
    final String? link = await _chan.invokeMethod('getInitialLink');
    if (link != null) _handleLink(link);
  }

  void _handleLink(String link) async {
    final uri = Uri.parse(link);
    final code = uri.queryParameters['code'];
    if (code == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Handle auth first if needed
      return;
    }

    final isValid = await FirebaseFirestore.instance
        .collection('referralLinks')
        .doc(code)
        .get()
        .then((doc) => 
            doc.exists && 
            !doc['used'] && 
            doc['expiresAt'].toDate().isAfter(DateTime.now()));

    if (isValid) {
      navKey.currentState!.pushNamed('/sponsor', arguments: code);
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}

Future<void> navigateAfterAuth(BuildContext context) async {
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser;
  if (user == null) return;

  try {
    // if the account was deleted in the console, this throws user-not-found
    await user.reload();
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      // clear the stale flag:
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('setupComplete_${user.uid}');
      // force sign‑out and send back to signup
      await auth.signOut();
      Navigator.pushReplacementNamed(context, '/signup');
      return;
    }
    rethrow;
  }

  // now do the normal prefs check:
  final prefs = await SharedPreferences.getInstance();
  final done = prefs.getBool('setupComplete_${user.uid}') ?? false;
  if (done) {
    Navigator.pushReplacementNamed(context, '/home');
  } else {
    Navigator.pushReplacementNamed(context, '/setup');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  // allows child widgets to call setThemeMode / setLocale
  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;
  Locale _locale = Locale('en');

  // 1) navigatorKey for ReferralLinkService
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  // 2) referral link handler
  late final ReferralLinkService _linkService;

  @override
  void initState() {
    super.initState();
    _loadPreferences();

    // 3) instantiate and init the link service
    _linkService = ReferralLinkService(_navKey);
    _linkService.init();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode =
          (prefs.getBool('isDarkMode') ?? false) ? ThemeMode.dark : ThemeMode.light;
      _locale = Locale(prefs.getString('locale') ?? 'en');
    });
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', mode == ThemeMode.dark);
    setState(() => _themeMode = mode);
  }

  Future<void> setLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale.languageCode);
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    const Color darkBlue = Color(0xFF0D47A1);
    const Color lightBlue = Color(0xFF42A5F5);
    const Color accentGreen = Color(0xFF43A047);
    const Color accentRed = Color(0xFFE53935);

    final lightColorScheme = ColorScheme.light(
      primary: darkBlue,
      primaryContainer: lightBlue,
      secondary: accentGreen,
      error: accentRed,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onError: Colors.white,
      background: Colors.white,
      surface: Colors.white,
      onBackground: Colors.black87,
      onSurface: Colors.black87,
    );

    final darkColorScheme = ColorScheme.dark(
      primary: lightBlue,
      primaryContainer: darkBlue,
      secondary: Colors.green.shade200,
      error: Colors.red.shade200,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onError: Colors.black,
      background: Colors.black,
      surface: Colors.grey.shade900,
      onBackground: Colors.white,
      onSurface: Colors.white,
    );

    final lightTheme = ThemeData.from(colorScheme: lightColorScheme).copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: lightColorScheme.primary,
        foregroundColor: lightColorScheme.onPrimary,
        elevation: 2,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: lightColorScheme.onPrimary,
        ),
        iconTheme: IconThemeData(color: lightColorScheme.onPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: lightColorScheme.onPrimary,
          backgroundColor: lightColorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: lightColorScheme.primary),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: lightColorScheme.primary),
        bodyMedium: TextStyle(fontSize: 16, color: lightColorScheme.onBackground),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightColorScheme.primaryContainer.withOpacity(0.1),
        labelStyle: TextStyle(color: lightColorScheme.primary, fontWeight: FontWeight.w500),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: lightColorScheme.primary, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: lightColorScheme.primaryContainer, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: lightColorScheme.error, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: lightColorScheme.error, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightColorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: lightColorScheme.primary,
        ),
        contentTextStyle: TextStyle(fontSize: 16, color: lightColorScheme.onSurface),
      ),
      iconTheme: IconThemeData(color: lightColorScheme.primary),
    );

    final darkTheme = ThemeData.from(colorScheme: darkColorScheme).copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: darkColorScheme.primary,
        foregroundColor: darkColorScheme.onPrimary,
        elevation: 2,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: darkColorScheme.onPrimary,
        ),
        iconTheme: IconThemeData(color: darkColorScheme.onPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: darkColorScheme.onPrimary,
          backgroundColor: darkColorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: darkColorScheme.primary),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: darkColorScheme.primary),
        bodyMedium: TextStyle(fontSize: 16, color: darkColorScheme.onBackground),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkColorScheme.surface,
        labelStyle: TextStyle(color: darkColorScheme.primary, fontWeight: FontWeight.w500),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: darkColorScheme.primary, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: darkColorScheme.primaryContainer, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: darkColorScheme.error, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: darkColorScheme.error, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkColorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: darkColorScheme.primary,
        ),
        contentTextStyle: TextStyle(fontSize: 16, color: darkColorScheme.onSurface),
      ),
      iconTheme: IconThemeData(color: darkColorScheme.primary),
    );

    return MaterialApp(
      navigatorKey: _navKey, // <-- plug in the nav key
      title: 'Flutter Firebase Auth App',
      locale: _locale,
      supportedLocales: [Locale('en'), Locale('fr')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        const SimpleLocalizationsDelegate(),
      ],
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      onGenerateTitle: (ctx) => SimpleLocalizations.of(ctx).get('app_title'),
      home: SignupPage(),

      // 4) routes
      routes: {
        '/signup': (_) => SignupPage(),
        '/login': (_) => LoginPage(),
        '/forgot': (_) => ForgotPasswordPage(),
        '/verifyAccount': (_) => VerifyAccountPage(),
        '/setup': (_) => SetupPage(),
        '/home': (_) => HomePage(),
        '/options': (_) => OptionsPage(),

        // read the `referrer` string out of settings.arguments:
        '/sponsor': (ctx) {
          final code = ModalRoute.of(ctx)!.settings.arguments as String;
          return SponsorPage(referralCode: code);
        },
      },
    );
  }
}

class SimpleLocalizations {
  final Locale locale;
  SimpleLocalizations(this.locale);

  static SimpleLocalizations of(BuildContext context) =>
      Localizations.of<SimpleLocalizations>(context, SimpleLocalizations)!;

  static const Map<String, Map<String, String>> _vals = {
    'en': {
    },
    'fr': {
    },
  };

  String get(String key) =>
      _vals[locale.languageCode]?[key] ?? key;
}

class SimpleLocalizationsDelegate
    extends LocalizationsDelegate<SimpleLocalizations> {
  const SimpleLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) =>
      ['en', 'fr'].contains(locale.languageCode);
  @override
  Future<SimpleLocalizations> load(Locale locale) async =>
      SimpleLocalizations(locale);
  @override
  bool shouldReload(covariant LocalizationsDelegate old) => false;
}

class SignupPage extends StatefulWidget {
  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _signup() async {
    try {
      if (_emailController.text.isNotEmpty && _passwordController.text.isNotEmpty) {
        UserCredential userCred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        await userCred.user!
            .updateDisplayName('${_firstNameController.text.trim()} ${_lastNameController.text.trim()}');
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCred.user!.uid)
            .set({
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
        }, SetOptions(merge: true));
        await userCred.user!.sendEmailVerification();
        Navigator.pushReplacementNamed(context, '/verifyAccount');
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Signup failed')),
      );
    }
  }

  Future<void> _signUpWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return;
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      UserCredential userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      String fullName = userCred.user?.displayName ?? '';
      List<String> nameParts = fullName.split(' ');
      String firstName = nameParts.first;
      String lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCred.user!.uid)
          .set({
        'firstName': firstName,
        'lastName': lastName,
      }, SetOptions(merge: true));
      await navigateAfterAuth(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google signup failed')),
      );
    }
  }

  Future<void> _signUpWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      await navigateAfterAuth(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apple signup failed')),
      );
    }
  }

  Future<void> _signUpWithFacebook() async {
    try {
      final result = await FacebookAuth.instance.login();
      if (result.status == LoginStatus.success) {
        final credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
        await FirebaseAuth.instance.signInWithCredential(credential);
        await navigateAfterAuth(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Facebook signup failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final accentGreen = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: Text('Signup'),
        centerTitle: true,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(height: 20),
            Text(
              'Create Account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 20),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // First Name Field
                    TextField(
                      controller: _firstNameController,
                      decoration: InputDecoration(
                        labelText: 'First Name',
                        prefixIcon: Icon(Icons.person, color: primaryColor),
                      ),
                    ),
                    SizedBox(height: 16),
                    // Last Name Field
                    TextField(
                      controller: _lastNameController,
                      decoration: InputDecoration(
                        labelText: 'Last Name',
                        prefixIcon: Icon(Icons.person_outline, color: primaryColor),
                      ),
                    ),
                    SizedBox(height: 16),
                    // Email Field
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email, color: primaryColor),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: 16),
                    // Password Field
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock, color: primaryColor),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 24),
                    // Signup Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _signup,
                        child: Text('Signup with Email'),
                      ),
                    ),
                    SizedBox(height: 16),
                    // Google Signup Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _signUpWithGoogle,
                        child: Text('Continue with Google'),
                      ),
                    ),
                    // Uncomment for Apple/Facebook when ready:
                    // SizedBox(height: 16),
                    // SizedBox(
                    //   width: double.infinity,
                    //   child: ElevatedButton(
                    //     onPressed: _signUpWithApple,
                    //     child: Text('Continue with Apple'),
                    //   ),
                    // ),
                    // SizedBox(height: 16),
                    // SizedBox(
                    //   width: double.infinity,
                    //   child: ElevatedButton(
                    //     onPressed: _signUpWithFacebook,
                    //     child: Text('Continue with Facebook'),
                    //   ),
                    // ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
              child: Text(
                'Go to Login',
                style: TextStyle(color: accentGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _login() async {
    try {
      if (_emailController.text.isNotEmpty && _passwordController.text.isNotEmpty) {
        UserCredential userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        await userCred.user!.reload(); // Refresh user info
        if (userCred.user!.emailVerified) {
          await navigateAfterAuth(context);
        } else {
          Navigator.pushReplacementNamed(context, '/verifyAccount');
        }
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Login failed')),
      );
    }
  }

  Future<void> _loginWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return;
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      await navigateAfterAuth(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google login failed')),
      );
    }
  }

  Future<void> _loginWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      await navigateAfterAuth(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apple login failed')),
      );
    }
  }

  Future<void> _loginWithFacebook() async {
    try {
      final result = await FacebookAuth.instance.login();
      if (result.status == LoginStatus.success) {
        final credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
        await FirebaseAuth.instance.signInWithCredential(credential);
        await navigateAfterAuth(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Facebook login failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pull colors from the active ThemeData
    final primaryColor = Theme.of(context).colorScheme.primary;
    final accentGreen = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: Text('Login'),
        centerTitle: true,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(height: 20),
            Text(
              'Welcome Back',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 20),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Email Field
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email, color: primaryColor),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: 16),
                    // Password Field
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock, color: primaryColor),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 24),
                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _login,
                        child: Text('Login with Email'),
                      ),
                    ),
                    SizedBox(height: 16),
                    // Google Login Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loginWithGoogle,
                        child: Text('Continue with Google'),
                      ),
                    ),
                    // If you uncomment Apple/Facebook options, they will match theme
                    // SizedBox(height: 16),
                    // SizedBox(
                    //   width: double.infinity,
                    //   child: ElevatedButton(
                    //     onPressed: _loginWithApple,
                    //     child: Text('Continue with Apple'),
                    //   ),
                    // ),
                    // SizedBox(height: 16),
                    // SizedBox(
                    //   width: double.infinity,
                    //   child: ElevatedButton(
                    //     onPressed: _loginWithFacebook,
                    //     child: Text('Continue with Facebook'),
                    //   ),
                    // ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            // Footer Links
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
                  child: Text(
                    'Go to Signup',
                    style: TextStyle(color: accentGreen),
                  ),
                ),
                SizedBox(width: 16),
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/forgot'),
                  child: Text(
                    'Forgot Password',
                    style: TextStyle(color: accentGreen),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  @override
  _ForgotPasswordPageState createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();

  Future<void> _resetPassword() async {
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _emailController.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent')),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Error sending reset email')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final accentGreen = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: Text('Forgot Password'),
        centerTitle: true,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(height: 20),
            Text(
              'Reset Your Password',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 20),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Email Field
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email, color: primaryColor),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: 24),
                    // Send Reset Email Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _resetPassword,
                        child: Text('Send Reset Email'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
              child: Text(
                'Back to Login',
                style: TextStyle(color: accentGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VerifyAccountPage extends StatefulWidget {
  @override
  _VerifyAccountPageState createState() => _VerifyAccountPageState();
}

class _VerifyAccountPageState extends State<VerifyAccountPage> {
  User? get user => FirebaseAuth.instance.currentUser;

  Future<void> _resendEmail() async {
    try {
      await user!.sendEmailVerification();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification email sent')), 
      );
    } catch (_) {}
  }

  Future<void> _continue() async {
    await user!.reload();
    if (FirebaseAuth.instance.currentUser!.emailVerified) {
      await navigateAfterAuth(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please verify your email first')),
      );
    }
  }

  Future<void> _restart() async {
    await user!.delete();
    Navigator.pushReplacementNamed(context, '/signup');
  }

  @override
  Widget build(BuildContext context) {
    final accentGreen = Theme.of(context).colorScheme.secondary;
    final accentRed = Theme.of(context).colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        title: Text('Verify Account'),
        centerTitle: true,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(height: 20),
            Text(
              'Email Verification',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 12),
            Text(
              'A verification email has been sent to your inbox. Please check your email and click on the verification link before continuing.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Resend Email Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _resendEmail,
                        icon: Icon(Icons.refresh, color: Colors.white),
                        label: Text('Resend Email'),
                      ),
                    ),
                    SizedBox(height: 16),
                    // Continue Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _continue,
                        icon: Icon(Icons.check_circle, color: Colors.white),
                        label: Text('Continue'),
                      ),
                    ),
                    SizedBox(height: 16),
                    // Restart Signup Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _restart,
                        icon: Icon(Icons.restart_alt, color: Colors.white),
                        label: Text('Restart Signup'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: accentRed,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 14),
                          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
              child: Text(
                'Back to Login',
                style: TextStyle(color: accentGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SetupPage extends StatefulWidget {
  @override
  _SetupPageState createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  int _stage = 1;

  // Stage 3 & 4 (phone)
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _smsController = TextEditingController();
  String? _verificationId;

  // Stage 5 (dob & gender)
  final TextEditingController _dobController = TextEditingController();
  String? _gender;

  // Stage 1 (driver?)
  bool? _wantsToDrive;

  // Stage 2 (car model)
  final TextEditingController _carModelController = TextEditingController();

  User? get _user => FirebaseAuth.instance.currentUser;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<void> _nextStage() async {
    final uid = _user!.uid;
    final batch = _db.batch();
    final doc = _db.collection('users').doc(uid);

    switch (_stage) {
      case 1:
        // initialize + wantsToDrive
        batch.set(doc, {
          'sponsorsCount': 0,
          'wantsToDrive': _wantsToDrive,
        }, SetOptions(merge: true));
        break;
      case 2:
        // driver chose a car
        if (_wantsToDrive == true && _carModelController.text.trim().isNotEmpty) {
          batch.set(doc, {
            'carModel': _carModelController.text.trim(),
          }, SetOptions(merge: true));
        }
        break;
      case 4:
        // verify SMS code & link phone
        if (_smsController.text.trim().isNotEmpty && _verificationId != null) {
          final cred = PhoneAuthProvider.credential(
            verificationId: _verificationId!,
            smsCode: _smsController.text.trim(),
          );
          await _user!.linkWithCredential(cred);
          batch.set(doc, {
            'phone': _phoneController.text.trim(),
          }, SetOptions(merge: true));
        }
        break;
      case 5:
        // dob & gender
        if (_dobController.text.trim().isNotEmpty) {
          batch.set(doc, {
            'dob': _dobController.text.trim(),
          }, SetOptions(merge: true));
        }
        if (_gender != null) {
          batch.set(doc, {
            'gender': _gender,
          }, SetOptions(merge: true));
        }
        break;
    }

    await batch.commit();

    setState(() {
      if (_stage < 5) {
        if (_stage == 1) {
          // go to car model or skip to phone
          _stage = _wantsToDrive! ? 2 : 3;
        } else if (_stage == 2) {
          _stage = 3;
        } else if (_stage == 4) {
          _stage = 5;
        } else {
          _stage++;
        }
      } else {
        _finishSetup();
      }
    });
  }

  void _prevStage() {
    setState(() {
      switch (_stage) {
        case 2:
          _stage = 1;
          break;
        case 3:
          _stage = _wantsToDrive! ? 2 : 1;
          break;
        case 4:
          _stage = 3;
          break;
        case 5:
          _stage = _wantsToDrive! ? 4 : 3;
          break;
      }
    });
  }

  Future<void> _finishSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setupComplete_${_user!.uid}', true);
    Navigator.pushReplacementNamed(context, '/home');
  }

  void _verifyPhone() {
    FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _phoneController.text.trim(),
      verificationCompleted: (_) {},
      verificationFailed: (e) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Phone verification failed: ${e.message}')),
      ),
      codeSent: (id, _) {
        setState(() {
          _verificationId = id;
          _stage = 4;
        });
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _pickDob() async {
    DateTime? d = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      _dobController.text =
          "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final accentGreen = Theme.of(context).colorScheme.secondary;

    Widget content;
    switch (_stage) {
      case 1:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Driver Setup',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 12),
            Text(
              'Do you want to become a driver?',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Radio<bool>(
                          value: true,
                          groupValue: _wantsToDrive,
                          onChanged: (v) => setState(() => _wantsToDrive = v),
                        ),
                        Text('Yes', style: TextStyle(color: primaryColor)),
                        SizedBox(width: 24),
                        Radio<bool>(
                          value: false,
                          groupValue: _wantsToDrive,
                          onChanged: (v) => setState(() => _wantsToDrive = v),
                        ),
                        Text('No', style: TextStyle(color: primaryColor)),
                      ],
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _wantsToDrive == null ? null : _nextStage,
                        child: Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        break;

      case 2:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vehicle Information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _carModelController,
                      decoration: InputDecoration(
                        labelText: 'Car Model',
                        prefixIcon: Icon(Icons.directions_car, color: primaryColor),
                      ),
                    ),
                    SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _nextStage,
                        child: Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        break;

      case 3:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Phone Verification',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: Icon(Icons.phone, color: primaryColor),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _verifyPhone,
                            child: Text('Verify Phone'),
                          ),
                        ),
                        if (_wantsToDrive == false)
                          SizedBox(width: 16),
                        if (_wantsToDrive == false)
                          Expanded(
                            child: TextButton(
                              onPressed: () => setState(() => _stage = 5),
                              child: Text(
                                'Skip',
                                style: TextStyle(color: accentGreen),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        break;

      case 4:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter SMS Code',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _smsController,
                      decoration: InputDecoration(
                        labelText: 'SMS Code',
                        prefixIcon: Icon(Icons.message, color: primaryColor),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _nextStage,
                        child: Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        break;

      case 5:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personal Details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _dobController,
                      decoration: InputDecoration(
                        labelText: 'Date of Birth',
                        prefixIcon: Icon(Icons.calendar_today, color: primaryColor),
                      ),
                      readOnly: true,
                      onTap: _pickDob,
                    ),
                    SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _gender,
                      items: ['Male', 'Female', 'Other']
                          .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (v) => setState(() => _gender = v),
                      decoration: InputDecoration(
                        labelText: 'Gender',
                        prefixIcon: Icon(Icons.person, color: primaryColor),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _nextStage,
                        child: Text('Finish'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        break;

      default:
        content = SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Setup — Stage $_stage of 5'),
        centerTitle: true,
        elevation: 2,
        leading: _stage > 1
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: _prevStage,
              )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _smsController.dispose();
    _dobController.dispose();
    _carModelController.dispose();
    super.dispose();
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final MapController _mapController = MapController();

  final Map<String, LatLng> _cityCoordinates = const {
    'Paris':    LatLng(48.8566, 2.3522),
    'London':   LatLng(51.5074, -0.1278),
    'New York': LatLng(40.7128, -74.0060),
    'Chicago':  LatLng(41.8781, -87.6298),
  };

  String? _location;
  bool? _driverLocationOn;
  bool? _autoDriveModeOn;
  bool? _driverNotificationsOn;
  bool? _sponsorshipVisibilityOn;
  final _doc = FirebaseFirestore.instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser!.uid);
  StreamSubscription<QuerySnapshot>? _reqSub;
  StreamSubscription<Position>? _posSub;
  int _prevReqCount = 0;

  final PopupController _popupController = PopupController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load().then((_) => _maybeStartLocationUpdates());

    _reqSub = ReferralService.incomingSponsorRequests().listen((snap) {
      final newCount = snap.docs.length;
      if (newCount > _prevReqCount && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You have a new sponsorship request!')),
        );
      }
      _prevReqCount = newCount;
    });
  }

  @override
  void dispose() {
    _reqSub?.cancel();
    _posSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _maybeStartLocationUpdates() async {
    // Only if driverLocationOn is true:
    if (_driverLocationOn != true) return;

    // 1. Ask for permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        // Permissions are denied, you could show a message here
        return;
      }
    }

    // 2. Start listening
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10, // only if moved ≥10m
      ),
    ).listen((Position pos) {
      // Write into Firestore
      FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .set({
          'currentLocation': GeoPoint(pos.latitude, pos.longitude),
          // Keep your driverLocationOn flag in sync too
          'driverLocationOn': true,
        }, SetOptions(merge: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only run if they’ve opted into auto‐drive mode
    if (_autoDriveModeOn == true) {
      if (state == AppLifecycleState.resumed) {
        // app came to foreground ⇒ turn location on
        _update('driverLocationOn', true);
      } else if (state == AppLifecycleState.paused ||
                 state == AppLifecycleState.inactive ||
                 state == AppLifecycleState.detached) {
        // app went to background ⇒ turn location off
        _update('driverLocationOn', false);
      }
    }
  }

  Future<void> _load() async {
    final snap = await _doc.get();
    final d = snap.data() ?? {};
    setState(() {
      _location = d['location'];
      _driverLocationOn = d['driverLocationOn'];
      _autoDriveModeOn = d['autoDriveModeOn'];
      _driverNotificationsOn = d['driverNotificationsOn'];
      _sponsorshipVisibilityOn = d['sponsorshipVisibilityOn'];
    });
    try {
      _mapController.move(_cityCoordinates[_location]!, 13.0);
    } catch (e) {
      
    }
  }

  Future<void> _update(String field, dynamic val) async {
    await _doc.set({field: val}, SetOptions(merge: true));
    await _load();
    if (field == 'driverLocationOn') {
      // stop or start updates
      if (val == true) {
        _maybeStartLocationUpdates();
      } else {
        await _posSub?.cancel();
        _posSub = null;
      }
    }
  }

  Future<void> _copyReferralLink(BuildContext ctx) async {
    try {
      final link = await ReferralService.generateReferralLink();
      await Clipboard.setData(ClipboardData(text: link));
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('One-time link copied! Expires in 24 hours')),
      );
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Error generating link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: (_selectedIndex == 0
            ? Text('Home')
            : _selectedIndex == 1
                ? Text('Ride')
                : Text('Drive')),
        centerTitle: true,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.menu),
            onPressed: () => Navigator.pushNamed(context, '/options'),
          ),
        ],
      ),
      body: StreamBuilder<int>(
        stream: ReferralService.getSponsorCount(),
        builder: (context, snapshot) {
          // Don’t default to 0. Instead, wait until we have real data.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final count = snapshot.data!; // safe because we know hasData == true
          if (count < 2) {
            return _buildSponsorInfo(context);
          } else {
            return IndexedStack(
              index: _selectedIndex,
              children: [
                _buildHomeTab(context),
                _buildRideTab(context),
                _buildDriveTab(context),
              ],
            );
          }
        },
      ),
      bottomNavigationBar: StreamBuilder<int>(
        stream: ReferralService.getSponsorCount(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox.shrink();
          }
          final count = snapshot.data!;
          if (count < 2) {
            return const SizedBox.shrink();
          }

          return BottomNavigationBar(
            currentIndex: _selectedIndex,
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor:
                Theme.of(context).colorScheme.onBackground.withOpacity(0.6),
            onTap: (i) => setState(() => _selectedIndex = i),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Ride'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.directions_car_filled), label: 'Drive'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Referral & Location',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _copyReferralLink(context),
                      icon: Icon(Icons.link),
                      label: Text('Generate Referral Link'),
                    ),
                  ),
                  SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _location,
                    items: ['Paris','London', 'New York', 'Chicago']
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) async {
                      if (v != null) await _update('location', v);
                      final newCenter = _cityCoordinates[v]!;
                      const double newZoom = 13.0;
                      _mapController.move(newCenter,newZoom);
                    },
                    selectedItemBuilder: (context) {
                      return ['Paris','London', 'New York', 'Chicago']
                          .map((l) => Text('Current location: $l'))
                          .toList();
                    },
                    decoration: InputDecoration(
                      labelText: 'Select Location',
                      prefixIcon: Icon(Icons.location_on, color: primaryColor),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: 20),
                  DropdownButtonFormField<bool>(
                    isExpanded: true,
                    value: _sponsorshipVisibilityOn,
                    items: [
                      DropdownMenuItem(value: true, child: Text('Allow')),
                      DropdownMenuItem(value: false, child: Text('Do not allow')),
                    ],
                    onChanged: (v) async {
                      if (v != null) await _update('sponsorshipVisibilityOn', v);
                    },
                    selectedItemBuilder: (BuildContext context) {
                      return [true, false].map((value) {
                        return Text(
                          value
                              ? 'Allow sponsorship visibility'
                              : 'Do not allow sponsorship visibility',
                          maxLines: 2,
                          softWrap: true,
                        );
                      }).toList();
                    },
                    decoration: InputDecoration(
                      labelText: 'Sponsorship visibility',
                      prefixIcon:
                          Icon(Icons.visibility, color: primaryColor),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 24),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'What would you like to do?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => setState(() => _selectedIndex = 1),
                      child: Text('I want to ride'),
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => setState(() => _selectedIndex = 2),
                      child: Text('I want to drive'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildRequestsSection(context),
        ],
      ),
    );
  }

  Widget _buildRideTab(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    final LatLng center = _cityCoordinates[_location] ?? LatLng(41.8781, -87.6298);

    return Stack(
      children: [
        // StreamBuilder around the map so we can update markers live
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('driverLocationOn', isEqualTo: true)
              .snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }

            // Convert each doc with a GeoPoint into a Marker
            final markers = <Marker>[];
            for (final doc in snap.data!.docs) {
              final data = doc.data()! as Map<String, dynamic>;
              final gp = data['currentLocation'] as GeoPoint?;
              if (gp == null) continue;

              final ll = LatLng(gp.latitude, gp.longitude);

              // capture the marker instance
              late final Marker marker;
              marker = Marker(
                point: ll,
                width: 30,
                height: 30,
                child: GestureDetector(
                  onTap: () => _popupController.togglePopup(marker),
                  child: Icon(
                    Icons.directions_car_filled,
                    size: 40,
                    color: primaryColor,
                  ),
                ),
              );

              markers.add(marker);
            }

            return FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 13.0,
                onTap: (_, __) => _popupController.hideAllPopups(),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                ),
                MarkerLayer(markers: markers),
                PopupMarkerLayerWidget(
                  options: PopupMarkerLayerOptions(
                    markers: markers,
                    popupController: _popupController,
                    popupDisplayOptions: PopupDisplayOptions(
                      builder: (BuildContext context, Marker marker) => Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Driver',
                                style: TextStyle(
                                    color: primaryColor,
                                    fontWeight: FontWeight.w600),
                              ),
                              Text('Tap for details'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        Positioned(
          bottom: 24,
          left: 16,
          right: 16,
          child: Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: Colors.white.withOpacity(0.9),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.qr_code_scanner),
                      label: Text('Scan a QR Code'),
                    ),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.call),
                      label: Text('Emergency Call'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.share_location),
                      label: Text('Share Location'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDriveTab(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Driver Settings',
                      style: Theme.of(context).textTheme.titleLarge),
                  SizedBox(height: 12),
                  DropdownButtonFormField<bool>(
                    isExpanded: true,
                    value: _driverLocationOn,
                    items: [
                      DropdownMenuItem(value: true, child: Text('On')),
                      DropdownMenuItem(value: false, child: Text('Off')),
                    ],
                    onChanged: _autoDriveModeOn == true
                        ? null
                        : (v) async {
                            if (v != null) await _update('driverLocationOn', v);
                          },
                    selectedItemBuilder: (BuildContext context) {
                      return [true, false].map((value) {
                        return Text(value
                            ? 'Driver location is on'
                            : 'Driver location is off');
                      }).toList();
                    },
                    decoration: InputDecoration(
                      labelText: 'Location Tracking',
                      prefixIcon:
                          Icon(Icons.location_on, color: primaryColor),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: 20),
                  DropdownButtonFormField<bool>(
                    isExpanded: true,
                    value: _autoDriveModeOn,
                    items: [
                      DropdownMenuItem(value: true, child: Text('Allow')),
                      DropdownMenuItem(value: false, child: Text('Do not allow')),
                    ],
                    onChanged: (v) async {
                      if (v != null) await _update('autoDriveModeOn', v);
                      if (v == true) await _update('driverLocationOn', true);
                    },
                    selectedItemBuilder: (BuildContext context) {
                      return [true, false].map((value) {
                        return Text(
                          value
                              ? 'Allow automatic location on/off'
                              : 'Do not allow automatic location',
                          maxLines: 2,
                          softWrap: true,
                        );
                      }).toList();
                    },
                    decoration: InputDecoration(
                      labelText: 'Auto-Drive Mode',
                      prefixIcon:
                          Icon(Icons.autorenew, color: primaryColor),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: 20),
                  DropdownButtonFormField<bool>(
                    isExpanded: true,
                    value: _driverNotificationsOn,
                    items: [
                      DropdownMenuItem(value: true, child: Text('Allow')),
                      DropdownMenuItem(value: false, child: Text('Do not allow')),
                    ],
                    onChanged: (v) async {
                      if (v != null) await _update('driverNotificationsOn', v);
                    },
                    selectedItemBuilder: (BuildContext context) {
                      return [true, false].map((value) {
                        return Text(
                          value
                              ? 'Allow notifications while driving'
                              : 'Do not allow notifications',
                          maxLines: 2,
                          softWrap: true,
                        );
                      }).toList();
                    },
                    decoration: InputDecoration(
                      labelText: 'Notifications',
                      prefixIcon:
                          Icon(Icons.notifications, color: primaryColor),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.qr_code),
                      label: Text('Create a QR Code'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSponsorInfo(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onBackground = Theme.of(context).colorScheme.onBackground;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Visible Users',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: primaryColor.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('sponsorshipVisibilityOn', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: TextStyle(color: onBackground.withOpacity(0.7)),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                print('Visible users count: ${docs.length}');
                for (var doc in docs) {
                  print('doc.id=${doc.id}, data=${doc.data()}');
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No users have enabled sponsorship visibility.\n(Count = 0)',
                      style: TextStyle(color: onBackground.withOpacity(0.6)),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Found ${docs.length} visible user(s)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data =
                              docs[index].data()! as Map<String, dynamic>;

                          final firstName = data['firstName'] as String?;
                          final lastName = data['lastName'] as String?;

                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: CircleAvatar(
                              backgroundColor: primaryColor.withOpacity(0.2),
                              child: Icon(Icons.person, color: primaryColor),
                            ),
                            title: Text('$firstName $lastName'),
                            onTap: () => _showSponsorRequestDialog(context, docs[index].id, '$firstName $lastName'),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('Sponsors Needed',
              style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 12),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: StreamBuilder<int>(
                stream: ReferralService.getSponsorCount(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Text(
                    'Sponsors: $count / 2',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(height: 24),
          Text('Sponsorship History',
              style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: ReferralService.getSponsorHistory(),
              builder: (context, snapshot) {
                final history = snapshot.data ?? [];
                if (history.isEmpty) {
                  return Center(
                    child: Text(
                      'No sponsorship history yet',
                      style: TextStyle(
                          color: onBackground.withOpacity(0.7)),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(entry['uid'])
                          .get(),
                      builder: (context, snapshot) {
                        final userData =
                            snapshot.data?.data() as Map<String, dynamic>?;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                primaryColor.withOpacity(0.2),
                            child: Icon(Icons.person,
                                color: primaryColor),
                          ),
                          title: Text(
                              userData?['displayName'] ??
                                  'Unknown User'),
                          subtitle: Text(
                            (entry['timestamp'] as Timestamp)
                                .toDate()
                                .toString(),
                            style: TextStyle(
                                color:
                                    onBackground.withOpacity(0.7)),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSponsorRequestDialog(
      BuildContext context,
      String toUid,
      String displayName,
  ) {
    final _msgCtrl = TextEditingController();

    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Request sponsorship from $displayName?'),
        content: TextField(
          controller: _msgCtrl,
          decoration: InputDecoration(labelText: 'Optional message'),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            child: Text('Send'),
            onPressed: () async {
              await ReferralService.sendSponsorRequest(
                toUid: toUid,
                message: _msgCtrl.text.trim(),
              );
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Request sent')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsSection(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return StreamBuilder<QuerySnapshot>(
      stream: ReferralService.incomingSponsorRequests(),
      builder: (ctx, reqSnap) {
        if (!reqSnap.hasData) return const SizedBox.shrink();
        final reqDocs = reqSnap.data!.docs;
        if (reqDocs.isEmpty) return const SizedBox.shrink();

        // 1) Gather unique UIDs
        final uids = reqDocs
            .map((d) => (d.data() as Map<String, dynamic>)['fromUid'] as String)
            .toSet()
            .toList();

        // 2) Batch‑fetch all user docs in one go
        return FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: uids)
              .get(),
          builder: (ctx2, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (userSnap.hasError || !userSnap.hasData) {
              return Center(child: Text('Error loading requesters'));
            }

            // 3) Build a map uid -> "First Last"
            final nameMap = {
              for (var u in userSnap.data!.docs)
                u.id: '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.trim()
            };

            // 4) Render the full list with names
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sponsorship Requests',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: reqDocs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx3, i) {
                    final doc = reqDocs[i];
                    final data = doc.data()! as Map<String, dynamic>;
                    final uid = data['fromUid'] as String;
                    final name = nameMap[uid] ?? uid;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: primaryColor.withOpacity(0.2),
                        child: Icon(Icons.person, color: primaryColor),
                      ),
                      title: Text('From: $name'),
                      subtitle: Text(data['message'] as String),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.check, color: Colors.green),
                            onPressed: () async {
                              try {
                                await ReferralService.updateSponsorRequestStatus(
                                  requestId: doc.id,
                                  status: 'accepted',
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Request accepted')),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Failed to accept: $e')),
                                );
                              }
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.clear, color: Colors.red),
                            onPressed: () async {
                              try {
                                await ReferralService.updateSponsorRequestStatus(
                                  requestId: doc.id,
                                  status: 'declined',
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Request declined')),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Failed to decline: $e')),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class OptionsPage extends StatefulWidget {
  @override
  _OptionsPageState createState() => _OptionsPageState();
}

class _OptionsPageState extends State<OptionsPage> {
  int _selectedIndex = 0;
  final List<Widget> _tabs = [
    ProfileContent(),
    SettingsContent(),
    AccountContent(),
  ];

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onBackground = Theme.of(context).colorScheme.onBackground;

    return Scaffold(
      appBar: AppBar(
        title: Text('Options'),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: Theme.of(context).colorScheme.surface,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            selectedIconTheme: IconThemeData(color: primaryColor),
            unselectedIconTheme: IconThemeData(color: onBackground.withOpacity(0.6)),
            selectedLabelTextStyle: TextStyle(color: primaryColor),
            unselectedLabelTextStyle: TextStyle(color: onBackground.withOpacity(0.6)),
            destinations: [
              NavigationRailDestination(
                icon: Icon(Icons.person),
                label: Text('Profile'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.account_circle),
                label: Text('Account'),
              ),
            ],
          ),
          VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _tabs[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileContent extends StatefulWidget {
  @override
  _ProfileContentState createState() => _ProfileContentState();
}

class _ProfileContentState extends State<ProfileContent> {
  String? _dob, _gender, _carModel;
  bool? _wantsToDrive;
  final _doc = FirebaseFirestore.instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser!.uid);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await _doc.get();
    final d = snap.data() ?? {};
    setState(() {
      _dob = d['dob'];
      _gender = d['gender'];
      _wantsToDrive = d['wantsToDrive'];
      _carModel = d['carModel'];
    });
  }

  Future<void> _update(String field, dynamic val) async {
    await _doc.set({field: val}, SetOptions(merge: true));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).colorScheme.onBackground;

    return ListView(
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            title: Text('Date of Birth', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600)),
            subtitle: Text(_dob ?? '-', style: TextStyle(color: textColor)),
            trailing: Icon(Icons.edit, color: primaryColor),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (d != null) {
                final s = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                await _update('dob', s);
              }
            },
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            title: Text('Gender', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600)),
            subtitle: Text(_gender ?? '-', style: TextStyle(color: textColor)),
            trailing: Icon(Icons.edit, color: primaryColor),
            onTap: () async {
              final choice = await showDialog<String>(
                context: context,
                builder: (_) => SimpleDialog(
                  title: Text('Gender'),
                  children: ['Male', 'Female', 'Other']
                      .map((g) => SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, g),
                            child: Text(g),
                          ))
                      .toList(),
                ),
              );
              if (choice != null) await _update('gender', choice);
            },
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            title: Text('Do you want to be a driver?', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600)),
            subtitle: Text(
              _wantsToDrive == null ? '-' : (_wantsToDrive! ? 'Yes' : 'No'),
              style: TextStyle(color: textColor),
            ),
            trailing: Icon(Icons.edit, color: primaryColor),
            onTap: () async {
              final c = await showDialog<bool>(
                context: context,
                builder: (_) => SimpleDialog(
                  title: Text('Do you want to be a driver?'),
                  children: [true, false]
                      .map((v) => SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, v),
                            child: Text(v ? 'Yes' : 'No'),
                          ))
                      .toList(),
                ),
              );
              if (c != null) await _update('wantsToDrive', c);
            },
          ),
        ),
        if (_wantsToDrive == true)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              title: Text('Car Model', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600)),
              subtitle: Text(_carModel ?? '-', style: TextStyle(color: textColor)),
              trailing: Icon(Icons.edit, color: primaryColor),
              onTap: () async {
                final ctl = TextEditingController(text: _carModel);
                final res = await showDialog<String>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('Car Model'),
                    content: TextField(controller: ctl),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, ctl.text.trim()),
                        child: Text('Save'),
                      ),
                    ],
                  ),
                );
                if (res != null && res.isNotEmpty) await _update('carModel', res);
              },
            ),
          ),
      ],
    );
  }
}

class SettingsContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appState = MyApp.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentLoc = Localizations.localeOf(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return ListView(
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text('Light / Dark Mode', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600)),
            value: isDark,
            onChanged: (v) => appState.setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text('Language', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600)),
            trailing: DropdownButton<Locale>(
              value: currentLoc,
              underline: SizedBox(),
              items: [Locale('en'), Locale('fr')]
                  .map(
                    (loc) => DropdownMenuItem(
                      value: loc,
                      child: Text(loc.languageCode.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: (loc) {
                if (loc != null) appState.setLocale(loc);
              },
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class AccountContent extends StatelessWidget {
  final _auth = FirebaseAuth.instance;
  final _google = GoogleSignIn();

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return ListView(
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leading: Icon(Icons.logout, color: primaryColor),
            title: Text('Logout', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Confirm Logout'),
                  content: Text('Are you sure you want to log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('Yes'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _auth.signOut();
                await _google.signOut();
                Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
              }
            },
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leading: Icon(Icons.password, color: primaryColor),
            title: Text('Add/Change Password', style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600)),
            onTap: () async {
              final user = _auth.currentUser;
              if (user?.email == null) return;
              await _auth.sendPasswordResetEmail(email: user!.email!);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Email sent to ${user.email} to set password.')),
              );
            },
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leading: Icon(Icons.delete_forever, color: Colors.red),
            title: Text('Delete Account', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Confirm Delete'),
                  content: Text(
                    'This will permanently delete your account and all associated data. Are you sure?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('Yes'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;

              final user = _auth.currentUser;
              if (user == null) return;
              final uid = user.uid;

              // 1. Delete Firestore data
              await FirebaseFirestore.instance.collection('users').doc(uid).delete();

              // 2. Remove setup flag
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('setupComplete_$uid');

              // 3. Delete auth user
              await user.delete();

              // 4. Sign out from providers
              await _auth.signOut();
              await _google.signOut();

              // 5. Navigate back to signup
              Navigator.pushNamedAndRemoveUntil(context, '/signup', (r) => false);
            },
          ),
        ),
      ],
    );
  }
}

class SponsorPage extends StatefulWidget {
  final String referralCode;
  const SponsorPage({required this.referralCode});

  @override
  _SponsorPageState createState() => _SponsorPageState();
}

class _SponsorPageState extends State<SponsorPage> {
  bool _processing = false;
  String? _error;

  Future<void> _handleAccept() async {
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final currentCount = await ReferralService.getSponsorCount().first;
      if (currentCount >= 2) {
        throw Exception('Maximum sponsors reached');
      }
      final referrerId = await ReferralService.claimReferralCode(widget.referralCode);
      if (referrerId == null) {
        throw Exception('Invalid or expired referral code');
      }

      await ReferralService.incrementSponsorCount(referrerId);
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: Text('Sponsorship Request'),
        centerTitle: true,
        elevation: 2,
      ),
      body: Center(
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(color: errorColor, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),
                ],
                Text(
                  'Accept sponsorship invitation?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: onSurface),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _processing ? null : _handleAccept,
                        child: _processing
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text('Accept'),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _processing ? null : () => Navigator.pop(context),
                        child: Text('Decline'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: onSurface,
                          backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}