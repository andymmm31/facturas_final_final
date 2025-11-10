import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:frontend_flutter/firebase_options.dart';
import 'package:frontend_flutter/src/services/company_service.dart';
import 'package:frontend_flutter/src/services/report_service.dart';
import 'package:frontend_flutter/src/services/export_service.dart';
// import 'package:frontend_flutter/src/services/invoice_service.dart'; // No se usaba
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:frontend_flutter/src/services/invoice_notifier.dart';

class ReportWidget extends StatefulWidget {
  const ReportWidget({super.key});

  @override
  _ReportWidgetState createState() => _ReportWidgetState();
}

class _ReportWidgetState extends State<ReportWidget> {
  late final ReportService _reportService;
  late final CompanyService _companyService;
  // late final InvoiceService _invoiceService; // CORREGIDO: Eliminado, no se usaba
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _companiesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _invoiceSubscription;
  Timer? _invoiceDebounce;
  StreamSubscription<Map<String, dynamic>?>? _invoiceNotifierSub;

  Map<String, bool> _selectedCompanies = {};
  Map<String, Set<String>> _selectedClients = {};
  String _filterType = 'range';
  DateTime? _startDate;
  DateTime? _endDate;
  // DateTime? _editInvoiceDate; // CORREGIDO: Eliminado, no se usaba
  // DateTime? _editDueDate; // CORREGIDO: Eliminado, no se usaba
  bool _includeDeletedCompanies = false;
  bool _showTotal = false;
  final TextEditingController _editAmountController = TextEditingController();
  final TextEditingController _editInvoiceDateController = TextEditingController();
  final TextEditingController _editDueDateController = TextEditingController();
  final String _rangeType = 'invoiceDate';

  Map<String, dynamic>? _reportResult;
  bool _isLoading = false;
  String? _selectedInvoiceDateFilter;
  String? _selectedDueDateFilter;

  @override
  void initState() {
    super.initState();
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    _reportService = ReportService(projectId);
    _companyService = CompanyService(projectId);
    
    // Calcular reporte inicial
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateReport(); // Carga inicial
      
      if (mounted) {
        // Reactivar listener de cambios en 'invoices' para que cualquier modificación
        // realizada desde otros tabs (ej. InvoiceFormWidget) actualice automáticamente
        // el reporte. Usamos debounce para agrupar ráfagas de cambios.
        _companiesSubscription = _firestore
            .collection('artifacts/$projectId/public/data/companies')
            .snapshots()
            .listen((snapshot) {
          if (mounted) {
            setState(() {
              _selectedCompanies.clear();
            });
            _calculateReport();
          }
        });

        // Listener para facturas (invoices) - recarga el reporte cuando cambian
    _invoiceSubscription = _firestore
            .collection('artifacts/$projectId/public/data/invoices')
            .snapshots()
            .listen((snapshot) {
          if (!mounted) return;
          // Debounce para evitar múltiples llamadas rápidas
          _invoiceDebounce?.cancel();
          _invoiceDebounce = Timer(const Duration(milliseconds: 300), () {
            if (mounted) _calculateReport();
          });
        });

        // Escuchar notificaciones internas (ej. desde InvoiceForm) para actualizar la UI
        _invoiceNotifierSub = InvoiceNotifier.instance.stream.listen((invoice) {
          if (!mounted) return;
          try {
            if (invoice != null && _reportResult != null) {
              // Intentar actualizar la lista local como hace la edición de factor
              final List<dynamic> currentInvoices = _reportResult!['invoices'];
              final id = invoice['id']?.toString();
              if (id != null && id.isNotEmpty) {
                final idx = currentInvoices.indexWhere((i) => i['id'] == id);
                if (idx != -1) {
                  // Reemplazar/actualizar campos locales
                  currentInvoices[idx] = {
                    ...currentInvoices[idx],
                    ...invoice,
                  };
                } else {
                  // Insertar al principio (más reciente)
                  currentInvoices.insert(0, invoice);
                }
                // Forzar actualización visual y recalcular totales
                setState(() {
                  _reportResult!['invoices'] = currentInvoices;
                });
                _recalculateTotalsLocally(currentInvoices);
                // (debug) removed temporary confirmation
                return; // Ya aplicamos la actualización localmente
              }
            }
          } catch (_) {}

          // Fallback: si no pudimos aplicar localmente, recalculemos desde Firestore
          _invoiceDebounce?.cancel();
          _invoiceDebounce = Timer(const Duration(milliseconds: 100), () {
            if (mounted) _calculateReport();
          });
        });
      }
    });
  }

  Future<void> _calculateReport() async {
    if (_isLoading) return;
    if (!mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    setState(() {
      _isLoading = true;
      _showTotal = true;
    });
    
    try {
      final selectedCompanies = _selectedCompanies.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();
      
      final clientFilters = <String, Set<String>>{};
      for (final company in selectedCompanies) {
        final selectedClientsForCompany = _selectedClients[company];
        if (selectedClientsForCompany != null && selectedClientsForCompany.isNotEmpty) {
          clientFilters[company] = selectedClientsForCompany;
        }
      }
          
      final reportData = await _reportService.calculateReport(
        selectedCompanies: selectedCompanies,
        selectedClients: clientFilters.isEmpty ? null : clientFilters,
        filterType: _filterType,
        startDate: _startDate?.toIso8601String().split('T').first,
        endDate: _endDate?.toIso8601String().split('T').first,
        rangeType: _rangeType,
        selectedInvoiceDate: _selectedInvoiceDateFilter,
        selectedDueDate: _selectedDueDateFilter,
        includeDeletedCompanies: _includeDeletedCompanies,
      );
      
      if (!mounted) return;
      setState(() {
        _reportResult = reportData;
        _isLoading = false;
      });
      // Recalculate totals locally so totals include the 'factor' multiplication
      // (ReportService returns 'amount' as total without factor; UI should
      // show total*factor). This ensures the displayed Total and breakdown
      // reflect the factor applied to each invoice.
      try {
        final invoices = reportData['invoices'] as List<dynamic>?;
        if (invoices != null) {
          _recalculateTotalsLocally(invoices);
        }
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _showTotal = false;
      });
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error al calcular el reporte: $e')),
      );
    }
  }

  // ignore: unused_element
  /// Recalcula los totales y actualiza la UI usando la lista local de facturas.
  /// Esto es mucho más rápido que volver a leer de Firestore.
  void _recalculateTotalsLocally(List<dynamic> invoices) {
    if (_reportResult == null) return;

    double newGlobalTotal = 0.0;
    final newSumByCompany = <String, dynamic>{};

    for (final inv in invoices) {
      // Recompute amount applying factor: (base + iva + re) * factor
      final base = (inv['baseAmount'] is num) ? (inv['baseAmount'] as num).toDouble() : double.tryParse(inv['baseAmount']?.toString() ?? '') ?? 0.0;
      final iva = (inv['iva'] is num) ? (inv['iva'] as num).toDouble() : 0.0;
      final re = (inv['re'] is num) ? (inv['re'] as num).toDouble() : 0.0;
      final factor = (inv['factor'] is num) ? (inv['factor'] as num).toDouble() : 1.0;

      final amount = (base + iva + re) * factor;
      final company = inv['company']?.toString();

      newGlobalTotal += amount;

      if (company != null) {
        if (!newSumByCompany.containsKey(company)) {
          newSumByCompany[company] = {'total': 0.0};
        }
        newSumByCompany[company]['total'] += amount;
      }
    }

    // Actualiza el estado con los nuevos datos calculados
    setState(() {
      _reportResult!['invoices'] = invoices; // Actualiza la lista
      _reportResult!['totalSum'] = newGlobalTotal; // Actualiza el total
      _reportResult!['sumByCompany'] = newSumByCompany; // Actualiza desglose
      _isLoading = false; // Quita cualquier spinner
      _showTotal = true; // Muestra el total
    });
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_reportResult == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalSum = _reportResult?['totalSum'] as double? ?? 0.0;
    final invoiceCount = _reportResult?['invoiceCount'] as int? ?? 0;
    // 'invoices' es una referencia a la lista dentro de _reportResult
    final invoices = _reportResult?['invoices'] as List<dynamic>? ?? <dynamic>[];
    final sumByCompany =
        (_reportResult?['sumByCompany'] as Map<String, dynamic>?) ?? {};

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ... (El código del Total y Desglose no cambia) ...
          Center(
            child: Text(
              'Total para la selección ($invoiceCount facturas)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          if (_showTotal && !_isLoading && _reportResult != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '${totalSum.toStringAsFixed(2)} €',
                        style: TextStyle(
                          color: Colors.teal.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (sumByCompany.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            Text('Desglose por empresa:',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...sumByCompany.entries.map((e) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(e.key)),
                          Text(
                            '${(e.value['total'] as double).toStringAsFixed(2)} €',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                  ],
                )),
          ],
          const SizedBox(height: 18),
          Text('Historial de facturas',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          invoices.isEmpty
              ? const Center(
                  child: Text('No hay facturas para los filtros seleccionados.'),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 20,
                    horizontalMargin: 12,
                    showCheckboxColumn: false,
                    columns: const [
                      DataColumn(label: Text('Empresa')),
                      DataColumn(label: Text('Cliente')),
                      DataColumn(label: Text('Base')),
                      DataColumn(label: Text('IVA')),
                      DataColumn(label: Text('RE')),
                      DataColumn(label: Text('Total')),
                      DataColumn(label: Text('Factor')),
                      DataColumn(
                          label: Text('Total c/ Factor',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Fecha factura')),
                      DataColumn(label: Text('Fecha vencimiento')),
                      DataColumn(
                          label: Text('Acciones',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: invoices.map((inv) {
                      final company = inv['company']?.toString() ?? '';
                      final client = inv['client']?.toString() ?? '';
            final baseAmount =
              (inv['baseAmount'] as num?)?.toDouble() ?? 0.0;
            final ivaAmount =
              (inv['iva'] as num?)?.toDouble() ?? 0.0;
            // Asegurar que RE no sea negativo
            double reAmount = (inv['re'] as num?)?.toDouble() ?? 0.0;
            if (reAmount < 0) reAmount = 0.0;
                      
            final totalSinFactor = baseAmount + ivaAmount + reAmount;
            final factor = (inv['factor'] as num?)?.toDouble() ?? 1.0;
            // Mostrar el total aplicando el factor (base+iva+re) * factor
            final totalConFactor = totalSinFactor * factor;

                      return DataRow(
                        cells: [
                          DataCell(Text(company)),
                          DataCell(Text(client)),
                          DataCell(Text('${baseAmount.toStringAsFixed(2)} €')),
                          DataCell(Text(() {
                            final ivaPct = baseAmount > 0 ? (ivaAmount / baseAmount * 100) : 0.0;
                            return '${ivaAmount.toStringAsFixed(2)} € (${ivaPct.toStringAsFixed(1)}%)';
                          }())),
                          DataCell(Text(() {
                            final rePct = baseAmount > 0 ? (reAmount / baseAmount * 100) : 0.0;
                            return '${reAmount.toStringAsFixed(2)} € (${rePct.toStringAsFixed(1)}%)';
                          }())),
                          DataCell(Text('${totalSinFactor.toStringAsFixed(2)} €')),
                          DataCell(
                            Builder(builder: (context) {
                              final TextEditingController controller =
                                  TextEditingController(text: factor.toString());
                              return Material(
                                color: Colors.transparent,
                                child: Tooltip(
                                  message:
                                      'Factor de multiplicación - El total se multiplicará por este valor\nEjemplo: Un factor de 1.5 aumentará el total en un 50%',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      border: Border.all(
                                          color: Colors.orange.shade400,
                                          width: 2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: SizedBox(
                                      width: 120,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.trending_up,
                                              size: 16,
                                              color: Colors.orange.shade700),
                                          Expanded(
                                            child: TextFormField(
                                              controller: controller,
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                      decimal: true),
                                              style: TextStyle(
                                                color: Colors.orange.shade900,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              decoration: InputDecoration(
                                                isDense: true,
                                                contentPadding: const EdgeInsets
                                                    .symmetric(
                                                        horizontal: 8,
                                                        vertical: 8),
                                                border: InputBorder.none,
                                                hintText: '1.0',
                                                hintStyle: TextStyle(
                                                    color: Colors.orange.shade300),
                                                prefixText: '×',
                                                prefixStyle: TextStyle(
                                                  color: Colors.orange.shade700,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              mouseCursor:
                                                  WidgetStateMouseCursor.clickable,

                                              
                                              // --- INICIO DE LA CORRECCIÓN ---
                                              onFieldSubmitted: (value) async {
                                                final newFactor =
                                                    double.tryParse(value.replaceAll(',', '.'));
                                                if (newFactor != null) {

                                                  // --- INICIO DE LA CORRECCIÓN ---
                                                  // 1. Obtenemos el ID de documento correcto
                                                  final docId = inv['id']?.toString() ??
                                                      inv['docId']?.toString() ??
                                                      inv['invoiceId']?.toString() ??
                                                      inv['documentId']?.toString();

                                                  // 2. Comprobamos si el ID es nulo
                                                  if (docId == null || docId.isEmpty) {
                                                    if (!mounted) return;
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                          content: Text(
                                                              'Error: No se pudo guardar. ID de factura no encontrado.')),
                                                    );
                                                    controller.text = factor.toString(); // Revierte el texto
                                                    return; // Salir si no hay ID
                                                  }
                                                  // --- FIN DE LA CORRECCIÓN ---

                                                  final projectId =
                                                      DefaultFirebaseOptions.currentPlatform.projectId;

                                                  // Calculamos el nuevo total CON el nuevo factor
                                                  final newTotalConFactor =
                                                      totalSinFactor * newFactor;

                                                  setState(() {
                                                    _isLoading = true;
                                                  });

                                                  try {
                                                    // 3. Guardar en Firestore USANDO EL 'docId' CORRECTO
                                                    // Ensure we pass a Map<String, Object?> to Firestore
                                                    final Map<String, Object?> _safe = Map<String, Object?>.from({
                                                      'factor': newFactor,
                                                      'amount': newTotalConFactor,
                                                    });
                                                    await _firestore
                                                        .doc('artifacts/$projectId/public/data/invoices/$docId')
                                                        .update(_safe);
                                                    
                                                    if (!mounted) return; // Volver a comprobar después del 'await'
                                                      // 4. Aplicar los cambios localmente usando los mismos pasos de normalización
                                                      final idx = invoices.indexWhere((i) => (i['id']?.toString() ?? '') == docId);
                                                      if (idx != -1) {
                                                        final old = Map<String, dynamic>.from(invoices[idx] as Map);
                                                        final merged = <String, dynamic>{...old};

                                                        // Update factor and amount from what we saved
                                                        final factorVal = newFactor;
                                                        final base = (merged['baseAmount'] is num) ? (merged['baseAmount'] as num).toDouble() : double.tryParse(merged['baseAmount']?.toString() ?? '') ?? 0.0;
                                                        final ivaAmt = (merged['iva'] is num) ? (merged['iva'] as num).toDouble() : 0.0;
                                                        final reAmt = (merged['re'] is num) ? (merged['re'] as num).toDouble() : 0.0;
                                                        final totalSin = base + ivaAmt + reAmt;
                                                        final totalCon = totalSin * factorVal;

                                                        merged['factor'] = factorVal;
                                                        merged['amount'] = totalCon;
                                                        // Ensure numeric normalization
                                                        merged['baseAmount'] = base;
                                                        merged['iva'] = ivaAmt;
                                                        merged['re'] = reAmt;

                                                        invoices[idx] = merged;

                                                        if (_reportResult != null) {
                                                          setState(() {
                                                            _reportResult!['invoices'] = List<dynamic>.from(invoices);
                                                          });
                                                        }

                                                        _recalculateTotalsLocally(invoices);
                                                      }

                                                  } catch (e) {
                                                    if (mounted) {
                                                      setState(() {
                                                        _isLoading = false;
                                                      });
                                                      ScaffoldMessenger.of(context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                            content: Text(
                                                                'Error al actualizar el factor: $e')),
                                                      );
                                                      controller.text =
                                                          factor.toString();
                                                    }
                                                  }
                                                }
                                                FocusScope.of(context).unfocus();
                                              },
                                              // --- FIN DE LA CORRECCIÓN ---
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          DataCell(Text(
                            '${totalConFactor.toStringAsFixed(2)} €',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade700),
                          )),
                          DataCell(Text(inv['invoiceDate']?.toString() ?? '')),
                          DataCell(Text(inv['dueDate']?.toString() ?? '')),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_auth.currentUser != null) ...[
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _showEditInvoiceDialog(inv),
                                  tooltip: 'Editar factura',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      size: 20, color: Colors.red),
                                  onPressed: () =>
                                      _showDeleteConfirmationDialog(inv),
                                  tooltip: 'Eliminar factura',
                                ),
                              ]
                            ],
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildDateRangePicker() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _selectDate(context, true),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Fecha de inicio'),
              child: Text(_startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : 'No seleccionada'),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () => _selectDate(context, false),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Fecha de fin'),
              child: Text(_endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : 'No seleccionada'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompanySelector() {
    return StreamBuilder<QuerySnapshot>(
      stream: _companyService.getCompaniesStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var companies = snapshot.data!.docs;
        if (_selectedCompanies.isEmpty && companies.isNotEmpty) {
          _selectedCompanies = { for (var item in companies) item['name'] : false };
          _selectedClients = { for (var item in companies) item['name'] : {} };
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Empresas:', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: [
                    FilterChip(
                      label: const Text('Todas'),
                      selected: _selectedCompanies.values.isNotEmpty && 
                              _selectedCompanies.values.every((v) => v == true),
                      onSelected: (val) {
                        setState(() {
                          _selectedCompanies.updateAll((key, old) => val);
                          if (!val) {
                            for (var clients in _selectedClients.values) {
                              clients.clear();
                            }
                          }
                          _showTotal = false;
                        });
                        // --- INICIO DE LA CORRECCIÓN ---
                        _calculateReport(); // <--- AÑADIR ESTA LÍNEA
                        // --- FIN DE LA CORRECCIÓN ---
                      },
                    ),
                    ..._selectedCompanies.keys.map((company) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 6.0),
                        child: FilterChip(
                          label: Text(company),
                          selected: _selectedCompanies[company]!,
                          onSelected: (value) {
                            setState(() {
                              _selectedCompanies[company] = value;
                              if (!value) {
                                _selectedClients[company]?.clear();
                              }
                              _showTotal = false;
                            });
                            // --- INICIO DE LA CORRECCIÓN ---
                            _calculateReport(); // <--- AÑADIR ESTA LÍNEA
                            // --- FIN DE LA CORRECCIÓN ---
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
            
            ..._selectedCompanies.entries.where((e) => e.value).map((entry) {
              final company = entry.key;
              return Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Clientes de $company:', 
                         style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot>(
                      stream: _companyService.getClientsStream(company),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        }
                        if (!snapshot.hasData) {
                          return const SizedBox(
                            height: 32,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final clients = snapshot.data!.docs
                            .map((doc) { // Corrección para clientes nulos (de antes)
                                final data = doc.data() as Map<String, dynamic>;
                                return data['name'] as String?;
                              })
                            .where((name) => name != null && name.isNotEmpty) 
                            .toSet(); // Usar toSet() para evitar duplicados

                        if (clients.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text('No hay clientes registrados'),
                          );
                        }

                        return Wrap(
                          spacing: 8.0,
                          runSpacing: 4.0,
                          children: [
                            FilterChip(
                              label: const Text('Todos'),
                              selected: _selectedClients[company]!.isEmpty ||
                                    _selectedClients[company]!.containsAll(clients),
                              onSelected: (value) {
                                setState(() {
                                  if (value) {
                                    _selectedClients[company] = clients.whereType<String>().toSet();
                                  } else {
                                    _selectedClients[company]?.clear();
                                  }
                                  _showTotal = false;
                                });
                                // --- INICIO DE LA CORRECCIÓN ---
                                _calculateReport(); // <--- AÑADIR ESTA LÍNEA
                                // --- FIN DE LA CORRECCIÓN ---
                              },
                            ),
                            ...clients.map((client) {
                              return FilterChip(
                                label: Text(client ?? ''),
                                selected: _selectedClients[company]?.contains(client) ?? false,
                                onSelected: (value) {
                                  setState(() {
                                    if (value) {
                                      if (client != null) {
                                        _selectedClients[company]?.add(client);
                                      }
                                    } else {
                                      _selectedClients[company]?.remove(client);
                                    }
                                    _showTotal = false;
                                  });
                                  // --- INICIO DE LA CORRECCIÓN ---
                                  _calculateReport(); // <--- AÑADIR ESTA LÍNEA
                                  // --- FIN DE LA CORRECCIÓN ---
                                },
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reporte Acumulado', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            _buildFilters(),
            const SizedBox(height: 20),
            _buildResults(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          _buildCompanySelector(),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Modo de filtro: '),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _filterType,
                items: const [
                  DropdownMenuItem(value: 'range', child: Text('Rango de fechas')),
                  DropdownMenuItem(value: 'invoiceDate', child: Text('Fecha de factura')),
                  DropdownMenuItem(value: 'dueDate', child: Text('Fecha de vencimiento')),
                ],
                onChanged: (val) {
                  setState(() {
                    _filterType = val ?? 'range';
                    if (_filterType != 'invoiceDate') _selectedInvoiceDateFilter = null;
                    if (_filterType != 'dueDate') _selectedDueDateFilter = null;
                    _showTotal = false;
                  });
                  _calculateReport();
                },
              ),
            ],
          ),

          if (_filterType == 'range') ...[
            const SizedBox(height: 12),
            _buildDateRangePicker(),
          ] else if (_filterType == 'invoiceDate') ...[
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final raw = (_reportResult?['uniqueInvoiceDates'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ?? <String>[];
              final invoiceDateOptions = raw.toSet().toList()..sort();

              if (invoiceDateOptions.isEmpty) {
                return const InputDecorator(
                  decoration: InputDecoration(labelText: 'Fecha factura'),
                  child: Text('No hay fechas de factura disponibles'),
                );
              }

              final hasSelected = _selectedInvoiceDateFilter != null && invoiceDateOptions.contains(_selectedInvoiceDateFilter);
              final effectiveValue = hasSelected ? _selectedInvoiceDateFilter : '';

              final items = <DropdownMenuItem<String>>[
                const DropdownMenuItem(value: '', child: Text('Todas')),
                ...invoiceDateOptions.map((d) => DropdownMenuItem(value: d, child: Text(d))),
              ];

              return DropdownButtonFormField<String>(
                initialValue: effectiveValue,
                hint: const Text('Filtrar por Fecha factura'),
                items: items,
                onChanged: (val) {
                  setState(() {
                    _selectedInvoiceDateFilter = (val == null || val.isEmpty) ? null : val;
                    _showTotal = false;
                  });
                  _calculateReport();
                },
              );
            }),
          ] else if (_filterType == 'dueDate') ...[
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final raw = (_reportResult?['uniqueDueDates'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ?? <String>[];
              final dueDateOptions = raw.toSet().toList()..sort();

              if (dueDateOptions.isEmpty) {
                return const InputDecorator(
                  decoration: InputDecoration(labelText: 'Fecha vencimiento'),
                  child: Text('No hay fechas de vencimiento disponibles'),
                );
              }

              final hasSelected = _selectedDueDateFilter != null && dueDateOptions.contains(_selectedDueDateFilter);
              final effectiveValue = hasSelected ? _selectedDueDateFilter : '';

              final items = <DropdownMenuItem<String>>[
                const DropdownMenuItem(value: '', child: Text('Todas')),
                ...dueDateOptions.map((d) => DropdownMenuItem(value: d, child: Text(d))),
              ];

              return DropdownButtonFormField<String>(
                initialValue: effectiveValue,
                hint: const Text('Filtrar por Fecha vencimiento'),
                items: items,
                onChanged: (val) {
                  setState(() {
                    _selectedDueDateFilter = (val == null || val.isEmpty) ? null : val;
                    _showTotal = false;
                  });
                  _calculateReport();
                },
              );
            }),
          ],
          Row(
            children: [
              Checkbox(
                value: _includeDeletedCompanies,
                onChanged: (bool? value) {
                  setState(() {
                    _includeDeletedCompanies = value ?? false;
                    _showTotal = false;
                  });
                  _calculateReport();
                },
              ),
              const Text('Incluir facturas de empresas eliminadas'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_auth.currentUser != null) OutlinedButton(
                onPressed: () async {
                  final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
                  final exportService = ExportService(projectId);
                  final selected = _selectedCompanies.entries
                      .where((e) => e.value)
                      .map((e) => e.key)
                      .toList();

                  String? exportStart;
                  String? exportEnd;
                  String exportRangeType = 'invoiceDate';

                  if (_filterType == 'range') {
                    exportStart = _startDate?.toIso8601String().split('T').first;
                    exportEnd = _endDate?.toIso8601String().split('T').first;
                    exportRangeType = _rangeType;
                  } else if (_filterType == 'invoiceDate') {
                    exportStart = _selectedInvoiceDateFilter;
                    exportEnd = _selectedInvoiceDateFilter;
                    exportRangeType = 'invoiceDate';
                  } else if (_filterType == 'dueDate') {
                    exportStart = _selectedDueDateFilter;
                    exportEnd = _selectedDueDateFilter;
                    exportRangeType = 'dueDate';
                  }

                  try {
                    // Construir filtros de cliente iguales a los usados en el cálculo del reporte
                    final clientFilters = <String, Set<String>>{};
                    for (final company in selected) {
                      final selectedClientsForCompany = _selectedClients[company];
                      if (selectedClientsForCompany != null && selectedClientsForCompany.isNotEmpty) {
                        clientFilters[company] = selectedClientsForCompany;
                      }
                    }

                    final result = await exportService.exportInvoicesToExcel(
                      selectedCompanies: selected.isEmpty ? null : selected,
                      selectedClients: clientFilters.isEmpty ? null : clientFilters,
                      startDate: exportStart,
                      endDate: exportEnd,
                      rangeType: exportRangeType,
                      includeDeletedCompanies: _includeDeletedCompanies,
                    );
                    if (!mounted) return;
                    if (result != null) {
                      if (result.startsWith('ERROR:')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result))
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Exportado: $result'))
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Error al exportar'))
                      );
                    }
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al exportar: $e'))
                    );
                  }
                },
                child: const Text('Exportar Reporte'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
        _showTotal = false;
      });
      _calculateReport();
    }
  }

  Future<void> _showDeleteConfirmationDialog(Map<String, dynamic> inv) async {
    final id = inv['id']?.toString() ??
        inv['docId']?.toString() ??
        inv['invoiceId']?.toString() ??
        inv['documentId']?.toString();

    if (id == null || id.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo determinar la factura a eliminar')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: const Text('¿Seguro que quieres eliminar esta factura? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // --- INICIO DE LA CORRECCIÓN ---
    setState(() {
      _isLoading = true; // Mostrar spinner
    });

    try {
      final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
      // 1. Borrar de Firestore
      await _firestore.doc('artifacts/$projectId/public/data/invoices/$id').delete();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura eliminada')),
      );

      // 2. Quitar de la lista local
      final List<dynamic> currentInvoices = _reportResult!['invoices'];
      currentInvoices.removeWhere((i) => i['id'] == id);

      // 3. Recalcular localmente (rápido)
      _recalculateTotalsLocally(currentInvoices);
        // 4. Asegurar consistencia: recargar el reporte desde Firestore
        // para que la UI refleje exactamente el estado persistido.
        await _calculateReport();

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false; // Quitar spinner en caso de error
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar factura: $e')),
      );
    }
    // --- FIN DE LA CORRECCIÓN ---
  }

  Future<void> _showEditInvoiceDialog(Map<String, dynamic> inv) async {
    final id = inv['id']?.toString() ??
        inv['docId']?.toString() ??
        inv['invoiceId']?.toString() ??
        inv['documentId']?.toString();

    if (id == null || id.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo determinar la factura a editar')),
      );
      return;
    }

    _editAmountController.text =
        ((inv['baseAmount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2);
    _editInvoiceDateController.text = inv['invoiceDate']?.toString() ?? '';
    _editDueDateController.text = inv['dueDate']?.toString() ?? '';

    // ... (la lógica de ivaRate y reRate no cambia) ...
    double? ivaRate;
    const validIvaRates = [4.0, 10.0, 21.0]; 
    if (inv['baseAmount'] != null && inv['iva'] != null && (inv['baseAmount'] as num).toDouble() != 0) {
      final baseAmount = (inv['baseAmount'] as num).toDouble();
      final ivaAmount = (inv['iva'] as num).toDouble();
      double calculatedRate = (ivaAmount / baseAmount * 100).round().toDouble();
      if (validIvaRates.contains(calculatedRate)) {
        ivaRate = calculatedRate;
      } else {
        ivaRate = 21.0; 
      }
    } else {
      ivaRate = 21.0;
    }
    double reRate = 0.0;
    if (inv['baseAmount'] != null && inv['re'] != null && (inv['baseAmount'] as num).toDouble() != 0) {
      final baseAmount = (inv['baseAmount'] as num).toDouble();
      final reAmount = (inv['re'] as num).toDouble();
      reRate = (reAmount / baseAmount * 100);
    }
    
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            
            // ... (El builder del diálogo no cambia) ...
            double baseAmount =
                double.tryParse(_editAmountController.text.replaceAll(',', '.')) ??
                    0.0;
            double selectedIVA = ivaRate ?? 21.0; 
            double currentRE = reRate; 
            double factor = (inv['factor'] as num?)?.toDouble() ?? 1.0;
            double ivaAmount = baseAmount * selectedIVA / 100;
            double reAmount = baseAmount * currentRE / 100;
            double totalSinFactor = baseAmount + ivaAmount + reAmount; 
            double totalConFactor = totalSinFactor * factor;

            return AlertDialog(
              title: const Text('Editar factura'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Selector de empresa
                    StreamBuilder<QuerySnapshot>(
                      stream: _companyService.getCompaniesStream(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }
                        final companies = snapshot.data!.docs
                            .map((doc) => doc['name'] as String)
                            .toList();
                        return DropdownButtonFormField<String>(
                          initialValue: inv['company'] as String?,
                          decoration: const InputDecoration(
                            labelText: 'Empresa',
                          ),
                          items: companies.map((company) {
                            return DropdownMenuItem(
                              value: company,
                              child: Text(company),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            if (newValue != null) {
                              setDialogState(() {
                                inv['company'] = newValue;
                                inv['client'] = null; 
                              });
                            }
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Selector de cliente
                    if (inv['company'] != null)
                      StreamBuilder<QuerySnapshot>(
                        stream: _companyService.getClientsStream(inv['company']),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final clients = snapshot.data!.docs
                              .map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return data['name'] as String?;
                              })
                              .where((name) => name != null && name.isNotEmpty) 
                              .toList();
                          String? currentClientValue = inv['client'] as String?;
                          if (currentClientValue != null && !clients.contains(currentClientValue)) {
                            currentClientValue = null;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              setDialogState(() {
                                inv['client'] = null;
                              });
                            });
                          }
                          return DropdownButtonFormField<String>(
                            initialValue: currentClientValue,
                            decoration: const InputDecoration(
                              labelText: 'Cliente',
                            ),
                            items: clients.map((client) {
                              return DropdownMenuItem(
                                  value: client,
                                  child: Text(client ?? ''),
                                );
                            }).toList(),
                            onChanged: (newValue) {
                              if (newValue != null) {
                                setDialogState(() {
                                  inv['client'] = newValue;
                                });
                              }
                            },
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _editAmountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Importe base (€)'),
                      onChanged: (value) {
                        setDialogState(() {
                          // Actualización automática
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<double>(
                      initialValue: selectedIVA,
                      decoration: const InputDecoration(
                        labelText: 'IVA',
                        suffixText: '%',
                      ),
                      items: const [
                        DropdownMenuItem(value: 4.0, child: Text('4%')),
                        DropdownMenuItem(value: 10.0, child: Text('10%')),
                        DropdownMenuItem(value: 21.0, child: Text('21%')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedIVA = value;
                            ivaRate = value; 
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'RE',
                        suffixText: '%',
                        helperText: 'Usar 0 si no aplica',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      controller: TextEditingController(text: currentRE.toString()),
                      onChanged: (value) {
                        setDialogState(() {
                          currentRE =
                              double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                          reRate = currentRE; 
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Base: ${baseAmount.toStringAsFixed(2)} €'),
                          Text('IVA: ${ivaAmount.toStringAsFixed(2)} €'),
                          Text('RE: ${reAmount.toStringAsFixed(2)} €'),
                          const Divider(),
                          Text(
                            'Total (sin factor): ${totalSinFactor.toStringAsFixed(2)} €',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Total c/ Factor (x$factor): ${totalConFactor.toStringAsFixed(2)} €',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade700,
                                fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Campos de Fecha
                    InkWell(
                      onTap: () async {
                        DateTime? parsed = DateTime.tryParse(_editInvoiceDateController.text);
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: parsed ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            _editInvoiceDateController.text = DateFormat('yyyy-MM-dd').format(picked);
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Fecha factura'),
                        child: Text(_editInvoiceDateController.text.isNotEmpty
                            ? _editInvoiceDateController.text
                            : 'No seleccionada'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        DateTime? parsed = DateTime.tryParse(_editDueDateController.text);
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: parsed ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            _editDueDateController.text = DateFormat('yyyy-MM-dd').format(picked);
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Fecha vencimiento'),
                        child: Text(_editDueDateController.text.isNotEmpty
                            ? _editDueDateController.text
                            : 'No seleccionada'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  // --- INICIO DE LA CORRECCIÓN ---
                  onPressed: () async {
                      // Guardar una referencia segura al context del State (no al contexto del diálogo)
                      final safeContext = this.context;
                      Navigator.of(ctx).pop(); // Cierra el diálogo
                    
                      setState(() {
                        _isLoading = true; // Mostrar spinner
                      });

                    final projectId =
                        DefaultFirebaseOptions.currentPlatform.projectId;

                    final baseAmount =
                        double.tryParse(_editAmountController.text.replaceAll(',', '.')) ??
                            0.0;
                    final factor = (inv['factor'] as num?)?.toDouble() ?? 1.0;
                    final ivaAmount = baseAmount * (ivaRate ?? 21.0) / 100;
                    final reAmount = baseAmount * reRate / 100;
                    final totalSinFactor = baseAmount + ivaAmount + reAmount;
                    final totalConFactor = totalSinFactor * factor; 

                    final updated = <String, dynamic>{
                      'baseAmount': baseAmount,
                      'iva': ivaAmount,
                      're': reAmount,
                      'amount': totalConFactor, 
                      'company': inv['company'],
                      'client': inv['client'] ?? '',
                    };
                    if (_editInvoiceDateController.text.isNotEmpty) {
                      updated['invoiceDate'] = _editInvoiceDateController.text;
                    }
                    if (_editDueDateController.text.isNotEmpty) {
                      updated['dueDate'] = _editDueDateController.text;
                    }

                    try {
                      // 1. Guardar en Firestore
                      // debug prints removed for production
            // Firestore web interop can be picky with runtime map types (LinkedMap<dynamic,dynamic>),
            // ensure we pass a Map<String, Object?> to avoid type errors on web.
            final Map<String, Object?> safeUpdated = Map<String, Object?>.from(updated);
            await _firestore
              .doc('artifacts/$projectId/public/data/invoices/$id')
              .update(safeUpdated);
                      
                      if (!mounted) return;
                      // Usar safeContext (context del State) para evitar buscar ancestros en el contexto del diálogo
                      ScaffoldMessenger.of(safeContext).showSnackBar(
                        const SnackBar(content: Text('Factura actualizada')),
                      );

                      // 2. Actualizar la lista local (envolvemos en setState para forzar rebuild)
                      final List<dynamic> currentInvoices = _reportResult!['invoices'];
                      final invoiceIndex = currentInvoices.indexWhere((i) => i['id'] == id);
                      if (invoiceIndex != -1) {
                        // debug prints removed for production
                        setState(() {
                          // Reemplazar el elemento por uno nuevo (no mutar en sitio) para
                          // asegurar que Flutter reconstruya correctamente los widgets
                          // Merge and normalize types so UI uses the expected fields
                          final old = Map<String, dynamic>.from(currentInvoices[invoiceIndex] as Map);
                          final merged = <String, dynamic>{...old, ...updated};

                          // Ensure numeric fields are doubles and compute totals with factor
                          final base = (merged['baseAmount'] is num) ? (merged['baseAmount'] as num).toDouble() : double.tryParse(merged['baseAmount']?.toString() ?? '') ?? 0.0;
                          final ivaAmt = (merged['iva'] is num) ? (merged['iva'] as num).toDouble() : 0.0;
                          final reAmt = (merged['re'] is num) ? (merged['re'] as num).toDouble() : 0.0;
                          final factorVal = (merged['factor'] is num) ? (merged['factor'] as num).toDouble() : (merged['amount'] is num && (base + ivaAmt + reAmt) > 0 ? ( (merged['amount'] as num).toDouble() / (base + ivaAmt + reAmt) ) : 1.0);
                          final totalSin = base + ivaAmt + reAmt;
                          final totalCon = totalSin * factorVal;

                          merged['baseAmount'] = base;
                          merged['iva'] = ivaAmt;
                          merged['re'] = reAmt;
                          merged['factor'] = factorVal;
                          merged['amount'] = totalCon; // amount is total with factor (used in UI)

                          currentInvoices[invoiceIndex] = merged;
                          _reportResult!['invoices'] = List<dynamic>.from(currentInvoices);
                        });
                      } else {
                        // debug prints removed for production
                        setState(() {
                          final merged = <String, dynamic>{ 'id': id, ...updated };
                          final base = (merged['baseAmount'] is num) ? (merged['baseAmount'] as num).toDouble() : double.tryParse(merged['baseAmount']?.toString() ?? '') ?? 0.0;
                          final ivaAmt = (merged['iva'] is num) ? (merged['iva'] as num).toDouble() : 0.0;
                          final reAmt = (merged['re'] is num) ? (merged['re'] as num).toDouble() : 0.0;
                          final factorVal = (merged['factor'] is num) ? (merged['factor'] as num).toDouble() : 1.0;
                          final totalSin = base + ivaAmt + reAmt;
                          final totalCon = totalSin * factorVal;
                          merged['baseAmount'] = base;
                          merged['iva'] = ivaAmt;
                          merged['re'] = reAmt;
                          merged['factor'] = factorVal;
                          merged['amount'] = totalCon;

                          final newList = [merged, ...currentInvoices];
                          _reportResult!['invoices'] = List<dynamic>.from(newList);
                        });
                      }

                      // 3. Recalcular localmente (rápido)
                      _recalculateTotalsLocally(currentInvoices);

                      // 4. Asegurar consistencia: recargar el reporte desde Firestore
                      // para que cualquier transformación/normalización en servidor se refleje.
                      // debug prints removed for production
                      await _calculateReport();

                    } catch (e) {
                      if (!mounted) return;
                      setState(() {
                        _isLoading = false; // Quitar spinner en caso de error
                      });
                      // Usar safeContext para evitar usar el contexto del diálogo ya desmontado
                      ScaffoldMessenger.of(safeContext).showSnackBar(
                        SnackBar(
                            content: Text('Error al actualizar factura: $e')),
                      );
                    }
                  },
                  // --- FIN DE LA CORRECCIÓN ---
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
    @override
    void dispose() {
      _editAmountController.dispose();
      _editInvoiceDateController.dispose();
      _editDueDateController.dispose();
    _companiesSubscription?.cancel();
    _invoiceSubscription?.cancel();
    _invoiceNotifierSub?.cancel();
    _invoiceDebounce?.cancel();
      super.dispose();
    }
  }