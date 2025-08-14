import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tenant_provider.dart';

class TenantJoinCreatePage extends ConsumerStatefulWidget {
  const TenantJoinCreatePage({super.key});
  @override
  ConsumerState<TenantJoinCreatePage> createState() => _State();
}

class _State extends ConsumerState<TenantJoinCreatePage> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool working = false;
  String? err;

  String _genCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // Gera um código que não existe em tenant_codes
  Future<String> _genUniqueCode(FirebaseFirestore db) async {
    for (int i = 0; i < 5; i++) {
      final c = _genCode();
      final exists = await db.collection('tenant_codes').doc(c).get();
      if (!exists.exists) return c;
    }
    // Se por algum motivo não achar, retorna um código mesmo assim
    return _genCode();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => err = 'Informe o nome da loja.');
      return;
    }
    setState(() {
      working = true;
      err = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;
      final db = FirebaseFirestore.instance;

      // cria loja
      final code = await _genUniqueCode(db);
      final tenantRef = await db.collection('tenants').add({
        'name': name,
        'code': code, // opcional manter também aqui
        'ownerUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // membership admin
      await tenantRef.collection('usuarios').doc(uid).set({
        'uid': uid,
        'role': 'admin',
        'displayName': user.displayName,
        'email': user.email,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      // index público para lookup por código (JOIN)
      await db.collection('tenant_codes').doc(code).set({
        'tenantId': tenantRef.id,
        'ownerUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await ref.read(tenantIdProvider.notifier).set(tenantRef.id);
      if (mounted) Navigator.of(context).pushReplacementNamed('/');
    } on FirebaseException catch (e) {
      setState(() => err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _join() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => err = 'Código inválido.');
      return;
    }
    setState(() {
      working = true;
      err = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;
      final db = FirebaseFirestore.instance;

      // busca em tenant_codes (não em /tenants)
      final codeDoc = await db.collection('tenant_codes').doc(code).get();
      if (!codeDoc.exists) {
        setState(() => err = 'Loja não encontrada.');
        return;
      }
      final tenantId = codeDoc.get('tenantId') as String;
      final tenantRef = db.collection('tenants').doc(tenantId);

      // cria/atualiza membership do usuário
      await tenantRef.collection('usuarios').doc(uid).set({
        'uid': uid,
        'role': 'staff', // ou 'viewer'
        'displayName': user.displayName,
        'email': user.email,
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await ref.read(tenantIdProvider.notifier).set(tenantId);
      if (mounted) Navigator.of(context).pushReplacementNamed('/');
    } on FirebaseException catch (e) {
      setState(() => err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sua loja')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Criar nova loja',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _name,
                      decoration:
                          const InputDecoration(labelText: 'Nome da loja')),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: working ? null : _create,
                    child: Text(working ? 'Criando...' : 'Criar e entrar'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Entrar em loja existente',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _code,
                      decoration:
                          const InputDecoration(labelText: 'Código da loja')),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: working ? null : _join,
                      child: const Text('Entrar')),
                ],
              ),
            ),
          ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(err!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
}
