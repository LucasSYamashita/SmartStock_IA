// lib/features/tenant/membership_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MembershipService {
  final FirebaseFirestore db;
  MembershipService(this.db);

  Future<String?> resolveTenantIdByCode(String code) async {
    final c = code.trim().toUpperCase();
    final q1 = await db
        .collection('tenants')
        .where('code', isEqualTo: c)
        .limit(1)
        .get();
    if (q1.docs.isNotEmpty) return q1.docs.first.id;

    final q2 = await db
        .collection('tenant_codes')
        .where('code', isEqualTo: c)
        .limit(1)
        .get();
    if (q2.docs.isNotEmpty)
      return (q2.docs.first.data()['tenantId'] ?? '').toString();

    return null;
  }

  /// Faz join por código sem rebaixar admin existente.
  Future<void> joinTenantByCode(String tenantId, String code) async {
    final me = FirebaseAuth.instance.currentUser!;
    final uid = me.uid;
    final tSnap = await db.collection('tenants').doc(tenantId).get();
    if (!tSnap.exists) throw StateError('Loja não encontrada.');

    final mRef =
        db.collection('tenants').doc(tenantId).collection('usuarios').doc(uid);
    final mSnap = await mRef.get();

    // Decisão de papel
    String? existingRole = mSnap.data()?['role']?.toString();
    String roleToWrite;
    if (existingRole == 'admin' || existingRole == 'staff') {
      roleToWrite = existingRole!;
    } else {
      final createdBy = tSnap.data()?['createdBy']?.toString();
      roleToWrite = (createdBy == uid) ? 'admin' : 'staff';
    }

    final data = <String, dynamic>{
      'active': true,
      'displayName': me.displayName ?? '',
      'email': me.email ?? '',
      'joinedAt': FieldValue.serverTimestamp(),
      'joinCode': code, // exigido pelas RULES para auto-join
    };
    if (!mSnap.exists || roleToWrite == 'admin') {
      data['role'] = roleToWrite;
    }

    await mRef.set(data, SetOptions(merge: true));
  }
}
