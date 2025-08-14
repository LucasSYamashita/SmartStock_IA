import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super(const []);

  /// Adiciona novo item ou incrementa a quantidade do existente
  void addOrInc(CartItem item, {int by = 1}) {
    final idx = state.indexWhere((e) => e.productId == item.productId);
    if (idx < 0) {
      state = [...state, item];
    } else {
      final cur = state[idx];
      state = [...state]..[idx] = cur.copyWith(quantity: cur.quantity + by);
    }
  }

  /// Define a quantidade exata
  void setQuantity(String productId, int qty) {
    if (qty <= 0) {
      remove(productId);
      return;
    }
    final idx = state.indexWhere((e) => e.productId == productId);
    if (idx < 0) return;
    state = [...state]..[idx] = state[idx].copyWith(quantity: qty);
  }

  void dec(String productId, {int by = 1}) {
    final idx = state.indexWhere((e) => e.productId == productId);
    if (idx < 0) return;
    final q = state[idx].quantity - by;
    setQuantity(productId, q);
  }

  void remove(String productId) {
    state = state.where((e) => e.productId != productId).toList();
  }

  void clear() => state = const [];
}

final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>((_) => CartNotifier());

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
