// lib/features/sales/sale_receipt_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'cart_state.dart';
import 'manual_sale_page.dart' show ManualSaleCatalogPage;

String _fmt(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

class SaleReceiptPage extends StatefulWidget {
  final String vendaId;
  final String tenantId;
  final String clienteNome;
  final List<CartItem> items;
  final double subtotal;
  final double desconto;
  final double total;
  final String paymentMethod; // 'pix' | 'dinheiro' | 'debito' | 'credito'

  const SaleReceiptPage({
    super.key,
    required this.vendaId,
    required this.tenantId,
    required this.clienteNome,
    required this.items,
    required this.subtotal,
    required this.desconto,
    required this.total,
    required this.paymentMethod,
  });

  @override
  State<SaleReceiptPage> createState() => _SaleReceiptPageState();
}

class _SaleReceiptPageState extends State<SaleReceiptPage> {
  String _loja = 'SmartStock';

  @override
  void initState() {
    super.initState();
    _loadLoja();
  }

  Future<void> _loadLoja() async {
    try {
      final t = await FirebaseFirestore.instance
          .collection('tenants')
          .doc(widget.tenantId)
          .get();
      setState(() {
        _loja = (t.data()?['name'] ?? _loja).toString();
      });
    } catch (_) {
      // mantém padrão
    }
  }

  String get _paymentHuman {
    switch (widget.paymentMethod) {
      case 'pix':
        return 'Pix';
      case 'dinheiro':
        return 'Dinheiro';
      case 'debito':
        return 'Débito';
      case 'credito':
        return 'Crédito';
      default:
        return widget.paymentMethod.toUpperCase();
    }
  }

  String _buildReceiptText() {
    final b = StringBuffer()
      ..writeln('Recibo – $_loja')
      ..writeln('Venda: ${widget.vendaId}');
    if (widget.clienteNome.isNotEmpty) {
      b.writeln('Cliente: ${widget.clienteNome}');
    }
    b.writeln('-----------------------------');
    for (final it in widget.items) {
      b.writeln(
          '${it.quantity}× ${it.nome} @ ${_fmt(it.unitPrice)} = ${_fmt(it.total)}');
    }
    b
      ..writeln('-----------------------------')
      ..writeln('Subtotal: ${_fmt(widget.subtotal)}')
      ..writeln('Desconto: ${_fmt(widget.desconto)}')
      ..writeln('Total:    ${_fmt(widget.total)}')
      ..writeln('Pagamento: $_paymentHuman');
    return b.toString();
  }

  Future<void> _share() async {
    final text = _buildReceiptText();
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Recibo copiado para a área de transferência.')),
      );
    }
  }

  Future<void> _copy() async {
    final text = _buildReceiptText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Recibo copiado para a área de transferência.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recibo da venda'),
        actions: [
          IconButton(onPressed: _share, icon: const Icon(Icons.share)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: Colors.green.withOpacity(0.12),
              child:
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Venda concluída',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '$_loja • ID: ${widget.vendaId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (widget.clienteNome.isNotEmpty) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Cliente: ${widget.clienteNome}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Itens
          Card(
            child: Column(
              children: [
                for (final it in widget.items)
                  ListTile(
                    dense: true,
                    title: Text(it.nome),
                    subtitle: Text('${it.quantity} × ${_fmt(it.unitPrice)}'),
                    trailing: Text(_fmt(it.total)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Totais
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _row('Subtotal', _fmt(widget.subtotal)),
                  const SizedBox(height: 6),
                  _row('Desconto', _fmt(widget.desconto)),
                  const Divider(height: 18),
                  _row('Total', _fmt(widget.total),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  _row('Pagamento', _paymentHuman),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Ações
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share),
                  label: const Text('Compartilhar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () {
              // Volta para o início e abre uma nova venda
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (_) => const ManualSaleCatalogPage()),
                (route) => route.isFirst,
              );
            },
            icon: const Icon(Icons.point_of_sale),
            label: const Text('Nova venda'),
          ),
        ],
      ),
    );
  }

  Widget _row(String a, String b, {TextStyle? style}) {
    return Row(
      children: [
        Expanded(child: Text(a)),
        Text(b, style: style),
      ],
    );
  }
}
