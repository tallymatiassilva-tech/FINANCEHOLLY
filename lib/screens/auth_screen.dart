import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../widgets/dialog_controller_owner.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _hasUsers = true;
  bool _checking = true;
  bool _biometricSupported = false;

  @override
  void initState() {
    super.initState();
    _checkUsers();
    _checkBiometrics();
  }

  Future<void> _checkUsers() async {
    final hasUsers = await context.read<AppState>().hasUsers();
    if (!mounted) return;
    setState(() {
      _hasUsers = hasUsers;
      _checking = false;
    });
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (mounted) {
        setState(() => _biometricSupported = canCheck || isSupported);
      }
    } catch (_) {}
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Autentique-se para acessar o Controle Financeiro',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
      if (authenticated && mounted) {
        final success = await context.read<AppState>().loginWithBiometrics(_username.text);
        if (!success && mounted) {
          _message('Nenhum usuário cadastrado. Cadastre o primeiro administrador.');
        }
      }
    } catch (e) {
      if (mounted) _message('Erro na autenticação biométrica: $e');
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    await showDialogWithControllers<void>(
      context: context,
      controllers: [name, username, password, recoveryKey],
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
                  labelText: recovery
                      ? 'Chave de recuperação'
                      : 'Criar chave de recuperação',
                ),
                textInputAction: TextInputAction.next,
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: recovery
                      ? 'Nova senha'
                      : 'Senha (mínimo 6 caracteres)',
                ),
                textInputAction: TextInputAction.done,
              ),
              if (!recovery && !isFirstUser)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Novos cadastros recebem acesso somente para consulta.',
                  ),
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
                final enteredUser = username.text;
                final enteredPass = password.text;
                if (recovery) {
                  await state.recoverPassword(
                    username: enteredUser,
                    recoveryKey: recoveryKey.text,
                    newPassword: enteredPass,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) _message('Senha redefinida.');
                } else {
                  await state.register(
                    name: name.text,
                    username: enteredUser,
                    password: enteredPass,
                    recoveryKey: recoveryKey.text,
                    role: isFirstUser ? 'Administrador' : 'Consulta',
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (isFirstUser) {
                    await state.login(enteredUser, enteredPass);
                  } else if (mounted) {
                    setState(() => _hasUsers = true);
                    _message('Usuário cadastrado.');
                  }
                }
              } catch (error) {
                if (mounted) {
                  _message(error.toString().replaceFirst('Exception: ', ''));
                }
              }
            },
            child: Text(recovery ? 'Redefinir' : 'Salvar'),
          ),
        ],
      ),
    );
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
                    if (_biometricSupported) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _authenticateWithBiometrics,
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Entrar com Biometria'),
                        ),
                      ),
                    ],
                    TextButton(
                      onPressed: () => _openAccountDialog(),
                      child: Text(
                        _hasUsers
                            ? 'Cadastrar usuário'
                            : 'Cadastrar primeiro administrador',
                      ),
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
