import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream do membership do usuário logado dentro do tenant.
final membershipStreamProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, tenantId) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || tenantId.isEmpty) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('usuarios')
      .doc(uid)
      .snapshots()
      .map((d) => d.data());
});

/// É admin?
final isAdminProvider = Provider.family<bool, String>((ref, tenantId) {
  final async = ref.watch(membershipStreamProvider(tenantId));
  return async.maybeWhen(
    data: (m) => ((m?['role'] ?? '') as String) == 'admin',
    orElse: () => false,
  );
});

/// Pode escrever? (staff ou admin)
final isStaffProvider = Provider.family<bool, String>((ref, tenantId) {
  final async = ref.watch(membershipStreamProvider(tenantId));
  return async.maybeWhen(
    data: (m) {
      final r = (m?['role'] ?? '') as String;
      return r == 'admin' || r == 'staff';
    },
    orElse: () => false,
  );
});

/// Papel efetivo para headers do backend (fallback em 'staff' p/ testes).
final effectiveRoleProvider = Provider.family<String, String>((ref, tenantId) {
  final async = ref.watch(membershipStreamProvider(tenantId));
  return async.maybeWhen(
    data: (m) {
      final r = (m?['role'] ?? '') as String;
      if (r == 'admin' || r == 'staff') return r;
      return 'staff';
    },
    orElse: () => 'staff',
  );
});
