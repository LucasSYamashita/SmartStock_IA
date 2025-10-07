import 'package:flutter_riverpod/flutter_riverpod.dart';

const kFallbackTenantId = 'TENANT01';

final tenantIdProvider =
    StateNotifierProvider<TenantIdController, String>((ref) {
  return TenantIdController();
});

class TenantIdController extends StateNotifier<String> {
  TenantIdController() : super(kFallbackTenantId);

  // aceita String? e normaliza
  void set(String? value) {
    final v = value?.trim();
    state = (v == null || v.isEmpty) ? kFallbackTenantId : v;
  }

  void clear() => state = kFallbackTenantId;
}
