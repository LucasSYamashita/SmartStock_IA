import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> ensureMember({
  required String tenantId,
  String role = 'admin', // 'admin' | 'staff' | 'viewer'
}) async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final ref = FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('usuarios')
      .doc(uid);
  await ref.set({'role': role}, SetOptions(merge: true));
}
