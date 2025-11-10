import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:frontend_flutter/src/screens/login_screen.dart';
import 'package:frontend_flutter/src/services/auth_service.dart';

class ProtectedRoute extends StatelessWidget {
  final Widget child;

  const ProtectedRoute({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final user = snapshot.data;

        if (user != null && !user.isAnonymous) {
          return child;
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
