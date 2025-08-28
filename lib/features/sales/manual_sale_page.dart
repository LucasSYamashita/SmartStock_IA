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

String _fmt(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

/// Página 1: catálogo
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
    final uniqueCount = ref.watch(cartCountProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final totalQty = ref.watch(cartTotalQtyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vender')),
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

                    // ---------- PADRONIZAÇÃO DE CAMPOS ----------
                    final nome = (m['nome'] ?? '').toString();
                    final marca = (m['marca'] ?? '').toString();
                    final qAny = m['quantidade'] ?? m['Quantidade'] ?? 0;
                    final minAny =
                        m['estoqueMinimo'] ?? m['EstoqueMinimo'] ?? 0;
                    final estoque =
                        qAny is num ? qAny.toInt() : int.tryParse('$qAny') ?? 0;
                    final minimo = minAny is num
                        ? minAny.toInt()
                        : int.tryParse('$minAny') ?? 0;

                    // preço unitário: preferimos `valor` (padrão), caindo para `precoVenda` se existir
                    final priceAny = m['valor'] ?? m['precoVenda'] ?? 0.0;
                    final price = priceAny is num
                        ? priceAny.toDouble()
                        : double.tryParse('$priceAny') ?? 0.0;
                    // -------------------------------------------

                    return _ProductCard(
                      productId: id,
                      nome: nome,
                      marca: marca,
                      estoque: estoque,
                      minimo: minimo,
                      price: price,
                      onAdd: (qtd) {
                        if (qtd <= 0) return;
                        ref.read(cartProvider.notifier).addOrInc(
                              CartItem(
                                productId: id,
                                nome: nome,
                                quantity: qtd,
                                unitPrice: price,
                              ),
                              by: qtd,
                            );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  '$qtd × "$nome" adicionado ao carrinho.')),
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

      // Resumo fixo no rodapé
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border:
                Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Itens: $uniqueCount  •  Unidades: $totalQty'),
                    Text('Subtotal: ${_fmt(subtotal)}',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: uniqueCount == 0
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Card com **stepper** de quantidade + status de estoque (“S/E”, “Baixo”, “OK”)
class _ProductCard extends StatefulWidget {
  final String productId;
  final String nome;
  final String marca;
  final int estoque;
  final int minimo;
  final double price;
  final void Function(int qtd) onAdd;

  const _ProductCard({
    required this.productId,
    required this.nome,
    required this.marca,
    required this.estoque,
    required this.minimo,
    required this.price,
    required this.onAdd,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  int qtd = 1;

  @override
  Widget build(BuildContext context) {
    // regra solicitada:
    // - estoque == 0  -> “S/E”
    // - estoque > 0 e <= mínimo -> “Baixo”
    // - caso contrário -> “OK” (sem chip)
    final se = widget.estoque == 0;
    final baixo = !se && widget.estoque <= widget.minimo;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              child: Text(
                  widget.nome.isNotEmpty ? widget.nome[0].toUpperCase() : '?'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.nome,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  if (widget.marca.isNotEmpty)
                    Text(widget.marca,
                        style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                          'Estoque: ${widget.estoque}  •  Preço: ${_fmt(widget.price)}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: 8),
                      if (se)
                        const Chip(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          label: Text('S/E'),
                          avatar: Icon(Icons.close, size: 16),
                        )
                      else if (baixo)
                        const Chip(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          label: Text('Baixo'),
                          avatar: Icon(Icons.warning_amber, size: 16),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            _QtyStepper(
              value: qtd,
              onChanged: (v) => setState(() => qtd = v),
              max: widget.estoque > 0 ? widget.estoque : 1, // evita 0
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: se ? null : () => widget.onAdd(qtd),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final int? max;
  const _QtyStepper({required this.value, required this.onChanged, this.max});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed:
              max == null || value < max! ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
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
  String method = 'pix'; // pix, dinheiro, debito, credito
  bool percent = false; // desconto em %?
  final _discountCtrl = TextEditingController();
  bool saving = false;
  String? err;

  @override
  void dispose() {
    _discountCtrl.dispose();
    super.dispose();
  }

  String _fmtLocal(num v) => _fmt(v);

  double _parseDiscount() {
    final raw = _discountCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(raw) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final d = _parseDiscount();
    final descontoBruto = percent ? subtotal * (d / 100.0) : d;
    // impede desconto > subtotal
    final desconto = descontoBruto.clamp(0.0, subtotal).toDouble();
    final double total =
        (subtotal - desconto).clamp(0.0, double.infinity).toDouble();

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
                    subtitle:
                        Text('${it.quantity} × ${_fmtLocal(it.unitPrice)}'),
                    trailing: Text(_fmtLocal(it.total)),
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
                        labelText: percent ? 'Desconto (%)' : 'Desconto (R\$)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<bool>(
                    segments: const [
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
                    title: const Text('Pix')),
                RadioListTile<String>(
                    value: 'dinheiro',
                    groupValue: method,
                    onChanged: (v) => setState(() => method = v!),
                    title: const Text('Dinheiro')),
                RadioListTile<String>(
                    value: 'debito',
                    groupValue: method,
                    onChanged: (v) => setState(() => method = v!),
                    title: const Text('Cartão de débito')),
                RadioListTile<String>(
                    value: 'credito',
                    groupValue: method,
                    onChanged: (v) => setState(() => method = v!),
                    title: const Text('Cartão de crédito')),
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
                  : () => _finalizar(total, desconto),
              child: Text(saving
                  ? 'Finalizando...'
                  : 'Finalizar venda • ${_fmtLocal(total)}'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizar(double total, double desconto) async {
    setState(() {
      saving = true;
      err = null;
    });

    try {
      final tenantId = ref.read(tenantIdProvider);
      if (tenantId == null) throw Exception('Loja não definida.');
      final db = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // snapshot dos itens ANTES de limpar (para recibo)
      final itemsSnapshot = List<CartItem>.from(ref.read(cartProvider));
      final subtotal = ref.read(cartSubtotalProvider);

      // 1) registra venda
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
        'subtotal': subtotal,
        'desconto': desconto,
        'total': total,
        'pagamento': method,
        'usuarioId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2) baixa do estoque
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

      // 3) limpa carrinho
      ref.read(cartProvider.notifier).clear();

      // 4) recibo (usando o snapshot)
      await _compartilharRecibo(
        vendaRef.id,
        total: total,
        desconto: desconto,
        subtotal: subtotal,
        items: itemsSnapshot,
      );

      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venda registrada com sucesso.')),
        );
      }
    } on FirebaseException catch (e) {
      setState(() => err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _compartilharRecibo(
    String vendaId, {
    required double total,
    required double desconto,
    required double subtotal,
    required List<CartItem> items,
  }) async {
    final tenantId = ref.read(tenantIdProvider);

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
          '${it.quantity}× ${it.nome} @ ${_fmt(it.unitPrice)} = ${_fmt(it.total)}');
    }
    buffer
      ..writeln('-----------------------------')
      ..writeln('Subtotal: ${_fmt(subtotal)}')
      ..writeln('Desconto: ${_fmt(desconto)}')
      ..writeln('Total:    ${_fmt(total)}')
      ..writeln('Pagamento: ${method.toUpperCase()}');

    final text = buffer.toString();
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
