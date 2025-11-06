import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tenant/tenant_provider.dart';
import '../tenant/membership_guard.dart'; // para checar role
import 'product_service.dart';

class ProductEditorPage extends ConsumerStatefulWidget {
  final String? productId; // null = criar
  const ProductEditorPage({super.key, this.productId});

  @override
  ConsumerState<ProductEditorPage> createState() => _ProductEditorPageState();
}

class _ProductEditorPageState extends ConsumerState<ProductEditorPage> {
  final _nome = TextEditingController();
  final _categoria = TextEditingController();
  final _sku = TextEditingController();
  final _preco = TextEditingController(text: '0');
  final _qtd = TextEditingController(text: '0');
  final _min = TextEditingController(text: '0');
  bool _ativo = true;

  bool _loading = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfNeeded());
  }

  @override
  void dispose() {
    _nome.dispose();
    _categoria.dispose();
    _sku.dispose();
    _preco.dispose();
    _qtd.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _loadIfNeeded() async {
    if (widget.productId == null) return;
    final tenantId = ref.read(tenantIdProvider);
    if (tenantId == null) return;

    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('tenants')
          .doc(tenantId)
          .collection('produtos')
          .doc(widget.productId)
          .get();

      if (!snap.exists) {
        setState(() => _err = 'Produto não encontrado.');
        return;
      }

      final p = snap.data()!;
      _nome.text = (p['nome'] ?? '').toString();
      _categoria.text = (p['categoria'] ?? '').toString();
      _sku.text = (p['sku'] ?? '').toString();
      _preco.text = ((p['preco'] ?? 0) as num).toStringAsFixed(2);
      _qtd.text = ((p['quantidade'] ?? 0) as num).toString();
      _min.text = ((p['estoqueMinimo'] ?? 0) as num).toString();
      _ativo = (p['ativo'] is bool) ? p['ativo'] as bool : true;
      setState(() {});
    } on FirebaseException catch (e) {
      setState(() => _err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _parsePreco() =>
      double.tryParse(_preco.text.trim().replaceAll(',', '.')) ?? 0.0;

  int _parseInt(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    final tenantId = ref.read(tenantIdProvider);
    if (tenantId == null) {
      setState(() => _err = 'Nenhuma loja selecionada.');
      return;
    }

    // checa role
    final member = ref.read(membershipProvider(tenantId)).maybeWhen(
          data: (m) => m,
          orElse: () => null,
        );
    final isAdmin = (member?['role'] ?? '') == 'admin';
    if (!isAdmin) {
      setState(
          () => _err = 'Permissão insuficiente (apenas admin pode salvar).');
      return;
    }

    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      setState(() => _err = 'Informe o nome.');
      return;
    }

    final preco = _parsePreco();
    final quantidade = _parseInt(_qtd).clamp(0, 999999);
    final minimo = _parseInt(_min).clamp(0, 999999);

    setState(() {
      _loading = true;
      _err = null;
    });

    try {
      if (widget.productId == null) {
        // CRIAR
        final uid = FirebaseAuth.instance.currentUser!.uid;
        final doc = await FirebaseFirestore.instance
            .collection('tenants')
            .doc(tenantId)
            .collection('produtos')
            .add({
          'nome': nome,
          'nomeLower': nome.toLowerCase(),
          'categoria': _categoria.text.trim(),
          'sku': _sku.text.trim().isEmpty ? '' : _sku.text.trim(),
          'preco': preco,
          'quantidade': quantidade,
          'estoqueMinimo': minimo,
          'ativo': _ativo,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        });

        // se criou com quantidade > 0, registra movimento de entrada
        if (quantidade > 0) {
          await ProductService.registrarEntradaNoProduto(
            tenantId: tenantId,
            produtoId: doc.id,
            quantidade: quantidade,
            motivo: 'cadastro_inicial',
          );
        }
      } else {
        // EDITAR (usa serviço que também loga ajuste se a quantidade mudou)
        await ProductService.salvarEdicaoProduto(
          tenantId: tenantId,
          produtoId: widget.productId!,
          nome: nome,
          categoria: _categoria.text.trim(),
          sku: _sku.text.trim(),
          preco: preco,
          quantidade: quantidade,
          estoqueMinimo: minimo,
          ativo: _ativo,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.productId == null
                ? 'Produto criado.'
                : 'Produto atualizado.',
          ),
        ),
      );
    } on FirebaseException catch (e) {
      setState(() => _err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.productId != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Editar produto' : 'Novo produto')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nome,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _categoria,
                  decoration: const InputDecoration(
                    labelText: 'Categoria',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sku,
                  decoration: const InputDecoration(
                    labelText: 'SKU (opcional)',
                    prefixIcon: Icon(Icons.tag_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _preco,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]'))
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Preço (R\$)',
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _qtd,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Quantidade',
                          prefixIcon: Icon(Icons.numbers),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _min,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Mínimo',
                          prefixIcon: Icon(Icons.warning_amber_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _ativo,
                  onChanged: (v) => setState(() => _ativo = v),
                  title: const Text('Ativo'),
                  subtitle: const Text(
                      'Se desmarcado, o item fica oculto nas vendas.'),
                ),
                const SizedBox(height: 12),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child:
                        Text(_err!, style: const TextStyle(color: Colors.red)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _save,
                    child: Text(
                      _loading
                          ? 'Salvando...'
                          : (isEdit ? 'Salvar alterações' : 'Criar produto'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
