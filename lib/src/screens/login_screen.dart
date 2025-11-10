import 'package:flutter/material.dart';
import 'package:frontend_flutter/src/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  String _errorMessage = '';
  bool _isLoading = false;
  bool _obscurePassword = true; // Para controlar la visibilidad de la contraseña

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final result = await _authService.signInWithUsernameAndPassword(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (result.credential != null) {
        // Success: AuthWrapper or auth state listener will navigate away.
        setState(() {
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = result.errorMessage ?? 'Credenciales incorrectas. Por favor, inténtalo de nuevo.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Iniciar Sesión', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Usuario', border: OutlineInputBorder()),
                    validator: (value) => value!.isEmpty ? 'Por favor, introduce tu usuario' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Contraseña', 
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (value) => value!.isEmpty ? 'Por favor, introduce tu contraseña' : null,
                  ),
                  const SizedBox(height: 20),
                  if (_errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading ? const CircularProgressIndicator() : const Text('Entrar'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _showForgotPasswordDialog(context),
                    child: const Text('¿Olvidaste la contraseña?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotPasswordDialog(BuildContext parentContext) {
    final emailController = TextEditingController();
    showDialog<void>(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restablecer contraseña'),
        content: TextField(
          controller: emailController,
          decoration: const InputDecoration(
            labelText: 'Introduce tu correo',
            hintText: 'ejemplo@correo.com',
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar')
          ),
          TextButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return;
              
              // Guardamos las referencias antes de cualquier operación asíncrona
              final navigator = Navigator.of(dialogContext);
              final messenger = ScaffoldMessenger.of(parentContext);
              
              final msg = await _authService.sendPasswordResetEmail(email);
              
              // Cerramos el diálogo
              navigator.pop();
              
              // Mostramos el mensaje apropiado
              if (msg == null) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Se ha enviado un enlace de recuperación a su correo electrónico'),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 4),
                  )
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.error, color: Colors.white),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Error: $msg'),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 4),
                  )
                );
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }
}
