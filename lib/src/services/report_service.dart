import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:math' as math;

class ReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String appId;

  ReportService(this.appId);

  /// Calculate report locally by querying Firestore. Returns a map with:
  /// - totalSum: double
  /// - invoiceCount: int
  /// - sumByDate: Map<String,double> (sums per invoiceDate)
  Future<Map<String, dynamic>> calculateReport({
    required List<String> selectedCompanies,
    Map<String, Set<String>>? selectedClients,
    required String filterType,
    List<String>? selectedDates,
    String? startDate,
    String? endDate,
    String? rangeType,
    String? selectedInvoiceDate,
    String? selectedDueDate,
    bool includeDeletedCompanies = false,
  }) async {
    try {
      // Primero obtener el estado de todas las empresas
      final companiesSnapshot = await _firestore
          .collection('artifacts/$appId/public/data/companies')
          .get();
      
      // Crear un mapa de empresas y su estado de eliminación
      final Map<String, bool> companyDeletedStatus = {};
      for (var doc in companiesSnapshot.docs) {
        final data = doc.data();
        companyDeletedStatus[data['name'] as String] = data['deleted'] == true;
      }

      final collectionPath = 'artifacts/$appId/public/data/invoices';
      
      // Obtener todas las facturas, ordenadas por fecha
      final snapshot = await _firestore
          .collection(collectionPath)
          .orderBy('timestamp', descending: true)
          .get();

      // Filtrar en memoria
      List<QueryDocumentSnapshot> docs = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return false;

        final company = data['company']?.toString() ?? '';
        
        // Verificar si la empresa está eliminada
        final isCompanyDeleted = companyDeletedStatus[company] ?? false;
        if (isCompanyDeleted && !includeDeletedCompanies) {
          return false;
        }

        // Filtrar por empresa si hay seleccionadas
        if (selectedCompanies.isNotEmpty) {
          if (!selectedCompanies.contains(company)) return false;
        }

        // Filtrar por cliente si hay seleccionados para esta empresa
        if (selectedClients != null && selectedClients.containsKey(company)) {
          final clientsForCompany = selectedClients[company];
          if (clientsForCompany != null && clientsForCompany.isNotEmpty) {
            final client = data['client']?.toString() ?? '';
            if (!clientsForCompany.contains(client)) return false;
          }
        }

        // Filtrar por fecha si hay rango seleccionado
        if (startDate != null && endDate != null) {
          final invoiceDate = data['invoiceDate']?.toString() ?? '';
          final dueDate = data['dueDate']?.toString() ?? '';

          switch (rangeType) {
            case 'invoiceDate':
              return invoiceDate.compareTo(startDate) >= 0 && 
                     invoiceDate.compareTo(endDate) <= 0;
            case 'dueDate':
              return dueDate.compareTo(startDate) >= 0 && 
                     dueDate.compareTo(endDate) <= 0;
            case 'both':
              return (invoiceDate.compareTo(startDate) >= 0 && 
                      invoiceDate.compareTo(endDate) <= 0) ||
                     (dueDate.compareTo(startDate) >= 0 && 
                      dueDate.compareTo(endDate) <= 0);
            default:
              return true;
          }
        }

        // Filtrar por fecha exacta de factura si se proporcionó
        if (selectedInvoiceDate != null && selectedInvoiceDate.isNotEmpty) {
          final invoiceDate = data['invoiceDate']?.toString() ?? '';
          if (invoiceDate != selectedInvoiceDate) return false;
        }

        // Filtrar por fecha exacta de vencimiento si se proporcionó
        if (selectedDueDate != null && selectedDueDate.isNotEmpty) {
          final dueDate = data['dueDate']?.toString() ?? '';
          if (dueDate != selectedDueDate) return false;
        }

        return true;
      }).toList();

      // Calcular totales
      double total = 0.0;
      double baseTotal = 0.0;
      double ivaTotal = 0.0;
      double reTotal = 0.0;
      
      final Map<String, double> sumByDate = {};
      final Map<String, Map<String, dynamic>> sumByCompany = {};
      final Map<String, Map<String, Map<String, dynamic>>> sumByClient = {};

      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

    final baseAmount = (data['baseAmount'] is num)
      ? (data['baseAmount'] as num).toDouble()
      : (data['amount'] is num)
        ? (data['amount'] as num).toDouble()
        : double.tryParse(data['amount']?.toString() ?? '') ?? 0.0;
                
    final ivaAmount = (data['iva'] is num)
      ? (data['iva'] as num).toDouble()
      : 0.0;

    // RE no puede ser negativo: normalizar a >= 0
    final reAmount = math.max(0.0, (data['re'] is num) ? (data['re'] as num).toDouble() : 0.0);
            
        final totalAmount = (data['amount'] is num)
            ? (data['amount'] as num).toDouble()
            : baseAmount + ivaAmount + reAmount;
        
        final invoiceDate = data['invoiceDate']?.toString() ?? '';
        final company = data['company']?.toString() ?? '';
        final client = data['client']?.toString() ?? '';

        total += totalAmount;
        baseTotal += baseAmount;
        ivaTotal += ivaAmount;
        reTotal += reAmount;

        if (invoiceDate.isNotEmpty) {
          sumByDate[invoiceDate] = (sumByDate[invoiceDate] ?? 0.0) + totalAmount;
        }

        // Actualizar sumas por empresa
        if (company.isNotEmpty) {
          if (!sumByCompany.containsKey(company)) {
            sumByCompany[company] = {
              'total': 0.0,
              'base': 0.0,
              'iva': 0.0,
              're': 0.0
            };
          }
          sumByCompany[company]!['total'] = (sumByCompany[company]!['total'] as double) + totalAmount;
          sumByCompany[company]!['base'] = (sumByCompany[company]!['base'] as double) + baseAmount;
          sumByCompany[company]!['iva'] = (sumByCompany[company]!['iva'] as double) + ivaAmount;
          sumByCompany[company]!['re'] = (sumByCompany[company]!['re'] as double) + reAmount;
        }

        // Actualizar sumas por cliente dentro de cada empresa
        if (company.isNotEmpty && client.isNotEmpty) {
          if (!sumByClient.containsKey(company)) {
            sumByClient[company] = {};
          }
          if (!sumByClient[company]!.containsKey(client)) {
            sumByClient[company]![client] = {
              'total': 0.0,
              'base': 0.0,
              'iva': 0.0,
              're': 0.0
            };
          }
          sumByClient[company]![client]!['total'] = (sumByClient[company]![client]!['total'] as double) + totalAmount;
          sumByClient[company]![client]!['base'] = (sumByClient[company]![client]!['base'] as double) + baseAmount;
          sumByClient[company]![client]!['iva'] = (sumByClient[company]![client]!['iva'] as double) + ivaAmount;
          sumByClient[company]![client]!['re'] = (sumByClient[company]![client]!['re'] as double) + reAmount;
        }
      }

      final invoiceList = docs.map((d) {
        final data = d.data() as Map<String, dynamic>?;
        return {
          'id': d.id,
          'company': data?['company']?.toString() ?? '',
          'client': data?['client']?.toString() ?? '',
          'baseAmount': (data?['baseAmount'] is num)
              ? (data!['baseAmount'] as num).toDouble()
              : (data?['amount'] is num)
                  ? (data!['amount'] as num).toDouble()
                  : double.tryParse(data?['amount']?.toString() ?? '') ?? 0.0,
          'iva': (data?['iva'] is num)
              ? (data!['iva'] as num).toDouble()
              : 0.0,
      're': (data?['re'] is num)
        ? math.max(0.0, (data!['re'] as num).toDouble())
        : 0.0,
          'amount': ((data?['baseAmount'] is num)
              ? (data!['baseAmount'] as num).toDouble()
              : (data?['amount'] is num)
                  ? (data!['amount'] as num).toDouble()
                  : double.tryParse(data?['amount']?.toString() ?? '') ?? 0.0) +
            ((data?['iva'] is num) ? (data!['iva'] as num).toDouble() : 0.0) +
            ((data?['re'] is num) ? (data!['re'] as num).toDouble() : 0.0),
          // Incluir factor si existe; si no existe, inferirlo (si baseAmount > 0)
          'factor': (data?['factor'] is num)
              ? (data!['factor'] as num).toDouble()
              : (() {
                  try {
                    final base = (data?['baseAmount'] is num)
                        ? (data!['baseAmount'] as num).toDouble()
                        : double.tryParse(data?['baseAmount']?.toString() ?? '') ?? 0.0;
                    final iva = (data?['iva'] is num) ? (data!['iva'] as num).toDouble() : 0.0;
                    final re = (data?['re'] is num) ? (data!['re'] as num).toDouble() : 0.0;
                    final totalSinFactor = base + iva + re;
                    final amountField = (data?['amount'] is num)
                        ? (data!['amount'] as num).toDouble()
                        : double.tryParse(data?['amount']?.toString() ?? '') ?? 0.0;
                    if (totalSinFactor > 0) {
                      return (amountField / totalSinFactor);
                    }
                  } catch (_) {}
                  return 1.0;
                })(),
          'invoiceDate': data?['invoiceDate']?.toString() ?? '',
          'dueDate': data?['dueDate']?.toString() ?? '',
          'userId': data?['userId']?.toString() ?? '',
          'timestamp': data?['timestamp']?.toString() ?? '',
        };
      }).toList();

      // Diagnostics: list of ids and unique companies found
      final debugIds = invoiceList.map((i) => i['id'] as String).toList();
      final debugCompanies = invoiceList.map((i) => i['company'] as String).toSet().toList();

      // Unique invoiceDate and dueDate values (for building filters in the UI)
      final uniqueInvoiceDates = invoiceList.map((i) => i['invoiceDate'] as String).toSet().toList()..sort();
      final uniqueDueDates = invoiceList.map((i) => i['dueDate'] as String).toSet().toList()..sort();

      return {
        'totalSum': total,
        'baseTotalSum': baseTotal,
        'ivaTotalSum': ivaTotal,
        'reTotalSum': reTotal,
        'invoiceCount': docs.length,
        'sumByDate': sumByDate,
        'sumByCompany': sumByCompany,
        'sumByClient': sumByClient,
        'invoices': invoiceList,
        'debug': {
          'loadedCount': snapshot.docs.length,
          'afterFilterCount': docs.length,
          'ids': debugIds,
          'companies': debugCompanies,
        },
        'uniqueInvoiceDates': uniqueInvoiceDates,
        'uniqueDueDates': uniqueDueDates,
      };
    } catch (e) {
      debugPrint('Error calculando reporte: $e');
      rethrow;
    }
  }
}
