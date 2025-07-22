import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';

final _uuid = Uuid();

Future<String> signup(email, password) async {
  try {
    UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = userCredential.user;

    await FirebaseFirestore.instance.collection('users').doc(user?.uid).set({
      'completedSetup': false,
      'driver': false,
      'carModel': null,
      'phoneNumber': null,
      'firstName': null,
      'lastName': null,
      'sponsorsCount': 0,
      'sponsorshipVisibility': false,
      'autoDriveModeOn': false,
    });

    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<String> login(email, password) async {
  try {
    UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    User? user = userCredential.user;
    if (user != null && user.emailVerified) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        bool completedSetup = userDoc.get('completedSetup') ?? false;
        if (completedSetup == true) {
          return "";
        } else {
          return "SetupPage";
        }
      } else {
        return "SetupPage";
      }
    }
    return "VerifyAccountPage";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<String> continueWithGoogle() async {
  try {
    GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();
    GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) return "Unable to signup using Google.";

    GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
    User? user = userCredential.user;
    if (user != null) {
      DocumentReference userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      DocumentSnapshot userDoc = await userDocRef.get();
      if (userDoc.exists) {
        bool completedSetup = userDoc.get('completedSetup') ?? false;
        if (completedSetup == true) {
          return "";
        } else {
          return "SetupPage";
        }
      } else {
        await userDocRef.set({
          'completedSetup': false,
          'driver': false,
          'carModel': null,
          'phoneNumber': null,
          'firstName': null,
          'lastName': null,
          'sponsorsCount': 0,
          'sponsorshipVisibility': false,
          'autoDriveModeOn': false,
        });
        return "SetupPage";
      }
    }
    return "Unable to signup using Google.";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<String> sendPasswordResetEmail(email) async {
  try {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<String> sendVerificationEmail() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return "Unable to send verification email";
    await user.sendEmailVerification();
    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<String> continueToSetup() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return "Unable to continue to setup";
    await user.reload();
    final updatedUser = FirebaseAuth.instance.currentUser;
    if (updatedUser?.emailVerified == true) {
      return "";
    }
    return "Unable to continue to setup";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<String> writeToUsersCollection(payload) async {
  try {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return "Unable to write to Firestore";
    await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .set(payload, SetOptions(merge: true));
    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

String? _verificationId;

Future<String> verifyPhoneNumber(String phoneNumber) async {
  try {
    final completer = Completer<String>();

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await FirebaseAuth.instance.signInWithCredential(credential);
          completer.complete("");
        } catch (e) {
          completer.complete("Auto-verification failed: ${e.toString()}");
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        completer.complete("Verification failed: ${e.message}");
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        completer.complete("");
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );

    return await completer.future;
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<String> verifySMSCode(String smsCode) async {
  try {
    if (_verificationId == null) {
      return "Verification ID not found. Please try verifying your phone number again.";
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: smsCode,
    );

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return "No user is currently signed in.";
    }

    final phoneNumber = getPhoneNumber() ?? "";
    if (phoneNumber.trim().isEmpty) {
      await user.linkWithCredential(credential);
    } else {
      await user.updatePhoneNumber(credential);
    }

    await writeToUsersCollection({"phoneNumber":getPhoneNumber()});

    return "";
  } on FirebaseAuthException catch (e) {
    if (e.code == 'provider-already-linked') {
      return "Phone number is already linked to this account.";
    } else if (e.code == 'credential-already-in-use') {
      return "This phone number is already linked to another account.";
    }
    return "Failed to verify SMS code: ${e.message}";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

String? getPhoneNumber() {
  try {
    User? user = FirebaseAuth.instance.currentUser;
    return user?.phoneNumber;
  } catch (e) {
    return "";
  }
}

String logout() {
  try {
    FirebaseAuth.instance.signOut();
    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<String> addOrChangePassword() async {
  try {
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return "No user is currently signed in.";
    }

    String? email = user.email;

    if (email == null || email.isEmpty) {
      return "No email is associated with this account.";
    }

    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<String> deleteAccount() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return "Unable to delete account";

    final uid = user.uid;
    final firestore = FirebaseFirestore.instance;
    final userDocRef = firestore.collection('users').doc(uid);

    await userDocRef.delete();
    await user.delete();
    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Stream<int> getSponsorsCountStream() {
  try {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseFirestore.instance
      .collection('users')
      .doc(user?.uid)
      .snapshots()
      .map((snapshot) {
        final data = snapshot.data();
        return (data?['sponsorsCount'] ?? 0) as int;
      });
  } catch (e) {
    return Stream.value(0);
  }
}

Future<Map<String,dynamic>?> getFromUsersCollection() async {
  try {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return {};

    final docSnapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .get();

    if (docSnapshot.exists) {
      return docSnapshot.data();
    } else {
      return {};
    }
  } catch (e) {
    return {};
  }
}

Stream<List<Map<String,String>>> getVisibleSponsorsStream() {
  try {
    return FirebaseFirestore.instance
      .collection('users')
      .where('sponsorshipVisibility', isEqualTo: true)
      .where('sponsorsCount', isGreaterThanOrEqualTo: 2)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          return {
            'uid': doc.id,
            'name': '${doc['firstName']} ${doc['lastName']}',
          };
        }).toList();
      });
  } catch (e) {
    return Stream.value([]);
  }
}

Future<String> sendSponsorshipRequest(String toUid) async {
  try {
    final fromUid = FirebaseAuth.instance.currentUser?.uid;
    final requestsRef = FirebaseFirestore.instance.collection('sponsorshipRequests');
    final existing = await requestsRef
      .where('fromUid', isEqualTo: fromUid)
      .where('toUid', isEqualTo: toUid)
      .where('status', isNotEqualTo: 'declined') // optional: only block pending ones
      .limit(1)
      .get();
    if (existing.docs.isNotEmpty) return "A request already exists from $fromUid to $toUid";

    final fromUserDoc = await FirebaseFirestore.instance.collection('users').doc(fromUid).get();
    if (!fromUserDoc.exists) return "User profile not found";
    final firstName = fromUserDoc.data()?['firstName'] ?? '';
    final lastName = fromUserDoc.data()?['lastName'] ?? '';
    final fullName = "$firstName $lastName";

    final requestData = {
      'fromUid': fromUid,
      'fromFullName': fullName,
      'toUid': toUid,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'pending',
    };
    await requestsRef.add(requestData);
    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Stream<List<Map<String,String>>> getSponsorshipRequestsStream() {
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return Stream.value([]);

    return FirebaseFirestore.instance
      .collection('sponsorshipRequests')
      .where('toUid', isEqualTo: currentUser.uid)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          return {
            'id': doc.id,
            'fromFullName': '${doc['fromFullName']}',
          };
        }).toList();
      });
  } catch (e) {
    return Stream.value([]);
  }
}

Future<String> updateSponsorshipRequestStatus(String requestId, String requestStatus) async {
  try {
    final requestRef = FirebaseFirestore.instance.collection('sponsorshipRequests').doc(requestId);

    // First, check if the request exists and its current status
    final doc = await requestRef.get();
    if (!doc.exists) {
      return "Sponsorship request not found.";
    }
    final currentStatus = doc.get('status');
    if (currentStatus != 'pending') {
      return "Sponsorship request is not pending.";
    }

    final fromUid = doc.get('fromUid');
    final toUid = doc.get('toUid');
    if (requestStatus == "accepted") {
      final alreadySponsored = await sponsorshipAlreadyExists(fromUid, toUid);
      if (alreadySponsored) return "Sponsorship already exists";
    }

    // Update status to accepted
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      transaction.update(requestRef, {'status': requestStatus});

      if (requestStatus == "accepted") {
        final sponsorshipRef = FirebaseFirestore.instance.collection('sponsorships').doc();
        transaction.set(sponsorshipRef, {
          'sponseeUid': fromUid,
          'sponsorUid': toUid,
          'createdAt': FieldValue.serverTimestamp(),
          'method': 'request',
        });
      }
    });

    if (fromUid == null || fromUid.isEmpty) {
      return "Invalid sender UID.";
    }

    if (requestStatus == "accepted") {
      String status = await incrementSponsorsCount(fromUid);
      if (status == "") {
        return "";
      }
    }
    if (requestStatus == "declined") return "";
    return "Unable to process sponsorship request";  // success
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<List<String>> getSponsorshipHistory() async {
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    final currentUserUid = currentUser.uid;

    // Query sponsorshipRequests where fromUid == currentUserUid and status is accepted or declined
    final querySnapshot = await FirebaseFirestore.instance
        .collection('sponsorshipRequests')
        .where('fromUid', isEqualTo: currentUserUid)
        .where('status', whereIn: ['accepted', 'declined'])
        .get();

    // To avoid many reads, fetch user data in bulk
    final toUids = querySnapshot.docs.map((doc) => doc['toUid'] as String).toSet().toList();

    if (toUids.isEmpty) return [];

    // Fetch user docs of all toUids
    final userDocs = await Future.wait(
      toUids.map((uid) => FirebaseFirestore.instance.collection('users').doc(uid).get())
    );

    // Map user docs to names
    List<String> names = [];
    for (final doc in userDocs) {
      if (doc.exists) {
        final data = doc.data();
        final firstName = data?['firstName'] ?? '';
        final lastName = data?['lastName'] ?? '';
        final fullName = '$firstName $lastName'.trim();
        if (fullName.isNotEmpty) {
          names.add(fullName);
        }
      }
    }

    return names;
  } catch (e) {
    return [];
  }
}

Future<String> generateSponsorshipInviteLink() async {
  final user = FirebaseAuth.instance.currentUser!;
  const duration = Duration(hours: 24);
  
  final code = _uuid.v4().substring(0, 8);
  await FirebaseFirestore.instance.collection('referralLinks').doc(code).set({
    'creator': user.uid,
    'createdAt': FieldValue.serverTimestamp(),
    'expiresAt': Timestamp.fromDate(DateTime.now().add(duration)),
    'used': false,
    'usedBy': null,
  });

  return 'https://covoisino.github.io/referral.html?code=$code';
}

Future<String?> acceptSponsorshipInvite(code) async {
  final success = await FirebaseFirestore.instance.runTransaction<bool>((transaction) async {
    final ref = FirebaseFirestore.instance.collection('referralLinks').doc(code);
    final doc = await transaction.get(ref);

    if (!doc.exists || doc['used'] || doc['expiresAt'].toDate().isBefore(DateTime.now())) {
      return false;
    }

    final alreadySponsored = await sponsorshipAlreadyExists(FirebaseAuth.instance.currentUser!.uid, doc['creator']);
    if (alreadySponsored) return false;

    transaction.update(ref, {
      'used': true,
      'usedBy': FirebaseAuth.instance.currentUser!.uid,
      'usedAt': FieldValue.serverTimestamp(),
    });

    final sponsorshipRef = FirebaseFirestore.instance.collection('sponsorships').doc();
    transaction.set(sponsorshipRef, {
      'sponseeUid': FirebaseAuth.instance.currentUser!.uid,
      'sponsorUid': doc['creator'],
      'createdAt': FieldValue.serverTimestamp(),
      'method': 'referral',
    });

    return true;
  });

  if (!success) return "Unable to accept sponsorship invite";

  String status = await incrementSponsorsCount(FirebaseAuth.instance.currentUser!.uid);
  if (status == "") {
    return "";
  }
  return "Unable to accept sponsorship invite";
}

Future<String> incrementSponsorsCount(String id) async {
  try {
    final userRef = FirebaseFirestore.instance.collection('users').doc(id);

    final userDoc = await userRef.get();
    if (!userDoc.exists) {
      return "User not found";
    }

    final currentCount = userDoc.data()?['sponsorsCount'] ?? 0;

    if (currentCount >= 2) {
      return "You can't have more than 2 sponsors.";
    }

    await userRef.update({
      'sponsorsCount': FieldValue.increment(1),
    });

    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Future<bool> sponsorshipAlreadyExists(String sponseeUid, String sponsorUid) async {
  final query = await FirebaseFirestore.instance
      .collection('sponsorships')
      .where('sponseeUid', isEqualTo: sponseeUid)
      .where('sponsorUid', isEqualTo: sponsorUid)
      .limit(1)
      .get();

  return query.docs.isNotEmpty;
}

Future<void> checkAndRequestLocationPermission() async {
  LocationPermission permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception('Location permissions are permanently denied. Please enable them in app settings.');
  }

  // Permission granted
}

Stream<Map<String, DriverMarkerInformation>> getDriverMarkerInformationsStream() {
  final userId = FirebaseAuth.instance.currentUser?.uid ?? "";

  final dbRef = FirebaseDatabase.instance.ref("users_locations");

  return dbRef.onValue.map((event) {
    final data = event.snapshot.value as Map<dynamic, dynamic>?;

    if (data == null) return {};

    return data.map<String, DriverMarkerInformation>((key, value) {
      final valueMap = value as Map<dynamic, dynamic>;
      final isYou = userId == key;
      final latitude = (valueMap['latitude'] as num).toDouble();
      final longitude = (valueMap['longitude'] as num).toDouble();
      final carModel = valueMap['carModel'];
      final phoneNumber = valueMap['phoneNumber'];
      final firstName = valueMap['firstName'];
      final lastName = valueMap['lastName'];
      return MapEntry(key as String, DriverMarkerInformation(isYou: isYou, latitude: latitude, longitude: longitude, carModel: carModel, phoneNumber: phoneNumber, firstName: firstName, lastName: lastName));
    });
  });
}

Stream<bool> getDriverLocationOnStream() {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(false);
    final ref = FirebaseDatabase.instance.ref('users/${user.uid}/driverLocationOn');

    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      return value == true;
    });
  } catch (e) {
    return Stream.value(false);
  }
}

Future<String> updateDriverLocationOn(bool driverLocationOn) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return 'User not authenticated';
    }

    final ref = FirebaseDatabase.instance.ref('users/${user.uid}/driverLocationOn');
    await ref.set(driverLocationOn);

    return '';
  } catch (e) {
    return 'An unexpected error occurred: ${e.toString()}';
  }
}

Future<String> sendRideRequest(String toUid) async {
  try {
    final fromUid = FirebaseAuth.instance.currentUser?.uid;
    final requestsRef = FirebaseFirestore.instance.collection('rideRequests');
    final fromUserDoc = await FirebaseFirestore.instance.collection('users').doc(fromUid).get();
    if (!fromUserDoc.exists) return "User profile not found";
    final firstName = fromUserDoc.data()?['firstName'] ?? '';
    final lastName = fromUserDoc.data()?['lastName'] ?? '';
    final fullName = "$firstName $lastName";

    final requestData = {
      'fromUid': fromUid,
      'fromFullName': fullName,
      'toUid': toUid,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'pending',
    };
    await requestsRef.add(requestData);
    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

Stream<List<Map<String,String>>> getRideRequestsStream() {
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return Stream.value([]);

    return FirebaseFirestore.instance
      .collection('rideRequests')
      .where('toUid', isEqualTo: currentUser.uid)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          return {
            'id': doc.id,
            'fromFullName': '${doc['fromFullName']}',
          };
        }).toList();
      });
  } catch (e) {
    return Stream.value([]);
  }
}

Future<String> updateRideRequestStatus(String requestId, String requestStatus) async {
  try {
    final requestRef = FirebaseFirestore.instance.collection('rideRequests').doc(requestId);

    // First, check if the request exists and its current status
    final doc = await requestRef.get();
    if (!doc.exists) {
      return "Ride request not found.";
    }
    final currentStatus = doc.get('status');
    if (currentStatus != 'pending') {
      return "Ride request is not pending.";
    }

    final fromUid = doc.get('fromUid');
    final toUid = doc.get('toUid');

    // Update status to accepted
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      transaction.update(requestRef, {'status': requestStatus});
    });

    if (fromUid == null || fromUid.isEmpty) {
      return "Invalid sender UID.";
    }

    return "";
  } catch (e) {
    return "An unexpected error occurred: ${e.toString()}";
  }
}

String scanQRCode() {
  return "";
}

String createQRCode() {
  return "";
}

String makeEmergencyCall() {
  return "";
}

String shareLocation() {
  return "";
}

class SetupPageStageNotifier extends StateNotifier<int> {
  SetupPageStageNotifier() : super(0) {
    _loadStage();
  }

  void _loadStage() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('setup_stage') ?? 0;
  }

  void setStage(int stage) async {
    state = stage;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('setup_stage', state);
  }
}

class UsersCollectionNotifier extends StateNotifier<UserModel?> {
  UsersCollectionNotifier() : super(null) {
    loadUsersCollection();
  }

  Future<void> loadUsersCollection() async {
    final usersCollection = await getFromUsersCollection();
    if (usersCollection != null) {
      state = UserModel.fromMap(usersCollection);
    }
  }

  void updateDriver(bool driver) {
    if (state != null) {
      state = state!.copyWith(driver: driver);
    }
  }

  void updateCarModel(String carModel) {
    if (state != null) {
      state = state!.copyWith(carModel: carModel);
    }
  }

  void updateFirstName(String firstName) {
    if (state != null) {
      state = state!.copyWith(firstName: firstName);
    }
  }

  void updateLastName(String lastName) {
    if (state != null) {
      state = state!.copyWith(lastName: lastName);
    }
  }

  void updateSponsorshipVisibility(bool sponsorshipVisibility) {
    if (state != null) {
      state = state!.copyWith(sponsorshipVisibility: sponsorshipVisibility);
    }
  }

  void updateAutoDriveModeOn(bool autoDriveModeOn) {
    if (state != null) {
      state = state!.copyWith(autoDriveModeOn: autoDriveModeOn);
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
      // Optionally queue code until login
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
      navKey.currentState?.pushNamed('/sponsor', arguments: code);
    }
  }
}

class LocationUpdater {
  Timer? _timer;
  bool _shouldUpdate = false;
  bool _firstTimeUpdating = true;

  bool get isRunning => _timer != null;

  void startUpdatingLocation() {
    if (_timer != null) return;

    _shouldUpdate = true;

    // Immediately run the update once

    _updateLocation();

    _timer = Timer.periodic(Duration(seconds: 10), (_) {
      if (_shouldUpdate) {
        _updateLocation();
      }
    });
  }

  Future<void> stopUpdatingLocation() async {
    _shouldUpdate = false;
    _firstTimeUpdating = true;
    _timer?.cancel();
    _timer = null;

    await Future.delayed(Duration(milliseconds: 1000));

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("No authenticated user found.");
        return;
      }
      final userId = user.uid;
      final dbRef = FirebaseDatabase.instance.ref("users_locations/$userId");
      await dbRef.remove();
    } catch (e) {
      print("Error removing location: $e");
    }
  }

  Future<void> _updateLocation() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (!_shouldUpdate || user == null) return;

      final userId = user.uid;

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!_shouldUpdate) return;

      await _updateLocationToFirebase(userId, position.latitude, position.longitude);
    } catch (e) {
      print("Failed to update location: $e");
    }
  }

  Future<void> _updateLocationToFirebase(String userId, double lat, double lon) async {
    final dbRef = FirebaseDatabase.instance.ref("users_locations/$userId");

    if (_firstTimeUpdating) {
      final usersCollection = await getFromUsersCollection();

      await dbRef.set({
        'latitude': lat,
        'longitude': lon,
        'timestamp': ServerValue.timestamp,
        'carModel': usersCollection?['carModel'],
        'phoneNumber': usersCollection?['phoneNumber'],
        'firstName': usersCollection?['firstName'],
        'lastName': usersCollection?['lastName']
      });
    } else {
      await dbRef.update({
        'latitude': lat,
        'longitude': lon,
        'timestamp': ServerValue.timestamp,
      }); 
    }

    _firstTimeUpdating = false;
  }
}

class UserModel {
  final bool driver;
  final String carModel;
  final String firstName;
  final String lastName;
  final bool sponsorshipVisibility;
  final bool autoDriveModeOn;

  UserModel({required this.driver, required this.carModel, required this.firstName, required this.lastName, required this.sponsorshipVisibility, required this.autoDriveModeOn});

  factory UserModel.fromMap(Map<String,dynamic> data) {
    return UserModel(
      driver: data['driver'] ?? false,
      carModel: data['carModel'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      sponsorshipVisibility: data['sponsorshipVisibility'] ?? false,
      autoDriveModeOn: data['autoDriveModeOn'] ?? false,
    );
  }

  UserModel copyWith({
    bool? driver,
    String? carModel,
    String? firstName,
    String? lastName,
    bool? sponsorshipVisibility,
    bool? autoDriveModeOn,
  }) {
    return UserModel(
      driver: driver ?? this.driver,
      carModel: carModel ?? this.carModel,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      sponsorshipVisibility: sponsorshipVisibility ?? this.sponsorshipVisibility,
      autoDriveModeOn: autoDriveModeOn ?? this.autoDriveModeOn,
    );
  }
}

class DriverMarkerInformation {
  final bool isYou;
  final double latitude;
  final double longitude;
  final String carModel;
  final String phoneNumber;
  final String firstName;
  final String lastName;

  DriverMarkerInformation({required this.isYou, required this.latitude, required this.longitude, required this.carModel, required this.phoneNumber, required this.firstName, required this.lastName});

  @override
  String toString() => 'Lat: $latitude, Lng: $longitude';
}