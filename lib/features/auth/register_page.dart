import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartstock_flutter_only/Homepage.dart';

import '../../shared/widgets/app_input.dart';
import '../../shared/widgets/app_button.dart';
import '../tenant/tenant_provider.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});
  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();

  bool _createStore = true; // criar loja (admin) OU entrar por código (staff)
  final _storeName = TextEditingController();
  final _joinCode = TextEditingController();

  bool loading = false;
  String? err;

  String _genCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<String> _genUniqueCode(FirebaseFirestore db) async {
    for (int i = 0; i < 5; i++) {
      final c = _genCode();
      final exists = await db.collection('tenant_codes').doc(c).get();
      if (!exists.exists) return c;
    }
    return _genCode();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final p1 = _pass.text.trim();
    final p2 = _pass2.text.trim();

    if (name.isEmpty || email.isEmpty || p1.length < 6 || p1 != p2) {
      setState(() =>
          err = 'Preencha tudo corretamente. Senha ≥ 6 e confirmação igual.');
      return;
    }

    setState(() {
      loading = true;
      err = null;
    });
    try {
      // 1) cria usuário auth
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: p1);
      await cred.user!.updateDisplayName(name);

      final db = FirebaseFirestore.instance;
      final uid = cred.user!.uid;

      // 2) cria loja (admin) OU entra por código (staff)
      DocumentReference<Map<String, dynamic>> tenantRef;

      if (_createStore) {
        final storeName = _storeName.text.trim();
        if (storeName.isEmpty) {
          setState(() => err = 'Informe o nome da loja.');
          return;
        }

        final code = await _genUniqueCode(db);

        tenantRef = await db.collection('tenants').add({
          'name': storeName,
          'code': code,
          'ownerUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await tenantRef.collection('usuarios').doc(uid).set({
          'uid': uid,
          'role': 'admin',
          'displayName': name,
          'email': email,
          'joinedAt': FieldValue.serverTimestamp(),
        });

        // index para lookup por código
        await db.collection('tenant_codes').doc(code).set({
          'tenantId': tenantRef.id,
          'ownerUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        final code = _joinCode.text.trim().toUpperCase();
        if (code.length < 4) {
          setState(() => err = 'Código inválido.');
          return;
        }

        // lookup seguro
        final codeDoc = await db.collection('tenant_codes').doc(code).get();
        if (!codeDoc.exists) {
          setState(() => err = 'Loja não encontrada.');
          return;
        }
        final tenantId = codeDoc.get('tenantId') as String;
        tenantRef = db.collection('tenants').doc(tenantId);

        await tenantRef.collection('usuarios').doc(uid).set({
          'uid': uid,
          'role': 'staff',
          'displayName': name,
          'email': email,
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 3) salva tenantId localmente e vai pra Home
      await ref.read(tenantIdProvider.notifier).set(tenantRef.id);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomePage()),
          (r) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = e.message ?? e.code;
      if (e.code == 'email-already-in-use') msg = 'Este e-mail já está em uso.';
      if (e.code == 'invalid-email') msg = 'E-mail inválido.';
      if (e.code == 'weak-password') msg = 'Senha fraca (mínimo 6).';
      setState(() => err = msg);
    } on FirebaseException catch (e) {
      setState(() => err = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    _storeName.dispose();
    _joinCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = _createStore;

    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text('Cadastre-se',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    AppTextField(
                        controller: _name,
                        label: 'Nome',
                        prefix: const Icon(Icons.person_outline)),
                    const SizedBox(height: 12),
                    AppTextField(
                        controller: _email,
                        label: 'E-mail',
                        prefix: const Icon(Icons.mail_outline)),
                    const SizedBox(height: 12),
                    AppTextField(
                        controller: _pass,
                        label: 'Senha',
                        obscure: true,
                        prefix: const Icon(Icons.lock_outline)),
                    const SizedBox(height: 12),
                    AppTextField(
                        controller: _pass2,
                        label: 'Confirmar senha',
                        obscure: true,
                        prefix: const Icon(Icons.lock_reset)),
                    const SizedBox(height: 16),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: true, label: Text('Criar loja (Admin)')),
                        ButtonSegment(
                            value: false,
                            label: Text('Entrar por código (Staff)')),
                      ],
                      selected: {_createStore},
                      onSelectionChanged: (s) =>
                          setState(() => _createStore = s.first),
                    ),
                    const SizedBox(height: 12),
                    if (isCreate)
                      AppTextField(
                          controller: _storeName,
                          label: 'Nome da loja',
                          prefix:
                              const Icon(Icons.store_mall_directory_outlined))
                    else
                      AppTextField(
                          controller: _joinCode,
                          label: 'Código da loja',
                          prefix: const Icon(Icons.qr_code_2_outlined)),
                    const SizedBox(height: 12),
                    if (err != null)
                      Text(err!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    AppButton(
                      text: loading
                          ? 'Criando...'
                          : (isCreate
                              ? 'Criar conta e loja'
                              : 'Criar conta e entrar'),
                      onPressed: loading ? null : _submit,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Já tenho conta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
