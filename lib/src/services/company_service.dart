import 'package:cloud_firestore/cloud_firestore.dart';

class CompanyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String appId;

  CompanyService(this.appId);

  // Add a new company document under the configured collection.
  // Returns the document path on success, or null on failure.
  Future<String?> addCompany(String companyName) async {
    try {
      print('Intentando agregar empresa: $companyName');
      print('Ruta de colección: artifacts/$appId/public/data/companies');
      
      final docRef = await _firestore.collection('artifacts/$appId/public/data/companies').add({
        'name': companyName,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
      });
      return docRef.path; // e.g. artifacts/{projectId}/public/data/companies/{docId}
    } catch (e) {
      // ignore: avoid_print
      print('Error adding company: $e');
      return null;
    }
  }

  // Edit a company's name by finding the document with matching name and updating it.
  // Also updates all invoices associated with this company
  Future<bool> editCompany(String oldName, String newName) async {
    try {
      print('Iniciando actualización de empresa: $oldName -> $newName');
      print('Ruta de colección: artifacts/$appId/public/data/companies');
      
      // Start a new transaction
      return await _firestore.runTransaction<bool>((transaction) async {
        // Get company document
        final companyQuery = await _firestore
            .collection('artifacts/$appId/public/data/companies')
            .where('name', isEqualTo: oldName)
            .limit(1)
            .get();
        
        if (companyQuery.docs.isEmpty) {
          print('Error: No se encontró la empresa con nombre: $oldName');
          return false;
        }

        final companyDoc = companyQuery.docs.first;
        print('Empresa encontrada, ID: ${companyDoc.id}');
        
        // Get all invoices for this company
        final invoicesRef = _firestore.collection('artifacts/$appId/public/data/invoices');
        final invoicesQuery = await invoicesRef
            .where('company', isEqualTo: oldName)
            .get();

        print('Encontradas ${invoicesQuery.docs.length} facturas para actualizar');

        // Update company name in transaction
        transaction.update(companyDoc.reference, {'name': newName});
        
        // Update all invoices in the same transaction
        for (var invoice in invoicesQuery.docs) {
          transaction.update(invoice.reference, {'company': newName});
        }

        print('Actualizando ${invoicesQuery.docs.length} facturas en una transacción atómica');
        return true;
      });
    } catch (e) {
      print('Error detallado al editar empresa:');
      print('- Empresa antigua: $oldName');
      print('- Empresa nueva: $newName');
      print('- Error: $e');
      print('- Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  // Mark a company as deleted and optionally delete associated invoices
  Future<bool> deleteCompany(String companyName, {bool deleteInvoices = false}) async {
    try {
      return await _firestore.runTransaction<bool>((transaction) async {
        // Get company document
        final companyQuery = await _firestore
            .collection('artifacts/$appId/public/data/companies')
            .where('name', isEqualTo: companyName)
            .limit(1)
            .get();
        
        if (companyQuery.docs.isEmpty) {
          print('Error: No se encontró la empresa "$companyName" para eliminar');
          return false;
        }
        
        // Get company document reference
        final companyDoc = companyQuery.docs.first;
        print('Empresa encontrada para eliminar, ID: ${companyDoc.id}');

        // If we need to delete invoices, get them first
        if (deleteInvoices) {
          final invoicesQuery = await _firestore
              .collection('artifacts/$appId/public/data/invoices')
              .where('company', isEqualTo: companyName)
              .get();

          // Delete all associated invoices in the transaction
          for (var invoice in invoicesQuery.docs) {
            transaction.delete(invoice.reference);
          }
        }

        // Mark company as deleted with timestamp
        transaction.update(companyDoc.reference, {
          'deleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
        });
        
        return true;
      });
    } catch (e) {
      // ignore: avoid_print
      print('Error marking company as deleted: $e');
      return false;
    }
  }

  // Get companies stream, optionally including deleted ones
  Stream<QuerySnapshot> getCompaniesStream({bool includeDeleted = false}) {
    Query query = _firestore.collection('artifacts/$appId/public/data/companies');
    
    // Si no queremos incluir las eliminadas, solo mostramos las que no están marcadas como eliminadas
    if (!includeDeleted) {
      query = query.where('deleted', isEqualTo: false);
    }
    
    return query.snapshots();
  }

  /// One-shot read of company names. Useful if the stream is not delivering
  /// (e.g. due to rules not deployed) — this lets the UI attempt a manual load.
  Future<List<String>> getCompaniesOnce() async {
    final snapshot = await _firestore.collection('artifacts/$appId/public/data/companies')
        .where('deleted', isEqualTo: false)
        .get();
    return snapshot.docs.map((d) => (d.data()['name'] as String?) ?? '').where((s) => s.isNotEmpty).toList();
  }

  // CLIENTS: support clients as a subcollection under each company document.
  // Returns a stream of client documents for the given company name (only active clients by default).
  Stream<QuerySnapshot> getClientsStream(String companyName, {bool includeDeleted = false}) {
    // Listen to company doc snapshots, then switch to the clients subcollection stream.
    final companyQueryStream = _firestore
        .collection('artifacts/$appId/public/data/companies')
        .where('name', isEqualTo: companyName)
        .limit(1)
        .snapshots();

    return companyQueryStream.asyncExpand((companySnap) {
      if (companySnap.docs.isEmpty) return const Stream.empty();
      final companyRef = companySnap.docs.first.reference;
      Query clientsQuery = companyRef.collection('clients');
      if (!includeDeleted) clientsQuery = clientsQuery.where('deleted', isEqualTo: false);
      return clientsQuery.snapshots();
    });
  }

  // One-shot read of clients for a company
  Future<List<String>> getClientsOnce(String companyName, {bool includeDeleted = false}) async {
    final companyQuery = await _firestore
        .collection('artifacts/$appId/public/data/companies')
        .where('name', isEqualTo: companyName)
        .limit(1)
        .get();
    if (companyQuery.docs.isEmpty) return <String>[];
    final companyRef = companyQuery.docs.first.reference;
    Query q = companyRef.collection('clients');
    if (!includeDeleted) q = q.where('deleted', isEqualTo: false);
    final clientsSnap = await q.get();
    return clientsSnap.docs.map((d) => ((d.data() as Map<String, dynamic>)['name'] as String?) ?? '').where((s) => s.isNotEmpty).toList();
  }

  Future<String?> addClient(String companyName, String clientName) async {
    try {
      print('Intentando agregar cliente "$clientName" a la empresa "$companyName" en la ruta: artifacts/$appId/public/data/companies');
      
      final companyQuery = await _firestore
          .collection('artifacts/$appId/public/data/companies')
          .where('name', isEqualTo: companyName)
          .limit(1)
          .get();
          
      print('Resultado de búsqueda de empresa: ${companyQuery.docs.length} documentos encontrados');
      
      if (companyQuery.docs.isEmpty) {
        print('No se encontró la empresa: $companyName');
        return null;
      }
      
      final companyRef = companyQuery.docs.first.reference;
      print('ID del documento de empresa encontrado: ${companyRef.id}');
      
      final docRef = await companyRef.collection('clients').add({
        'name': clientName,
        'createdAt': FieldValue.serverTimestamp(),
        'deleted': false,
      });
      
      print('Cliente agregado exitosamente. Path: ${docRef.path}');
      return docRef.path;
    } catch (e) {
      print('Error detallado al agregar cliente:');
      print('- Empresa: $companyName');
      print('- Cliente: $clientName');
      print('- Error: $e');
      print('- Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  Future<bool> editClient(String companyName, String oldName, String newName) async {
    try {
      final companyQuery = await _firestore
          .collection('artifacts/$appId/public/data/companies')
          .where('name', isEqualTo: companyName)
          .limit(1)
          .get();
      if (companyQuery.docs.isEmpty) return false;
      final companyRef = companyQuery.docs.first.reference;
      final clientQuery = await companyRef.collection('clients').where('name', isEqualTo: oldName).limit(1).get();
      if (clientQuery.docs.isEmpty) return false;
      await clientQuery.docs.first.reference.update({'name': newName});
      return true;
    } catch (e) {
      print('Error editing client: $e');
      return false;
    }
  }

  Future<bool> deleteClient(String companyName, String clientName) async {
    try {
      final companyQuery = await _firestore
          .collection('artifacts/$appId/public/data/companies')
          .where('name', isEqualTo: companyName)
          .limit(1)
          .get();
      if (companyQuery.docs.isEmpty) return false;
      final companyRef = companyQuery.docs.first.reference;
      final clientQuery = await companyRef.collection('clients').where('name', isEqualTo: clientName).limit(1).get();
      if (clientQuery.docs.isEmpty) return false;
      // Soft-delete the client
      await clientQuery.docs.first.reference.update({
        'deleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Error deleting client: $e');
      return false;
    }
  }
}
