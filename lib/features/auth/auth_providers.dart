import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/app_user.dart';

final firebaseAuthStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final userDocProvider =
    StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
  final user = ref.watch(firebaseAuthStateProvider).value;
  if (user == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('usuarios')
      .doc(user.uid)
      .snapshots();
});

final appUserProvider = Provider<AppUser?>((ref) {
  final user = ref.watch(firebaseAuthStateProvider).value;
  final doc = ref.watch(userDocProvider).value;
  if (user == null || doc == null || !doc.exists) return null;
  final data = doc.data()!;
  return AppUser.fromMap(user.uid, {
    'email': user.email ?? data['email'],
    'displayName': user.displayName ?? data['displayName'],
    'role': data['role'] ?? 'viewer',
  });
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

final roleProvider = Provider<Role>((ref) {
  final u = ref.watch(appUserProvider);
  return roleFromString(u?.role ?? 'viewer');
});
