import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class InvoiceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final String appId;

  InvoiceService(this.appId);

  String get _collectionPath => 'artifacts/$appId/public/data/invoices';

  Future<String> addInvoice({
    required String company,
    String? client,
    required double amount,
    required DateTime invoiceDate,
    required DateTime dueDate,
    double? baseAmount,
    double? iva,
    double? re,
  }) async {
    final User? currentUser = _auth.currentUser;

    final ref = await _firestore.collection(_collectionPath).add({
      'company': company,
      'client': client,
      'amount': amount,
      'baseAmount': baseAmount ?? amount,
      'iva': iva,
      're': re,
      'invoiceDate': invoiceDate.toIso8601String().split('T').first, // Format as YYYY-MM-DD
      'dueDate': dueDate.toIso8601String().split('T').first,       // Format as YYYY-MM-DD
      'userId': currentUser?.uid ?? 'anonymous',
      'timestamp': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  Future<Map<String, dynamic>?> getInvoiceById(String id) async {
    final doc = await _firestore.collection(_collectionPath).doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data();
    return {
      'id': doc.id,
      ...data ?? {},
    };
  }

  Future<Map<String, dynamic>?> getLastInvoice() async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return null;

      final doc = querySnapshot.docs.first;
      final data = doc.data();
      return {
        'id': doc.id,
        ...data,
      };
    } catch (e) {
      debugPrint('Error obteniendo última factura: $e');
      return null;
    }
  }

  Future<bool> updateInvoice({
    required String id,
    required String company,
    String? client,
    required double amount,
    required DateTime invoiceDate,
    required DateTime dueDate,
    double? baseAmount,
    double? iva,
    double? re,
  }) async {
    try {
      final updated = <String, Object?>{
        'company': company,
        'client': client,
        'amount': amount,
        'baseAmount': baseAmount ?? amount,
        'iva': iva,
        're': re,
        'invoiceDate': invoiceDate.toIso8601String().split('T').first,
        'dueDate': dueDate.toIso8601String().split('T').first,
        'lastModified': FieldValue.serverTimestamp(),
      };
      final safe = Map<String, Object?>.from(updated);
      await _firestore.collection(_collectionPath).doc(id).update(safe);
      return true;
    } catch (e) {
      debugPrint('Error actualizando factura: $e');
      return false;
    }
  }

  Future<bool> deleteInvoice(String id) async {
    try {
      // Diagnostics: log attempt
      debugPrint('Attempting deleteInvoice id=$id on path=$_collectionPath');
      // Primero verificamos si el documento existe
      final docRef = _firestore.collection(_collectionPath).doc(id);
      final doc = await docRef.get();
      debugPrint('deleteInvoice: doc.exists=${doc.exists}');
      if (!doc.exists) {
        debugPrint('La factura no existe (id=$id)');
        return false;
      }

      final data = doc.data();
      final userId = data?['userId'] as String?;
      final currentUser = _auth.currentUser;
      debugPrint('deleteInvoice: doc.userId=$userId, currentUser=${currentUser?.uid}');

      if (currentUser == null) {
        debugPrint('Usuario no autenticado');
        return false;
      }

      if (userId != 'anonymous' && userId != currentUser.uid) {
        debugPrint('Usuario no autorizado para eliminar esta factura (doc.userId=$userId)');
        return false;
      }

      await docRef.delete();
      debugPrint('deleteInvoice: deleted id=$id');
      return true;
    } catch (e) {
      debugPrint('Error eliminando factura: $e');
      return false;
    }
  }
}
