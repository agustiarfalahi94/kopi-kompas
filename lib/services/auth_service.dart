import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Who is signed in, if anyone.
sealed class AuthState {
  const AuthState();
}

class SignedOut extends AuthState {
  const SignedOut();
}

class SignedIn extends AuthState {
  const SignedIn(this.uid, {this.label});

  final String uid;

  /// An email, phone number or display name — whatever the provider gave.
  /// Only ever shown back to the user, never used to identify them.
  final String? label;
}

/// Why a sign-in did not complete.
///
/// `cancelled` is deliberately separate: backing out of the Google sheet is
/// not an error and must never show one. Treating it as a failure was a bug
/// in random_recall worth not repeating.
enum AuthError { cancelled, wrongPassword, network, needsLinking, unknown }

class AuthFailure implements Exception {
  const AuthFailure(this.kind, [this.detail]);
  final AuthError kind;
  final String? detail;
}

/// The three sign-in methods, behind one interface.
///
/// Signing in is optional throughout the app: everything works signed out,
/// and an account only buys a backup.
class AuthService {
  AuthService({FirebaseAuth? auth, GoogleSignIn? google})
    : _auth = auth ?? FirebaseAuth.instance,
      _google = google ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  Stream<AuthState> get changes => _auth.authStateChanges().map(_toState);

  AuthState get current => _toState(_auth.currentUser);

  static AuthState _toState(User? u) => u == null
      ? const SignedOut()
      : SignedIn(u.uid, label: u.email ?? u.phoneNumber ?? u.displayName);

  Future<void> signInWithGoogle() async {
    try {
      // google_sign_in 7.x requires initialize() before authenticate(), and
      // the serverClientId from google-services.json — omitting it is the
      // classic cause of a sign-in that works in debug and fails in release.
      await _google.initialize();
      final account = await _google.authenticate();
      final auth = account.authentication;
      await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: auth.idToken),
      );
    } on GoogleSignInException catch (e) {
      // Backing out of the sheet is not a failure worth reporting.
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure(AuthError.cancelled);
      }
      throw AuthFailure(AuthError.unknown, e.description);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebase(e);
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapFirebase(e);
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapFirebase(e);
    }
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  /// Sends the SMS code. [onCodeSent] hands back the verification id that
  /// [confirmPhoneCode] needs.
  Future<void> startPhoneSignIn(
    String phoneNumber, {
    required void Function(String verificationId) onCodeSent,
    required void Function(AuthFailure) onFailed,
  }) => _auth.verifyPhoneNumber(
    phoneNumber: phoneNumber.trim(),
    // Android can verify some numbers without an SMS at all.
    verificationCompleted: (credential) =>
        _auth.signInWithCredential(credential),
    verificationFailed: (e) => onFailed(_mapFirebase(e)),
    codeSent: (id, _) => onCodeSent(id),
    codeAutoRetrievalTimeout: (_) {},
  );

  Future<void> confirmPhoneCode(String verificationId, String code) async {
    try {
      await _auth.signInWithCredential(
        PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: code.trim(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      throw _mapFirebase(e);
    }
  }

  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }

  static AuthFailure _mapFirebase(FirebaseAuthException e) => switch (e.code) {
    'wrong-password' ||
    'invalid-credential' ||
    'user-not-found' => const AuthFailure(AuthError.wrongPassword),
    'network-request-failed' => const AuthFailure(AuthError.network),
    // The same address already exists under a different provider. This
    // needs the linking flow, not an error message.
    'account-exists-with-different-credential' => const AuthFailure(
      AuthError.needsLinking,
    ),
    _ => AuthFailure(AuthError.unknown, e.message),
  };
}
