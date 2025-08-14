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
  bool loading = false;
  String? err;

  Future<void> _login() async {
    setState(() {
      loading = true;
      err = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        final pass = _pass.text.trim();
        if (pass.length < 6) {
          setState(() {
            err = 'A senha precisa ter pelo menos 6 caracteres.';
          });
        } else {
          // Cria a conta rapidamente para o MVP.
          // (O vínculo com a loja é feito na TenantJoinCreatePage)
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _email.text.trim(),
            password: pass,
          );
        }
      } else {
        setState(() {
          err = '${e.code}: ${e.message ?? ''}';
        });
      }
    } catch (e) {
      setState(() {
        err = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
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
                    if (err != null)
                      Text(err!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    AppButton(
                      text: loading ? 'Entrando...' : 'Entrar / Criar',
                      onPressed: loading ? null : _login,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Não tem conta?'),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const RegisterPage()),
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
