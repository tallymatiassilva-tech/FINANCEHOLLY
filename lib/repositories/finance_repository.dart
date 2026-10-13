import '../database/app_database.dart';
import '../models/finance_record.dart';

class FinanceRepository {
  FinanceRepository(this.database);

  final AppDatabase database;

  static const _editableTables = {
    'entradas',
    'despesas',
    'estoque',
    'vendas_cantina',
    'compras_cantina',
  };

  Future<List<FinanceRecord>> list(String table, {String? orderBy}) async {
    final rows = await database.query(table, orderBy: orderBy ?? 'id DESC');
    return rows.map(FinanceRecord.fromMap).toList();
  }

  Future<int> create(String table, Map<String, Object?> values) {
    _ensureEditable(table);
    return database.insert(table, values);
  }

  Future<int> update(String table, int id, Map<String, Object?> values) {
    _ensureEditable(table);
    return database.update(table, values, id);
  }

  Future<int> delete(String table, int id) {
    _ensureEditable(table);
    return database.delete(table, id);
  }

  void _ensureEditable(String table) {
    if (!_editableTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Tabela fora do escopo de edição.');
    }
  }
}
