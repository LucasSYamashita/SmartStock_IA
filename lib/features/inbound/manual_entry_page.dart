import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tenant/tenant_provider.dart';
import '../../data/datasources/firestore_movements.dart';

/// Dica: proteja esta tela com MembershipGuard(adminOnly: true) nas rotas,
/// e garanta o mesmo nas Firestore Rules.
class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key});
  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends ConsumerState<ManualEntryPage> {
  final _form = GlobalKey<FormState>();

  final _nome = TextEditingController();
  final _qtd = TextEditingController(text: '1');
  final _min = TextEditingController(text: '0');
  final _valor = TextEditingController(text: '0');
  final _marca = TextEditingController();

  // doc selecionado a partir das sugestões (se houver)
  DocumentSnapshot<Map<String, dynamic>>? _selectedDoc;

  bool working = false;
  String? err;

  @override
  void dispose() {
    _nome.dispose();
    _qtd.dispose();
    _min.dispose();
    _valor.dispose();
    _marca.dispose();
    super.dispose();
  }

  int _parseInt(TextEditingController c, {int def = 0}) {
    final v = int.tryParse(c.text.trim());
    return v == null ? def : v;
  }

  double _parseMoney(TextEditingController c, {double def = 0}) {
    final raw = c.text.trim().replaceAll(',', '.');
    final v = double.tryParse(raw);
    return v == null ? def : v;
  }

  Future<void> _salvar() async {
    FocusScope.of(context).unfocus();

    // validações simples
    if (!_form.currentState!.validate()) return;

    setState(() {
      working = true;
      err = null;
    });

    try {
      final tenantId = ref.read(tenantIdProvider);
      if (tenantId == null) throw Exception('Loja não definida.');

      final db = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final nome = _nome.text.trim();
      final nomeLower = nome.toLowerCase();
      final qtd = _parseInt(_qtd).clamp(1, 999999); // >= 1
      final min = _parseInt(_min).clamp(0, 999999); // >= 0
      final valor = _parseMoney(_valor).clamp(0.0, 9999999.0); // >= 0
      final marca = _marca.text.trim();

      // tenta usar o doc já selecionado pela sugestão
      DocumentReference<Map<String, dynamic>>? prodRef;

      if (_selectedDoc != null) {
        prodRef = _selectedDoc!.reference;

        // Atualiza campos e incrementa quantidade com transaction
        await db.runTransaction((tx) async {
          final snap = await tx.get(prodRef!);
          if (!snap.exists) throw Exception('Produto não encontrado.');
          tx.update(prodRef!, {
            'quantidade': FieldValue.increment(qtd),
            'estoqueMinimo': min,
            'valor': valor,
            if (marca.isNotEmpty)
              'marca': marca
            else
              'marca': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });

        // Movimentação
        final mov = FirestoreMovements(db, tenantId);
        await mov.applyMovement(
          produtoId: prodRef.id,
          tipo: 'entrada',
          quantidade: qtd,
          motivo: 'entrada manual',
          usuarioId: uid,
          origem: 'manual_entry',
          mensagemOriginal: 'Entrada manual de $qtd × $nome',
        );
      } else {
        // busca por nomeLower para evitar duplicado
        final existing = await db
            .collection('tenants')
            .doc(tenantId)
            .collection('produtos')
            .where('nomeLower', isEqualTo: nomeLower)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          prodRef = existing.docs.first.reference;

          await db.runTransaction((tx) async {
            final snap = await tx.get(prodRef!);
            tx.update(prodRef!, {
              'quantidade': FieldValue.increment(qtd),
              'estoqueMinimo': min,
              'valor': valor,
              if (marca.isNotEmpty)
                'marca': marca
              else
                'marca': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          });

          final mov = FirestoreMovements(db, tenantId);
          await mov.applyMovement(
            produtoId: prodRef.id,
            tipo: 'entrada',
            quantidade: qtd,
            motivo: 'entrada manual',
            usuarioId: uid,
            origem: 'manual_entry',
            mensagemOriginal: 'Entrada manual de $qtd × $nome',
          );
        } else {
          // cria novo
          prodRef = await db
              .collection('tenants')
              .doc(tenantId)
              .collection('produtos')
              .add({
            'nome': nome,
            'nomeLower': nomeLower,
            'quantidade': qtd,
            'estoqueMinimo': min,
            'valor': valor,
            if (marca.isNotEmpty) 'marca': marca,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // movimentação
          final mov = FirestoreMovements(db, tenantId);
          await mov.applyMovement(
            produtoId: prodRef.id,
            tipo: 'entrada',
            quantidade: qtd,
            motivo: 'entrada manual (novo)',
            usuarioId: uid,
            origem: 'manual_entry',
            mensagemOriginal: 'Entrada manual de $qtd × $nome (novo)',
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrada registrada.')),
      );

      // reset suave (mantém nome para próximas entradas rápidas)
      _qtd.text = '1';
      // não sobrescreva min/valor/marca automaticamente se o usuário quer manter novos parâmetros
      setState(() {
        _selectedDoc = null;
      });
    } on FirebaseException catch (e) {
      setState(() => err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  /// Stream de sugestões pelo nome (startsWith)
  Stream<QuerySnapshot<Map<String, dynamic>>> _suggestions(
      String tenantId, String q) {
    if (q.isEmpty) return const Stream.empty();
    final from = q;
    final to = '$q\uf8ff';
    return FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('produtos')
        .where('nomeLower', isGreaterThanOrEqualTo: from)
        .where('nomeLower', isLessThanOrEqualTo: to)
        .limit(5)
        .snapshots();
  }

  void _prefillFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    _selectedDoc = doc;

    final minAny = m['estoqueMinimo'] ?? 0;
    final valAny = m['valor'] ?? 0.0;

    _min.text = (minAny is num ? minAny.toInt() : int.tryParse('$minAny') ?? 0)
        .toString();
    _valor.text =
        (valAny is num ? valAny.toDouble() : double.tryParse('$valAny') ?? 0.0)
            .toStringAsFixed(2);
    _marca.text = (m['marca'] ?? '').toString();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ref.watch(tenantIdProvider);

    if (tenantId == null) {
      return const Scaffold(
        body: Center(child: Text('Selecione/crie uma loja para continuar.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Entrada manual')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Nome + sugestões
            TextFormField(
              controller: _nome,
              decoration: const InputDecoration(
                labelText: 'Nome do produto',
                prefixIcon: Icon(Icons.inventory_outlined),
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {
                _selectedDoc = null; // alterou o texto, desassocia seleção
              }),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome.' : null,
            ),
            const SizedBox(height: 8),

            // Sugestões (auto-complete simples)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _suggestions(tenantId, _nome.text.trim().toLowerCase()),
              builder: (context, snap) {
                if (!snap.hasData || _nome.text.trim().isEmpty) {
                  return const SizedBox.shrink();
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const SizedBox.shrink();

                return Wrap(
                  spacing: 8,
                  runSpacing: -6,
                  children: [
                    for (final d in docs)
                      ActionChip(
                        avatar: const Icon(Icons.tag, size: 16),
                        label: Text((d.data()['nome'] ?? '').toString()),
                        onPressed: () {
                          final name = (d.data()['nome'] ?? '').toString();
                          _nome.text = name;
                          _prefillFromDoc(d);
                        },
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            // Quantidade (stepper-like)
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _qtd,
                    decoration: const InputDecoration(
                      labelText: 'Quantidade (entrada)',
                      prefixIcon: Icon(Icons.add),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n <= 0)
                        return 'Informe uma quantidade > 0';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final n = _parseInt(_qtd, def: 1) + 1;
                        _qtd.text = n.toString();
                        setState(() {});
                      },
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final n =
                            (_parseInt(_qtd, def: 1) - 1).clamp(1, 999999);
                        _qtd.text = n.toString();
                        setState(() {});
                      },
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Quantidade mínima (stepper-like)
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _min,
                    decoration: const InputDecoration(
                      labelText: 'Quantidade mínima',
                      prefixIcon: Icon(Icons.warning_amber_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 0) return 'Mínimo deve ser ≥ 0';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final n = _parseInt(_min) + 1;
                        _min.text = n.toString();
                        setState(() {});
                      },
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final n = (_parseInt(_min) - 1).clamp(0, 999999);
                        _min.text = n.toString();
                        setState(() {});
                      },
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Valor(R$)
            TextFormField(
              controller: _valor,
              decoration: const InputDecoration(
                labelText: 'Valor (R\$)',
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]')),
              ],
              validator: (v) {
                final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (n == null || n < 0) return 'Valor inválido';
                return null;
              },
            ),
            const SizedBox(height: 8),

            // Marca (opcional)
            TextFormField(
              controller: _marca,
              decoration: const InputDecoration(
                labelText: 'Marca (opcional)',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _salvar(),
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
                onPressed: working ? null : _salvar,
                child: Text(working ? 'Salvando...' : 'Registrar entrada'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
