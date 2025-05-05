import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Firebase Auth App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/signup',
      routes: {
        '/signup': (_) => SignupPage(),
        '/login': (_) => LoginPage(),
        '/forgot': (_) => ForgotPasswordPage(),
        '/verifyAccount': (_) => VerifyAccountPage(),
        '/setup': (_) => SetupPage(),
        '/home': (_) => HomePage(),
      },
    );
  }
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
      await FirebaseAuth.instance.signInWithCredential(credential);
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
    return Scaffold(
      appBar: AppBar(title: Text('Signup')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _firstNameController,
                decoration: InputDecoration(labelText: 'First Name'),
              ),
              TextField(
                controller: _lastNameController,
                decoration: InputDecoration(labelText: 'Last Name'),
              ),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _signup,
                child: Text('Signup with email'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _signUpWithGoogle,
                child: Text('Continue with Google'),
              ),
              // SizedBox(height: 10),
              // ElevatedButton(
              //   onPressed: _signUpWithApple,
              //   child: Text('Continue with Apple'),
              // ),
              // SizedBox(height: 10),
              // ElevatedButton(
              //   onPressed: _signUpWithFacebook,
              //   child: Text('Continue with Facebook'),
              // ),
              SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                child: Text('Go to login'),
              ),
            ],
          ),
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
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _login,
                child: Text('Login with email'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loginWithGoogle,
                child: Text('Continue with Google'),
              ),
              // SizedBox(height: 10),
              // ElevatedButton(
              //   onPressed: _loginWithApple,
              //   child: Text('Continue with Apple'),
              // ),
              // SizedBox(height: 10),
              // ElevatedButton(
              //   onPressed: _loginWithFacebook,
              //   child: Text('Continue with Facebook'),
              // ),
              SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
                child: Text('Go to signup'),
              ),
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/forgot'),
                child: Text('Forgot password'),
              ),
            ],
          ),
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
    return Scaffold(
      appBar: AppBar(title: Text('Forgot Password')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _resetPassword,
              child: Text('Send reset email'),
            ),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
              child: Text('Back to login'),
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
    return Scaffold(
      appBar: AppBar(title: Text('Verify Account')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Center(child: ElevatedButton(onPressed: _resendEmail, child: Text('Resend email'))),
            Center(child: ElevatedButton(onPressed: _continue, child: Text('Continue'))),
            Center(child: TextButton(onPressed: _restart, child: Text('Restart signup'))),
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

  // Stage 1 & 2 (phone)
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _smsController = TextEditingController();
  String? _verificationId;

  // Stage 3 (dob & gender)
  final TextEditingController _dobController = TextEditingController();
  String? _gender;

  // Stage 4 (driver?)
  bool? _wantsToDrive;

  // Stage 5 (car model)
  final TextEditingController _carModelController = TextEditingController();

  // Stage 6 (location)
  String? _location;

  User? get _user => FirebaseAuth.instance.currentUser;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<void> _nextStage() async {
    final uid = _user!.uid;
    final batch = _db.batch();
    final doc = _db.collection('users').doc(uid);

    switch (_stage) {
      case 1:
        // will be triggered by verifyPhone() or skip
        break;
      case 2:
        // verify SMS code & link phone
        if (_smsController.text.trim().isNotEmpty && _verificationId != null) {
          final cred = PhoneAuthProvider.credential(
            verificationId: _verificationId!,
            smsCode: _smsController.text.trim(),
          );
          await _user!.linkWithCredential(cred);
          batch.set(doc, {'phone': _phoneController.text.trim()}, SetOptions(merge: true));
        }
        break;
      case 3:
        if (_dobController.text.trim().isNotEmpty) {
          batch.set(doc, {'dob': _dobController.text.trim()}, SetOptions(merge: true));
        }
        if (_gender != null) {
          batch.set(doc, {'gender': _gender}, SetOptions(merge: true));
        }
        break;
      case 4:
        if (_wantsToDrive != null) {
          batch.set(doc, {'wantsToDrive': _wantsToDrive}, SetOptions(merge: true));
        }
        break;
      case 5:
        if (_carModelController.text.trim().isNotEmpty) {
          batch.set(doc, {'carModel': _carModelController.text.trim()}, SetOptions(merge: true));
        }
        break;
      case 6:
        if (_location != null) {
          batch.set(doc, {'location': _location}, SetOptions(merge: true));
        }
        break;
    }

    await batch.commit();

    setState(() {
      if (_stage < 6) {
        if (_stage == 4) {
          _stage = _wantsToDrive == true ? 5 : 6;
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
        case 3:
          _stage = 1;
          break;
        case 4:
          _stage = 3;
          break;
        case 5:
          _stage = 4;
          break;
        case 6:
          _stage = (_wantsToDrive == true) ? 5 : 4;
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
          _stage = 2;
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
    Widget content;
    switch (_stage) {
      case 1:
        content = Column(
          children: [
            TextField(
              controller: _phoneController,
              decoration: InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(onPressed: _verifyPhone, child: Text('Verify Phone')),
                TextButton(
                  onPressed: () => setState(() => _stage = 3),
                  child: Text('Skip'),
                ),
              ],
            ),
          ],
        );
        break;

      case 2:
        content = Column(
          children: [
            TextField(
              controller: _smsController,
              decoration: InputDecoration(labelText: 'SMS Code'),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton(onPressed: _nextStage, child: Text('Continue')),
          ],
        );
        break;

      case 3:
        content = Column(
          children: [
            TextField(
              controller: _dobController,
              decoration: InputDecoration(labelText: 'Date of Birth'),
              readOnly: true,
              onTap: _pickDob,
            ),
            DropdownButtonFormField<String>(
              value: _gender,
              items: ['Male', 'Female', 'Other']
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _gender = v),
              decoration: InputDecoration(labelText: 'Gender'),
            ),
            ElevatedButton(onPressed: _nextStage, child: Text('Continue')),
          ],
        );
        break;

      case 4:
        content = Column(
          children: [
            Text('Do you want to become a driver?'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Radio<bool>(
                  value: true,
                  groupValue: _wantsToDrive,
                  onChanged: (v) => setState(() => _wantsToDrive = v),
                ),
                Text('Yes'),
                Radio<bool>(
                  value: false,
                  groupValue: _wantsToDrive,
                  onChanged: (v) => setState(() => _wantsToDrive = v),
                ),
                Text('No'),
              ],
            ),
            ElevatedButton(onPressed: _nextStage, child: Text('Continue')),
          ],
        );
        break;

      case 5:
        content = Column(
          children: [
            TextField(
              controller: _carModelController,
              decoration: InputDecoration(labelText: 'Car Model'),
            ),
            ElevatedButton(onPressed: _nextStage, child: Text('Continue')),
          ],
        );
        break;

      case 6:
        content = Column(
          children: [
            DropdownButtonFormField<String>(
              value: _location,
              items: ['New York', 'Los Angeles', 'Chicago']
                  .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                  .toList(),
              onChanged: (v) => setState(() => _location = v),
              decoration: InputDecoration(labelText: 'Where do you live?'),
            ),
            ElevatedButton(onPressed: _nextStage, child: Text('Finish')),
          ],
        );
        break;

      default:
        content = SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Setup — Stage $_stage of 6'),
        leading: _stage > 1
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: _prevStage,
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(child: content),
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

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  bool _canAddPassword = false;

  @override
  void initState() {
    super.initState();
    _checkIfCanAddPassword();
  }

  Future<void> _checkIfCanAddPassword() async {
    final user = _auth.currentUser;
    if (user != null) {
      final hasPassword = user.providerData
          .any((p) => p.providerId == EmailAuthProvider.PROVIDER_ID);
      setState(() => _canAddPassword = !hasPassword);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _logout,
              child: Text('Logout'),
            ),
            ElevatedButton(
              onPressed: _canAddPassword ? _sendSetPasswordEmail : null,
              child: Text('Add/Change Account Password'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _sendSetPasswordEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No signed-in user or email found.')),
      );
      return;
    }

    try {
      await _auth.sendPasswordResetEmail(email: user.email!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'An email has been sent to ${user.email!}. '
            'Click the link to set your password.',
          ),
        ),
      );
      setState(() {
        // disable button until they sign out/sign back in
        _canAddPassword = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending email: $e')),
      );
    }
  }
}