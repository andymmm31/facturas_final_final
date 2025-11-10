import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:frontend_flutter/firebase_options.dart';
import 'package:frontend_flutter/src/services/company_service.dart';

class CompanyManagementWidget extends StatefulWidget {
  const CompanyManagementWidget({super.key});

  @override
  _CompanyManagementWidgetState createState() => _CompanyManagementWidgetState();
}

class _CompanyManagementWidgetState extends State<CompanyManagementWidget> {
  final _companyNameController = TextEditingController();
  late final CompanyService _companyService;
  bool _isAdding = false;
  bool _debugShowDocs = false;

  @override
  void initState() {
    super.initState();
    _companyService = CompanyService(DefaultFirebaseOptions.currentPlatform.projectId);
  }

  void _addCompany() {
    final name = _companyNameController.text.trim();
    if (name.isEmpty) return;
    _addCompanyAsync(name);
  }

  Future<void> _addCompanyAsync(String name) async {
    setState(() {
      _isAdding = true;
    });
    final docPath = await _companyService.addCompany(name);
    if (docPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Empresa añadida: $docPath')));
      _companyNameController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al añadir la empresa')));
    }
    setState(() {
      _isAdding = false;
    });
  }

  void _showEditDialog(String oldName) {
    final editController = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Editar Empresa'),
          content: TextFormField(
            controller: editController,
            decoration: const InputDecoration(labelText: 'Nuevo nombre'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (editController.text.isNotEmpty) {
                  _companyService.editCompany(oldName, editController.text);
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteDialog(String companyName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar Empresa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿Está seguro que desea eliminar la empresa "$companyName"?'),
              const SizedBox(height: 16),
              const Text('¿Desea eliminar también todas las facturas asociadas a esta empresa?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                _companyService.deleteCompany(companyName, deleteInvoices: false);
                Navigator.of(context).pop();
              },
              child: const Text('Solo la Empresa'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                _companyService.deleteCompany(companyName, deleteInvoices: true);
                Navigator.of(context).pop();
              },
              child: const Text('Empresa y Facturas'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildClientsSection(String companyName) {
    return StreamBuilder<QuerySnapshot>(
      stream: _companyService.getClientsStream(companyName),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          ));
        }
        
        final clients = snap.data?.docs ?? [];
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (clients.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'No hay clientes registrados',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ...clients.map((client) {
              final data = client.data() as Map<String, dynamic>;
              final name = data['name']?.toString() ?? '(sin nombre)';
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline, size: 20),
                  title: Text(name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        iconSize: 18,
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () {
                          final editController = TextEditingController(text: name);
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Editar Cliente'),
                              content: TextFormField(
                                controller: editController,
                                decoration: const InputDecoration(labelText: 'Nombre'),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    if (editController.text.isNotEmpty) {
                                      _companyService.editClient(companyName, name, editController.text);
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  child: const Text('Guardar'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      IconButton(
                        iconSize: 18,
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Confirmar'),
                            content: Text('¿Eliminar cliente "$name"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () {
                                  _companyService.deleteClient(companyName, name);
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            // Botón para agregar cliente
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Agregar Cliente'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal,
                ),
                onPressed: () {
                  final addController = TextEditingController();
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Agregar Cliente'),
                      content: TextFormField(
                        controller: addController,
                        decoration: const InputDecoration(labelText: 'Nombre del cliente'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            if (addController.text.isNotEmpty) {
                              _companyService.addClient(companyName, addController.text);
                              Navigator.of(context).pop();
                            }
                          },
                          child: const Text('Agregar'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gestionar Empresas', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _companyNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la nueva empresa',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isAdding ? null : _addCompany,
                child: _isAdding
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Empresas y Clientes', style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                tooltip: 'Toggle debug',
                icon: Icon(_debugShowDocs ? Icons.bug_report : Icons.bug_report_outlined),
                onPressed: () => setState(() => _debugShowDocs = !_debugShowDocs),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _companyService.getCompaniesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No hay empresas registradas.'));
                }

                var companies = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: companies.length,
                  itemBuilder: (context, index) {
                    var company = companies[index];
                    String companyName = '(sin nombre)';
                    try {
                      final data = company.data() as Map<String, dynamic>;
                      if (data.containsKey('name') && data['name'] != null) {
                        companyName = data['name'].toString();
                      }
                    } catch (_) {}

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Cabecera de empresa con color de fondo
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.teal[50],
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8),
                              ),
                            ),
                            child: ListTile(
                              leading: Icon(Icons.business, color: Colors.teal[700]),
                              title: Text(
                                companyName,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    color: Colors.blue,
                                    onPressed: () => _showEditDialog(companyName),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    color: Colors.red,
                                    onPressed: () => _showDeleteDialog(companyName),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Sección de clientes con borde y sangría
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(8),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Encabezado de la sección de clientes
                                Container(
                                  padding: const EdgeInsets.all(8.0),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    border: Border(
                                      bottom: BorderSide(color: Colors.grey[300]!),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.people, size: 20, color: Colors.grey[700]),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Clientes',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Lista de clientes
                                _buildClientsSection(companyName),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}