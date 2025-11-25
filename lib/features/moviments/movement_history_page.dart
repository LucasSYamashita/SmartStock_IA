import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../tenant/tenant_provider.dart';

class MovementHistoryPage extends ConsumerStatefulWidget {
  const MovementHistoryPage({super.key});

  @override
  ConsumerState<MovementHistoryPage> createState() =>
      _MovementHistoryPageState();
}

class _MovementHistoryPageState extends ConsumerState<MovementHistoryPage> {
  String _tipo = 'todos'; // todos, entrada, saida
  DateTime? _from;
  DateTime? _to;

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const Scaffold(body: Center(child: Text('Selecione uma loja.')));
    }

    // base da coleção
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('movimentos');

    // filtro por tipo
    if (_tipo != 'todos') q = q.where('tipo', isEqualTo: _tipo);

    // filtro por data
    if (_from != null) {
      final fromDayStart =
          DateTime(_from!.year, _from!.month, _from!.day); // 00:00
      q = q.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(fromDayStart),
      );
    }
    if (_to != null) {
      final toDayEnd =
          DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59, 999);
      q = q.where(
        'createdAt',
        isLessThanOrEqualTo: Timestamp.fromDate(toDayEnd),
      );
    }

    // ordenação + limite
    q = q.orderBy('createdAt', descending: true).limit(300);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de movimentações'),
        actions: [
          IconButton(
            tooltip: 'Compartilhar',
            icon: const Icon(Icons.share),
            onPressed: () => _shareReport(context, q),
          ),
          IconButton(
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.file_download),
            onPressed: () => _exportCsv(context, q),
          ),
        ],
      ),
      body: Column(
        children: [
          _Filters(
            tipo: _tipo,
            from: _from,
            to: _to,
            onChangeTipo: (v) => setState(() {
              _tipo = v;
            }),
            onChangeFrom: (d) => setState(() => _from = d),
            onChangeTo: (d) => setState(() => _to = d),
            onClearDates: () => setState(() {
              _from = null;
              _to = null;
            }),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
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

                double totEntradas = 0, totSaidas = 0;
                final tiles = <Widget>[];

                for (final d in docs) {
                  final m = d.data();
                  final tipo = (m['tipo'] ?? '').toString();
                  final qtd = (m['quantidade'] ?? 0) as int;
                  final nome =
                      (m['produtoNome'] ?? m['produtoId'] ?? '').toString();
                  final pay = (m['paymentMethod'] ?? '').toString();
                  final ts = m['createdAt'];
                  final dt = ts is Timestamp ? ts.toDate() : null;

                  // preços possíveis
                  final unitCost = (m['unitCost'] as num?)?.toDouble();
                  final unitPrice = (m['unitPrice'] as num?)?.toDouble();
                  final totalValue = (m['totalValue'] as num?)?.toDouble();
                  final valorTotalLegacy =
                      (m['valorTotal'] as num?)?.toDouble();
                  final preco = (m['preco'] as num?)?.toDouble();

                  // mesmo cálculo que usamos em dashboard/CSV
                  final total = valorTotalLegacy ??
                      totalValue ??
                      (((tipo == 'entrada'
                                  ? (unitCost ?? preco)
                                  : (unitPrice ?? preco)) ??
                              0.0) *
                          qtd);

                  if (tipo == 'entrada') {
                    totEntradas += total;
                  } else if (tipo == 'saida') {
                    totSaidas += total;
                  }

                  final cor = tipo == 'entrada'
                      ? Colors.green
                      : (tipo == 'saida' ? Colors.red : Colors.amber);

                  final extra = <String>[
                    if ((m['motivo'] ?? '').toString().isNotEmpty)
                      'Motivo: ${m['motivo']}',
                    if (tipo == 'saida' && pay.isNotEmpty)
                      'Pagamento: ${_labelPay(pay)}',
                    if (preco != null) 'Preço: ${_brl(preco)}',
                  ].join(' · ');

                  tiles.add(
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cor.withOpacity(.15),
                        child: Icon(
                          tipo == 'entrada'
                              ? Icons.call_received
                              : (tipo == 'saida'
                                  ? Icons.call_made
                                  : Icons.tune_outlined),
                          color: cor,
                        ),
                      ),
                      title: Text(
                        '${tipo.toUpperCase()} · $qtd × $nome',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text([
                        if (extra.isNotEmpty) extra,
                        if (dt != null) _fmt(dt),
                      ].join(' • ')),
                      trailing: Text(
                        _brl(total),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cor,
                        ),
                      ),
                    ),
                  );
                }

                final header = Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Entradas: ${_brl(totEntradas)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text('Saídas: ${_brl(totSaidas)}',
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text('Saldo: ${_brl(totEntradas - totSaidas)}',
                            textAlign: TextAlign.end,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                );

                return ListView.separated(
                  itemCount: tiles.length + 1,
                  separatorBuilder: (_, i) => i == 0
                      ? const SizedBox.shrink()
                      : const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == 0) return header;
                    return tiles[i - 1];
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _brl(double v) => 'R\$ ${v.toStringAsFixed(2)}';

  String _labelPay(String v) {
    switch (v) {
      case 'pix':
        return 'Pix';
      case 'credito':
        return 'Crédito';
      case 'debito':
        return 'Débito';
      case 'dinheiro':
        return 'Dinheiro';
      default:
        return 'Outros';
    }
  }

  static String _fmt(DateTime dt) {
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _shareReport(
      BuildContext context, Query<Map<String, dynamic>> q) async {
    try {
      final snap = await q.limit(80).get();
      double totE = 0, totS = 0;

      final lines = <String>['*Relatório de movimentações*'];
      if (_tipo != 'todos') lines.add('Tipo: ${_tipo.toUpperCase()}');
      if (_from != null || _to != null) {
        final parts = <String>[];
        if (_from != null) {
          parts.add('de ${_fmt(_from!)}');
        }
        if (_to != null) {
          parts.add('até ${_fmt(_to!)}');
        }
        lines.add(parts.join(' '));
      }
      lines.add('');

      for (final d in snap.docs) {
        final m = d.data();
        final tipo = (m['tipo'] ?? '').toString().toUpperCase();
        final nome = (m['produtoNome'] ?? m['produtoId'] ?? '').toString();
        final qtd = (m['quantidade'] ?? 0) as int;
        final ts = m['createdAt'];
        final dt = ts is Timestamp ? _fmt(ts.toDate()) : '';
        final pay = (m['paymentMethod'] ?? '').toString();

        final unitCost = (m['unitCost'] as num?)?.toDouble();
        final unitPrice = (m['unitPrice'] as num?)?.toDouble();
        final totalValue = (m['totalValue'] as num?)?.toDouble();
        final valorTotalLegacy = (m['valorTotal'] as num?)?.toDouble();
        final preco = (m['preco'] as num?)?.toDouble();

        final total = valorTotalLegacy ??
            totalValue ??
            (((tipo == 'ENTRADA'
                        ? (unitCost ?? preco)
                        : (unitPrice ?? preco)) ??
                    0.0) *
                qtd);

        if (tipo == 'ENTRADA') totE += total;
        if (tipo == 'SAIDA') totS += total;

        final paySuf =
            tipo == 'SAIDA' && pay.isNotEmpty ? ' · ${_labelPay(pay)}' : '';

        lines.add('• $tipo · $qtd × $nome · $dt$paySuf · Valor ${_brl(total)}');
      }

      lines.add('');
      lines.add('Entradas: ${_brl(totE)}');
      lines.add('Saídas: ${_brl(totS)}');
      lines.add('Saldo: ${_brl(totE - totS)}');

      final text = lines.join('\n');
      final wa = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
      await launchUrl(wa, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Falha ao compartilhar: $e')));
      }
    }
  }

  Future<void> _exportCsv(
      BuildContext context, Query<Map<String, dynamic>> q) async {
    try {
      final snap = await q.get();
      final rows = <List<String>>[
        [
          'tipo',
          'quantidade',
          'produtoId',
          'produtoNome',
          'paymentMethod',
          'preco',
          'valorTotal',
          'motivo',
          'origem',
          'usuarioId',
          'createdAt',
        ]
      ];
      for (final d in snap.docs) {
        final m = d.data();
        final ts = m['createdAt'];
        final dt = ts is Timestamp ? ts.toDate().toIso8601String() : '$ts';

        final tipo = (m['tipo'] ?? '').toString();
        final qtd = (m['quantidade'] ?? 0) as int;

        final unitCost = (m['unitCost'] as num?)?.toDouble();
        final unitPrice = (m['unitPrice'] as num?)?.toDouble();
        final totalValue = (m['totalValue'] as num?)?.toDouble();
        final valorTotalLegacy = (m['valorTotal'] as num?)?.toDouble();
        final preco = (m['preco'] as num?)?.toDouble();

        final total = valorTotalLegacy ??
            totalValue ??
            (((tipo == 'entrada'
                        ? (unitCost ?? preco)
                        : (unitPrice ?? preco)) ??
                    0.0) *
                qtd);

        rows.add([
          tipo,
          '$qtd',
          '${m['produtoId'] ?? ''}',
          '${m['produtoNome'] ?? ''}',
          '${m['paymentMethod'] ?? ''}',
          (preco ?? 0.0).toStringAsFixed(2),
          total.toStringAsFixed(2),
          '${m['motivo'] ?? ''}',
          '${m['origem'] ?? ''}',
          '${m['usuarioId'] ?? ''}',
          dt,
        ]);
      }
      final csv = const _Csv().convert(rows);
      final bytes = utf8.encode(csv);
      final blob = Uri.dataFromBytes(bytes, mimeType: 'text/csv');
      await launchUrl(blob);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('CSV gerado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Falha ao exportar: $e')));
      }
    }
  }
}

class _Filters extends StatelessWidget {
  final String tipo;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<String> onChangeTipo;
  final ValueChanged<DateTime?> onChangeFrom;
  final ValueChanged<DateTime?> onChangeTo;
  final VoidCallback onClearDates;

  const _Filters({
    required this.tipo,
    required this.from,
    required this.to,
    required this.onChangeTipo,
    required this.onChangeFrom,
    required this.onChangeTo,
    required this.onClearDates,
  });

  @override
  Widget build(BuildContext context) {
    String two(int x) => x.toString().padLeft(2, '0');
    String fmtDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Tipo:'),
          DropdownButton<String>(
            value: tipo,
            items: const [
              DropdownMenuItem(value: 'todos', child: Text('Todos')),
              DropdownMenuItem(value: 'entrada', child: Text('Entrada')),
              DropdownMenuItem(value: 'saida', child: Text('Saída')),
            ],
            onChanged: (v) => onChangeTipo(v ?? 'todos'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: from ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) onChangeFrom(picked);
            },
            child: Text(
              from == null ? 'Data inicial' : 'De: ${fmtDate(from!)}',
            ),
          ),
          FilledButton.tonal(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: to ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) onChangeTo(picked);
            },
            child: Text(
              to == null ? 'Data final' : 'Até: ${fmtDate(to!)}',
            ),
          ),
          if (from != null || to != null)
            IconButton(
              tooltip: 'Limpar datas',
              onPressed: onClearDates,
              icon: const Icon(Icons.clear),
            ),
        ],
      ),
    );
  }
}

class _Csv {
  const _Csv();
  String convert(List<List<String>> rows) {
    String esc(String v) {
      final needsQuote = v.contains(',') || v.contains('"') || v.contains('\n');
      final s = v.replaceAll('"', '""');
      return needsQuote ? '"$s"' : s;
    }

    return rows.map((r) => r.map(esc).join(',')).join('\n');
  }
}
