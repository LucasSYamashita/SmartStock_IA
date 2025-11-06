import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/movement.dart';
import '../tenant/tenant_provider.dart';
import '../tenant/membership_guard.dart';

/// Filtro de tipo: 'todos' | 'entrada' | 'saida' | 'ajuste'
final movementTypeFilterProvider =
    StateProvider.autoDispose<String>((_) => 'todos');

/// Filtro de pagamento: 'todos' | 'pix' | 'credito' | 'debito' | 'dinheiro' | 'outros'
/// OBS: só tem efeito quando tipo == 'saida'
final movementPayFilterProvider =
    StateProvider.autoDispose<String>((_) => 'todos');

/// Período selecionado (padrão: últimos 7 dias)
final movementRangeProvider =
    StateProvider.autoDispose<(DateTime from, DateTime to)>((ref) {
  final now = DateTime.now();
  final from =
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
  final to = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  return (from, to);
});

/// Stream de movimentos no período, com filtros de tipo/pagamento aplicados em memória
final movementsStreamProvider =
    StreamProvider.autoDispose<List<Movement>>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null) return Stream.value(<Movement>[]);

  // Garante membership ativo
  final member = ref.watch(membershipProvider(tenantId)).maybeWhen(
        data: (v) => v,
        orElse: () => null,
      );
  final active = (member?['active'] ?? true) as bool? ?? false;
  if (!active || member == null) return Stream.value(<Movement>[]);

  // Período
  final (from, to) = ref.watch(movementRangeProvider);

  // Filtros (aplicados após o fetch, para não exigir índice composto)
  final tipo = ref.watch(movementTypeFilterProvider);
  final pay = ref.watch(movementPayFilterProvider);

  // Query no servidor: SOMENTE por createdAt (range) + orderBy
  final col = FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('movimentos')
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(to))
      .orderBy('createdAt', descending: true)
      .limit(500); // limite defensivo para pagina/UX

  return col.snapshots().map((s) {
    var list =
        s.docs.map((d) => Movement.fromFirestore(d.id, d.data())).toList();

    // Filtro por tipo em memória
    if (tipo != 'todos') {
      list = list.where((m) => (m.tipo ?? '') == tipo).toList();
    }

    // Filtro por pagamento só quando for saída
    if (tipo == 'saida' && pay != 'todos') {
      list = list.where((m) => (m.paymentMethod ?? '') == pay).toList();
    }

    return list;
  });
});
