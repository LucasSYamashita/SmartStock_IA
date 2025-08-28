import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tenant/tenant_provider.dart';

class CartItem {
  final String productId;
  final String nome;
  final int quantity;
  final double unitPrice;

  const CartItem({
    required this.productId,
    required this.nome,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => unitPrice * quantity;

  CartItem copyWith({int? quantity, double? unitPrice}) => CartItem(
        productId: productId,
        nome: nome,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'nome': nome,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };

  factory CartItem.fromJson(Map<String, dynamic> m) => CartItem(
        productId: (m['productId'] ?? '') as String,
        nome: (m['nome'] ?? '') as String,
        quantity: (m['quantity'] as num?)?.toInt() ?? 0,
        unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Carrinho com persistência por tenant.
/// Salva/restaura automaticamente ao trocar de loja.
class CartNotifier extends StateNotifier<List<CartItem>> {
  final Ref ref;
  SharedPreferences? _prefs;
  String? _tenantId;

  CartNotifier(this.ref) : super(const []) {
    // observa mudanças de loja
    ref.listen<String?>(tenantIdProvider, (prev, next) async {
      await _ensurePrefs();

      // salva carrinho da loja anterior
      if (prev != next && prev != null) {
        await _saveFor(prev);
      }

      // carrega carrinho da nova loja
      _tenantId = next;
      await _loadFor(_tenantId);
    });

    // carga inicial
    _init();
  }

  Future<void> _init() async {
    await _ensurePrefs();
    _tenantId = ref.read(tenantIdProvider);
    await _loadFor(_tenantId);
  }

  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  String _keyFor(String? tenantId) => 'cart_${tenantId ?? "orphan"}';

  Future<void> _loadFor(String? tenantId) async {
    await _ensurePrefs();
    final raw = _prefs!.getString(_keyFor(tenantId));
    if (raw == null || raw.isEmpty) {
      state = const [];
      return;
    }
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList();
      state = list;
    } catch (_) {
      state = const [];
    }
  }

  Future<void> _save() => _saveFor(_tenantId);
  Future<void> _saveFor(String? tenantId) async {
    await _ensurePrefs();
    final raw = jsonEncode(state.map((e) => e.toJson()).toList());
    await _prefs!.setString(_keyFor(tenantId), raw);
  }

  /// Adiciona novo item ou incrementa a quantidade do existente
  void addOrInc(CartItem item, {int by = 1}) {
    if (by == 0) return;
    final idx = state.indexWhere((e) => e.productId == item.productId);
    if (idx < 0) {
      final initialQty = item.quantity > 0 ? item.quantity : (by > 0 ? by : 1);
      state = [...state, item.copyWith(quantity: initialQty)];
    } else {
      final cur = state[idx];
      final next = cur.quantity + by;
      if (next <= 0) {
        remove(cur.productId);
        return;
      }
      state = [...state]..[idx] = cur.copyWith(quantity: next);
    }
    _save();
  }

  /// Incrementa 1 (ou N) um item existente
  void inc(String productId, {int by = 1}) {
    final idx = state.indexWhere((e) => e.productId == productId);
    if (idx < 0) return;
    final cur = state[idx];
    state = [...state]..[idx] = cur.copyWith(quantity: cur.quantity + by);
    _save();
  }

  /// Decrementa 1 (ou N). Se chegar a 0, remove.
  void dec(String productId, {int by = 1}) {
    final idx = state.indexWhere((e) => e.productId == productId);
    if (idx < 0) return;
    final q = state[idx].quantity - by;
    setQuantity(productId, q);
  }

  /// Define a quantidade exata (<=0 remove)
  void setQuantity(String productId, int qty) {
    final idx = state.indexWhere((e) => e.productId == productId);
    if (idx < 0) return;
    if (qty <= 0) {
      remove(productId);
      return;
    }
    state = [...state]..[idx] = state[idx].copyWith(quantity: qty);
    _save();
  }

  /// Atualiza preço unitário (se necessário)
  void setUnitPrice(String productId, double unitPrice) {
    final idx = state.indexWhere((e) => e.productId == productId);
    if (idx < 0) return;
    state = [...state]..[idx] = state[idx].copyWith(unitPrice: unitPrice);
    _save();
  }

  void remove(String productId) {
    state = state.where((e) => e.productId != productId).toList();
    _save();
  }

  void clear() {
    state = const [];
    _save();
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier(ref);
});

/// Quantidade de **itens distintos** (para badge)
final cartCountProvider = Provider<int>((ref) {
  final items = ref.watch(cartProvider);
  return items.length;
});

/// Quantidade **total de unidades** (somando quantidades)
final cartTotalQtyProvider = Provider<int>((ref) {
  final items = ref.watch(cartProvider);
  return items.fold(0, (sum, e) => sum + e.quantity);
});

/// Subtotal (R$)
final cartSubtotalProvider = Provider<double>((ref) {
  final items = ref.watch(cartProvider);
  return items.fold(0.0, (sum, e) => sum + e.total);
});
