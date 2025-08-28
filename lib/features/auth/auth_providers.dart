import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../tenant/tenant_provider.dart'; // <- usa o tenantId salvo
import '../../data/models/app_user.dart'; // seu modelo

/// Auth reativo (inclui mudanças de displayName/email sem deslogar)
final firebaseAuthStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.userChanges(),
);

/// Perfil “global” do usuário (raiz /usuarios/{uid}) — opcional, só para dados públicos/perfil
final userProfileDocProvider =
    StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
  final auth = ref.watch(firebaseAuthStateProvider).value;
  if (auth == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('usuarios')
      .doc(auth.uid)
      .snapshots();
});

/// Membership do usuário na LOJA atual (role/admin/staff) — FONTE DA VERDADE DO ACESSO
final membershipDocProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final auth = ref.watch(firebaseAuthStateProvider).value;
  final tenantId = ref.watch(tenantIdProvider);
  if (auth == null || tenantId == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('usuarios')
      .doc(auth.uid)
      .snapshots()
      .map((d) => d.data());
});

/// AppUser combinado: dados básicos do auth/perfil + role do membership do tenant atual
final appUserProvider = Provider<AppUser?>((ref) {
  final auth = ref.watch(firebaseAuthStateProvider).value;
  if (auth == null) return null;

  final profileSnap = ref.watch(userProfileDocProvider).value;
  final membership = ref.watch(membershipDocProvider).value;

  final profile = profileSnap?.data();
  final role = (membership?['role'] ?? 'viewer').toString();

  return AppUser.fromMap(
    auth.uid,
    {
      'email': auth.email ?? profile?['email'],
      'displayName': auth.displayName ?? profile?['displayName'],
      'role': role, // <- vem do membership do tenant atual
    },
  );
});

enum Role { viewer, staff, admin }

Role roleFromString(String s) {
  switch (s) {
    case 'admin':
      return Role.admin;
    case 'staff':
      return Role.staff;
    default:
      return Role.viewer;
  }
}

/// Role atual (baseado no tenant selecionado)
final roleProvider = Provider<Role>((ref) {
  final user = ref.watch(appUserProvider);
  return roleFromString(user?.role ?? 'viewer');
});

/// Helpers práticos de permissão
final isAdminProvider =
    Provider<bool>((ref) => ref.watch(roleProvider) == Role.admin);
final isStaffProvider = Provider<bool>((ref) {
  final r = ref.watch(roleProvider);
  return r == Role.staff || r == Role.admin;
});
