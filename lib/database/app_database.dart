import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  Database? _database;

  Database get database {
    final db = _database;
    if (db == null) {
      throw StateError('O banco de dados ainda não foi inicializado.');
    }
    return db;
  }

  Future<void> open() async {
    if (_database != null) return;
    final databasePath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(databasePath, 'controle_financeiro_igreja.db'),
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
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

  Future<double> sum(String table, String column, {String? where}) async {
    final result = await database.rawQuery(
      'SELECT COALESCE(SUM($column), 0) AS total FROM $table${where == null ? '' : ' WHERE $where'}',
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
