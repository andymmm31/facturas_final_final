import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class SignInResult {
  final UserCredential? credential;
  final String? errorMessage;

  SignInResult({this.credential, this.errorMessage});
}

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  Stream<User?> get user => _firebaseAuth.authStateChanges();

  /// Attempts to sign in using [identifier] and [password].
  ///
  /// [identifier] may be a full email (contains '@') or a username. If it's a
  /// username the service will append the default domain `@invoicereports.com`.
  /// Returns a [SignInResult] containing either the [UserCredential] on success
  /// or an [errorMessage] with firebase's error for display.
  Future<SignInResult> signInWithUsernameAndPassword(String identifier, String password) async {
    try {
      final String email = identifier.contains('@') ? identifier : '$identifier@invoicereports.com';
      final cred = await _firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
      return SignInResult(credential: cred);
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} - ${e.message}');
      // Map some common error codes to friendly messages if desired
      String userMessage = e.message ?? 'Error de autenticación.';
      if (e.code == 'user-not-found') userMessage = 'Usuario no encontrado.';
      if (e.code == 'wrong-password') userMessage = 'Contraseña incorrecta.';
      if (e.code == 'too-many-requests') userMessage = 'Demasiados intentos. Intenta más tarde.';
      return SignInResult(errorMessage: userMessage);
    } catch (e) {
      debugPrint('Unknown auth error: $e');
      return SignInResult(errorMessage: 'Error inesperado durante la autenticación.');
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  /// Sends a password reset email to [email]. Returns null on success or an
  /// error message on failure.
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('Password reset error: ${e.code} - ${e.message}');
      return e.message ?? 'Error enviando email de restablecimiento';
    } catch (e) {
      debugPrint('Unknown password reset error: $e');
      return 'Error inesperado';
    }
  }

  /// Change password for currently signed-in user after reauthentication.
  /// Returns null on success or an error message on failure.
  Future<String?> changePassword(String currentPassword, String newPassword) async {
    final user = _firebaseAuth.currentUser;
    if (user == null || user.email == null) return 'No hay usuario autenticado';
    try {
      final cred = EmailAuthProvider.credential(email: user.email!, password: currentPassword);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('Change password error: ${e.code} - ${e.message}');
      if (e.code == 'wrong-password') return 'Contraseña actual incorrecta';
      return e.message ?? 'Error cambiando la contraseña';
    } catch (e) {
      debugPrint('Unknown change password error: $e');
      return 'Error inesperado';
    }
  }
}
