import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';

class AppState extends ChangeNotifier {
  AppState(this.database) {
    _loadTheme();
  }

  final AppDatabase database;
  Map<String, Object?>? user;
  bool darkMode = false;

  String _newSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _hash(String value, String salt) =>
      sha256.convert(utf8.encode('$salt:$value')).toString();

  Future<bool> hasUsers() async =>
      (await database.query('usuarios', limit: 1)).isNotEmpty;

  Future<void> register({
    required String name,
    required String username,
    required String password,
    required String recoveryKey,
    required String role,
  }) async {
    if (name.trim().isEmpty || username.trim().isEmpty) {
      throw ArgumentError('Informe nome e usuário.');
    }
    if (password.length < 6) {
      throw ArgumentError('A senha precisa ter pelo menos 6 caracteres.');
    }
    if (recoveryKey.trim().length < 6) {
      throw ArgumentError('A chave de recuperação precisa ter 6 caracteres.');
    }
    final passwordSalt = _newSalt();
    final recoverySalt = _newSalt();
    await database.insert('usuarios', {
      'nome': name.trim(),
      'usuario': username.trim().toLowerCase(),
      'senha_hash': _hash(password, passwordSalt),
      'senha_salt': passwordSalt,
      'chave_recuperacao_hash': _hash(recoveryKey.trim(), recoverySalt),
      'recuperacao_salt': recoverySalt,
      'perfil': role,
      'criado_em': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> login(String username, String password) async {
    final rows = await database.query(
      'usuarios',
      where: 'usuario = ?',
      whereArgs: [username.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.first['senha_hash'] !=
            _hash(password, rows.first['senha_salt'] as String)) {
      return false;
    }
    user = rows.first;
    notifyListeners();
    return true;
  }

  Future<void> recoverPassword({
    required String username,
    required String recoveryKey,
    required String newPassword,
  }) async {
    if (newPassword.length < 6) {
      throw ArgumentError('A nova senha precisa ter pelo menos 6 caracteres.');
    }
    final rows = await database.query(
      'usuarios',
      where: 'usuario = ?',
      whereArgs: [username.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.first['chave_recuperacao_hash'] !=
            _hash(recoveryKey.trim(), rows.first['recuperacao_salt'] as String)) {
      throw StateError('Usuário ou chave de recuperação incorretos.');
    }
    final salt = _newSalt();
    await database.update('usuarios', {
      'senha_hash': _hash(newPassword, salt),
      'senha_salt': salt,
    }, rows.first['id'] as int);
  }

  Future<void> logout() async {
    user = null;
    notifyListeners();
  }

  Future<void> _loadTheme() async {
    final rows = await database.query(
      'configuracoes',
      where: 'chave = ?',
      whereArgs: ['tema_escuro'],
      limit: 1,
    );
    darkMode = rows.isNotEmpty && rows.first['valor'] == '1';
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    await database.database.update(
      'configuracoes',
      {'valor': value ? '1' : '0'},
      where: 'chave = ?',
      whereArgs: ['tema_escuro'],
    );
    notifyListeners();
  }
}
