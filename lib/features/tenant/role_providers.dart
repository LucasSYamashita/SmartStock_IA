// lib/features/tenant/role_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final memberDocProvider = StreamProvider.family
    .autoDispose<Map<String, dynamic>?, String>((ref, tenantId) {
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

final effectiveRoleProvider = Provider.family<String, String>((ref, tenantId) {
  final snap = ref.watch(memberDocProvider(tenantId)).value;
  final role = (snap?['role'] ?? '') as String;
  return (role == 'admin' || role == 'staff') ? role : 'viewer';
});

final isStaffProvider = Provider.family<bool, String>((ref, tenantId) {
  final r = ref.watch(effectiveRoleProvider(tenantId));
  return r == 'admin' || r == 'staff';
});

final isAdminProvider = Provider.family<bool, String>((ref, tenantId) {
  final r = ref.watch(effectiveRoleProvider(tenantId));
  return r == 'admin';
});
