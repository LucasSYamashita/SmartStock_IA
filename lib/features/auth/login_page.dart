// lib/features/auth/login_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../shared/widgets/app_input.dart';
import '../../shared/widgets/app_button.dart';
import '../../features/auth/register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _showPass = false;

  bool loading = false;
  String? err;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      loading = true;
      err = null;
    });

    final email = _email.text.trim();
    final pass = _pass.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      setState(() {
        err = 'Preencha e-mail e senha.';
        loading = false;
      });
      return;
    }

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );
      // Navegação pós-login costuma ser feita pelo Gate/Stream de auth.
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        if (pass.length < 6) {
          setState(() {
            err = 'A senha precisa ter pelo menos 6 caracteres.';
          });
        } else {
          // MVP: cria a conta automaticamente
          try {
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
              email: email,
              password: pass,
            );
          } on FirebaseAuthException catch (e2) {
            String msg = e2.message ?? e2.code;
            if (e2.code == 'email-already-in-use') {
              msg = 'Este e-mail já está em uso.';
            } else if (e2.code == 'invalid-email') {
              msg = 'E-mail inválido.';
            } else if (e2.code == 'weak-password') {
              msg = 'Senha fraca (mínimo 6).';
            }
            setState(() => err = msg);
          }
        }
      } else {
        String msg = e.message ?? e.code;
        if (e.code == 'invalid-email') msg = 'E-mail inválido.';
        if (e.code == 'wrong-password') msg = 'Senha incorreta.';
        if (e.code == 'user-disabled') msg = 'Usuário desativado.';
        setState(() => err = msg);
      }
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => err = 'Informe seu e-mail para enviar o reset de senha.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enviamos um e-mail para redefinir a senha.')),
      );
    } on FirebaseAuthException catch (e) {
      String msg = e.message ?? e.code;
      if (e.code == 'invalid-email') msg = 'E-mail inválido.';
      if (e.code == 'user-not-found') msg = 'Não há usuário com esse e-mail.';
      setState(() => err = msg);
    } catch (e) {
      setState(() => err = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bem-vindo ao SmartStock',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _email,
                      label: 'E-mail',
                      keyboardType: TextInputType.emailAddress,
                      prefix: const Icon(Icons.mail_outline),
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _pass,
                      label: 'Senha',
                      obscure: !_showPass,
                      prefix: const Icon(Icons.lock_outline),
                      suffix: IconButton(
                        onPressed: () => setState(() => _showPass = !_showPass),
                        icon: Icon(_showPass
                            ? Icons.visibility_off
                            : Icons.visibility),
                        tooltip: _showPass ? 'Ocultar' : 'Mostrar',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: loading ? null : _forgotPassword,
                        child: const Text('Esqueci a senha'),
                      ),
                    ),
                    if (err != null) ...[
                      const SizedBox(height: 4),
                      Text(err!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 8),
                    AppButton(
                      text: loading ? 'Entrando...' : 'Entrar / Criar',
                      onPressed: loading ? null : _login,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Prefere cadastrar primeiro?'),
                        TextButton(
                          onPressed: loading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterPage(),
                                    ),
                                  ),
                          child: const Text('Cadastre-se'),
                        ),
                      ],
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
