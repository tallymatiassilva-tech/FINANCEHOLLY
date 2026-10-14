import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../services/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _keys = [
    ('nome_igreja', 'Nome da igreja'),
    ('cnpj', 'CNPJ'),
    ('telefone', 'Telefone'),
    ('endereco', 'Endereço'),
    ('pastor', 'Pastor responsável'),
  ];
  final _controllers = <String, TextEditingController>{};
  String? _logoPath;
  late Future<void> _loaded;

  @override
  void initState() {
    super.initState();
    for (final item in _keys) {
      _controllers[item.$1] = TextEditingController();
    }
    _loaded = _load();
  }

  Future<void> _load() async {
    final rows = await context.read<AppState>().database.query('configuracoes');
    for (final row in rows) {
      final key = row['chave']?.toString();
      if (_controllers.containsKey(key)) {
        _controllers[key]!.text = row['valor']?.toString() ?? '';
      }
      if (key == 'logo_path') _logoPath = row['valor']?.toString();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (context.read<AppState>().user?['perfil'] == 'Consulta') {
      _message('Seu perfil tem acesso somente para consulta.');
      return;
    }
    final db = context.read<AppState>().database.database;
    for (final item in _keys) {
      await db.insert(
        'configuracoes',
        {'chave': item.$1, 'valor': _controllers[item.$1]!.text.trim()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (_logoPath != null) {
      await db.insert(
        'configuracoes',
        {'chave': 'logo_path', 'valor': _logoPath!},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configurações salvas no aparelho.')));
    }
  }

  Future<void> _addUser() async {
    final name = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final recovery = TextEditingController();
    var role = 'Tesoureiro';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cadastrar usuário'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
                TextField(controller: username, decoration: const InputDecoration(labelText: 'Usuário')),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha (mínimo 6 caracteres)'),
                ),
                TextField(
                  controller: recovery,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Chave de recuperação (mínimo 6 caracteres)'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Perfil'),
                  items: const ['Administrador', 'Tesoureiro', 'Consulta']
                      .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => role = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  await context.read<AppState>().register(
                        name: name.text,
                        username: username.text,
                        password: password.text,
                        recoveryKey: recovery.text,
                        role: role,
                      );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (mounted) _message('Não foi possível cadastrar: $error');
                }
              },
              child: const Text('Cadastrar'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    username.dispose();
    password.dispose();
    recovery.dispose();
    if (saved == true && mounted) _message('Usuário cadastrado.');
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _chooseLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        _message('Não foi possível ler o arquivo de imagem.');
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        _message('A imagem deve ter no máximo 5 MB.');
        return;
      }
      final extension = p.extension(file.name).toLowerCase();
      final validImage = switch (extension) {
        '.jpg' || '.jpeg' =>
          bytes.length >= 3 &&
              bytes[0] == 0xff &&
              bytes[1] == 0xd8 &&
              bytes[2] == 0xff,
        '.png' =>
          bytes.length >= 8 &&
              bytes.take(8).join(',') == '137,80,78,71,13,10,26,10',
        '.webp' =>
          bytes.length >= 12 &&
              String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
              String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP',
        _ => false,
      };
      if (!validImage) {
        _message('Selecione uma imagem PNG, JPG ou WebP válida.');
        return;
      }
      final directory = await getApplicationDocumentsDirectory();
      final localFile = File(p.join(directory.path, 'logo_igreja$extension'));
      await localFile.writeAsBytes(bytes, flush: true);
      if (mounted) setState(() => _logoPath = localFile.path);
    } catch (error) {
      if (mounted) _message('Não foi possível salvar a logo: $error');
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _loaded,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Dados da igreja', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final item in _keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _controllers[item.$1],
                    decoration: InputDecoration(labelText: item.$2),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _chooseLogo,
                icon: const Icon(Icons.image_outlined),
                label: Text(_logoPath == null ? 'Selecionar logo' : 'Logo selecionada'),
              ),
              if (_logoPath != null && File(_logoPath!).existsSync())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Image.file(File(_logoPath!), height: 100, fit: BoxFit.contain),
                ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text('Tema escuro'),
                value: context.watch<AppState>().darkMode,
                onChanged: context.read<AppState>().setDarkMode,
              ),
              const SizedBox(height: 12),
              if (context.watch<AppState>().user?['perfil'] == 'Administrador')
                OutlinedButton.icon(
                  onPressed: _addUser,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Cadastrar usuário e definir perfil'),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: context.watch<AppState>().user?['perfil'] == 'Consulta' ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('Salvar configurações'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Todos os dados são mantidos somente neste dispositivo. Faça backup periódico e guarde o arquivo em local seguro.',
              ),
            ],
          );
        },
      );
}
