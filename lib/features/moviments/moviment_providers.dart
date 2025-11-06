import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/movement.dart';
import '../tenant/tenant_provider.dart';
import '../tenant/membership_guard.dart';

final movementRangeProvider =
    StateProvider.autoDispose<(DateTime from, DateTime to)>((ref) {
  final now = DateTime.now();
  final from =
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
  final to = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  return (from, to);
});

final movementsStreamProvider =
    StreamProvider.autoDispose<List<Movement>>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null) return Stream.value(<Movement>[]);

  final member = ref.watch(membershipProvider(tenantId)).maybeWhen(
        data: (v) => v,
        orElse: () => null,
      );
  final active = (member?['active'] ?? true) as bool? ?? false;
  if (!active || member == null) return Stream.value(<Movement>[]);

  final (from, to) = ref.watch(movementRangeProvider);

  final col = FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('movimentos')
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(to))
      .orderBy('createdAt', descending: true);

  return col.snapshots().map(
        (s) =>
            s.docs.map((d) => Movement.fromFirestore(d.id, d.data())).toList(),
      );
});
