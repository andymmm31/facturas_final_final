import 'package:flutter/material.dart';
import 'package:frontend_flutter/src/services/auth_service.dart';

class ChangePasswordWidget extends StatefulWidget {
  const ChangePasswordWidget({super.key});

  @override
  _ChangePasswordWidgetState createState() => _ChangePasswordWidgetState();
}

class _ChangePasswordWidgetState extends State<ChangePasswordWidget> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSaving = false;
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    // Validate that new and confirm match
    if (_newController.text != _confirmController.text) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La nueva contraseña y su confirmación no coinciden')));
      return;
    }

    final err = await _authService.changePassword(_currentController.text, _newController.text);
    setState(() => _isSaving = false);
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña actualizada')));
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar contraseña')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _currentController,
                decoration: const InputDecoration(labelText: 'Contraseña actual'),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? 'Introduce la contraseña actual' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newController,
                decoration: const InputDecoration(labelText: 'Nueva contraseña'),
                obscureText: true,
                validator: (v) => v == null || v.length < 6 ? 'La contraseña debe tener al menos 6 caracteres' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                decoration: const InputDecoration(labelText: 'Confirmar nueva contraseña'),
                obscureText: true,
                validator: (v) => v == null || v.length < 6 ? 'Confirma la nueva contraseña' : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _changePassword,
                  child: _isSaving ? const CircularProgressIndicator() : const Text('Cambiar contraseña'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
