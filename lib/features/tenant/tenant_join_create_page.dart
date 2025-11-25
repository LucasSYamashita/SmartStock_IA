// lib/features/tenant/tenant_join_create_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_input.dart';
import 'tenant_provider.dart';

class TenantJoinCreatePage extends ConsumerStatefulWidget {
  const TenantJoinCreatePage({super.key});

  @override
  ConsumerState<TenantJoinCreatePage> createState() =>
      _TenantJoinCreatePageState();
}

class _TenantJoinCreatePageState extends ConsumerState<TenantJoinCreatePage> {
  // para entrar em loja existente (código)
  final _codeCtrl = TextEditingController();

  // para criar nova loja
  final _storeNameCtrl = TextEditingController();

  bool _loadingJoin = false;
  bool _loadingCreate = false;
  String? _errorJoin;
  String? _errorCreate;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _storeNameCtrl.dispose();
    super.dispose();
  }

  // -------------------- entrar em loja existente por código -----------------
  Future<void> _joinByCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _errorJoin = 'Informe o código da loja.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _errorJoin = 'Você precisa estar logado.');
      return;
    }

    setState(() {
      _loadingJoin = true;
      _errorJoin = null;
    });

    try {
      final db = FirebaseFirestore.instance;

      // procura o código em tenant_codes/{code}
      final codeSnap =
          await db.collection('tenant_codes').doc(code).get(const GetOptions());

      if (!codeSnap.exists) {
        setState(() => _errorJoin = 'Código inválido ou loja não encontrada.');
        return;
      }

      final data = codeSnap.data()!;
      final tenantId = (data['tenantId'] ?? '').toString();

      if (tenantId.isEmpty) {
        setState(() => _errorJoin = 'Código inválido (tenantId ausente).');
        return;
      }

      // cria/atualiza membership do usuário como STAFF
      final memberRef = db
          .collection('tenants')
          .doc(tenantId)
          .collection('usuarios')
          .doc(user.uid);

      await memberRef.set({
        'role': 'staff',
        'displayName': user.displayName ?? '',
        'email': user.email ?? '',
        'active': true,
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // salva o tenant atual para o app inteiro
      await ref.read(tenantIdProvider.notifier).set(tenantId);

      if (!mounted) return;

      // ✅ depois de escolher a loja, volta para a tela anterior (Home)
      Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      setState(() => _errorJoin = e.message ?? e.code);
    } catch (e) {
      setState(() => _errorJoin = e.toString());
    } finally {
      if (mounted) setState(() => _loadingJoin = false);
    }
  }

  // -------------------- criar nova loja -------------------------------------
  Future<void> _createTenant() async {
    final name = _storeNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorCreate = 'Informe o nome da loja.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _errorCreate = 'Você precisa estar logado.');
      return;
    }

    setState(() {
      _loadingCreate = true;
      _errorCreate = null;
    });

    try {
      final db = FirebaseFirestore.instance;

      // cria um ID aleatório para o tenant
      final tenantRef = db.collection('tenants').doc();

      // 1) cria o documento do tenant
      await tenantRef.set({
        'name': name,
        'ownerId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2) cria o membership do dono como ADMIN nessa loja
      await tenantRef.collection('usuarios').doc(user.uid).set({
        'role': 'admin',
        'displayName': user.displayName ?? '',
        'email': user.email ?? '',
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3) define o tenant atual no provider global
      await ref.read(tenantIdProvider.notifier).set(tenantRef.id);

      if (!mounted) return;

      // ✅ volta para a Home depois de criar a loja
      Navigator.of(context).pop();

      // snackbar opcional com o código da loja
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loja "$name" criada. Código: ${tenantRef.id}'),
        ),
      );
    } on FirebaseException catch (e) {
      setState(() => _errorCreate = e.message ?? e.code);
    } catch (e) {
      setState(() => _errorCreate = e.toString());
    } finally {
      if (mounted) setState(() => _loadingCreate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Selecionar / Criar loja')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Entrar em loja existente',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              AppTextField(
                                controller: _codeCtrl,
                                label: 'Código da loja',
                                prefix: const Icon(Icons.qr_code),
                              ),
                              const SizedBox(height: 12),
                              if (_errorJoin != null)
                                Text(
                                  _errorJoin!,
                                  style:
                                      const TextStyle(color: Colors.redAccent),
                                ),
                              const SizedBox(height: 8),
                              AppButton(
                                text: _loadingJoin
                                    ? 'Entrando...'
                                    : 'Entrar na loja',
                                onPressed:
                                    _loadingJoin ? null : () => _joinByCode(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Criar nova loja',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              AppTextField(
                                controller: _storeNameCtrl,
                                label: 'Nome da loja',
                                prefix: const Icon(Icons.store_mall_directory),
                              ),
                              const SizedBox(height: 12),
                              if (_errorCreate != null)
                                Text(
                                  _errorCreate!,
                                  style:
                                      const TextStyle(color: Colors.redAccent),
                                ),
                              const SizedBox(height: 8),
                              AppButton(
                                text: _loadingCreate
                                    ? 'Criando...'
                                    : 'Criar loja',
                                onPressed: _loadingCreate
                                    ? null
                                    : () => _createTenant(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
