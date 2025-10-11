// lib/features/tenant/membership.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> ensureMembership(String tenantId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || tenantId.isEmpty) return;

  final ref = FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('usuarios')
      .doc(uid);

  final snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      'role': 'staff', // mínimo p/ ler/escrever estoque
      'active': true,
      'displayName': FirebaseAuth.instance.currentUser?.displayName ?? '',
      'email': FirebaseAuth.instance.currentUser?.email ?? '',
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } else {
    // se existir mas estiver desativado, reativa
    final data = snap.data() ?? {};
    if (data['active'] == false) {
      await ref.set({'active': true}, SetOptions(merge: true));
    }
  }
}
