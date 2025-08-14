import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TenantIdController extends StateNotifier<String?> {
  TenantIdController() : super(null) {
    _load();
  }

  static const _key = 'tenantId';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) state = saved;
  }

  Future<void> set(String? id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, id);
    }
  }
}

final tenantIdProvider =
    StateNotifierProvider<TenantIdController, String?>((ref) {
  return TenantIdController();
});
