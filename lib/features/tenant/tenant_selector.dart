// lib/features/tenant/tenant_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTenantKey = 'selected_tenant_id';

final tenantIdProvider = StateNotifierProvider<TenantController, String?>(
  (ref) => TenantController()..load(),
);

class TenantController extends StateNotifier<String?> {
  TenantController() : super(null);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    state = sp.getString(_kTenantKey);
  }

  Future<void> set(String tenantId) async {
    state = tenantId;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kTenantKey, tenantId);
  }

  Future<void> clear() async {
    state = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kTenantKey);
  }
}
