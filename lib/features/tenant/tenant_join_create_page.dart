import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tenant_provider.dart';

class TenantJoinCreatePage extends ConsumerStatefulWidget {
  const TenantJoinCreatePage({super.key});
  @override
  ConsumerState<TenantJoinCreatePage> createState() =>
      _TenantJoinCreatePageState();
}

class _TenantJoinCreatePageState extends ConsumerState<TenantJoinCreatePage> {
  final _createForm = GlobalKey<FormState>();
  final _joinForm = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _creating = false;
  bool _joining = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String _genCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<String> _createUniqueCode(FirebaseFirestore db) async {
    // tenta gerar um code único algumas vezes para evitar colisão
    for (var i = 0; i < 6; i++) {
      final code = _genCode();
      final snap = await db.collection('tenant_codes').doc(code).get();
      if (!snap.exists) return code;
    }
    throw Exception('Não foi possível gerar um código único. Tente novamente.');
  }

  Future<void> _createTenant() async {
    if (!(_createForm.currentState?.validate() ?? false)) return;

    setState(() => _creating = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;
      final db = FirebaseFirestore.instance;

      final code = await _createUniqueCode(db);

      // cria tenant
      final tenantRef = await db.collection('tenants').add({
        'name': _nameCtrl.text.trim(),
        'code': code,
        'ownerUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // index público para ingresso por código
      await db.collection('tenant_codes').doc(code).set({
        'tenantId': tenantRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // membership do criador como admin
      await tenantRef.collection('usuarios').doc(uid).set({
        'uid': uid,
        'role': 'admin',
        'displayName': user.displayName,
        'email': user.email,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      ref.read(tenantIdProvider.notifier).state = tenantRef.id;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loja criada com sucesso.')),
        );
        Navigator.of(context).pushReplacementNamed('/');
      }
    } on FirebaseException catch (e) {
      _showErr('${e.code}: ${e.message}');
    } catch (e) {
      _showErr(e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _joinTenant() async {
    if (!(_joinForm.currentState?.validate() ?? false)) return;

    setState(() => _joining = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;
      final db = FirebaseFirestore.instance;

      final code = _codeCtrl.text.trim().toUpperCase();
      final codeDoc = await db.collection('tenant_codes').doc(code).get();
      if (!codeDoc.exists) {
        _showErr('Loja não encontrada para o código informado.');
        return;
      }

      final tenantId = codeDoc.get('tenantId') as String;
      final tenantRef = db.collection('tenants').doc(tenantId);

      // cria/atualiza membership
      await tenantRef.collection('usuarios').doc(uid).set({
        'uid': uid,
        'role': 'staff',
        'displayName': user.displayName,
        'email': user.email,
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ref.read(tenantIdProvider.notifier).state = tenantId;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ingresso realizado na loja ($code).')),
        );
        Navigator.of(context).pushReplacementNamed('/');
      }
    } on FirebaseException catch (e) {
      _showErr('${e.code}: ${e.message}');
    } catch (e) {
      _showErr(e.toString());
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sua loja')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // CRIAR LOJA
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _createForm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Criar nova loja',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Nome da loja'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Informe o nome.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _creating ? null : _createTenant,
                      icon: _creating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_business),
                      label: Text(_creating ? 'Criando...' : 'Criar e entrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ENTRAR POR CÓDIGO
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _joinForm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Entrar em loja existente',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: 'Código da loja (6 chars)'),
                      validator: (v) {
                        final code = (v ?? '').trim();
                        if (code.length < 4) return 'Código inválido.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _joining ? null : _joinTenant,
                      icon: _joining
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(_joining ? 'Entrando...' : 'Entrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
