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
  String _tipo = 'todos'; // todos | entrada | saida | ajuste
  String _pay = 'todos'; // todos | pix | credito | debito | dinheiro | outros

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(tenantIdProvider);
    if (tenantId == null) {
      return const Scaffold(body: Center(child: Text('Selecione uma loja.')));
    }

    // Só filtra por período + ordenação no servidor (não exige índice composto)
    final q = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('movimentos')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(
              // últimos 30 dias; ajuste se quiser
              DateTime.now().subtract(const Duration(days: 30)),
            ))
        .orderBy('createdAt', descending: true)
        .limit(500);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
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
            pagamento: _pay,
            onChangeTipo: (v) => setState(() => _tipo = v),
            onChangePagamento: (v) => setState(() => _pay = v),
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

                // Aplica os filtros de tipo/pagamento em memória
                final docs = snap.data!.docs.where((d) {
                  final m = d.data();
                  final tipo = (m['tipo'] ?? '').toString();
                  final pay = (m['paymentMethod'] ?? '').toString();

                  final tipoOk = _tipo == 'todos' || tipo == _tipo;
                  final payOk =
                      !(_tipo == 'saida' && _pay != 'todos') || pay == _pay;
                  return tipoOk && payOk;
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('Sem movimentações.'));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final tipo = (m['tipo'] ?? '').toString();
                    final qtd = (m['quantidade'] ?? 0).toString();
                    final nome =
                        (m['produtoNome'] ?? m['produtoId'] ?? '').toString();
                    final pay = (m['paymentMethod'] ?? '').toString();
                    final ts = m['createdAt'];
                    final dt = ts is Timestamp ? ts.toDate() : null;
                    final cor = tipo == 'entrada'
                        ? Colors.green
                        : (tipo == 'saida' ? Colors.red : Colors.amber);

                    final extra = <String>[
                      if ((m['motivo'] ?? '').toString().isNotEmpty)
                        'Motivo: ${m['motivo']}',
                      if (tipo == 'saida' && pay.isNotEmpty)
                        'Pagamento: ${_labelPay(pay)}',
                    ].join(' · ');

                    return ListTile(
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
                      title: Text('${tipo.toUpperCase()} · $qtd × $nome',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([
                        if (extra.isNotEmpty) extra,
                        if (dt != null) _fmt(dt),
                      ].join(' • ')),
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
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _shareReport(
      BuildContext context, Query<Map<String, dynamic>> baseQuery) async {
    try {
      final snap = await baseQuery.limit(120).get(); // amostra para share
      final lines = <String>['*Relatório de movimentações*'];
      if (_tipo != 'todos') lines.add('Tipo: ${_tipo.toUpperCase()}');
      if (_tipo == 'saida' && _pay != 'todos')
        lines.add('Pagamento: ${_labelPay(_pay)}');
      lines.add('');

      for (final d in snap.docs) {
        final m = d.data();
        final tipo = (m['tipo'] ?? '').toString().toUpperCase();
        final nome = (m['produtoNome'] ?? m['produtoId'] ?? '').toString();
        final qtd = (m['quantidade'] ?? '').toString();
        final ts = m['createdAt'];
        final dt = ts is Timestamp ? _fmt(ts.toDate()) : '';
        final pay = (m['paymentMethod'] ?? '').toString();
        final paySuf =
            tipo == 'SAIDA' && pay.isNotEmpty ? ' · ${_labelPay(pay)}' : '';

        // aplica filtro em memória antes de adicionar
        if ((_tipo == 'todos' || tipo == _tipo.toUpperCase()) &&
                !(_tipo == 'saida' && _pay != 'todos') ||
            (_pay == pay)) {
          lines.add('• $tipo · $qtd × $nome · $dt$paySuf');
        }
      }

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
      BuildContext context, Query<Map<String, dynamic>> baseQuery) async {
    try {
      final snap = await baseQuery.get();
      final rows = <List<String>>[
        [
          'tipo',
          'quantidade',
          'produtoId',
          'produtoNome',
          'paymentMethod',
          'motivo',
          'origem',
          'usuarioId',
          'createdAt'
        ]
      ];

      for (final d in snap.docs) {
        final m = d.data();

        // filtros em memória
        final tipo = (m['tipo'] ?? '').toString();
        final pay = (m['paymentMethod'] ?? '').toString();
        final tipoOk = _tipo == 'todos' || tipo == _tipo;
        final payOk = !(_tipo == 'saida' && _pay != 'todos') || pay == _pay;
        if (!(tipoOk && payOk)) continue;

        final ts = m['createdAt'];
        final dt = ts is Timestamp ? ts.toDate().toIso8601String() : '$ts';

        rows.add([
          '$tipo',
          '${m['quantidade'] ?? ''}',
          '${m['produtoId'] ?? ''}',
          '${m['produtoNome'] ?? ''}',
          '$pay',
          '${m['motivo'] ?? ''}',
          '${m['origem'] ?? ''}',
          '${m['usuarioId'] ?? ''}',
          dt,
        ]);
      }

      final csv = const _Csv().convert(rows);
      final bytes = utf8.encode(csv);
      final blob = Uri.dataFromBytes(bytes, mimeType: 'text/csv');
      await launchUrl(blob); // dispara download no web

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
  final String pagamento;
  final ValueChanged<String> onChangeTipo;
  final ValueChanged<String> onChangePagamento;
  const _Filters({
    required this.tipo,
    required this.pagamento,
    required this.onChangeTipo,
    required this.onChangePagamento,
  });

  @override
  Widget build(BuildContext context) {
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
              DropdownMenuItem(value: 'ajuste', child: Text('Ajuste')),
            ],
            onChanged: (v) => onChangeTipo(v ?? 'todos'),
          ),
          const SizedBox(width: 8),
          const Text('Pagamento:'),
          DropdownButton<String>(
            value: pagamento,
            items: const [
              DropdownMenuItem(value: 'todos', child: Text('Todos')),
              DropdownMenuItem(value: 'pix', child: Text('Pix')),
              DropdownMenuItem(value: 'credito', child: Text('Crédito')),
              DropdownMenuItem(value: 'debito', child: Text('Débito')),
              DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
              DropdownMenuItem(value: 'outros', child: Text('Outros')),
            ],
            onChanged: (v) => onChangePagamento(v ?? 'todos'),
          ),
          const SizedBox(width: 8),
          const Text('(pagamento só filtra “Saída”)',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
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
