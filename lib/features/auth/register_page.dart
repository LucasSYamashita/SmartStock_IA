import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_input.dart';
import '../tenant/tenant_provider.dart';
import '../tenant/tenant_join_create_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();

  bool loading = false;
  String? err, ok;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final p1 = _pass.text.trim();
    final p2 = _pass2.text.trim();

    if (name.isEmpty || email.isEmpty || p1.length < 6 || p1 != p2) {
      setState(
        () =>
            err = 'Preencha tudo corretamente. Senha ≥ 6 e confirmação igual.',
      );
      return;
    }

    setState(() {
      loading = true;
      err = null;
      ok = null;
    });

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: p1,
      );

      await cred.user!.updateDisplayName(name);

      // Perfil global (opcional)
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(cred.user!.uid)
          .set({
            'email': email,
            'displayName': name,
            'role': 'viewer',
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => ok = 'Conta criada! Agora selecione/crie sua loja.');

      // Leva para a tela de entrar/criar loja
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TenantJoinCreatePage()),
      );
    } on FirebaseAuthException catch (e) {
      String msg = e.message ?? e.code;
      if (e.code == 'email-already-in-use') msg = 'Este e-mail já está em uso.';
      if (e.code == 'invalid-email') msg = 'E-mail inválido.';
      if (e.code == 'weak-password') msg = 'Senha fraca (mínimo 6).';
      setState(() => err = msg);
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    Text(
                      'Cadastre-se',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _name,
                      label: 'Nome',
                      prefix: const Icon(Icons.person_outline),
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _email,
                      label: 'E-mail',
                      prefix: const Icon(Icons.mail_outline),
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _pass,
                      label: 'Senha',
                      obscure: true,
                      prefix: const Icon(Icons.lock_outline),
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _pass2,
                      label: 'Confirmar senha',
                      obscure: true,
                      prefix: const Icon(Icons.lock_reset),
                    ),
                    const SizedBox(height: 16),
                    if (err != null)
                      Text(err!, style: const TextStyle(color: Colors.red)),
                    if (ok != null)
                      Text(ok!, style: const TextStyle(color: Colors.green)),
                    const SizedBox(height: 8),
                    AppButton(
                      text: loading ? 'Criando...' : 'Criar conta',
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
