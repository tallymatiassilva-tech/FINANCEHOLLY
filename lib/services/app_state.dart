import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../database/app_database.dart';
import 'audit_service.dart';

const _passwordHashIterations = 120000;
const _passwordHashPrefix = 'pbkdf2-sha256-120000:';

String _derivePasswordHash(Map<String, String> parameters) {
  final password = utf8.encode(parameters['password']!);
  final salt = utf8.encode(parameters['salt']!);
  final block = [...salt, 0, 0, 0, 1];
  final hmac = Hmac(sha256, password);
  var u = hmac.convert(block).bytes;
  final result = List<int>.from(u);
  for (var iteration = 1; iteration < _passwordHashIterations; iteration++) {
    u = hmac.convert(u).bytes;
    for (var index = 0; index < result.length; index++) {
      result[index] ^= u[index];
    }
  }
  return '$_passwordHashPrefix${base64Encode(result)}';
}

class AppState extends ChangeNotifier {
  AppState(this.database) {
    auditService = AuditService(database);
    _loadTheme();
  }

  final AppDatabase database;
  late final AuditService auditService;
  final LocalAuthentication _localAuth = LocalAuthentication();

  Map<String, Object?>? user;
  bool darkMode = false;

  int _failedLoginAttempts = 0;
  DateTime? _lockoutUntil;

  bool get isLockedOut =>
      _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!);

  void _registerFailedLoginAttempt() {
    _failedLoginAttempts++;
    if (_failedLoginAttempts >= 5) {
      _lockoutUntil = DateTime.now().add(const Duration(seconds: 30));
    }
  }

  Future<bool> authenticateBiometric({
    required String reason,
    required String operation,
    String? details,
  }) async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck && !isSupported) {
        await auditService.logAction(
          user: user,
          authType: 'Sessão de Usuário (Sem Biometria no Aparelho)',
          operation: operation,
          details: details,
        );
        return true;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );

      if (authenticated) {
        await auditService.logAction(
          user: user,
          authType: 'Biometria (Digital/Facial/Windows Hello)',
          operation: operation,
          details: details,
        );
        return true;
      } else {
        await auditService.logAction(
          user: user,
          authType: 'Cancelamento / Falha Biométrica',
          operation: 'Acesso Negado: $operation',
          details: details,
        );
        return false;
      }
    } catch (e) {
      await auditService.logAction(
        user: user,
        authType: 'Erro Biometria',
        operation: 'Erro: $operation',
        details: e.toString(),
      );
      return false;
    }
  }

  String _newSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<String> _hash(String value, String salt) => compute(
        _derivePasswordHash,
        {'password': value, 'salt': salt},
      );

  Future<bool> _verifyHash(String value, String salt, String storedHash) async {
    if (storedHash.startsWith(_passwordHashPrefix)) {
      return await _hash(value, salt) == storedHash;
    }
    final legacyHash = sha256.convert(utf8.encode('$salt:$value')).toString();
    return legacyHash == storedHash;
  }

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
    final passwordHash = await _hash(password, passwordSalt);
    final recoveryHash = await _hash(recoveryKey.trim(), recoverySalt);
    await database.insert('usuarios', {
      'nome': name.trim(),
      'usuario': username.trim().toLowerCase(),
      'senha_hash': passwordHash,
      'senha_salt': passwordSalt,
      'chave_recuperacao_hash': recoveryHash,
      'recuperacao_salt': recoverySalt,
      'perfil': role,
      'criado_em': DateTime.now().toIso8601String(),
    });
    await auditService.logAction(
      user: user,
      authType: 'Sistema',
      operation: 'Novo Usuário Cadastrado',
      details: 'Usuário: ${username.trim().toLowerCase()}, Perfil: $role',
    );
  }

  Future<bool> login(String username, String password) async {
    if (isLockedOut) {
      final secondsLeft = _lockoutUntil!.difference(DateTime.now()).inSeconds;
      throw StateError(
        'Muitas tentativas incorretas. Tente novamente em $secondsLeft segundo(s).',
      );
    }

    final rows = await database.query(
      'usuarios',
      where: 'usuario = ?',
      whereArgs: [username.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) {
      _registerFailedLoginAttempt();
      await auditService.logAction(
        user: null,
        authType: 'Senha Incorreta',
        operation: 'Falha de Login (Usuário não encontrado: $username)',
      );
      return false;
    }
    final account = rows.first;
    final storedHash = account['senha_hash'] as String;
    final salt = account['senha_salt'] as String;
    if (!await _verifyHash(password, salt, storedHash)) {
      _registerFailedLoginAttempt();
      await auditService.logAction(
        user: account,
        authType: 'Senha Incorreta',
        operation: 'Falha de Login (Senha errada)',
      );
      return false;
    }
    if (!storedHash.startsWith(_passwordHashPrefix)) {
      final upgradedSalt = _newSalt();
      final upgradedHash = await _hash(password, upgradedSalt);
      await database.update('usuarios', {
        'senha_hash': upgradedHash,
        'senha_salt': upgradedSalt,
      }, account['id'] as int);
      account['senha_hash'] = upgradedHash;
      account['senha_salt'] = upgradedSalt;
    }

    _failedLoginAttempts = 0;
    _lockoutUntil = null;
    user = account;

    await auditService.logAction(
      user: user,
      authType: 'Senha',
      operation: 'Login Realizado',
    );
    notifyListeners();
    return true;
  }

  Future<bool> loginWithBiometrics(String? preferredUsername) async {
    final username = preferredUsername?.trim().toLowerCase() ?? '';
    final rows = username.isNotEmpty
        ? await database.query(
            'usuarios',
            where: 'usuario = ?',
            whereArgs: [username],
            limit: 1,
          )
        : await database.query('usuarios', limit: 1);

    if (rows.isEmpty) return false;
    user = rows.first;

    await auditService.logAction(
      user: user,
      authType: 'Biometria (Digital/Facial/Windows Hello)',
      operation: 'Login Realizado por Biometria',
    );
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
    if (rows.isEmpty) {
      throw StateError('Usuário ou chave de recuperação incorretos.');
    }
    final account = rows.first;
    final recoveryHash = account['chave_recuperacao_hash'] as String;
    final recoverySalt = account['recuperacao_salt'] as String;
    if (!await _verifyHash(recoveryKey.trim(), recoverySalt, recoveryHash)) {
      throw StateError('Usuário ou chave de recuperação incorretos.');
    }
    final passwordSalt = _newSalt();
    final passwordHash = await _hash(newPassword, passwordSalt);
    final updates = <String, Object?>{
      'senha_hash': passwordHash,
      'senha_salt': passwordSalt,
    };
    if (!recoveryHash.startsWith(_passwordHashPrefix)) {
      final upgradedRecoverySalt = _newSalt();
      updates['chave_recuperacao_hash'] =
          await _hash(recoveryKey.trim(), upgradedRecoverySalt);
      updates['recuperacao_salt'] = upgradedRecoverySalt;
    }
    await database.update('usuarios', {
      ...updates,
    }, account['id'] as int);

    await auditService.logAction(
      user: account,
      authType: 'Chave de Recuperação',
      operation: 'Senha Redefinida',
    );
  }

  Future<void> logout() async {
    await auditService.logAction(
      user: user,
      authType: 'Sessão',
      operation: 'Logout Realizado',
    );
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) notifyListeners();
    });
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    await database.database.insert(
      'configuracoes',
      {'chave': 'tema_escuro', 'valor': value ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }
}
