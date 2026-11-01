import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class AppDatabase {
  static const _keyStorageName = 'controle_financeiro_sqlcipher_key_v1';
  static const _sumColumns = <String, Set<String>>{
    'entradas': {'valor'},
    'despesas': {'valor'},
    'vendas_cantina': {'valor_total'},
    'compras_cantina': {'valor_compra'},
  };
  static const _sumFilters = <String, Set<String>>{
    'despesas': {'status'},
  };

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Database? _database;
  String? _encryptionKey;

  Database get database {
    final db = _database;
    if (db == null) {
      throw StateError('O banco de dados ainda não foi inicializado.');
    }
    return db;
  }

  /// Índices de leitura. Aplicados na criação e na migração para a versão 4.
  static Future<void> _createIndexes(Database db) async {
    const statements = [
      'CREATE INDEX IF NOT EXISTS idx_entradas_data ON entradas(data)',
      'CREATE INDEX IF NOT EXISTS idx_despesas_data ON despesas(data)',
      'CREATE INDEX IF NOT EXISTS idx_despesas_status ON despesas(status)',
      'CREATE INDEX IF NOT EXISTS idx_despesas_vencimento ON despesas(vencimento)',
      'CREATE INDEX IF NOT EXISTS idx_vendas_data ON vendas_cantina(data)',
      'CREATE INDEX IF NOT EXISTS idx_vendas_produto ON vendas_cantina(produto_id)',
      'CREATE INDEX IF NOT EXISTS idx_compras_data ON compras_cantina(data)',
      'CREATE INDEX IF NOT EXISTS idx_mov_data ON movimentacao_estoque(data)',
      'CREATE INDEX IF NOT EXISTS idx_mov_produto ON movimentacao_estoque(produto_id)',
      'CREATE INDEX IF NOT EXISTS idx_estoque_produto ON estoque(produto)',
      'CREATE INDEX IF NOT EXISTS idx_auditoria_data ON auditoria_logs(data_hora)',
      'CREATE INDEX IF NOT EXISTS idx_fluxocaixa_data ON fluxocaixa(data)',
    ];
    for (final sql in statements) {
      await db.execute(sql);
    }
  }

  Future<void> open() async {
    if (_database != null) return;
    final databasePath = await getDatabasesPath();
    final filePath = p.join(databasePath, 'controle_financeiro_igreja.db');
    await _restoreInterruptedMigration(filePath);
    final databaseFile = File(filePath);
    final databaseExists = await databaseFile.exists();
    final isPlaintext = databaseExists && await _isPlaintextDatabase(filePath);
    var key = await _secureStorage.read(key: _keyStorageName);
    if (key == null) {
      if (databaseExists && !isPlaintext) {
        throw StateError(
          'A chave segura do banco não está disponível. '
          'O banco criptografado não foi alterado.',
        );
      }
      key = _newEncryptionKey();
      await _secureStorage.write(key: _keyStorageName, value: key);
    }
    _encryptionKey = key;
    if (isPlaintext) await _encryptPlaintextDatabase(filePath, key);
    _database = await openDatabase(
      filePath,
      password: key,
      version: 4,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE despesas ADD COLUMN vencimento TEXT');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS auditoria_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              usuario_id INTEGER,
              usuario_nome TEXT,
              tipo_autenticacao TEXT NOT NULL,
              data_hora TEXT NOT NULL,
              operacao TEXT NOT NULL,
              detalhes TEXT,
              dispositivo TEXT,
              ip_endereco TEXT
            )
          ''');
        }
        if (oldVersion < 4) {
          await _createIndexes(db);
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE usuarios (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            usuario TEXT NOT NULL UNIQUE,
            senha_hash TEXT NOT NULL,
            senha_salt TEXT NOT NULL,
            chave_recuperacao_hash TEXT NOT NULL,
            recuperacao_salt TEXT NOT NULL,
            perfil TEXT NOT NULL CHECK (perfil IN ('Administrador', 'Tesoureiro', 'Consulta')),
            criado_em TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE categorias (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            tipo TEXT NOT NULL CHECK (tipo IN ('entrada', 'despesa')),
            UNIQUE(nome, tipo)
          )
        ''');
        await db.execute('''
          CREATE TABLE fornecedores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL UNIQUE,
            telefone TEXT,
            observacao TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE entradas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            data TEXT NOT NULL,
            tipo TEXT NOT NULL,
            categoria_id INTEGER REFERENCES categorias(id) ON DELETE SET NULL,
            valor REAL NOT NULL CHECK (valor >= 0),
            forma_pagamento TEXT NOT NULL,
            descricao TEXT,
            responsavel TEXT,
            usuario_id INTEGER REFERENCES usuarios(id) ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE despesas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            data TEXT NOT NULL,
            vencimento TEXT,
            categoria TEXT NOT NULL,
            categoria_id INTEGER REFERENCES categorias(id) ON DELETE SET NULL,
            descricao TEXT NOT NULL,
            fornecedor_id INTEGER REFERENCES fornecedores(id) ON DELETE SET NULL,
            fornecedor TEXT,
            valor REAL NOT NULL CHECK (valor >= 0),
            status TEXT NOT NULL CHECK (status IN ('Pago', 'Pendente')),
            usuario_id INTEGER REFERENCES usuarios(id) ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE fluxocaixa (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            data TEXT NOT NULL UNIQUE,
            entradas REAL NOT NULL DEFAULT 0,
            saidas REAL NOT NULL DEFAULT 0,
            saldo_diario REAL NOT NULL DEFAULT 0,
            saldo_acumulado REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE estoque (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            codigo TEXT UNIQUE,
            produto TEXT NOT NULL UNIQUE,
            categoria TEXT NOT NULL,
            quantidade REAL NOT NULL DEFAULT 0,
            quantidade_minima REAL NOT NULL DEFAULT 0,
            valor_compra REAL NOT NULL DEFAULT 0,
            valor_venda REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE compras_cantina (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            data TEXT NOT NULL,
            produto_id INTEGER REFERENCES estoque(id) ON DELETE SET NULL,
            produto TEXT NOT NULL,
            fornecedor_id INTEGER REFERENCES fornecedores(id) ON DELETE SET NULL,
            fornecedor TEXT,
            quantidade REAL NOT NULL CHECK (quantidade > 0),
            valor_compra REAL NOT NULL CHECK (valor_compra >= 0)
          )
        ''');
        await db.execute('''
          CREATE TABLE vendas_cantina (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            data TEXT NOT NULL,
            produto_id INTEGER REFERENCES estoque(id) ON DELETE SET NULL,
            produto TEXT NOT NULL,
            quantidade REAL NOT NULL CHECK (quantidade > 0),
            valor_unitario REAL NOT NULL CHECK (valor_unitario >= 0),
            valor_total REAL NOT NULL CHECK (valor_total >= 0)
          )
        ''');
        await db.execute('''
          CREATE TABLE movimentacao_estoque (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            data TEXT NOT NULL,
            produto_id INTEGER NOT NULL REFERENCES estoque(id) ON DELETE CASCADE,
            tipo TEXT NOT NULL CHECK (tipo IN ('Entrada', 'Saída', 'Ajuste', 'Venda')),
            quantidade REAL NOT NULL,
            observacao TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE configuracoes (
            chave TEXT PRIMARY KEY,
            valor TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE auditoria_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            usuario_id INTEGER,
            usuario_nome TEXT,
            tipo_autenticacao TEXT NOT NULL,
            data_hora TEXT NOT NULL,
            operacao TEXT NOT NULL,
            detalhes TEXT,
            dispositivo TEXT,
            ip_endereco TEXT
          )
        ''');

        await _createIndexes(db);

        await db.insert('configuracoes', {'chave': 'tema_escuro', 'valor': '0'});
        for (final name in [
          'Dízimos',
          'Ofertas',
          'Doações',
          'Campanhas',
          'Eventos',
          'Missões',
          'Outros',
        ]) {
          await db.insert('categorias', {'nome': name, 'tipo': 'entrada'});
        }
        for (final name in [
          'Água',
          'Energia',
          'Internet',
          'Limpeza',
          'Manutenção',
          'Salários',
          'Eventos',
          'Missões',
          'Outros',
        ]) {
          await db.insert('categorias', {'nome': name, 'tipo': 'despesa'});
        }
      },
    );
    final oldDatabase = File('$filePath.legacy');
    if (await oldDatabase.exists() && !await _isPlaintextDatabase(filePath)) {
      await oldDatabase.delete();
    }
  }

  String _newEncryptionKey() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<bool> _isPlaintextDatabase(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return false;
    final handle = await file.open();
    try {
      final signature = await handle.read(16);
      return String.fromCharCodes(signature) == 'SQLite format 3\u0000';
    } finally {
      await handle.close();
    }
  }

  Future<void> _restoreInterruptedMigration(String filePath) async {
    final databaseFile = File(filePath);
    final legacyFile = File('$filePath.legacy');
    if (!await databaseFile.exists() && await legacyFile.exists()) {
      await legacyFile.rename(filePath);
    }
  }

  Future<void> _encryptPlaintextDatabase(String filePath, String key) async {
    final stagingFile = File('$filePath.encrypted');
    final legacyFile = File('$filePath.legacy');
    if (await legacyFile.exists()) {
      throw StateError(
        'A migração anterior do banco não foi concluída; '
        'o arquivo legado foi preservado.',
      );
    }
    if (await stagingFile.exists()) await stagingFile.delete();

    final source = await openDatabase(filePath);
    var attached = false;
    try {
      await source.rawQuery('PRAGMA wal_checkpoint(FULL)');
      await source.execute(
        'ATTACH DATABASE ? AS encrypted KEY ?',
        [stagingFile.path, key],
      );
      attached = true;
      await source.rawQuery("SELECT sqlcipher_export('encrypted')");
      await source.execute('DETACH DATABASE encrypted');
      attached = false;
    } finally {
      try {
        if (attached) await source.execute('DETACH DATABASE encrypted');
      } finally {
        await source.close();
      }
    }

    final verification = await openDatabase(
      stagingFile.path,
      password: key,
      readOnly: true,
    );
    try {
      final tables = await verification.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      if (!tables.any((row) => row['name'] == 'usuarios')) {
        throw StateError(
          'A cópia criptografada do banco não passou na validação.',
        );
      }
    } finally {
      await verification.close();
    }

    await File(filePath).rename(legacyFile.path);
    try {
      await stagingFile.rename(filePath);
    } catch (error, stackTrace) {
      if (!await File(filePath).exists() && await legacyFile.exists()) {
        await legacyFile.rename(filePath);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Database> openDatabaseForBackupValidation(String filePath) async {
    final isPlaintext = await _isPlaintextDatabase(filePath);
    final key = _encryptionKey;
    if (!isPlaintext && key == null) {
      throw StateError(
        'A chave do banco não está disponível para validar o backup.',
      );
    }
    return openDatabase(
      filePath,
      password: isPlaintext ? null : key,
      readOnly: true,
    );
  }

  Future<String> prepareBackupForRestore(String sourcePath) async {
    final key = _encryptionKey;
    if (key == null) {
      throw StateError('O banco precisa estar aberto para restaurar um backup.');
    }
    final directory = await getTemporaryDirectory();
    final stagingPath = p.join(
      directory.path,
      'restore_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    await File(sourcePath).copy(stagingPath);
    try {
      if (await _isPlaintextDatabase(stagingPath)) {
        await _encryptPlaintextDatabase(stagingPath, key);
        final legacyFile = File('$stagingPath.legacy');
        if (await legacyFile.exists()) await legacyFile.delete();
      }
      final validation = await openDatabase(
        stagingPath,
        password: key,
        readOnly: true,
      );
      try {
        final tables = await validation.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );
        if (!tables.any((row) => row['name'] == 'usuarios')) {
          throw FormatException(
            'O arquivo não contém um banco criptografado válido para este aparelho.',
          );
        }
      } finally {
        await validation.close();
      }
      return stagingPath;
    } catch (error, stackTrace) {
      final stagedFile = File(stagingPath);
      if (await stagedFile.exists()) await stagedFile.delete();
      final legacyFile = File('$stagingPath.legacy');
      if (await legacyFile.exists()) await legacyFile.delete();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> exportUnencryptedBackup(String outputPath) async {
    final key = _encryptionKey;
    if (key == null) {
      throw StateError('O banco precisa estar aberto para exportar um backup.');
    }
    final output = File(outputPath);
    if (await output.exists()) await output.delete();
    try {
      final source = database;
      var attached = false;
      try {
        await source.execute(
          'ATTACH DATABASE ? AS backup KEY ?',
          [outputPath, ''],
        );
        attached = true;
        await source.rawQuery("SELECT sqlcipher_export('backup')");
        await source.execute('DETACH DATABASE backup');
        attached = false;
      } finally {
        if (attached) await source.execute('DETACH DATABASE backup');
      }

      final verification = await openDatabase(outputPath, readOnly: true);
      try {
        final tables = await verification.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );
        if (!tables.any((row) => row['name'] == 'usuarios')) {
          throw StateError('O arquivo de backup não passou na validação.');
        }
      } finally {
        await verification.close();
      }
    } catch (error, stackTrace) {
      if (await output.exists()) await output.delete();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<List<Map<String, Object?>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) =>
      database.query(
        table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
      );

  Future<int> insert(String table, Map<String, Object?> values) =>
      database.insert(table, values);

  Future<int> update(
    String table,
    Map<String, Object?> values,
    int id,
  ) =>
      database.update(table, values, where: 'id = ?', whereArgs: [id]);

  Future<int> delete(String table, int id) =>
      database.delete(table, where: 'id = ?', whereArgs: [id]);

  Future<double> sum(
    String table,
    String column, {
    String? whereColumn,
    Object? whereValue,
  }) async {
    if (_sumColumns[table]?.contains(column) != true) {
      throw ArgumentError.value(column, 'column', 'Coluna fora do escopo de soma.');
    }
    if (whereColumn != null &&
        !(_sumFilters[table]?.contains(whereColumn) ?? false)) {
      throw ArgumentError.value(
        whereColumn,
        'whereColumn',
        'Coluna fora do escopo de filtro.',
      );
    }
    if ((whereColumn == null) != (whereValue == null)) {
      throw ArgumentError('Informe a coluna e o valor do filtro juntos.');
    }
    final where = whereColumn == null ? '' : ' WHERE $whereColumn = ?';
    final result = await database.rawQuery(
      'SELECT COALESCE(SUM($column), 0) AS total FROM $table$where',
      whereColumn == null ? null : [whereValue],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}