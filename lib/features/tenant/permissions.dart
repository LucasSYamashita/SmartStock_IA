import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tenant_provider.dart';

/// Admin = role 'admin' no membership da loja atual
final isAdminProvider = StreamProvider<bool>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (tenantId == null || uid == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('usuarios')
      .doc(uid)
      .snapshots()
      .map((d) => (d.data()?['role'] ?? '') == 'admin');
});
