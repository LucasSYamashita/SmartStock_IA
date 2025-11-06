import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firestore_movements.dart';
import '../tenant/tenant_provider.dart';

class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key});

  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends ConsumerState<ManualEntryPage> {
  final _prodIdCtrl = TextEditingController(); // pode ficar vazio (gera ID)
  final _qtyCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController(text: 'compra');

  bool _saving = false;

  @override
  void dispose() {
    _prodIdCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final tenantId = ref.read(tenantIdProvider);
    if (tenantId == null) {
      _toast('Loja não selecionada.');
      setState(() => _saving = false);
      return;
    }

    final qty = int.tryParse(_qtyCtrl.text.trim());
    final custo = double.tryParse(_costCtrl.text.trim().replaceAll(',', '.'));
    final motivo = _reasonCtrl.text.trim();

    if (qty == null || qty <= 0) {
      _toast('Quantidade inválida (inteiro > 0).');
      setState(() => _saving = false);
      return;
    }
    if (_costCtrl.text.trim().isNotEmpty && custo == null) {
      _toast('Custo unitário inválido.');
      setState(() => _saving = false);
      return;
    }

    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;

    try {
      // 1) garantir que o produto exista (ou criá-lo)
      final produtoId = await _ensureProductExistsOrCreate(
        tenantId: tenantId,
        providedId: _prodIdCtrl.text.trim(),
        precoSugerido: custo ?? 0.0,
        uid: uid,
      );
      if (produtoId == null) {
        // usuário cancelou o diálogo de criação
        setState(() => _saving = false);
        return;
      }

      // 2) registra ENTRADA
      final mov = FirestoreMovements(db, tenantId);
      await mov.applyMovement(
        produtoId: produtoId,
        tipo: 'entrada',
        quantidade: qty,
        usuarioId: uid,
        motivo: motivo.isEmpty ? null : motivo,
        origem: 'entrada_manual',
        mensagemOriginal: 'Entrada manual • ${qty}×',
        preco: custo, // opcional no log
      );

      _toast('Entrada registrada com sucesso.');
      if (mounted) Navigator.pop(context);
    } on FirebaseException catch (e) {
      _toast('${e.code}: ${e.message}');
    } on StateError catch (e) {
      _toast(e.message ?? 'Erro');
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Garante existência do produto. Se não existir (ou se ID não fornecido), abre diálogo
  /// para criar com os campos mínimos exigidos pelas RULES.
  Future<String?> _ensureProductExistsOrCreate({
    required String tenantId,
    required String uid,
    String? providedId,
    required double precoSugerido,
  }) async {
    final db = FirebaseFirestore.instance;
    final col = db.collection('tenants').doc(tenantId).collection('produtos');

    // Se veio um ID, tenta achar
    if (providedId != null && providedId.isNotEmpty) {
      final ref = col.doc(providedId);
      final snap = await ref.get();
      if (snap.exists) return ref.id;

      // Não existe -> perguntar dados mínimos e criar com ESTE ID
      final data = await showDialog<_NewProductData>(
        context: context,
        builder: (_) => _NewProductDialog(
          suggestedName: '',
          suggestedPrice: precoSugerido,
          allowCustomId: false, // já temos o ID informado
          fixedId: providedId,
        ),
      );
      if (data == null) return null;

      await ref.set(data.toMap(uid));
      return ref.id;
    }

    // Sem ID -> cria com ID automático
    final data = await showDialog<_NewProductData>(
      context: context,
      builder: (_) => _NewProductDialog(
        suggestedName: '',
        suggestedPrice: precoSugerido,
        allowCustomId: true,
      ),
    );
    if (data == null) return null;

    final ref =
        data.customId?.isNotEmpty == true ? col.doc(data.customId) : col.doc();
    await ref.set(data.toMap(uid));
    // coloca o ID gerado no campo, pra facilitar entradas futuras
    _prodIdCtrl.text = ref.id;
    return ref.id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrada manual')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _prodIdCtrl,
            decoration: const InputDecoration(
              labelText: 'ID do produto (documentId) – opcional',
              helperText: 'Deixe vazio para criar com ID automático',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(
                signed: false, decimal: false),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Quantidade (+)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _costCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Custo unitário (opcional)',
              helperText: 'Se informado, uso como preço sugerido do produto',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(labelText: 'Motivo'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Salvando...' : 'Salvar'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dados mínimos para criar um produto
class _NewProductData {
  final String nome;
  final double preco;
  final int estoqueMinimo;
  final String? categoria;
  final String? sku;
  final String? customId;

  _NewProductData({
    required this.nome,
    required this.preco,
    required this.estoqueMinimo,
    this.categoria,
    this.sku,
    this.customId,
  });

  Map<String, dynamic> toMap(String uid) {
    final map = <String, dynamic>{
      'nome': nome,
      'nomeLower': nome.toLowerCase(),
      'precoVenda': preco, // garante "algum preço" nas RULES
      'quantidade': 0, // saldo inicial; a entrada somará depois
      'estoqueMinimo': estoqueMinimo,
      'ativo': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'updatedBy': uid,
    };
    if ((categoria ?? '').trim().isNotEmpty)
      map['categoria'] = categoria!.trim();
    if ((sku ?? '').trim().isNotEmpty) map['sku'] = sku!.trim();
    return map;
  }
}

/// Diálogo para capturar dados mínimos do novo produto
class _NewProductDialog extends StatefulWidget {
  final String suggestedName;
  final double suggestedPrice;
  final bool allowCustomId;
  final String? fixedId;

  const _NewProductDialog({
    required this.suggestedName,
    required this.suggestedPrice,
    required this.allowCustomId,
    this.fixedId,
  });

  @override
  State<_NewProductDialog> createState() => _NewProductDialogState();
}

class _NewProductDialogState extends State<_NewProductDialog> {
  final _nome = TextEditingController();
  final _preco = TextEditingController();
  final _min = TextEditingController(text: '0');
  final _cat = TextEditingController();
  final _sku = TextEditingController();
  final _id = TextEditingController(); // opcional

  @override
  void initState() {
    super.initState();
    _nome.text = widget.suggestedName;
    _preco.text = widget.suggestedPrice.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _nome.dispose();
    _preco.dispose();
    _min.dispose();
    _cat.dispose();
    _sku.dispose();
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Criar produto'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            if (widget.allowCustomId)
              TextField(
                controller: _id,
                decoration: const InputDecoration(
                  labelText: 'ID do produto (opcional)',
                  helperText: 'Deixe vazio para ID automático',
                ),
              )
            else if (widget.fixedId != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('ID: ${widget.fixedId}',
                    style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _preco,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço de venda *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _min,
              keyboardType: const TextInputType.numberWithOptions(
                  signed: false, decimal: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Estoque mínimo'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cat,
              decoration:
                  const InputDecoration(labelText: 'Categoria (opcional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sku,
              decoration: const InputDecoration(labelText: 'SKU (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final nome = _nome.text.trim();
            final preco =
                double.tryParse(_preco.text.trim().replaceAll(',', '.')) ?? -1;
            final minimo = int.tryParse(_min.text.trim()) ?? 0;
            if (nome.isEmpty || preco < 0) return;

            Navigator.pop(
              context,
              _NewProductData(
                nome: nome,
                preco: preco,
                estoqueMinimo: minimo,
                categoria: _cat.text.trim().isEmpty ? null : _cat.text.trim(),
                sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
                customId: _id.text.trim().isEmpty ? null : _id.text.trim(),
              ),
            );
          },
          child: const Text('Criar'),
        ),
      ],
    );
  }
}
