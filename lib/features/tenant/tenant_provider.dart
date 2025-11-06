// lib/features/tenant/tenant_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'membership.dart';

final tenantIdProvider =
    StateNotifierProvider<TenantIdNotifier, String?>((ref) {
  return TenantIdNotifier();
});

class TenantIdNotifier extends StateNotifier<String?> {
  TenantIdNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('tenantId');
    state = v;
  }

  Future<void> set(String? tenantId) async {
    final prefs = await SharedPreferences.getInstance();
    if (tenantId == null || tenantId.isEmpty) {
      await prefs.remove('tenantId');
      state = null;
      return;
    }
    await prefs.setString('tenantId', tenantId);
    state = tenantId;

    // garante membership assim que entra/seleciona a loja
    try {
      await ensureMembership(tenantId);
    } catch (_) {/* evita quebrar UI */}
  }

  Future<void> clear() => set(null);
}

/// Nome da loja para exibir na AppBar (aceita "name" ou "nome")
final tenantNameProvider = StreamProvider.autoDispose<String?>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .snapshots()
      .map((doc) {
    final data = doc.data();
    if (data == null) return tenantId;
    return (data['name'] as String?) ?? (data['nome'] as String?) ?? tenantId;
  });
});
