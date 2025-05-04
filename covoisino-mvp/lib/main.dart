import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
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
      Navigator.pushReplacementNamed(context, '/home');
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
      Navigator.pushReplacementNamed(context, '/home');
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
        Navigator.pushReplacementNamed(context, '/home');
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
                child: Text('Signup with Google'),
              ),
              // SizedBox(height: 10),
              // ElevatedButton(
              //   onPressed: _signUpWithApple,
              //   child: Text('Signup with Apple'),
              // ),
              // SizedBox(height: 10),
              // ElevatedButton(
              //   onPressed: _signUpWithFacebook,
              //   child: Text('Signup with Facebook'),
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
          Navigator.pushReplacementNamed(context, '/home');
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
      Navigator.pushReplacementNamed(context, '/home');
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
      Navigator.pushReplacementNamed(context, '/home');
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
        Navigator.pushReplacementNamed(context, '/home');
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
                child: Text('Login with Google'),
              ),
              // SizedBox(height: 10),
              // ElevatedButton(
              //   onPressed: _loginWithApple,
              //   child: Text('Login with Apple'),
              // ),
              // SizedBox(height: 10),
              // ElevatedButton(
              //   onPressed: _loginWithFacebook,
              //   child: Text('Login with Facebook'),
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
      Navigator.pushReplacementNamed(context, '/home');
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
    User? user = _auth.currentUser;

    if (user != null) {
      bool hasPassword = user.providerData.any((provider) => provider.providerId == 'password');
      setState(() {
        _canAddPassword = !hasPassword;
      });
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
              onPressed: () async {
                await _auth.signOut();
                await _googleSignIn.signOut();
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: Text('Logout'),
            ),
            ElevatedButton(
              onPressed: _canAddPassword
                  ? () async {
                      await _addPasswordToAccount(context);
                    }
                  : null, // Disabled if false
              child: Text('Add Password to Account'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPasswordToAccount(BuildContext context) async {
    User? user = _auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You need to be signed in to add a password.')),
      );
      return;
    }

    if (user.providerData.every((provider) => provider.providerId != 'password')) {
      _showAddPasswordDialog(context, user);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You already have a password set up.')),
      );
    }
  }

  void _showAddPasswordDialog(BuildContext context, User user) {
    final TextEditingController _passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Set a Password'),
          content: TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(hintText: 'Enter a new password'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                String password = _passwordController.text.trim();
                if (password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please enter a password.')),
                  );
                  return;
                }

                try {
                  final googleUser = await _googleSignIn.signIn();
                  if (googleUser == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Google sign-in failed.')),
                    );
                    return;
                  }

                  final googleAuth = await googleUser.authentication;
                  final accessToken = googleAuth.accessToken;
                  final idToken = googleAuth.idToken;

                  if (accessToken == null || idToken == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to get authentication tokens.')),
                    );
                    return;
                  }

                  final credential = GoogleAuthProvider.credential(
                    accessToken: accessToken,
                    idToken: idToken,
                  );

                  await user.reauthenticateWithCredential(credential);
                  await user.updatePassword(password);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Password added successfully!')),
                  );

                  setState(() {
                    _canAddPassword = false; // Update UI to reflect new password state
                  });

                  Navigator.of(context).pop();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to add password: $e')),
                  );
                }
              },
              child: Text('Set Password'),
            ),
          ],
        );
      },
    );
  }
}
