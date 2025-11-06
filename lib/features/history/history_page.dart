// lib/features/history/history_page.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../tenant/tenant_provider.dart';

class MovementHistoryPage extends ConsumerStatefulWidget {
  const MovementHistoryPage({super.key});

  @override
  ConsumerState<MovementHistoryPage> createState() =>
      _MovementHistoryPageState();
}

class _MovementHistoryPageState extends ConsumerState<MovementHistoryPage> {
  // Filtros
  String _type = 'Todos'; // Todos | Entrada | Saída | Ajuste
  String _payment =
      'Todos'; // Pix | Dinheiro | Débito | Crédito | Outros | Todos

  // Mapeamentos de labels <-> valores persistidos
  static const _typeToValue = {
    'Entrada': 'entrada',
    'Saída': 'saida',
    'Ajuste': 'ajuste',
  };

  static const _payLabelToValue = {
    'Pix': 'pix',
    'Dinheiro': 'dinheiro',
    'Débito': 'debito',
    'Crédito': 'credito',
    'Outros': 'outros',
  };

  Query<Map<String, dynamic>> _buildQuery(String tenantId) {
    var q = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('movimentos')
        .orderBy('createdAt', descending: true);

    // Filtro por tipo
    if (_type != 'Todos') {
      q = q.where('tipo', isEqualTo: _typeToValue[_type]);
    }

    // Filtro por pagamento: só aplica para Saída (ou quando não filtramos tipo)
    final payVal = _payment == 'Todos' ? null : _payLabelToValue[_payment];
    final typeIsSaida = _type == 'Saída';
    final typeIsTodos = _type == 'Todos';
    if (payVal != null && (typeIsSaida || typeIsTodos)) {
      q = q.where('paymentMethod', isEqualTo: payVal);
    }

    // limite para evitar listas gigantes
    return q.limit(300);
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const Scaffold(
        body: Center(child: Text('Selecione uma loja.')),
      );
    }

    final query = _buildQuery(tenantId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          IconButton(
            tooltip: 'Compartilhar',
            icon: const Icon(Icons.share),
            onPressed: () => _shareCurrent(context, query),
          ),
          IconButton(
            tooltip: 'Exportar CSV (clipboard)',
            icon: const Icon(Icons.download),
            onPressed: () => _exportCsv(context, query),
          ),
        ],
      ),
      body: Column(
        children: [
          // Cabeçalho de filtros
          Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  _FilterDropdown<String>(
                    label: 'Tipo',
                    value: _type,
                    items: const ['Todos', 'Entrada', 'Saída', 'Ajuste'],
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                  const SizedBox(width: 12),
                  _FilterDropdown<String>(
                    label: 'Pagamento',
                    value: _payment,
                    items: const [
                      'Todos',
                      'Pix',
                      'Crédito',
                      'Débito',
                      'Dinheiro',
                      'Outros'
                    ],
                    onChanged: (v) => setState(() => _payment = v!),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '(pagamento só filtra "Saída")',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Lista
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Erro: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('Sem movimentações.'));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final tipo = (m['tipo'] ?? '').toString();
                    final qnt = (m['quantidade'] as num?)?.toInt() ?? 0;
                    final nome = (m['produtoNome'] ?? '').toString();
                    final motivo = (m['motivo'] ?? '').toString();
                    final pay =
                        (m['paymentMethod'] ?? '').toString(); // pode ser vazio
                    final payNote = (m['paymentNote'] ?? '').toString();
                    final ts = m['createdAt'] is Timestamp
                        ? (m['createdAt'] as Timestamp).toDate()
                        : null;

                    final leadingIcon = _iconForType(tipo);
                    final leadingColor = _colorForType(tipo);

                    final title = '${tipo.toUpperCase()} • $qnt × $nome';
                    final payHuman = pay.isEmpty ? '-' : _humanPayment(pay);
                    final dataHuman = ts == null ? '' : _fmtDate(ts);

                    final subtitle = [
                      if (motivo.isNotEmpty) 'Motivo: $motivo',
                      if (tipo == 'saida') 'Pagamento: $payHuman',
                      if (payNote.isNotEmpty) 'Obs.: $payNote',
                      if (dataHuman.isNotEmpty) dataHuman,
                    ].join(' • ');

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: leadingColor.withOpacity(0.18),
                        child: Icon(leadingIcon, color: leadingColor),
                      ),
                      title: Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(subtitle),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helpers de UI/formatos

  IconData _iconForType(String tipo) {
    switch (tipo) {
      case 'entrada':
        return Icons.call_received; // seta para baixo/esq
      case 'saida':
        return Icons.call_made; // seta para cima/dir
      default:
        return Icons.tune; // ajuste
    }
  }

  Color _colorForType(String tipo) {
    switch (tipo) {
      case 'entrada':
        return const Color(0xFF2E7D32); // verde
      case 'saida':
        return const Color(0xFFC62828); // vermelho
      default:
        return const Color(0xFFF9A825); // amarelo
    }
  }

  String _humanPayment(String v) {
    switch (v) {
      case 'pix':
        return 'Pix';
      case 'dinheiro':
        return 'Dinheiro';
      case 'debito':
        return 'Débito';
      case 'credito':
        return 'Crédito';
      default:
        return 'Outros';
    }
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n < 10 ? '0$n' : '$n';
    final dia = two(d.day);
    final mes = two(d.month);
    final ano = d.year;
    final hh = two(d.hour);
    final mm = two(d.minute);
    return '$dia/$mes/$ano $hh:$mm';
    // Se quiser timezone local correto no Web, garanta que d já está em localtime.
  }

  Future<void> _shareCurrent(
    BuildContext context,
    Query<Map<String, dynamic>> query,
  ) async {
    try {
      final snap = await query.get();
      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nada para compartilhar.')));
        return;
      }
      final lines = <String>['Histórico de Movimentações'];
      for (final d in snap.docs) {
        final m = d.data();
        final tipo = (m['tipo'] ?? '').toString();
        final qnt = (m['quantidade'] as num?)?.toInt() ?? 0;
        final nome = (m['produtoNome'] ?? '').toString();
        final pay = (m['paymentMethod'] ?? '').toString();
        final ts = m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate()
            : null;
        final dataHuman = ts == null ? '' : _fmtDate(ts);
        final tipoUp = tipo.toUpperCase();
        final payHuman =
            tipo == 'saida' && pay.isNotEmpty ? ' • ${_humanPayment(pay)}' : '';
        lines.add('$tipoUp • $qnt × $nome • $dataHuman$payHuman');
      }
      await Share.share(lines.join('\n'));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falha ao compartilhar: $e')));
    }
  }

  Future<void> _exportCsv(
    BuildContext context,
    Query<Map<String, dynamic>> query,
  ) async {
    try {
      final snap = await query.get();
      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Nada para exportar.')));
        return;
      }

      final rows = <List<String>>[
        [
          'tipo',
          'produtoId',
          'produtoNome',
          'quantidade',
          'delta',
          'motivo',
          'paymentMethod',
          'paymentNote',
          'createdAt',
        ]
      ];

      for (final d in snap.docs) {
        final m = d.data();
        final tipo = (m['tipo'] ?? '').toString();
        final produtoId = (m['produtoId'] ?? '').toString();
        final nome = (m['produtoNome'] ?? '').toString();
        final qnt = (m['quantidade'] as num?)?.toInt() ?? 0;
        final delta = (m['delta'] as num?)?.toInt() ?? 0;
        final motivo = (m['motivo'] ?? '').toString();
        final pm = (m['paymentMethod'] ?? '').toString();
        final pn = (m['paymentNote'] ?? '').toString();
        final ts = m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate()
            : null;
        final created = ts == null ? '' : _fmtDate(ts);

        rows.add([
          tipo,
          produtoId,
          nome,
          '$qnt',
          '$delta',
          motivo,
          pm,
          pn,
          created,
        ]);
      }

      final csv = const ListToCsv().convert(rows);
      await Clipboard.setData(ClipboardData(text: csv));

      // feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('CSV copiado para a área de transferência.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falha ao exportar: $e')));
    }
  }
}

/// Dropdown simples usado no cabeçalho
class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: text.labelMedium),
        DropdownButton<T>(
          value: value,
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text('$e'),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Conversor CSV bem leve (sem dependências externas)
class ListToCsv {
  const ListToCsv();
  String convert(List<List<String>> rows) {
    final b = StringBuffer();
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        final cell = row[c].replaceAll('"', '""'); // escape de aspas
        b.write('"$cell"');
        if (c != row.length - 1) b.write(',');
      }
      if (r != rows.length - 1) b.write('\n');
    }
    return b.toString();
  }
}
