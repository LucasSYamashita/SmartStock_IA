// lib/features/tenant/tenant_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

    // 🔴 fundamental: garante membership assim que seleciona/entra na loja
    try {
      await ensureMembership(tenantId);
    } catch (_) {/* evita quebrar UI */}
  }

  Future<void> clear() => set(null);
}
