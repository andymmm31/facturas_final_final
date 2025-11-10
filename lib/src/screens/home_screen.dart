import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:frontend_flutter/src/services/auth_service.dart';
import 'package:frontend_flutter/src/widgets/company_management_widget.dart';
import 'package:frontend_flutter/src/widgets/invoice_form_widget.dart';
import 'package:frontend_flutter/src/widgets/report_widget.dart';
import 'package:frontend_flutter/src/widgets/protected_route.dart';
import 'package:frontend_flutter/src/widgets/change_password_widget.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestión de Facturas'),
          actions: [
            StreamBuilder<User?>(
              stream: authService.user,
              builder: (context, snapshot) {
                final user = snapshot.data;
                if (user != null && !user.isAnonymous) {
                  return Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.lock),
                        tooltip: 'Cambiar contraseña',
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordWidget())),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout),
                        onPressed: () => authService.signOut(),
                      ),
                    ],
                  );
                } else {
                  return const SizedBox.shrink();
                }
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.business), text: 'Empresas'),
              Tab(icon: Icon(Icons.receipt), text: 'Registrar'),
              Tab(icon: Icon(Icons.analytics), text: 'Reportes'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ProtectedRoute(child: CompanyManagementWidget()),
            InvoiceFormWidget(),
            ProtectedRoute(child: ReportWidget()),
          ],
        ),
      ),
    );
  }
}
