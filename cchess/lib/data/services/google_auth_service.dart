import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google Sign-In wrapper for `google_sign_in` 7.x + `firebase_auth` 6.x.
///
/// Use case: link an anonymous Firebase user to a permanent Google identity.
/// Keeps the same uid (and therefore all cloud data) when linking succeeds.
class GoogleAuthService {
  GoogleAuthService(this._auth);
  final FirebaseAuth _auth;

  /// Web OAuth client id (client_type 3) from `google-services.json`.
  /// Required for Android to receive an id_token Firebase can verify.
  static const String _webClientId =
      '1063038096342-vlcb8vthqi6r580sut3f9h5gqpah3apu.apps.googleusercontent.com';

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _initialized = true;
  }

  Future<String> _getGoogleIdToken() async {
    await _ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'no-id-token',
        message: 'Google không trả về id_token. Kiểm tra serverClientId.',
      );
    }
    return idToken;
  }

  /// Link the current (anonymous) Firebase user to a Google account.
  /// Same uid is preserved on success.
  ///
  /// Throws [FirebaseAuthException] with code `credential-already-in-use`
  /// if this Google account is already attached to a different Firebase
  /// user — in that case fall back to [signInWithGoogle] (which loses
  /// the anonymous data but switches to the existing account).
  Future<UserCredential> linkAnonymousWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Cần đăng nhập (ẩn danh) trước khi liên kết.',
      );
    }
    final idToken = await _getGoogleIdToken();
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return await user.linkWithCredential(credential);
  }

  /// Sign in with Google as a full replacement of the current session.
  /// Use only when linking is impossible (`credential-already-in-use`).
  Future<UserCredential> signInWithGoogle() async {
    final idToken = await _getGoogleIdToken();
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return await _auth.signInWithCredential(credential);
  }

  /// Sign out of Google on the device (doesn't sign out Firebase).
  Future<void> signOutGoogle() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
  }
}

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  return GoogleAuthService(FirebaseAuth.instance);
});
