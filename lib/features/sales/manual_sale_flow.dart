import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../tenant/tenant_provider.dart';
import '../../data/datasources/firestore_movements.dart';
import 'cart_state.dart';

/// Stream de produtos da loja atual
final _productsProvider =
    StreamProvider<QuerySnapshot<Map<String, dynamic>>>((ref) {
  final tenantId = ref.watch(tenantIdProvider);
  if (tenantId == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('tenants')
      .doc(tenantId)
      .collection('produtos')
      .orderBy('nome')
      .snapshots();
});

/// Página 1: catálogo com cards e badge do carrinho
class ManualSaleCatalogPage extends ConsumerStatefulWidget {
  const ManualSaleCatalogPage({super.key});
  @override
  ConsumerState<ManualSaleCatalogPage> createState() =>
      _ManualSaleCatalogPageState();
}

class _ManualSaleCatalogPageState extends ConsumerState<ManualSaleCatalogPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_productsProvider);
    final cartCount = ref.watch(cartCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vender'),
        actions: [
          // ícone do carrinho com badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: cartCount == 0
                    ? null
                    : () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ManualSaleCheckoutPage(),
                        ));
                      },
              ),
              if (cartCount > 0)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$cartCount',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, height: 1),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar produto…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: async.when(
              data: (snap) {
                final docs = snap.docs.where((d) {
                  if (_query.isEmpty) return true;
                  final m = d.data();
                  final nome = (m['nome'] ?? '').toString().toLowerCase();
                  final marca = (m['marca'] ?? m['categoria'] ?? '')
                      .toString()
                      .toLowerCase();
                  return nome.contains(_query) || marca.contains(_query);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(
                      child: Text('Nenhum produto encontrado.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final id = docs[i].id;
                    final nome = (m['nome'] ?? '').toString();
                    final qAny = m['quantidade'] ?? 0;
                    final qtd =
                        qAny is num ? qAny.toInt() : int.tryParse('$qAny') ?? 0;
                    final priceAny = m['precoVenda'] ?? m['valor'] ?? 0.0;
                    final price = priceAny is num
                        ? priceAny.toDouble()
                        : double.tryParse('$priceAny') ?? 0.0;

                    return _ProductCard(
                      productId: id,
                      nome: nome,
                      estoque: qtd,
                      price: price,
                      onAdd: () {
                        ref.read(cartProvider.notifier).addOrInc(CartItem(
                              productId: id,
                              nome: nome,
                              quantity: 1,
                              unitPrice: price,
                            ));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('"$nome" adicionado ao carrinho.')),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: cartCount == 0
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ManualSaleCheckoutPage()),
                );
              },
        icon: const Icon(Icons.point_of_sale),
        label: const Text('Fechar venda'),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final String productId;
  final String nome;
  final int estoque;
  final double price;
  final VoidCallback onAdd;
  const _ProductCard({
    required this.productId,
    required this.nome,
    required this.estoque,
    required this.price,
    required this.onAdd,
  });

  String _fmt(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
            child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?')),
        title: Text(nome),
        subtitle: Text('Estoque: $estoque  •  Preço: ${_fmt(price)}'),
        trailing: FilledButton.tonalIcon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Adicionar'),
        ),
      ),
    );
  }
}

/// Página 2: checkout (pagamento/ desconto) e gravação + recibo
class ManualSaleCheckoutPage extends ConsumerStatefulWidget {
  const ManualSaleCheckoutPage({super.key});
  @override
  ConsumerState<ManualSaleCheckoutPage> createState() =>
      _ManualSaleCheckoutPageState();
}

class _ManualSaleCheckoutPageState
    extends ConsumerState<ManualSaleCheckoutPage> {
  // pagamento
  String method = 'pix'; // pix, dinheiro, debito, credito
  // desconto
  bool percent = false; // false = valor, true = porcentagem
  final _discountCtrl = TextEditingController();

  bool saving = false;
  String? err;

  String _fmt(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  double _parseDiscount() {
    final raw = _discountCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(raw) ?? 0.0;
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final d = _parseDiscount();
    final desconto = percent ? subtotal * (d / 100.0) : d;
    // ✅ forçar double para evitar erro de tipo ao chamar _finalizar
    final total = (subtotal - desconto).clamp(0, double.infinity).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Pagamento & desconto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // itens
          Card(
            child: Column(
              children: [
                for (final it in items)
                  ListTile(
                    title: Text(it.nome),
                    subtitle: Text('${it.quantity} × ${_fmt(it.unitPrice)}'),
                    trailing: Text(_fmt(it.total)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // desconto
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _discountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        // ✅ corrigido para "R$"
                        labelText: percent ? 'Desconto (%)' : 'Desconto (R\$)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      // ✅ corrigido para "R$"
                      ButtonSegment(value: false, label: Text('R\$')),
                      ButtonSegment(value: true, label: Text('%')),
                    ],
                    selected: {percent},
                    onSelectionChanged: (s) =>
                        setState(() => percent = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // pagamento
          Card(
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'pix',
                  groupValue: method,
                  onChanged: (v) => setState(() => method = v!),
                  title: const Text('Pix'),
                ),
                RadioListTile<String>(
                  value: 'dinheiro',
                  groupValue: method,
                  onChanged: (v) => setState(() => method = v!),
                  title: const Text('Dinheiro'),
                ),
                RadioListTile<String>(
                  value: 'debito',
                  groupValue: method,
                  onChanged: (v) => setState(() => method = v!),
                  title: const Text('Cartão de débito'),
                ),
                RadioListTile<String>(
                  value: 'credito',
                  groupValue: method,
                  onChanged: (v) => setState(() => method = v!),
                  title: const Text('Cartão de crédito'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(err!, style: const TextStyle(color: Colors.red)),
            ),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: saving || items.isEmpty
                  ? null
                  : () => _finalizar(
                        total,
                        desconto,
                        // snapshot para o recibo antes de limpar o carrinho
                        List<CartItem>.from(items),
                      ),
              child: Text(
                saving ? 'Finalizando...' : 'Finalizar venda • ${_fmt(total)}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ recebe os itens (snapshot), assim o recibo não fica vazio
  Future<void> _finalizar(
    double total,
    double desconto,
    List<CartItem> itemsSnapshot,
  ) async {
    setState(() {
      saving = true;
      err = null;
    });

    try {
      final tenantId = ref.read(tenantIdProvider);
      if (tenantId == null) throw Exception('Loja não definida.');
      final db = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // 1) registra uma venda agregada (para relatórios futuros)
      final vendaRef = await db
          .collection('tenants')
          .doc(tenantId)
          .collection('vendas')
          .add({
        'itens': [
          for (final it in itemsSnapshot)
            {
              'productId': it.productId,
              'nome': it.nome,
              'qtd': it.quantity,
              'preco': it.unitPrice,
              'total': it.total,
            }
        ],
        'subtotal': itemsSnapshot.fold<double>(
            0.0, (s, it) => s + it.total), // subtotal consistente
        'desconto': desconto,
        'total': total,
        'pagamento': method,
        'usuarioId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2) aplica movimentações (baixa do estoque)
      final mov = FirestoreMovements(db, tenantId);
      for (final it in itemsSnapshot) {
        await mov.applyMovement(
          produtoId: it.productId,
          tipo: 'saida',
          quantidade: it.quantity,
          motivo: 'venda manual',
          usuarioId: uid,
          origem: 'venda_manual',
          mensagemOriginal: 'Venda ${vendaRef.id} • ${it.quantity}× ${it.nome}',
        );
      }

      // 3) zera carrinho
      ref.read(cartProvider.notifier).clear();

      // 4) gerar/compartilhar recibo (com snapshot dos itens)
      await _compartilharRecibo(
        vendaRef.id,
        total,
        desconto,
        itemsSnapshot,
        method,
        tenantId,
      );

      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venda registrada com sucesso.')),
        );
    } on FirebaseException catch (e) {
      setState(() => err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  // ✅ agora recebe os itens e o método de pagamento explicitamente
  Future<void> _compartilharRecibo(
    String vendaId,
    double total,
    double desconto,
    List<CartItem> items,
    String paymentMethod,
    String? tenantId,
  ) async {
    final subtotal = items.fold<double>(0.0, (s, it) => s + it.total);

    // pegar nome da loja (se existir)
    String loja = tenantId ?? 'SmartStock';
    try {
      if (tenantId != null) {
        final t = await FirebaseFirestore.instance
            .collection('tenants')
            .doc(tenantId)
            .get();
        loja = (t.data()?['name'] ?? loja).toString();
      }
    } catch (_) {}

    final buffer = StringBuffer()
      ..writeln('Recibo – $loja')
      ..writeln('Venda: $vendaId')
      ..writeln('-----------------------------');

    for (final it in items) {
      buffer.writeln(
          '${it.quantity}× ${it.nome} @ R\$ ${it.unitPrice.toStringAsFixed(2)} = R\$ ${it.total.toStringAsFixed(2)}');
    }
    buffer
      ..writeln('-----------------------------')
      ..writeln('Subtotal: R\$ ${subtotal.toStringAsFixed(2)}')
      ..writeln('Desconto: R\$ ${desconto.toStringAsFixed(2)}')
      ..writeln('Total:    R\$ ${total.toStringAsFixed(2)}')
      ..writeln('Pagamento: ${paymentMethod.toUpperCase()}');

    final text = buffer.toString();

    try {
      await Share.share(text); // WhatsApp, e-mail etc.
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text)); // fallback
    }
  }
}
