import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _hasUsers = true;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkUsers();
  }

  Future<void> _checkUsers() async {
    final hasUsers = await context.read<AppState>().hasUsers();
    if (!mounted) return;
    setState(() {
      _hasUsers = hasUsers;
      _checking = false;
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _login() async {
    final ok = await context.read<AppState>().login(
          _username.text,
          _password.text,
        );
    if (!ok && mounted) _message('Usuário ou senha incorretos.');
  }

  Future<void> _openAccountDialog({bool recovery = false}) async {
    final name = TextEditingController();
    final username = TextEditingController(text: _username.text);
    final password = TextEditingController();
    final recoveryKey = TextEditingController();
    final isFirstUser = !_hasUsers && !recovery;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
          title: Text(
            recovery
                ? 'Recuperar senha'
                : isFirstUser
                    ? 'Criar administrador'
                    : 'Cadastrar usuário',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!recovery)
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nome'),
                  ),
                TextField(
                  controller: username,
                  decoration: const InputDecoration(labelText: 'Usuário'),
                  textInputAction: TextInputAction.next,
                ),
                TextField(
                  controller: recoveryKey,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: recovery ? 'Chave de recuperação' : 'Criar chave de recuperação',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: recovery ? 'Nova senha' : 'Senha (mínimo 6 caracteres)',
                  ),
                  textInputAction: TextInputAction.done,
                ),
                if (!recovery && !isFirstUser)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Novos cadastros recebem acesso somente para consulta.'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final state = context.read<AppState>();
                  if (recovery) {
                    await state.recoverPassword(
                      username: username.text,
                      recoveryKey: recoveryKey.text,
                      newPassword: password.text,
                    );
                  } else {
                    await state.register(
                      name: name.text,
                      username: username.text,
                      password: password.text,
                      recoveryKey: recoveryKey.text,
                      role: isFirstUser ? 'Administrador' : 'Consulta',
                    );
                    if (isFirstUser) {
                      await state.login(username.text, password.text);
                    }
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) {
                    setState(() => _hasUsers = true);
                    _message(recovery ? 'Senha redefinida.' : 'Usuário cadastrado.');
                  }
                } catch (error) {
                  if (mounted) _message(error.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: Text(recovery ? 'Redefinir' : 'Salvar'),
            ),
          ],
      ),
    );
    name.dispose();
    username.dispose();
    password.dispose();
    recoveryKey.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      'Controle Financeiro Igreja',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _username,
                      decoration: const InputDecoration(labelText: 'Usuário'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Senha'),
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _login,
                        child: const Text('Entrar'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openAccountDialog(),
                      child: Text(_hasUsers ? 'Cadastrar usuário' : 'Cadastrar primeiro administrador'),
                    ),
                    if (_hasUsers)
                      TextButton(
                        onPressed: () => _openAccountDialog(recovery: true),
                        child: const Text('Recuperar senha'),
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
