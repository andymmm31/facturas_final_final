import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:excel/excel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Only used on web
import 'package:universal_html/html.dart' as html;

// Only used on non-web
import 'package:path_provider/path_provider.dart';

class ExportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String projectId;

  ExportService(this.projectId);

  /// Exports invoices to Excel. Optional filters:
  /// - selectedCompanies: list of company names to include (null = all)
  /// - startDate/endDate: filter range in YYYY-MM-DD format (inclusive)
  /// - rangeType: 'invoiceDate' or 'dueDate' or 'both' (determines which date field to filter)
  Future<String?> exportInvoicesToExcel({
    String? userId,
    List<String>? selectedCompanies,
    String? startDate,
    String? endDate,
    String rangeType = 'invoiceDate',
    Map<String, Set<String>>? selectedClients,
    bool includeDeletedCompanies = false,
  }) async {
    try {
      final collectionPath = 'artifacts/$projectId/public/data/invoices';

      // To avoid requiring composite indexes on Firestore, always fetch
      // invoices ordered by timestamp and apply company/date filters client-side.
      // This avoids 'The query requires an index' errors at the cost of
      // transferring more documents when the dataset is large.
      // Load invoices ordered by timestamp
      final snapshot = await _firestore.collection(collectionPath).orderBy('timestamp', descending: true).get();
      List<QueryDocumentSnapshot> docs = snapshot.docs;

      // If excluding deleted companies, load companies deletion status
      final Map<String, bool> companyDeletedStatus = {};
      if (!includeDeletedCompanies) {
        final companiesSnapshot = await _firestore.collection('artifacts/$projectId/public/data/companies').get();
        for (var doc in companiesSnapshot.docs) {
          final data = doc.data();
          companyDeletedStatus[data['name'] as String] = data['deleted'] == true;
        }
      }

      // Apply company filter client-side if provided
      if (selectedCompanies != null && selectedCompanies.isNotEmpty) {
        final Set<String> allowed = selectedCompanies.toSet();
        docs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>?;
          final company = data?['company']?.toString() ?? '';
          if (!includeDeletedCompanies && (companyDeletedStatus[company] ?? false)) return false;
          return allowed.contains(company);
        }).toList();
      }

      // Apply client filters per company if provided
      if (selectedClients != null && selectedClients.isNotEmpty) {
        docs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>?;
          final company = data?['company']?.toString() ?? '';
          final client = data?['client']?.toString() ?? '';
          final clientsForCompany = selectedClients[company];
          if (clientsForCompany != null && clientsForCompany.isNotEmpty) {
            return clientsForCompany.contains(client);
          }
          return true;
        }).toList();
      }

      // Apply date filters client-side (invoiceDate / dueDate / both)
      if (startDate != null && endDate != null) {
        if (rangeType == 'invoiceDate') {
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>?;
            final invoiceDate = data?['invoiceDate']?.toString() ?? '';
            return invoiceDate.compareTo(startDate) >= 0 && invoiceDate.compareTo(endDate) <= 0;
          }).toList();
        } else if (rangeType == 'dueDate') {
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>?;
            final dueDate = data?['dueDate']?.toString() ?? '';
            return dueDate.compareTo(startDate) >= 0 && dueDate.compareTo(endDate) <= 0;
          }).toList();
        } else if (rangeType == 'both') {
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>?;
            final invoiceDate = data?['invoiceDate']?.toString();
            final dueDate = data?['dueDate']?.toString();
            final inInvoice = invoiceDate != null && invoiceDate.compareTo(startDate) >= 0 && invoiceDate.compareTo(endDate) <= 0;
            final inDue = dueDate != null && dueDate.compareTo(startDate) >= 0 && dueDate.compareTo(endDate) <= 0;
            return inInvoice || inDue;
          }).toList();
        }
      }

      // Crear un nuevo Excel limpio
      final excel = Excel.createExcel();
      final sheet = excel.sheets['Sheet1']!; // Sheet1 siempre existe en un nuevo Excel
      
      // Configurar encabezados de Facturas con estilo (ampliados)
      final headers = [
        'Empresa',
        'Cliente',
        'Base (€)',
        'IVA (€)',
        'RE (€)',
        'Total sin Factor (€)',
        'Factor',
        'Total c/ Factor (€)',
        'Fecha de Factura',
        'Fecha de Vencimiento',
        'ID'
      ];
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = headers[i];
        cell.cellStyle = CellStyle(
          bold: true,
          horizontalAlign: HorizontalAlign.Center,
        );
      }

      double total = 0.0;
      final Map<String, double> sumByDate = {}; // invoiceDate -> sum

      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>?;
        final id = doc.id;
        final company = data?['company']?.toString() ?? '';
        final client = data?['client']?.toString() ?? '';

        final base = (data?['baseAmount'] is num)
            ? (data?['baseAmount'] as num).toDouble()
            : double.tryParse(data?['baseAmount']?.toString() ?? '') ?? 0.0;

        final iva = (data?['iva'] is num)
            ? (data?['iva'] as num).toDouble()
            : 0.0;

    // Asegurar que RE no sea negativo
    final re = math.max(0.0, (data?['re'] is num) ? (data?['re'] as num).toDouble() : 0.0);

        final factor = (data?['factor'] is num)
            ? (data?['factor'] as num).toDouble()
            : double.tryParse(data?['factor']?.toString() ?? '') ?? 1.0;

        final totalSinFactor = base + iva + re;
        final totalConFactor = totalSinFactor * factor;

        final invoiceDate = data?['invoiceDate']?.toString() ?? '';
        final dueDate = data?['dueDate']?.toString() ?? '';

        // userId and timestamp intentionally omitted from export

        total += totalConFactor;
        if (invoiceDate.isNotEmpty) sumByDate[invoiceDate] = (sumByDate[invoiceDate] ?? 0.0) + totalConFactor;

        // Escribir cada fila de datos con el tipo correcto
        final rowIndex = sheet.maxRows;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = company;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value = client;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value = base;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value = iva;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value = re;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value = totalSinFactor;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex)).value = factor;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex)).value = totalConFactor;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex)).value = invoiceDate;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex)).value = dueDate;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIndex)).value = id;
      }

      // Crear y formatear la hoja de Resumen como segunda hoja
      final resumenSheet = excel['Resumen'];
      
      // Configurar encabezados del resumen
      final summaryHeaders = ['Fecha', 'Importe Total (€)'];
      for (var i = 0; i < summaryHeaders.length; i++) {
        final cell = resumenSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = summaryHeaders[i];
        cell.cellStyle = CellStyle(
          bold: true,
          horizontalAlign: HorizontalAlign.Center,
        );
      }

      // Escribir los datos del resumen
      var rowIndex = 1;
      final sortedDates = sumByDate.keys.toList()..sort();
      for (final date in sortedDates) {
        resumenSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = date;
        resumenSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value = sumByDate[date];
        rowIndex++;
      }

      // Agregar el total
      rowIndex++; // Dejar una fila en blanco
      final totalCell = resumenSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex));
      totalCell.value = 'Total';
      totalCell.cellStyle = CellStyle(bold: true);
      
      final totalAmountCell = resumenSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex));
      totalAmountCell.value = total;
      totalAmountCell.cellStyle = CellStyle(
        bold: true
      );

      final fileBytes = excel.encode();
      if (fileBytes == null) return null;

      if (kIsWeb) {
        final content = base64Encode(fileBytes);
        final anchor = html.AnchorElement(href: 'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$content')
          ..download = 'facturas.xlsx'
          ..target = 'blank';
        html.document.body!.append(anchor);
        anchor.click();
        anchor.remove();
        return 'downloaded: facturas.xlsx';
      } else {
        final bytes = Uint8List.fromList(fileBytes);
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/invoices_${DateTime.now().millisecondsSinceEpoch}.xlsx';
        final file = File(path);
        await file.writeAsBytes(bytes, flush: true);
        return path;
      }
    } catch (e) {
      // Log and return an explicit error string so the UI can display it
      print('Error exporting invoices: $e');
      return 'ERROR: $e';
    }
  }
}
