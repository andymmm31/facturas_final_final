import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:frontend_flutter/firebase_options.dart';
import 'package:frontend_flutter/src/services/company_service.dart';
import 'package:frontend_flutter/src/services/invoice_service.dart';
import 'package:intl/intl.dart';
import 'package:frontend_flutter/src/services/invoice_notifier.dart';

class InvoiceFormWidget extends StatefulWidget {
  const InvoiceFormWidget({super.key});

  @override
  _InvoiceFormWidgetState createState() => _InvoiceFormWidgetState();
}

class _InvoiceFormWidgetState extends State<InvoiceFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _invoiceDateController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _companyController = TextEditingController();
  
  String? _editingInvoiceId;
  bool _isEditing = false;
  bool _isLoading = false;

  late final InvoiceService _invoiceService;
  late final CompanyService _companyService;

  String? _selectedCompany;
  String? _selectedClient;
  DateTime? _selectedInvoiceDate;
  DateTime? _selectedDueDate;
  bool _canSave = false;
  bool _isSaving = false;
  String? _amountError;
  String? _invoiceDateError;
  String? _dueDateError;
  List<String>? _oneTimeCompanies;
  bool _triedOneShot = false;
  String? _oneShotError;
  
  // Nuevos campos para impuestos
  double? _selectedIVA = 21.0; // Por defecto 21%
  final _reController = TextEditingController();
  final _totalController = TextEditingController();
  final _ivaAmountController = TextEditingController();  // Monto del IVA en euros
  final _reAmountController = TextEditingController();   // Monto del RE en euros

  @override
  void initState() {
    super.initState();
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    _invoiceService = InvoiceService(projectId);
    _companyService = CompanyService(projectId);
    _amountController.addListener(() {
      _validateForm();
      _updateTotal();
    });
    _invoiceDateController.addListener(_validateForm);
    _dueDateController.addListener(_validateForm);
    _companyController.addListener(_validateForm);
    _reController.addListener(_updateTotal);
    // Try one-shot load so anonymous users can see companies immediately
    _loadCompaniesOnce();
    // Calcular total inicial
    _updateTotal();
  }

  Future<void> _saveInvoice() async {
    if (!_formKey.currentState!.validate()) return;
    // Validate dates: invoice date must not be after due date
    if (_selectedInvoiceDate == null || _selectedDueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona ambas fechas')));
      return;
    }
    if (_selectedInvoiceDate!.isAfter(_selectedDueDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La fecha de factura no puede ser posterior a la fecha de vencimiento')));
      return;
    }
    if (_selectedClient == null || _selectedClient!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debes seleccionar un cliente')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final amount = double.parse(_amountController.text.replaceAll(',', '.'));
      final baseAmount = amount;
      final iva = baseAmount * (_selectedIVA ?? 0.0) / 100;
      final rePercentage = double.tryParse(_reController.text.replaceAll(',', '.')) ?? 0.0;
      final re = baseAmount * rePercentage / 100;

      String docId;
      Map<String, dynamic>? saved;

      if (_editingInvoiceId != null) {
        // Updating existing invoice
        final success = await _invoiceService.updateInvoice(
          id: _editingInvoiceId!,
          company: (_selectedCompany != null && _selectedCompany!.isNotEmpty) ? _selectedCompany! : _companyController.text,
          client: _selectedClient,
          amount: amount,
          baseAmount: baseAmount,
          iva: iva,
          re: re,
          invoiceDate: _selectedInvoiceDate!,
          dueDate: _selectedDueDate!,
        );

        if (success) {
          saved = await _invoiceService.getInvoiceById(_editingInvoiceId!);
          docId = _editingInvoiceId!;
        } else {
          throw Exception('Error actualizando la factura');
        }
      } else {
        // Creating new invoice
        docId = await _invoiceService.addInvoice(
          company: (_selectedCompany != null && _selectedCompany!.isNotEmpty) ? _selectedCompany! : _companyController.text,
          client: _selectedClient,
          amount: amount,
          baseAmount: baseAmount,
          iva: iva,
          re: re,
          invoiceDate: _selectedInvoiceDate!,
          dueDate: _selectedDueDate!,
        );

        // Try to read back the saved invoice to confirm persistence
        saved = await _invoiceService.getInvoiceById(docId);
      }

      debugPrint('Factura ${_editingInvoiceId != null ? "actualizada" : "guardada"}, docId=$docId, data=$saved');

      // Reset form only if saved successfully
      _formKey.currentState!.reset();
      _amountController.clear();
      _invoiceDateController.clear();
      _dueDateController.clear();
      _companyController.clear();
      _reController.clear();
      setState(() {
        _selectedCompany = null;
        _editingInvoiceId = null; // Clear editing state
      });

      if (saved != null) {
        final summary = '${saved['company'] ?? ''} - ${saved['amount'] ?? ''} € - ${saved['invoiceDate'] ?? ''}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Factura ${_editingInvoiceId != null ? "actualizada" : "guardada"}: $summary')),
        );
        // Notify other widgets in the same app that an invoice changed
        try {
          // Enviar el objeto guardado para que ReportWidget pueda actualizar la lista local inmediatamente
          final toNotify = Map<String, dynamic>.from(saved);
          toNotify['id'] = docId;
          InvoiceNotifier.instance.notify(toNotify);
        } catch (_) {}
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Factura ${_editingInvoiceId != null ? "actualizada" : "guardada"} (id: $docId) pero no se pudo leer')),
        );
      }
    } catch (e) {
      debugPrint('Error ${_editingInvoiceId != null ? "actualizando" : "guardando"} factura: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error ${_editingInvoiceId != null ? "actualizando" : "guardando"} factura: ${e.toString()}')),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _loadLastInvoice() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final lastInvoice = await _invoiceService.getLastInvoice();
      if (lastInvoice != null) {
        // Update form with last invoice data
        _amountController.text = (lastInvoice['baseAmount'] ?? lastInvoice['amount']).toString();
        _selectedCompany = lastInvoice['company'] as String?;
        _selectedClient = lastInvoice['client'] as String?;
        _invoiceDateController.text = lastInvoice['invoiceDate'] as String;
        _dueDateController.text = lastInvoice['dueDate'] as String;
        _selectedInvoiceDate = DateTime.parse(lastInvoice['invoiceDate'] as String);
        _selectedDueDate = DateTime.parse(lastInvoice['dueDate'] as String);

        if (lastInvoice['iva'] != null) {
          final baseAmount = lastInvoice['baseAmount'] ?? lastInvoice['amount'];
          _selectedIVA = (lastInvoice['iva'] / baseAmount * 100).roundToDouble();
        }

        if (lastInvoice['re'] != null) {
          final baseAmount = lastInvoice['baseAmount'] ?? lastInvoice['amount'];
          _reController.text = (lastInvoice['re'] / baseAmount * 100).toString();
        }

        setState(() {
          _editingInvoiceId = lastInvoice['id'] as String;
          _isEditing = true;
        });

        _updateTotal();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Última factura cargada para edición'),
            action: SnackBarAction(
              label: 'Nueva Factura',
              onPressed: _clearForm,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron facturas anteriores')),
        );
      }
    } catch (e) {
      debugPrint('Error cargando última factura: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando última factura: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _amountController.clear();
    _invoiceDateController.clear();
    _dueDateController.clear();
    _companyController.clear();
    _reController.clear();
    setState(() {
      _selectedCompany = null;
      _selectedClient = null;
      _selectedInvoiceDate = null;
      _selectedDueDate = null;
      _editingInvoiceId = null;
      _isEditing = false;
    });
    _updateTotal();
  }

  void _validateForm() {
    String? amountError;
    String? invoiceDateError;
    String? dueDateError;

    // Validar campos requeridos
    final hasCompany = (_selectedCompany != null && _selectedCompany != '__other__') || _companyController.text.isNotEmpty;
    final hasClient = _selectedClient != null && _selectedClient!.isNotEmpty;
    final hasInvoiceDate = _invoiceDateController.text.isNotEmpty;
    final hasDueDate = _dueDateController.text.isNotEmpty;

    // Validar importe base
    final baseAmount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (_amountController.text.isEmpty) {
      amountError = 'Campo requerido';
    } else if (baseAmount == null || baseAmount <= 0) {
      amountError = 'El importe debe ser un número mayor que 0';
    }

    // Validar IVA (requerido)
    final hasIVA = _selectedIVA != null;
    if (!hasIVA) {
      setState(() {
        _selectedIVA = 21.0; // Valor por defecto
      });
    }

    // Validar RE (requerido)
    final reValue = double.tryParse(_reController.text.replaceAll(',', '.'));
    if (_reController.text.isEmpty) {
      _reController.text = '0.0'; // Valor por defecto
    } else if (reValue == null || reValue < 0) {
      setState(() {
        _reController.text = '0.0';
      });
    }

    if (!hasInvoiceDate) invoiceDateError = 'Selecciona la fecha de factura';
    if (!hasDueDate) dueDateError = 'Selecciona la fecha de vencimiento';

    bool datesValid = true;
    if (_selectedInvoiceDate != null && _selectedDueDate != null) {
      if (_selectedInvoiceDate!.isAfter(_selectedDueDate!)) {
        invoiceDateError = 'La fecha de factura no puede ser posterior a la fecha de vencimiento';
        datesValid = false;
      }
    }

    final can = hasCompany && hasClient && amountError == null && 
                invoiceDateError == null && dueDateError == null && 
                datesValid && hasIVA;

    if (amountError != _amountError || invoiceDateError != _invoiceDateError || dueDateError != _dueDateError || can != _canSave) {
      setState(() {
        _amountError = amountError;
        _invoiceDateError = invoiceDateError;
        _dueDateError = dueDateError;
        _canSave = can;
      });
    }
  }

  Future<void> _loadCompaniesOnce() async {
    if (_triedOneShot) return;
    _triedOneShot = true;
    debugPrint('Attempting one-shot companies load for project ${_companyService.appId}');
    try {
      final list = await _companyService.getCompaniesOnce(); // Este método ya filtra las empresas eliminadas
      debugPrint('One-shot companies loaded: ${list.length}');
      if (list.isNotEmpty) {
        setState(() {
          _oneTimeCompanies = list;
          _selectedCompany = _selectedCompany ?? list.first;
          _oneShotError = null;
        });
      } else {
        setState(() {
          _oneTimeCompanies = <String>[];
          _oneShotError = null;
        });
      }
    } catch (e) {
      debugPrint('Error cargando empresas one-shot: $e');
      setState(() {
        _oneShotError = e.toString();
        _oneTimeCompanies = null;
      });
    }
  }

  Future<void> _selectDate(BuildContext context, {required bool isInvoiceDate}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (isInvoiceDate) {
          _selectedInvoiceDate = picked;
          _invoiceDateController.text = DateFormat('yyyy-MM-dd').format(picked);
        } else {
          _selectedDueDate = picked;
          _dueDateController.text = DateFormat('yyyy-MM-dd').format(picked);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_isEditing ? 'Editar Factura' : 'Registrar Factura', 
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 6),
                        // Show which Firebase projectId the widget is using (debug help)
                        Text('Proyecto: ${_companyService.appId}', 
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  // Botones de acción
                  _isEditing
                      ? TextButton.icon(
                          onPressed: _clearForm,
                          icon: const Icon(Icons.add),
                          label: const Text('Nueva Factura'),
                        )
                      : TextButton.icon(
                          onPressed: _loadLastInvoice,
                          icon: _isLoading 
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.edit),
                          label: const Text('Cargar Última'),
                        ),
                ],
              ),
              const SizedBox(height: 20),
              StreamBuilder<QuerySnapshot>(
                stream: _companyService.getCompaniesStream(),
                builder: (context, snapshot) {
                  // If we already loaded companies one-shot (for anonymous users), prefer that list
                  if (_oneTimeCompanies != null) {
                    final original = _oneTimeCompanies!;
                    final companies = List<String>.from(original);

                    if (original.isEmpty) {
                      // No public companies found for anonymous users - show a clear message and retry
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text('No se encontraron empresas públicas para el proyecto ${_companyService.appId}.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)))),
                              TextButton(onPressed: () { setState(() { _triedOneShot = false; _oneShotError = null; _loadCompaniesOnce(); }); }, child: const Text('Reintentar')),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Fallback free-text input so user can still type the company
                          TextFormField(
                            controller: _companyController,
                            decoration: const InputDecoration(labelText: 'Empresa'),
                            validator: (v) => v == null || v.isEmpty ? 'Campo requerido' : null,
                          ),
                        ],
                      );
                    }

                    if ((_selectedCompany == null || _selectedCompany!.isEmpty) && companies.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _selectedCompany = companies.first;
                          });
                        }
                      });
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_oneShotError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                Expanded(child: Text('Error cargando empresas: $_oneShotError', style: TextStyle(color: Theme.of(context).colorScheme.error))),
                                TextButton(onPressed: () { setState(() { _triedOneShot = false; _oneShotError = null; _loadCompaniesOnce(); }); }, child: const Text('Reintentar')),
                              ],
                            ),
                          ),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCompany,
                          hint: const Text('Selecciona una empresa'),
                          onChanged: (String? newValue) => setState(() {
                            _selectedCompany = newValue;
                            if (newValue != '__other__') _companyController.clear();
                            // Reset selected client when company changes
                            _selectedClient = null;
                          }),
                          items: companies.map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(value: value, child: Text(value));
                          }).toList(),
                          validator: (value) {
                            if ((value != null && value != '__other__') || _companyController.text.isNotEmpty) return null;
                            return 'Campo requerido';
                          },
                        ),
                        if (_selectedCompany != null && _selectedCompany != '__other__')
                          Padding(
                            padding: const EdgeInsets.only(top: 10.0),
                            child: StreamBuilder<QuerySnapshot>(
                              stream: _companyService.getClientsStream(_selectedCompany!),
                              builder: (context, snapshot) {
                                if (snapshot.hasError) {
                                  return Text('Error cargando clientes: ${snapshot.error}',
                                      style: TextStyle(color: Theme.of(context).colorScheme.error));
                                }
                                if (!snapshot.hasData) {
                                  return const SizedBox(
                                    height: 48,
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }
                                final clients = snapshot.data!.docs
                                    .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
                                    .where((name) => name.isNotEmpty)
                                    .toList();
                                
                                return DropdownButtonFormField<String>(
                                  initialValue: _selectedClient,
                                  hint: const Text('Selecciona un cliente'),
                                  decoration: const InputDecoration(
                                    labelText: 'Cliente',
                                  ),
                                  onChanged: (String? newValue) {
                                    if (newValue == '__other__') {
                                      final newClientController = TextEditingController();
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Nuevo Cliente'),
                                          content: TextField(
                                            controller: newClientController,
                                            decoration: const InputDecoration(
                                              labelText: 'Nombre del cliente',
                                              hintText: 'Ingrese el nombre del cliente',
                                            ),
                                            autofocus: true,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pop(),
                                              child: const Text('Cancelar'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () async {
                                                final name = newClientController.text.trim();
                                                if (name.isNotEmpty) {
                                                  final result = await _companyService.addClient(_selectedCompany!, name);
                                                  if (result != null) {
                                                    setState(() {
                                                      _selectedClient = name;
                                                    });
                                                    Navigator.of(context).pop();
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('Cliente agregado exitosamente')),
                                                    );
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('Error al agregar el cliente')),
                                                    );
                                                  }
                                                }
                                              },
                                              child: const Text('Guardar'),
                                            ),
                                          ],
                                        ),
                                      );
                                    } else {
                                      setState(() {
                                        _selectedClient = newValue;
                                      });
                                    }
                                  },
                                  validator: (value) => value == null || value.isEmpty ? 'Debes seleccionar un cliente' : null,
                                  items: [
                                    ...clients.map<DropdownMenuItem<String>>((String value) {
                                      return DropdownMenuItem<String>(value: value, child: Text(value));
                                    }),
                                    // Añadir opción "Otro..." si hay al menos una empresa seleccionada
                                    if (_selectedCompany != null && _selectedCompany!.isNotEmpty)
                                      const DropdownMenuItem<String>(
                                        value: '__other__',
                                        child: Text('Otro...'),
                                      ),
                                    if (clients.isEmpty)
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('No hay clientes registrados'),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  }

                  // Fallback to stream behavior
                  if (snapshot.hasError) {
                    final err = snapshot.error?.toString() ?? 'Error desconocido';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Error leyendo empresas desde Firestore: $err', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        Row(
                          children: [
                            TextButton(onPressed: () { setState(() { _triedOneShot = false; _oneShotError = null; _loadCompaniesOnce(); }); }, child: const Text('Reintentar carga one-shot')),
                            TextButton(onPressed: () { setState(() { /* try stream again by rebuilding */ }); }, child: const Text('Reintentar stream')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Fallback free-text input so user can still type the company
                        TextFormField(
                          controller: _companyController,
                          decoration: const InputDecoration(labelText: 'Empresa'),
                          validator: (v) => v == null || v.isEmpty ? 'Campo requerido' : null,
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  // Filtrar solo las empresas no eliminadas
                  var docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['deleted'] != true;
                  }).toList();

                  if (docs.isNotEmpty && (_selectedCompany == null || _selectedCompany!.isEmpty)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() {
                        _selectedCompany = (docs.first.data() as Map<String, dynamic>)['name'] as String?;
                      });
                    });
                  }
                  if (docs.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('No hay empresas públicas visibles. Es posible que las reglas de Firestore bloqueen la lectura para usuarios anónimos.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)))),
                            TextButton(onPressed: () { setState(() { _triedOneShot = false; _oneShotError = null; _loadCompaniesOnce(); }); }, child: const Text('Reintentar')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _companyController,
                          decoration: const InputDecoration(labelText: 'Empresa'),
                          validator: (v) => v == null || v.isEmpty ? 'Campo requerido' : null,
                        ),
                      ],
                    );
                  }
                  var companies = docs.map((doc) => doc['name'] as String).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCompany,
                        hint: const Text('Selecciona una empresa'),
                        onChanged: (String? newValue) => setState(() {
                          _selectedCompany = newValue;
                          if (newValue != '__other__') _companyController.clear();
                        }),
                        items: companies.map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(value: value, child: Text(value));
                        }).toList(),
                        validator: (value) {
                          if ((value != null && value != '__other__') || _companyController.text.isNotEmpty) return null;
                          return 'Campo requerido';
                        },
                      ),
                      if (_selectedCompany == '__other__')
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: TextFormField(
                            controller: _companyController,
                            decoration: const InputDecoration(labelText: 'Empresa (otra)'),
                            validator: (v) => v == null || v.isEmpty ? 'Campo requerido' : null,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(labelText: 'Importe base (€)', errorText: _amountError),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<double>(
                      initialValue: _selectedIVA,
                      decoration: const InputDecoration(
                        labelText: 'IVA *',
                        suffixText: '%',
                        helperText: 'Campo requerido',
                      ),
                      items: const [
                        DropdownMenuItem(value: 4.0, child: Text('4%')),
                        DropdownMenuItem(value: 10.0, child: Text('10%')),
                        DropdownMenuItem(value: 21.0, child: Text('21%')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedIVA = value;
                        });
                        _updateTotal();
                      },
                      validator: (value) => value == null ? 'Campo requerido' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      enabled: false,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'IVA (€)',
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      controller: _ivaAmountController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _reController,
                      decoration: const InputDecoration(
                        labelText: 'RE *',
                        suffixText: '%',
                        helperText: 'Campo requerido (use 0 si no aplica)',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Campo requerido';
                        }
                        final number = double.tryParse(value.replaceAll(',', '.'));
                        if (number == null || number < 0) {
                          return 'Debe ser un número mayor o igual a 0';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      enabled: false,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'RE (€)',
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      controller: _reAmountController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _totalController,
                decoration: InputDecoration(
                  labelText: 'Importe total (€)',
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                readOnly: true,
                enabled: false,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _invoiceDateController,
                decoration: InputDecoration(labelText: 'Fecha de factura', suffixIcon: Icon(Icons.calendar_today), errorText: _invoiceDateError),
                readOnly: true,
                onTap: () => _selectDate(context, isInvoiceDate: true),
                validator: (value) => value!.isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _dueDateController,
                decoration: InputDecoration(labelText: 'Fecha de vencimiento', suffixIcon: Icon(Icons.calendar_today), errorText: _dueDateError),
                readOnly: true,
                onTap: () => _selectDate(context, isInvoiceDate: false),
                validator: (value) => value!.isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_canSave && !_isSaving) ? _saveInvoice : null,
                  child: _isSaving 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : Text(_isEditing ? 'Actualizar Factura' : 'Guardar Factura'),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _updateTotal() {
    try {
      final baseAmount = double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0.0;
      final ivaAmount = baseAmount * (_selectedIVA ?? 0.0) / 100;
      final rePercentage = double.tryParse(_reController.text.replaceAll(',', '.')) ?? 0.0;
      final reAmount = baseAmount * rePercentage / 100;
      final total = baseAmount + ivaAmount + reAmount;
      
      _ivaAmountController.text = ivaAmount > 0 ? '${ivaAmount.toStringAsFixed(2)} €' : '';
      _reAmountController.text = reAmount > 0 ? '${reAmount.toStringAsFixed(2)} €' : '';
      _totalController.text = total.toStringAsFixed(2);
    } catch (e) {
      _ivaAmountController.text = '';
      _reAmountController.text = '';
      _totalController.text = '';
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_validateForm);
    _invoiceDateController.removeListener(_validateForm);
    _dueDateController.removeListener(_validateForm);
    _companyController.removeListener(_validateForm);
    _amountController.dispose();
    _invoiceDateController.dispose();
    _dueDateController.dispose();
    _companyController.dispose();
    _reController.dispose();
    _totalController.dispose();
    _ivaAmountController.dispose();
    _reAmountController.dispose();
    super.dispose();
  }
}