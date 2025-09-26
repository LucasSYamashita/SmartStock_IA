// lib/features/tenant/tenant_join_create_page.dart
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
  final _joinCode = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _working = false;
  String? _err, _ok;

  @override
  void dispose() {
    _joinCode.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String _genCode({int len = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _joinByCode() async {
    setState(() {
      _working = true;
      _err = null;
      _ok = null;
    });

    try {
      final code = _joinCode.text.trim().toUpperCase();
      if (code.isEmpty) {
        setState(() => _err = 'Informe um código.');
        return;
      }

      final db = FirebaseFirestore.instance;
      String? tenantId;

      // 1) Primeiro tenta direto em /tenants pelo campo 'code'
      final snapTenants = await db
          .collection('tenants')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();
      if (snapTenants.docs.isNotEmpty) {
        tenantId = snapTenants.docs.first.id;
      } else {
        // 2) Fallback: /tenant_codes (se você ainda usa esse alias)
        final snapCodes = await db
            .collection('tenant_codes')
            .where('code', isEqualTo: code)
            .limit(1)
            .get();
        if (snapCodes.docs.isNotEmpty) {
          tenantId = (snapCodes.docs.first.data()['tenantId'] ?? '').toString();
        }
      }

      if (tenantId == null || tenantId.isEmpty) {
        setState(() => _err = 'Código inválido.');
        return;
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Cria/atualiza membership do próprio usuário como 'staff'
      await db
          .collection('tenants')
          .doc(tenantId)
          .collection('usuarios')
          .doc(uid)
          .set({
        'role': 'staff',
        'active': true,
        'displayName': FirebaseAuth.instance.currentUser?.displayName ?? '',
        'email': FirebaseAuth.instance.currentUser?.email ?? '',
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Salva seleção local
      await ref.read(tenantIdProvider.notifier).set(tenantId);

      setState(() => _ok = 'Você entrou na loja.');
    } on FirebaseException catch (e) {
      setState(() => _err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _createTenant() async {
    setState(() {
      _working = true;
      _err = null;
      _ok = null;
    });

    try {
      final name = _nameCtrl.text.trim();
      if (name.isEmpty) {
        setState(() => _err = 'Informe o nome da loja.');
        return;
      }

      final db = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Gera code curto e garante unicidade básica em /tenants
      String code = _genCode();
      for (int i = 0; i < 6; i++) {
        final exists = await db
            .collection('tenants')
            .where('code', isEqualTo: code)
            .limit(1)
            .get();
        if (exists.docs.isEmpty) break;
        code = _genCode();
      }

      // Cria tenant com TODOS os campos exigidos pelas rules
      final tRef = await db.collection('tenants').add({
        'name': name,
        'code': code,
        'createdBy': uid, // obrigatório p/ rule de create
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Criador vira admin
      await tRef.collection('usuarios').doc(uid).set({
        'role': 'admin',
        'active': true,
        'displayName': FirebaseAuth.instance.currentUser?.displayName ?? '',
        'email': FirebaseAuth.instance.currentUser?.email ?? '',
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // (Opcional) cria alias em /tenant_codes — útil pra compartilhar
      try {
        await db.collection('tenant_codes').add({
          'code': code,
          'tenantId': tRef.id,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': uid,
        });
      } catch (_) {
        // se a coleção não existir / regra bloquear, não quebra o fluxo principal
      }

      // Salva tenant selecionado
      await ref.read(tenantIdProvider.notifier).set(tRef.id);

      setState(() => _ok = 'Loja criada. Código de convite: $code');
    } on FirebaseException catch (e) {
      setState(() => _err = '(${e.code}) ${e.message}');
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Selecionar loja')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Entrar por código
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Entrar numa loja existente',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _joinCode,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Código da loja',
                      hintText: 'Ex.: 7K3W9Q',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                    onSubmitted: (_) => _working ? null : _joinByCode(),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _working ? null : _joinByCode,
                      child: Text(_working ? 'Processando...' : 'Entrar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Criar nova loja
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Criar nova loja', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome da loja',
                      prefixIcon: Icon(Icons.store_mall_directory_outlined),
                    ),
                    onSubmitted: (_) => _working ? null : _createTenant(),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: _working ? null : _createTenant,
                      child: Text(_working ? 'Criando...' : 'Criar loja'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_err!, style: const TextStyle(color: Colors.red)),
            ),
          if (_ok != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_ok!, style: const TextStyle(color: Colors.green)),
            ),
        ],
      ),
    );
  }
}
