import 'package:flutter_riverpod/flutter_riverpod.dart';

class TenantIdNotifier extends StateNotifier<String?> {
  TenantIdNotifier() : super(null);
  Future<void> set(String? id) async => state = id;
}

final tenantIdProvider = StateNotifierProvider<TenantIdNotifier, String?>(
    (ref) => TenantIdNotifier());
