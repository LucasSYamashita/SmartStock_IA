import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controller do tenantId selecionado (loja atual).
class TenantIdController extends StateNotifier<String?> {
  TenantIdController(this._ref) : super(null) {
    _init();
  }

  final Ref _ref;
  static const _key = 'tenantId';

  // Uma única future de SharedPreferences para evitar várias criações.
  late final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  Future<void> _init() async {
    try {
      final prefs = await _prefsFuture;
      final saved = prefs.getString(_key);
      state = saved;
    } catch (e) {
      debugPrint('TenantIdController _init error: $e');
    }

    // Se o usuário deslogar, limpamos o tenant selecionado.
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) {
        await set(null);
      }
    });
  }

  /// Define o tenant atual (ou limpa com null) e persiste.
  Future<void> set(String? id) async {
    state = id;
    try {
      final prefs = await _prefsFuture;
      if (id == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, id);
      }
    } catch (e) {
      debugPrint('TenantIdController set error: $e');
    }
  }

  /// Atalho para limpar.
  Future<void> clear() => set(null);
}

/// Estado reativo do tenantId atual.
final tenantIdProvider =
    StateNotifierProvider<TenantIdController, String?>((ref) {
  return TenantIdController(ref);
});

/// Referência do documento da loja atual (ou null se não houver).
final tenantRefProvider =
    Provider<DocumentReference<Map<String, dynamic>>?>((ref) {
  final id = ref.watch(tenantIdProvider);
  if (id == null) return null;
  return FirebaseFirestore.instance.collection('tenants').doc(id);
});

/// Documento da loja atual (stream), útil para pegar nome, code, etc.
final tenantDocProvider =
    StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
  final tenantRef = ref.watch(tenantRefProvider);
  if (tenantRef == null) return const Stream.empty();
  return tenantRef.snapshots();
});
