import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../database/app_database.dart';

/// Monta o workbook fora da thread de UI. Recebe apenas dados enviáveis.
List<int> _encodeWorkbook(Map<String, Object?> payload) {
  final sheets = (payload['sheets']! as List).cast<Map<String, Object?>>();
  final book = Excel.createExcel();

  for (final spec in sheets) {
    final name = spec['name']! as String;
    final table = spec['table']! as String;
    final rows = (spec['rows']! as List).cast<Map<String, Object?>>();
    final headers = FileService._headers[table]!;
    final columns = FileService._tableColumns[table]!;

    final sheet = book[name];
    sheet.appendRow(headers.take(columns.length).map(TextCellValue.new).toList());

    for (final row in rows) {
      sheet.appendRow(
        columns.map((column) {
          final value = row[column];
          if (value is num) return DoubleCellValue(value.toDouble());
          return TextCellValue(value?.toString() ?? '');
        }).toList(),
      );
    }

    _applyTotalFormulas(sheet, table, rows.length);
  }

  book.delete('Sheet1');
  return book.encode()!;
}

void _applyTotalFormulas(Sheet sheet, String table, int rowCount) {
  final lastDataRow = rowCount + 1 < 2 ? 2 : rowCount + 1;
  final formula = switch (table) {
    'entradas' => 'SUM(C2:C$lastDataRow)',
    'despesas' => 'SUM(F2:F$lastDataRow)',
    'vendas_cantina' => 'SUM(E2:E$lastDataRow)',
    'compras_cantina' => 'SUM(E2:E$lastDataRow)',
    'estoque' => 'COUNTA(B2:B$lastDataRow)',
    _ => null,
  };

  if (formula != null) {
    final column = switch (table) {
      'entradas' => 'C',
      'despesas' => 'F',
      'vendas_cantina' => 'E',
      'compras_cantina' => 'E',
      _ => 'B',
    };
    sheet.cell(CellIndex.indexByString('A${rowCount + 2}')).value =
        TextCellValue('Total');
    sheet.cell(CellIndex.indexByString('$column${rowCount + 2}')).value =
        FormulaCellValue(formula);
  }

  if (table == 'despesas') {
    sheet.cell(CellIndex.indexByString('E${rowCount + 4}')).value =
        FormulaCellValue('SUMIF(G:G,"Pago",F:F)');
    sheet.cell(CellIndex.indexByString('E${rowCount + 5}')).value =
        FormulaCellValue('SUMIF(G:G,"Pendente",F:F)');
    sheet.cell(CellIndex.indexByString('D${rowCount + 4}')).value =
        TextCellValue('Despesas pagas');
    sheet.cell(CellIndex.indexByString('D${rowCount + 5}')).value =
        TextCellValue('Despesas pendentes');
  }

  if (table == 'vendas_cantina') {
    for (var row = 2; row <= rowCount + 1; row++) {
      sheet.cell(CellIndex.indexByString('E$row')).value =
          FormulaCellValue('C$row*D$row');
    }
  }

  if (table == 'fluxocaixa') {
    for (var row = 2; row <= rowCount + 1; row++) {
      sheet.cell(CellIndex.indexByString('D$row')).value =
          FormulaCellValue('B$row-C$row');
      sheet.cell(CellIndex.indexByString('E$row')).value =
          FormulaCellValue(row == 2 ? 'B$row-C$row' : 'E${row - 1}+B$row-C$row');
    }
  }

  if (table == 'estoque') {
    for (var row = 2; row <= rowCount + 1; row++) {
      sheet.cell(CellIndex.indexByString('H$row')).value =
          FormulaCellValue('IF(D$row<E$row,"REPOR ESTOQUE","OK")');
      sheet.cell(CellIndex.indexByString('I$row')).value =
          FormulaCellValue('IF(D$row=0,"ESGOTADO","DISPONÍVEL")');
    }
  }
}

class FileService {
  FileService(this.database);

  final AppDatabase database;

  static const _headers = <String, List<String>>{
    'entradas': [
      'Data',
      'Tipo',
      'Valor',
      'Forma de pagamento',
      'Descrição',
      'Responsável',
    ],
    'despesas': [
      'Data',
      'Vencimento',
      'Categoria',
      'Descrição',
      'Fornecedor',
      'Valor',
      'Status',
    ],
    'fluxocaixa': [
      'Data',
      'Entradas',
      'Saídas',
      'Saldo diário',
      'Saldo acumulado',
    ],
    'vendas_cantina': [
      'Data',
      'Produto',
      'Quantidade',
      'Valor unitário',
      'Valor total',
    ],
    'estoque': [
      'Código',
      'Produto',
      'Categoria',
      'Quantidade',
      'Quantidade mínima',
      'Valor de compra',
      'Valor de venda',
      'Alerta estoque',
      'Status estoque',
    ],
    'compras_cantina': [
      'Data',
      'Produto',
      'Fornecedor',
      'Quantidade',
      'Valor compra',
    ],
  };

  static const _tableColumns = <String, List<String>>{
    'entradas': [
      'data',
      'tipo',
      'valor',
      'forma_pagamento',
      'descricao',
      'responsavel',
    ],
    'despesas': [
      'data',
      'vencimento',
      'categoria',
      'descricao',
      'fornecedor',
      'valor',
      'status',
    ],
    'fluxocaixa': [
      'data',
      'entradas',
      'saidas',
      'saldo_diario',
      'saldo_acumulado',
    ],
    'vendas_cantina': [
      'data',
      'produto',
      'quantidade',
      'valor_unitario',
      'valor_total',
    ],
    'estoque': [
      'codigo',
      'produto',
      'categoria',
      'quantidade',
      'quantidade_minima',
      'valor_compra',
      'valor_venda',
    ],
    'compras_cantina': [
      'data',
      'produto',
      'fornecedor',
      'quantidade',
      'valor_compra',
    ],
  };

  Future<void> exportExcel(
    String table,
    String filename, {
    String? startDate,
    String? endDate,
    String? category,
  }) async {
    final rows = await _loadRows(
      table,
      startDate: startDate,
      endDate: endDate,
      category: category,
    );

    final bytes = await compute(_encodeWorkbook, <String, Object?>{
      'sheets': <Map<String, Object?>>[
        {'name': 'Dados', 'table': table, 'rows': rows},
      ],
    });

    await _shareBytes(bytes, filename);
  }

  Future<void> exportConsolidated({
    String? startDate,
    String? endDate,
    String? category,
  }) async {
    const tables = [
      'entradas',
      'despesas',
      'vendas_cantina',
      'compras_cantina',
      'estoque',
    ];

    final results = await Future.wait(
      tables.map(
        (table) => _loadRows(
          table,
          startDate: startDate,
          endDate: endDate,
          category: category,
        ),
      ),
    );

    final sheets = <Map<String, Object?>>[
      for (var i = 0; i < tables.length; i++)
        {'name': tables[i], 'table': tables[i], 'rows': results[i]},
    ];

    final bytes = await compute(_encodeWorkbook, <String, Object?>{
      'sheets': sheets,
    });

    await _shareBytes(bytes, 'RelatorioConsolidado.xlsx');
  }

  Future<void> exportCanteen({
    String? startDate,
    String? endDate,
    String? category,
  }) async {
    const tables = ['vendas_cantina', 'compras_cantina'];
    const names = ['Vendas', 'Compras'];

    final results = await Future.wait(
      tables.map(
        (table) => _loadRows(
          table,
          startDate: startDate,
          endDate: endDate,
          category: category,
        ),
      ),
    );

    final sheets = <Map<String, Object?>>[
      for (var i = 0; i < tables.length; i++)
        {'name': names[i], 'table': tables[i], 'rows': results[i]},
    ];

    final bytes = await compute(_encodeWorkbook, <String, Object?>{
      'sheets': sheets,
    });

    await _shareBytes(bytes, 'Cantina.xlsx');
  }

  Future<void> _shareBytes(List<int> bytes, String filename) async {
    final temp = await getTemporaryDirectory();
    final output = File(p.join(temp.path, filename));
    await output.writeAsBytes(bytes, flush: true);
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(output.path)]));
    } finally {
      // O app de destino lê o arquivo de forma assíncrona; apagar só depois.
      Future.delayed(const Duration(seconds: 30), () async {
        if (await output.exists()) {
          await output.delete().catchError((_) => output);
        }
      });
    }
  }

  Future<List<Map<String, Object?>>> _loadRows(
    String table, {
    String? startDate,
    String? endDate,
    String? category,
  }) async {
    if (!_tableColumns.containsKey(table)) {
      throw ArgumentError.value(
        table,
        'table',
        'Tabela não disponível para exportação.',
      );
    }

    final columns = _tableColumns[table]!;
    final hasDate = columns.contains('data');

    final clauses = <String>[];
    final args = <Object?>[];

    if (hasDate && startDate != null && startDate.isNotEmpty) {
      clauses.add('data >= ?');
      args.add(startDate);
    }
    if (hasDate && endDate != null && endDate.isNotEmpty) {
      clauses.add('data <= ?');
      args.add(endDate);
    }

    final term = category?.trim() ?? '';
    if (term.isNotEmpty) {
      final searchable = columns.where((c) => c != 'data').toList();
      if (searchable.isNotEmpty) {
        clauses.add(
          '(${searchable.map((c) => 'CAST($c AS TEXT) LIKE ?').join(' OR ')})',
        );
        args.addAll(List<String>.filled(searchable.length, '%$term%'));
      }
    }

    final where = clauses.isEmpty ? null : clauses.join(' AND ');
    final whereArgs = args.isEmpty ? null : args;

    if (table == 'fluxocaixa') {
      final income = await database.query(
        'entradas',
        where: where,
        whereArgs: whereArgs,
      );
      final expenses = await database.query(
        'despesas',
        where: where == null ? "status = 'Pago'" : "status = 'Pago' AND $where",
        whereArgs: whereArgs,
      );
      final sales = await database.query(
        'vendas_cantina',
        where: where,
        whereArgs: whereArgs,
      );
      final purchases = await database.query(
        'compras_cantina',
        where: where,
        whereArgs: whereArgs,
      );

      final totals = <String, List<double>>{};
      for (final row in income) {
        final key = row['data']! as String;
        totals.putIfAbsent(key, () => [0, 0])[0] +=
            (row['valor'] as num).toDouble();
      }
      for (final row in expenses) {
        final key = row['data']! as String;
        totals.putIfAbsent(key, () => [0, 0])[1] +=
            (row['valor'] as num).toDouble();
      }
      for (final row in sales) {
        final key = row['data']! as String;
        totals.putIfAbsent(key, () => [0, 0])[0] +=
            (row['valor_total'] as num).toDouble();
      }
      for (final row in purchases) {
        final key = row['data']! as String;
        totals.putIfAbsent(key, () => [0, 0])[1] +=
            (row['valor_compra'] as num).toDouble();
      }

      final dates = totals.keys.toList()..sort();
      var accumulated = 0.0;
      return dates.map((date) {
        final daily = totals[date]!;
        accumulated += daily[0] - daily[1];
        return <String, Object?>{
          'data': date,
          'entradas': daily[0],
          'saidas': daily[1],
          'saldo_diario': daily[0] - daily[1],
          'saldo_acumulado': accumulated,
        };
      }).toList();
    }

    return database.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: hasDate ? 'data ASC' : 'id ASC',
    );
  }

  Future<void> printPdf(
    String table,
    String title, {
    String? startDate,
    String? endDate,
    String? category,
  }) async {
    final rows = await _loadRows(
      table,
      startDate: startDate,
      endDate: endDate,
      category: category,
    );
    final columns = _tableColumns[table]!;
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
          ),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: _headers[table]!.take(columns.length).toList(),
            data: rows
                .map(
                  (row) => columns
                      .map((column) => row[column]?.toString() ?? '')
                      .toList(),
                )
                .toList(),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await document.save(),
      filename: '${_safeName(title)}.pdf',
    );
  }

  Future<void> printSummaryPdf({
    required String title,
    String? startDate,
    String? endDate,
  }) async {
    final args = <Object?>[];

    String filterFor({String? status}) {
      final parts = <String>[];
      if (status != null) parts.add("status = '$status'");
      if (startDate != null) {
        parts.add('data >= ?');
        args.add(startDate);
      }
      if (endDate != null) {
        parts.add('data <= ?');
        args.add(endDate);
      }
      return parts.isEmpty ? '' : ' WHERE ${parts.join(' AND ')}';
    }

    final entradasFilter = filterFor();
    final pagasFilter = filterFor(status: 'Pago');
    final pendentesFilter = filterFor(status: 'Pendente');
    final vendasFilter = filterFor();
    final comprasFilter = filterFor();

    final row = (await database.database.rawQuery('''
      SELECT
        (SELECT COALESCE(SUM(valor),0) FROM entradas$entradasFilter)     AS entradas,
        (SELECT COALESCE(SUM(valor),0) FROM despesas$pagasFilter)        AS pagas,
        (SELECT COALESCE(SUM(valor),0) FROM despesas$pendentesFilter)    AS pendentes,
        (SELECT COALESCE(SUM(valor_total),0) FROM vendas_cantina$vendasFilter)   AS vendas,
        (SELECT COALESCE(SUM(valor_compra),0) FROM compras_cantina$comprasFilter) AS compras
    ''', args)).first;

    final incomes = (row['entradas'] as num).toDouble();
    final paidExpenses = (row['pagas'] as num).toDouble();
    final pendingExpenses = (row['pendentes'] as num).toDouble();
    final sales = (row['vendas'] as num).toDouble();
    final purchases = (row['compras'] as num).toDouble();

    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
            ),
            if (startDate != null || endDate != null)
              pw.Text(
                'Período: ${startDate ?? 'início'} a ${endDate ?? 'hoje'}',
              ),
            pw.SizedBox(height: 16),
            pw.Table.fromTextArray(
              headers: const ['Indicador', 'Valor'],
              data: [
                ['Entradas', incomes.toStringAsFixed(2)],
                ['Despesas pagas', paidExpenses.toStringAsFixed(2)],
                ['Despesas pendentes', pendingExpenses.toStringAsFixed(2)],
                [
                  'Saldo disponível',
                  (incomes - paidExpenses + sales - purchases).toStringAsFixed(2),
                ],
                ['Vendas da cantina', sales.toStringAsFixed(2)],
                ['Compras da cantina', purchases.toStringAsFixed(2)],
                [
                  'Resultado da cantina',
                  (sales - purchases).toStringAsFixed(2),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    await Printing.sharePdf(
      bytes: await document.save(),
      filename: '${_safeName(title)}.pdf',
    );
  }

  Future<void> printCanteenPdf({
    String? startDate,
    String? endDate,
    String? category,
  }) async {
    final results = await Future.wait([
      _loadRows(
        'vendas_cantina',
        startDate: startDate,
        endDate: endDate,
        category: category,
      ),
      _loadRows(
        'compras_cantina',
        startDate: startDate,
        endDate: endDate,
        category: category,
      ),
    ]);
    final sales = results[0];
    final purchases = results[1];

    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text(
            'Relatório da Cantina',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
          ),
          if (startDate != null || endDate != null)
            pw.Text('Período: ${startDate ?? 'início'} a ${endDate ?? 'hoje'}'),
          pw.SizedBox(height: 12),
          pw.Text(
            'Vendas',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Table.fromTextArray(
            headers: _headers['vendas_cantina'],
            data: sales
                .map(
                  (row) => _tableColumns['vendas_cantina']!
                      .map((column) => row[column]?.toString() ?? '')
                      .toList(),
                )
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Compras',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Table.fromTextArray(
            headers: _headers['compras_cantina'],
            data: purchases
                .map(
                  (row) => _tableColumns['compras_cantina']!
                      .map((column) => row[column]?.toString() ?? '')
                      .toList(),
                )
                .toList(),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'relatorio_cantina.pdf',
    );
  }

  String _safeName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  Future<String> importExcel({String? targetTable}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (picked == null) return 'Importação cancelada.';
    final bytes = picked.files.single.bytes;
    if (bytes == null)
      throw StateError('Não foi possível ler o arquivo selecionado.');

    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) throw FormatException('A planilha não possui abas.');

    final candidates = [
      'entradas',
      'despesas',
      'vendas_cantina',
      'compras_cantina',
      'estoque',
    ];

    String? table;
    Sheet? selectedSheet;
    List<String> header = [];

    for (final entry in book.tables.entries) {
      if (entry.value.rows.isEmpty) continue;
      final candidateHeader = entry.value.rows.first
          .map((cell) => cell?.value?.toString().trim().toLowerCase() ?? '')
          .toList();
      for (final candidate in candidates) {
        if (targetTable != null && candidate != targetTable) continue;
        final expected = _headers[candidate]!
            .take(_tableColumns[candidate]!.length)
            .map((item) => item.toLowerCase())
            .toSet();
        if (expected.every(candidateHeader.contains)) {
          table = candidate;
          selectedSheet = entry.value;
          header = candidateHeader;
          break;
        }
      }
      if (table != null) break;
    }

    if (table == null) {
      throw FormatException(
        targetTable == null
            ? 'Colunas obrigatórias não reconhecidas. Use uma planilha exportada pelo app.'
            : 'Não foi encontrada uma aba com as colunas obrigatórias para "$targetTable".',
      );
    }

    final sheet = selectedSheet!;
    final columns = _tableColumns[table]!;
    final required = _headers[table]!
        .take(columns.length)
        .map((item) => item.toLowerCase())
        .toList();
    final requiredValues = switch (table) {
      'entradas' => {'data', 'tipo', 'valor', 'forma_pagamento'},
      'despesas' => {'data', 'categoria', 'descricao', 'valor', 'status'},
      'vendas_cantina' => {'data', 'produto', 'quantidade', 'valor_unitario'},
      'compras_cantina' => {'data', 'produto', 'quantidade', 'valor_compra'},
      _ => {
        'codigo',
        'produto',
        'categoria',
        'quantidade',
        'quantidade_minima',
        'valor_compra',
        'valor_venda',
      },
    };

    final indexes = required.map(header.indexOf).toList();
    final problems = <String>[];
    final additions = <Map<String, Object?>>[];
    final seen = <String>{};

    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.every(
        (cell) => cell?.value == null || cell!.value.toString().trim().isEmpty,
      ))
        continue;

      final firstCell = row.isEmpty
          ? ''
          : row.first?.value?.toString().trim().toLowerCase() ?? '';
      final dateColumn = required.indexOf('data');
      final dateCell = dateColumn < 0 || dateColumn >= row.length
          ? ''
          : row[dateColumn]?.value?.toString().trim() ?? '';
      final containsFormula = row.any((cell) => cell?.value is FormulaCellValue);

      if (firstCell == 'total' || (containsFormula && dateCell.isEmpty)) continue;

      final values = <String, Object?>{};
      try {
        for (var col = 0; col < indexes.length; col++) {
          final raw = indexes[col] < row.length
              ? row[indexes[col]]?.value?.toString().trim() ?? ''
              : '';
          final name = columns[col];

          if (raw.isEmpty && requiredValues.contains(name)) {
            throw FormatException('Coluna "${_headers[table]![col]}" vazia');
          }
          if (name == 'data' &&
              (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ||
                  DateTime.tryParse(raw) == null)) {
            throw FormatException('Data inválida (use AAAA-MM-DD)');
          }

          final numeric = name == 'valor' ||
              name == 'quantidade' ||
              name == 'valor_unitario' ||
              name == 'valor_total' ||
              name == 'valor_compra' ||
              name == 'quantidade_minima' ||
              name == 'valor_venda';

          if (raw.isEmpty) {
            values[name] = null;
          } else if (numeric) {
            final number = _parseNumber(raw);
            if (number < 0 ||
                (name == 'quantidade' &&
                    (table == 'vendas_cantina' ||
                        table == 'compras_cantina') &&
                    number == 0)) {
              throw FormatException(
                'Valor fora do intervalo permitido na coluna "${_headers[table]![col]}"',
              );
            }
            values[name] = number;
          } else {
            values[name] = raw;
          }
        }

        if (table == 'despesas' &&
            values['status'] != 'Pago' &&
            values['status'] != 'Pendente') {
          throw FormatException('Status deve ser Pago ou Pendente');
        }

        if (table == 'vendas_cantina') {
          values['valor_total'] = (values['quantidade']! as double) *
              (values['valor_unitario']! as double);
        }

        final key =
            '${values['data'] ?? ''}|${values['produto'] ?? values['descricao'] ?? values['codigo'] ?? ''}';
        if (!seen.add(key))
          throw FormatException('Registro duplicado dentro do arquivo');

        additions.add(values);
      } catch (error) {
        problems.add('Linha ${i + 1}: $error');
      }
    }

    if (problems.isNotEmpty) {
      throw FormatException(
        'Planilha validada com erros:\n${problems.take(20).join('\n')}',
      );
    }
    if (additions.isEmpty) return 'Nenhuma linha de dados encontrada.';

    await database.database.transaction((txn) async {
      for (final item in additions) {
        if (table == 'entradas') {
          final duplicates = await txn.query(
            'entradas',
            where:
                "data = ? AND tipo = ? AND valor = ? AND COALESCE(descricao, '') = ?",
            whereArgs: [
              item['data'],
              item['tipo'],
              item['valor'],
              item['descricao'] ?? '',
            ],
            limit: 1,
          );
          if (duplicates.isNotEmpty)
            throw StateError('Entrada duplicada para ${item['data']}.');
        }

        if (table == 'despesas') {
          final duplicates = await txn.query(
            'despesas',
            where: 'data = ? AND categoria = ? AND descricao = ? AND valor = ?',
            whereArgs: [
              item['data'],
              item['categoria'],
              item['descricao'],
              item['valor'],
            ],
            limit: 1,
          );
          if (duplicates.isNotEmpty)
            throw StateError('Despesa duplicada para ${item['data']}.');
        }

        if (table == 'vendas_cantina') {
          final duplicates = await txn.query(
            'vendas_cantina',
            where:
                'data = ? AND produto = ? AND quantidade = ? AND valor_unitario = ?',
            whereArgs: [
              item['data'],
              item['produto'],
              item['quantidade'],
              item['valor_unitario'],
            ],
            limit: 1,
          );
          if (duplicates.isNotEmpty)
            throw StateError(
              'Venda duplicada para ${item['produto']} em ${item['data']}.',
            );
        }

        if (table == 'compras_cantina') {
          final duplicates = await txn.query(
            'compras_cantina',
            where:
                'data = ? AND produto = ? AND quantidade = ? AND valor_compra = ?',
            whereArgs: [
              item['data'],
              item['produto'],
              item['quantidade'],
              item['valor_compra'],
            ],
            limit: 1,
          );
          if (duplicates.isNotEmpty) {
            throw StateError(
              'Compra duplicada para ${item['produto']} em ${item['data']}.',
            );
          }
        }

        if (table == 'entradas' || table == 'despesas') {
          final name = item[table == 'entradas' ? 'tipo' : 'categoria'];
          final type = table == 'entradas' ? 'entrada' : 'despesa';
          final categories = await txn.query(
            'categorias',
            where: 'nome = ? AND tipo = ?',
            whereArgs: [name, type],
            limit: 1,
          );
          if (categories.isNotEmpty)
            item['categoria_id'] = categories.first['id'];

          if (table == 'despesas') {
            final supplier = item['fornecedor']?.toString().trim() ?? '';
            if (supplier.isNotEmpty) {
              final matches = await txn.query(
                'fornecedores',
                where: 'nome = ?',
                whereArgs: [supplier],
                limit: 1,
              );
              item['fornecedor_id'] = matches.isEmpty
                  ? await txn.insert('fornecedores', {'nome': supplier})
                  : matches.first['id'];
            }
          }
        }

        if (table == 'vendas_cantina') {
          final match = await txn.query(
            'estoque',
            where: 'produto = ?',
            whereArgs: [item['produto']],
            limit: 1,
          );
          if (match.isEmpty)
            throw StateError(
              'Produto "${item['produto']}" não encontrado no estoque.',
            );
          final stock = match.first;
          final amount = item['quantidade']! as double;
          final current = (stock['quantidade'] as num).toDouble();
          if (amount > current)
            throw StateError('Estoque insuficiente para "${item['produto']}".');
          item['produto_id'] = stock['id'];
          await txn.update(
            'estoque',
            {'quantidade': current - amount},
            where: 'id = ?',
            whereArgs: [stock['id']],
          );
          await txn.insert('movimentacao_estoque', {
            'data': item['data'],
            'produto_id': stock['id'],
            'tipo': 'Venda',
            'quantidade': -amount,
            'observacao': 'Importação de planilha',
          });
        }

        if (table == 'compras_cantina') {
          final matches = await txn.query(
            'estoque',
            where: 'produto = ?',
            whereArgs: [item['produto']],
            limit: 1,
          );
          if (matches.isEmpty)
            throw StateError(
              'Produto "${item['produto']}" não encontrado no estoque.',
            );
          final stock = matches.first;
          final amount = item['quantidade']! as double;
          item['produto_id'] = stock['id'];
          item['fornecedor_id'] = await _findOrCreateSupplier(
            txn,
            item['fornecedor']?.toString().trim() ?? '',
          );
          await txn.update(
            'estoque',
            {'quantidade': (stock['quantidade'] as num).toDouble() + amount},
            where: 'id = ?',
            whereArgs: [stock['id']],
          );
          await txn.insert('movimentacao_estoque', {
            'data': item['data'],
            'produto_id': stock['id'],
            'tipo': 'Entrada',
            'quantidade': amount,
            'observacao': 'Importação de compra da cantina',
          });
        }

        if (table == 'estoque') {
          final duplicate = await txn.query(
            'estoque',
            where: 'produto = ? OR (codigo IS NOT NULL AND codigo = ?)',
            whereArgs: [item['produto'], item['codigo']],
            limit: 1,
          );
          if (duplicate.isNotEmpty)
            throw StateError('Produto/código duplicado: ${item['produto']}.');
        }

        await txn.insert(table!, item);
      }
    });

    return 'Importados ${additions.length} registros para $table.';
  }

  Future<int?> _findOrCreateSupplier(Transaction txn, String name) async {
    if (name.isEmpty) return null;
    final rows = await txn.query(
      'fornecedores',
      where: 'nome = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;
    return txn.insert('fornecedores', {'nome': name});
  }

  double _parseNumber(String value) {
    var normalized = value.trim().replaceAll('R\$', '').replaceAll(' ', '');
    if (normalized.contains(',') && normalized.contains('.')) {
      if (normalized.lastIndexOf(',') > normalized.lastIndexOf('.')) {
        normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
      } else {
        normalized = normalized.replaceAll(',', '');
      }
    } else {
      normalized = normalized.replaceAll(',', '.');
    }
    final result = double.tryParse(normalized);
    if (result == null) throw FormatException('Número inválido: $value');
    return result;
  }

  Future<void> shareBackup({bool email = false}) async {
    await database.database.rawQuery('PRAGMA wal_checkpoint(FULL)');
    final directory = await getTemporaryDirectory();
    final stamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    final backup = File(
      p.join(directory.path, 'backup_controle_financeiro_$stamp.db'),
    );
    await database.exportUnencryptedBackup(backup.path);

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(backup.path)],
          title: email ? 'Enviar backup por e-mail' : 'Compartilhar backup',
          subject: email ? 'Backup do Controle Financeiro Igreja' : null,
          text: email ? 'Segue o backup do Controle Financeiro Igreja.' : null,
        ),
      );
    } finally {
      // O app de destino lê o arquivo de forma assíncrona; apagar só depois.
      Future.delayed(const Duration(seconds: 30), () async {
        if (await backup.exists()) {
          await backup.delete().catchError((_) => backup);
        }
      });
    }
  }

  Future<void> restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite'],
      withData: false,
    );
    if (picked == null) return;
    final path = picked.files.single.path;
    if (path == null)
      throw StateError('Não foi possível acessar o backup selecionado.');

    final validation = await database.openDatabaseForBackupValidation(path);
    try {
      final tables = await validation.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final available = tables
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();
      const requiredTables = {
        'usuarios',
        'entradas',
        'despesas',
        'estoque',
        'configuracoes',
      };
      if (!available.containsAll(requiredTables)) {
        throw FormatException(
          'O arquivo não contém as tabelas de backup deste aplicativo.',
        );
      }
    } finally {
      await validation.close();
    }

    final restorePath = await database.prepareBackupForRestore(path);
    try {
      await database.database.rawQuery('PRAGMA wal_checkpoint(FULL)');
      final target = File(
        p.join(await getDatabasesPath(), 'controle_financeiro_igreja.db'),
      );
      final recoveryCopy = File(
        p.join(
          (await getTemporaryDirectory()).path,
          'backup_anterior_${DateTime.now().microsecondsSinceEpoch}.db',
        ),
      );
      await target.copy(recoveryCopy.path);
      await database.close();
      try {
        await File(restorePath).copy(target.path);
        await database.open();
      } catch (error, stackTrace) {
        await recoveryCopy.copy(target.path);
        await database.open();
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        if (await recoveryCopy.exists()) await recoveryCopy.delete();
      }
    } finally {
      final restoreFile = File(restorePath);
      if (await restoreFile.exists()) await restoreFile.delete();
      final legacyFile = File('$restorePath.legacy');
      if (await legacyFile.exists()) await legacyFile.delete();
    }
  }
}