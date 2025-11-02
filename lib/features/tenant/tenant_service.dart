import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TenantService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Cria um tenant (loja) com `name` e um `code` derivado.
  /// Depois cria o documento do usuário logado em `usuarios/{uid}` com role=admin.
  Future<String> createTenant(String name) async {
    final uid = _auth.currentUser!.uid;
    final code = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

    // 1) cria o tenant (regras aceitam createdAt/updatedAt opcionais na criação)
    final ref = await _db.collection('tenants').add({
      'name': name.trim(),
      'code': code,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2) bootstrap: o criador vira admin
    await ref.collection('usuarios').doc(uid).set({
      'role': 'admin',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return ref.id; // tenantId
  }

  /// Caso você já tenha o tenant criado mas o usuário não esteja em /usuarios,
  /// chama isso para se adicionar como admin (desde que seja o createdBy).
  Future<void> repairAccess(String tenantId) async {
    final uid = _auth.currentUser!.uid;
    final ten = await _db.collection('tenants').doc(tenantId).get();
    if (!ten.exists) {
      throw Exception('Tenant inexistente.');
    }
    if (ten.data()!['createdBy'] != uid) {
      throw Exception(
          'Somente o criador do tenant pode se adicionar como admin.');
    }
    await _db
        .collection('tenants')
        .doc(tenantId)
        .collection('usuarios')
        .doc(uid)
        .set({
      'role': 'admin',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
