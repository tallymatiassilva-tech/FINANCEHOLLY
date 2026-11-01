import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../database/app_database.dart';
import '../repositories/finance_repository.dart';
import '../services/app_state.dart';
import '../services/file_service.dart';
import '../services/receipt_ocr_service.dart';
import '../widgets/dialog_controller_owner.dart';
import '../widgets/empty_state.dart';

enum DataKind { income, expense, cashflow, canteen, stock, reports }

class _Field {
  const _Field(this.name, this.label, {this.numeric = false, this.options});

  final String name;
  final String label;
  final bool numeric;
  final List<String>? options;
}

class DataScreen extends StatefulWidget {
  const DataScreen({
    required this.title,
    required this.table,
    required this.kind,
    super.key,
  });

  final String title;
  final String table;
  final DataKind kind;

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  late Future<List<Map<String, Object?>>> _rows;
  final _search = TextEditingController();
  final _stockSearch = TextEditingController();
  String? _stockCategory;
  String? _startDate;
  String? _endDate;

  List<_Field> get _fields => switch (widget.kind) {
    DataKind.income => const [
      _Field('data', 'Data (AAAA-MM-DD)'),
      _Field(
        'tipo',
        'Categoria',
        options: [
          'Dízimos',
          'Ofertas',
          'Doações',
          'Campanhas',
          'Eventos',
          'Missões',
          'Outros',
        ],
      ),
      _Field('valor', 'Valor', numeric: true),
      _Field(
        'forma_pagamento',
        'Forma de pagamento',
        options: ['Dinheiro', 'Pix', 'Cartão', 'Transferência', 'Outro'],
      ),
      _Field('descricao', 'Descrição'),
      _Field('responsavel', 'Responsável'),
    ],
    DataKind.expense => const [
      _Field('data', 'Data (AAAA-MM-DD)'),
      _Field('vencimento', 'Vencimento (AAAA-MM-DD)'),
      _Field(
        'categoria',
        'Categoria',
        options: [
          'Água',
          'Energia',
          'Internet',
          'Limpeza',
          'Manutenção',
          'Salários',
          'Eventos',
          'Missões',
          'Outros',
        ],
      ),
      _Field('descricao', 'Descrição'),
      _Field('fornecedor', 'Fornecedor'),
      _Field('valor', 'Valor', numeric: true),
      _Field('status', 'Status', options: ['Pago', 'Pendente']),
    ],
    DataKind.canteen => const [
      _Field('data', 'Data (AAAA-MM-DD)'),
      _Field('produto', 'Produto'),
      _Field('quantidade', 'Quantidade', numeric: true),
      _Field('valor_unitario', 'Valor unitário', numeric: true),
    ],
    DataKind.stock => const [
      _Field('codigo', 'Código'),
      _Field('produto', 'Produto'),
      _Field('categoria', 'Categoria'),
      _Field('quantidade', 'Quantidade', numeric: true),
      _Field('quantidade_minima', 'Quantidade mínima', numeric: true),
      _Field('valor_compra', 'Valor de compra', numeric: true),
      _Field('valor_venda', 'Valor de venda', numeric: true),
    ],
    _ => const [],
  };

  String? _validateField(_Field field, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Campo obrigatório';
    if (field.name == 'data') {
      final parsed = DateTime.tryParse(value);
      if (parsed == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        return 'Use o formato AAAA-MM-DD';
      }
    }
    if (field.numeric) {
      final normalized = value.contains(',') && value.contains('.')
          ? value.replaceAll('.', '').replaceAll(',', '.')
          : value.replaceAll(',', '.');
      final number = double.tryParse(normalized);
      if (number == null ||
          number < 0 ||
          (field.name == 'quantidade' &&
              widget.kind == DataKind.canteen &&
              number == 0)) {
        return 'Informe um valor numérico válido';
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    _stockSearch.dispose();
    super.dispose();
  }

  void _refresh() {
    _rows = _loadRows();
  }

  Future<List<Map<String, Object?>>> _loadRows() async {
    final db = context.read<AppState>().database;
    if (widget.kind == DataKind.cashflow) {
      return _cashflow(db);
    }
    if (widget.kind == DataKind.canteen) {
      return db.query('vendas_cantina', orderBy: 'data DESC, id DESC');
    }
    final records = await FinanceRepository(db).list(widget.table);
    return records.map((record) => record.values).toList();
  }

  Future<List<Map<String, Object?>>> _cashflow(AppDatabase db) async {
    final income = await db.query('entradas', orderBy: 'data DESC');
    final expenses = await db.query(
      'despesas',
      where: "status = 'Pago'",
      orderBy: 'data DESC',
    );
    final sales = await db.query('vendas_cantina', orderBy: 'data DESC');
    final purchases = await db.query('compras_cantina', orderBy: 'data DESC');
    final totals = <String, List<double>>{};
    for (final row in income) {
      final date = row['data'] as String;
      totals.putIfAbsent(date, () => [0, 0])[0] += (row['valor'] as num)
          .toDouble();
    }
    for (final row in expenses) {
      final date = row['data'] as String;
      totals.putIfAbsent(date, () => [0, 0])[1] += (row['valor'] as num)
          .toDouble();
    }
    for (final row in sales) {
      final date = row['data'] as String;
      totals.putIfAbsent(date, () => [0, 0])[0] += (row['valor_total'] as num)
          .toDouble();
    }
    for (final row in purchases) {
      final date = row['data'] as String;
      totals.putIfAbsent(date, () => [0, 0])[1] += (row['valor_compra'] as num)
          .toDouble();
    }
    final dates = totals.keys.toList()..sort();
    var balance = 0.0;
    final rows = dates.map((date) {
      final daily = totals[date]!;
      balance += daily[0] - daily[1];
      return {
        'data': date,
        'entradas': daily[0],
        'saidas': daily[1],
        'saldo_diario': daily[0] - daily[1],
        'saldo_acumulado': balance,
      };
    }).toList();
    await db.database.transaction((txn) async {
      await txn.delete('fluxocaixa');
      for (final row in rows) {
        await txn.insert('fluxocaixa', row);
      }
    });
    return rows.reversed.toList();
  }

  bool get _canWrite => context.read<AppState>().user?['perfil'] != 'Consulta';

  Future<void> _scanReceipt({
    required ReceiptOcrService service,
    required String scanType,
    required Map<String, TextEditingController> controllers,
    required StateSetter setDialogState,
    required BuildContext dialogContext,
  }) async {
    try {
      final scanResult = switch (scanType) {
        'camera' => await service.pickFromCamera(),
        'pdf' => await service.pickFromPdf(),
        _ => await service.pickFromGallery(),
      };
      if (scanResult == null || !dialogContext.mounted || !mounted) return;
      final fields = scanResult.toFields(
        isExpense: widget.kind == DataKind.expense,
      );
      for (final entry in fields.entries) {
        final controller = controllers[entry.key];
        if (controller != null) controller.text = entry.value;
      }
      setDialogState(() {});
      final typeLabel = scanResult.entryType == 'entrada' ? 'Entrada' : 'Despesa';
      _message(
        'Documento ($typeLabel) lido com sucesso via OCR! Revise os campos antes de salvar.',
      );
    } catch (error) {
      if (mounted) {
        final message = error is FormatException
            ? error.message
            : error.toString().replaceFirst('Exception: ', '');
        _message('Não foi possível ler o documento: $message');
      }
    }
  }

  Future<void> _openForm({Map<String, Object?>? initial}) async {
    if (!_canWrite) {
      _message(
        'Seu perfil Consulta permite apenas visualizar. Entre com uma conta '
        'Administrador ou Tesoureiro para cadastrar.',
      );
      return;
    }
    final controllers = <String, TextEditingController>{};
    for (final field in _fields) {
      final value =
          initial?[field.name]?.toString() ??
          (field.name == 'data'
              ? DateFormat('yyyy-MM-dd').format(DateTime.now())
              : '');
      controllers[field.name] = TextEditingController(text: value);
    }
    final formKey = GlobalKey<FormState>();
    await showDialogWithControllers<void>(
      context: context,
      controllers: controllers.values,
      builder: (dialogContext) {
        final receiptService = ReceiptOcrService();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                initial == null
                    ? 'Cadastrar ${widget.title.toLowerCase()}'
                    : 'Editar ${widget.title.toLowerCase()}',
              ),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Leitura Automática OCR (Foto / Imagem / PDF)',
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton.filledTonal(
                                    tooltip: 'Tirar Foto (Câmera)',
                                    onPressed: () => _scanReceipt(
                                      service: receiptService,
                                      scanType: 'camera',
                                      controllers: controllers,
                                      setDialogState: setDialogState,
                                      dialogContext: dialogContext,
                                    ),
                                    icon: const Icon(Icons.camera_alt),
                                  ),
                                  IconButton.filledTonal(
                                    tooltip: 'Imagem JPG / PNG',
                                    onPressed: () => _scanReceipt(
                                      service: receiptService,
                                      scanType: 'gallery',
                                      controllers: controllers,
                                      setDialogState: setDialogState,
                                      dialogContext: dialogContext,
                                    ),
                                    icon: const Icon(Icons.photo_library),
                                  ),
                                  IconButton.filledTonal(
                                    tooltip: 'PDF Digitalizado',
                                    onPressed: () => _scanReceipt(
                                      service: receiptService,
                                      scanType: 'pdf',
                                      controllers: controllers,
                                      setDialogState: setDialogState,
                                      dialogContext: dialogContext,
                                    ),
                                    icon: const Icon(Icons.picture_as_pdf),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._fields.map((field) {
                          final controller = controllers[field.name]!;
                          if (field.options != null) {
                            if (controller.text.isEmpty)
                              controller.text = field.options!.first;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DropdownButtonFormField<String>(
                                initialValue:
                                    field.options!.contains(controller.text)
                                    ? controller.text
                                    : field.options!.first,
                                decoration: InputDecoration(
                                  labelText: field.label,
                                ),
                                items: field.options!
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(value),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) =>
                                    controller.text = value ?? '',
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextFormField(
                              controller: controller,
                              decoration: InputDecoration(
                                labelText: field.label,
                              ),
                              keyboardType: field.numeric
                                  ? const TextInputType.numberWithOptions(
                                      decimal: true,
                                    )
                                  : TextInputType.text,
                              validator: (value) =>
                                  _validateField(field, value),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final values = <String, Object?>{};
                      for (final field in _fields) {
                        final value = controllers[field.name]!.text.trim();
                        if (field.numeric) {
                          values[field.name] = double.parse(
                            value.replaceAll(',', '.'),
                          );
                        } else {
                          values[field.name] = value;
                        }
                      }
                      if (widget.kind == DataKind.canteen) {
                        await _saveSale(values, initial: initial);
                      } else if (widget.kind == DataKind.stock) {
                        if (initial == null) {
                          await FinanceRepository(
                            context.read<AppState>().database,
                          ).create('estoque', values);
                        } else {
                          await FinanceRepository(
                            context.read<AppState>().database,
                          ).update('estoque', initial['id'] as int, values);
                        }
                      } else {
                        final state = context.read<AppState>();
                        final db = state.database.database;
                        await db.transaction((txn) async {
                          final categoryName =
                              values[widget.kind == DataKind.income
                                  ? 'tipo'
                                  : 'categoria'];
                          final categoryType = widget.kind == DataKind.income
                              ? 'entrada'
                              : 'despesa';
                          final categories = await txn.query(
                            'categorias',
                            where: 'nome = ? AND tipo = ?',
                            whereArgs: [categoryName, categoryType],
                            limit: 1,
                          );
                          if (categories.isNotEmpty)
                            values['categoria_id'] = categories.first['id'];
                          values['usuario_id'] = state.user?['id'];
                          final supplierName =
                              values['fornecedor']?.toString().trim() ?? '';
                          if (widget.kind == DataKind.expense &&
                              supplierName.isNotEmpty) {
                            final suppliers = await txn.query(
                              'fornecedores',
                              where: 'nome = ?',
                              whereArgs: [supplierName],
                              limit: 1,
                            );
                            final supplierId = suppliers.isEmpty
                                ? await txn.insert('fornecedores', {
                                    'nome': supplierName,
                                  })
                                : suppliers.first['id'] as int;
                            values['fornecedor_id'] = supplierId;
                          }
                          if (initial == null) {
                            await txn.insert(widget.table, values);
                          } else {
                            await txn.update(
                              widget.table,
                              values,
                              where: 'id = ?',
                              whereArgs: [initial['id']],
                            );
                          }
                        });
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (mounted) setState(_refresh);
                    } catch (error) {
                      if (mounted) _message('Não foi possível salvar: $error');
                    }
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openStockForm({Map<String, Object?>? initial}) async {
    if (!_canWrite) {
      _message('Seu perfil tem acesso somente para consulta.');
      return;
    }
    final controllers = <String, TextEditingController>{};
    for (final field in const [
      _Field('codigo', 'Código'),
      _Field('produto', 'Produto'),
      _Field('categoria', 'Categoria'),
      _Field('quantidade', 'Quantidade', numeric: true),
      _Field('quantidade_minima', 'Quantidade mínima', numeric: true),
      _Field('valor_compra', 'Valor de compra', numeric: true),
      _Field('valor_venda', 'Valor de venda', numeric: true),
    ]) {
      final value = initial?[field.name]?.toString() ?? '';
      controllers[field.name] = TextEditingController(text: value);
    }
    final formKey = GlobalKey<FormState>();
    await showDialogWithControllers<void>(
      context: context,
      controllers: controllers.values,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          initial == null
              ? 'Adicionar item ao estoque'
              : 'Editar item do estoque',
        ),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in const [
                    _Field('codigo', 'Código'),
                    _Field('produto', 'Produto'),
                    _Field('categoria', 'Categoria'),
                    _Field('quantidade', 'Quantidade', numeric: true),
                    _Field(
                      'quantidade_minima',
                      'Quantidade mínima',
                      numeric: true,
                    ),
                    _Field('valor_compra', 'Valor de compra', numeric: true),
                    _Field('valor_venda', 'Valor de venda', numeric: true),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: controllers[field.name]!,
                        decoration: InputDecoration(labelText: field.label),
                        keyboardType: field.numeric
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        validator: (value) => _validateField(field, value),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final values = <String, Object?>{};
                for (final field in const [
                  _Field('codigo', 'Código'),
                  _Field('produto', 'Produto'),
                  _Field('categoria', 'Categoria'),
                  _Field('quantidade', 'Quantidade', numeric: true),
                  _Field(
                    'quantidade_minima',
                    'Quantidade mínima',
                    numeric: true,
                  ),
                  _Field('valor_compra', 'Valor de compra', numeric: true),
                  _Field('valor_venda', 'Valor de venda', numeric: true),
                ]) {
                  final raw = controllers[field.name]!.text.trim();
                  values[field.name] = field.numeric
                      ? double.parse(raw.replaceAll(',', '.'))
                      : raw;
                }
                final db = context.read<AppState>().database;
                if (initial == null) {
                  await FinanceRepository(db).create('estoque', values);
                } else {
                  await FinanceRepository(
                    db,
                  ).update('estoque', initial['id'] as int, values);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) setState(_refresh);
              } catch (error) {
                if (mounted)
                  _message('Não foi possível salvar o estoque: $error');
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSale(
    Map<String, Object?> values, {
    Map<String, Object?>? initial,
  }) async {
    final db = context.read<AppState>().database.database;
    await db.transaction((txn) async {
      final productName = values['produto']?.toString().trim() ?? '';
      final quantity = (values['quantidade'] as num).toDouble();
      final unitPrice = (values['valor_unitario'] as num).toDouble();
      final saleId = initial?['id'] as int?;
      final previousSaleRows = saleId == null
          ? const <Map<String, Object?>>[]
          : await txn.query(
              'vendas_cantina',
              where: 'id = ?',
              whereArgs: [saleId],
              limit: 1,
            );
      final previousSale = previousSaleRows.isNotEmpty
          ? previousSaleRows.first
          : null;
      final previousProductName = previousSale?['produto']?.toString() ?? '';
      final previousQuantity =
          (previousSale?['quantidade'] as num?)?.toDouble() ?? 0;

      final products = await txn.query(
        'estoque',
        where: 'produto = ?',
        whereArgs: [productName],
        limit: 1,
      );
      if (products.isEmpty) {
        throw StateError(
          'Cadastre o produto no estoque antes de registrar uma venda.',
        );
      }
      final product = products.first;
      final available = (product['quantidade'] as num).toDouble();

      if (saleId == null) {
        if (quantity > available) {
          throw StateError(
            'Estoque insuficiente. Disponível: ${available.toStringAsFixed(2)}.',
          );
        }
        await txn.insert('vendas_cantina', {
          'data': values['data'],
          'produto_id': product['id'],
          'produto': productName,
          'quantidade': quantity,
          'valor_unitario': unitPrice,
          'valor_total': quantity * unitPrice,
        });
        await txn.update(
          'estoque',
          {'quantidade': available - quantity},
          where: 'id = ?',
          whereArgs: [product['id']],
        );
        await txn.insert('movimentacao_estoque', {
          'data': values['data'],
          'produto_id': product['id'],
          'tipo': 'Venda',
          'quantidade': -quantity,
          'observacao': 'Venda na cantina',
        });
        return;
      }

      final previousProductRows = previousProductName.isEmpty
          ? const <Map<String, Object?>>[]
          : await txn.query(
              'estoque',
              where: 'produto = ?',
              whereArgs: [previousProductName],
              limit: 1,
            );
      final previousProduct = previousProductRows.isNotEmpty
          ? previousProductRows.first
          : null;

      if (previousProduct != null && previousProduct['id'] == product['id']) {
        final adjustedStock = available + previousQuantity - quantity;
        if (adjustedStock < 0) {
          throw StateError(
            'Estoque insuficiente. Disponível: ${(available + previousQuantity).toStringAsFixed(2)}.',
          );
        }
        await txn.update(
          'estoque',
          {'quantidade': adjustedStock},
          where: 'id = ?',
          whereArgs: [product['id']],
        );
      } else {
        if (previousProduct != null) {
          final previousStock = (previousProduct['quantidade'] as num)
              .toDouble();
          await txn.update(
            'estoque',
            {'quantidade': previousStock + previousQuantity},
            where: 'id = ?',
            whereArgs: [previousProduct['id']],
          );
        }
        if (quantity > available) {
          throw StateError(
            'Estoque insuficiente. Disponível: ${available.toStringAsFixed(2)}.',
          );
        }
        await txn.update(
          'estoque',
          {'quantidade': available - quantity},
          where: 'id = ?',
          whereArgs: [product['id']],
        );
      }

      await txn.update(
        'vendas_cantina',
        {
          'data': values['data'],
          'produto_id': product['id'],
          'produto': productName,
          'quantidade': quantity,
          'valor_unitario': unitPrice,
          'valor_total': quantity * unitPrice,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );
      await txn.insert('movimentacao_estoque', {
        'data': values['data'],
        'produto_id': product['id'],
        'tipo': 'Venda',
        'quantidade': -quantity,
        'observacao': 'Atualização de venda na cantina',
      });
    });
  }

  Future<void> _stockMovement(
    Map<String, Object?> product,
    String action,
  ) async {
    final controller = TextEditingController();
    final db = context.read<AppState>().database.database;
    var amountText = '';
    final ok = await showDialogWithControllers<bool>(
      context: context,
      controllers: [controller],
      builder: (dialogContext) => AlertDialog(
        title: Text('$action: ${product['produto']}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: action == 'Ajuste' ? 'Nova quantidade' : 'Quantidade',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              amountText = controller.text;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final amount = double.parse(amountText.replaceAll(',', '.'));
      if (amount <= 0 && action != 'Ajuste')
        throw ArgumentError('Informe uma quantidade maior que zero.');
      await db.transaction((txn) async {
        final current = (product['quantidade'] as num).toDouble();
        final next = switch (action) {
          'Entrada' => current + amount,
          'Saída' => current - amount,
          _ => amount,
        };
        if (next < 0) throw StateError('A quantidade não pode ficar negativa.');
        await txn.update(
          'estoque',
          {'quantidade': next},
          where: 'id = ?',
          whereArgs: [product['id']],
        );
        await txn.insert('movimentacao_estoque', {
          'data': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'produto_id': product['id'],
          'tipo': action,
          'quantidade': action == 'Saída'
              ? -amount
              : action == 'Ajuste'
              ? next - current
              : amount,
          'observacao': 'Movimentação manual',
        });
      });
      if (mounted) setState(_refresh);
    } catch (error) {
      if (mounted) _message('Não foi possível atualizar o estoque: $error');
    }
  }

  Future<void> _deleteSale(Map<String, Object?> row) async {
    final db = context.read<AppState>().database.database;
    await db.transaction((txn) async {
      final productName = row['produto']?.toString() ?? '';
      final quantity = (row['quantidade'] as num?)?.toDouble() ?? 0;
      final productRows = await txn.query(
        'estoque',
        where: 'produto = ?',
        whereArgs: [productName],
        limit: 1,
      );
      if (productRows.isNotEmpty) {
        final productId = productRows.first['id'] as int;
        final current = (productRows.first['quantidade'] as num).toDouble();
        await txn.update(
          'estoque',
          {'quantidade': current + quantity},
          where: 'id = ?',
          whereArgs: [productId],
        );
      }
      await txn.delete(
        'vendas_cantina',
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      final productId = productRows.isNotEmpty
          ? productRows.first['id'] as int
          : row['produto_id'] as int?;
      if (productId != null) {
        await txn.insert('movimentacao_estoque', {
          'data':
              row['data'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'produto_id': productId,
          'tipo': 'Ajuste',
          'quantidade': quantity,
          'observacao': 'Exclusão de venda na cantina',
        });
      }
    });
  }

  Future<void> _delete(Map<String, Object?> row) async {
    if (!_canWrite) return;
    final database = context.read<AppState>().database;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir registro?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (widget.kind == DataKind.canteen) {
        await _deleteSale(row);
      } else {
        await FinanceRepository(
          database,
        ).delete(widget.table, row['id'] as int);
      }
      if (mounted) setState(_refresh);
    }
  }

  Future<void> _filterDates() async {
    final start = TextEditingController(text: _startDate);
    final end = TextEditingController(text: _endDate);
    await showDialogWithControllers<void>(
      context: context,
      controllers: [start, end],
      builder: (dialogContext) => AlertDialog(
        title: const Text('Filtrar período'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: start,
              decoration: const InputDecoration(
                labelText: 'Data inicial (AAAA-MM-DD)',
              ),
            ),
            TextField(
              controller: end,
              decoration: const InputDecoration(
                labelText: 'Data final (AAAA-MM-DD)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _startDate = start.text.trim().isEmpty
                    ? null
                    : start.text.trim();
                _endDate = end.text.trim().isEmpty ? null : end.text.trim();
                _refresh();
              });
              Navigator.pop(dialogContext);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Widget _buildTabSummaryHeader(List<Map<String, Object?>> rows) {
    if (widget.kind == DataKind.income) {
      final total = rows.fold<double>(
        0.0,
        (sum, row) => sum + ((row['valor'] as num?)?.toDouble() ?? 0.0),
      );
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.south_west, color: Colors.green.shade800),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aba Entradas (Apenas Receitas)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Total acumulado no período: R\$ ${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (widget.kind == DataKind.expense) {
      double totalPagas = 0;
      double totalPendentes = 0;
      for (final row in rows) {
        final valor = (row['valor'] as num?)?.toDouble() ?? 0.0;
        if (row['status'] == 'Pago') {
          totalPagas += valor;
        } else {
          totalPendentes += valor;
        }
      }
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.north_east, color: Colors.red.shade800),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aba Despesas (Apenas Gastos)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Pagas: R\$ ${totalPagas.toStringAsFixed(2)} · Pendentes: R\$ ${totalPendentes.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kind == DataKind.reports) return _buildReports();
    if (widget.kind == DataKind.cashflow) return _buildCashflow();
    if (widget.kind == DataKind.canteen) return _buildCanteen();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Pesquisar',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'Filtrar período',
                onPressed: _filterDates,
                icon: const Icon(Icons.date_range),
              ),
              IconButton(
                tooltip: _canWrite
                    ? 'Adicionar'
                    : 'Cadastro indisponível para o perfil Consulta',
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add_circle),
              ),
            ],
          ),
        ),
        if (widget.kind == DataKind.stock)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Vermelho: esgotado · Âmbar: abaixo da quantidade mínima',
            ),
          ),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: _rows,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError)
                return Center(
                  child: Text('Erro ao carregar dados: ${snapshot.error}'),
                );
              final rows = _filtered(snapshot.data ?? []);
              if (rows.isEmpty)
                return Column(
                  children: [
                    _buildTabSummaryHeader(rows),
                    const Expanded(child: EmptyState(message: 'Nenhum registro encontrado.')),
                  ],
                );
              return Column(
                children: [
                  _buildTabSummaryHeader(rows),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: rows.length,
                      itemBuilder: (context, index) => _recordCard(rows[index]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  List<Map<String, Object?>> _filtered(List<Map<String, Object?>> input) {
    final term = _search.text.trim().toLowerCase();
    return input.where((row) {
      final date = row['data']?.toString() ?? '';
      if (_startDate != null &&
          date.isNotEmpty &&
          date.compareTo(_startDate!) < 0)
        return false;
      if (_endDate != null && date.isNotEmpty && date.compareTo(_endDate!) > 0)
        return false;
      return term.isEmpty ||
          row.values.any(
            (value) => value.toString().toLowerCase().contains(term),
          );
    }).toList();
  }

  Widget _recordCard(Map<String, Object?> row) {
    final stock = widget.kind == DataKind.stock;
    final quantity = (row['quantidade'] as num?)?.toDouble() ?? 0;
    final minimum = (row['quantidade_minima'] as num?)?.toDouble() ?? 0;
    final lowStock = stock && (quantity <= 0 || quantity < minimum);
    final title =
        row['produto']?.toString() ??
        row['descricao']?.toString() ??
        row['tipo']?.toString() ??
        row['categoria']?.toString() ??
        'Registro';
    final summary = row.entries
        .where(
          (entry) =>
              entry.key != 'id' &&
              entry.value != null &&
              entry.value.toString().isNotEmpty,
        )
        .map((entry) => '${_label(entry.key)}: ${entry.value}')
        .join('  ·  ');
    return Card(
      color: lowStock
          ? (quantity <= 0
                ? Colors.red.withValues(alpha: .12)
                : Colors.amber.withValues(alpha: .15))
          : null,
      child: ListTile(
        title: Text(title),
        subtitle: Text(
          '$summary${lowStock ? (quantity <= 0 ? '  ·  ESGOTADO' : '  ·  ESTOQUE BAIXO') : ''}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'edit') _openForm(initial: row);
            if (action == 'delete') _delete(row);
            if (stock && action == 'Entrada') _stockMovement(row, 'Entrada');
            if (stock && action == 'Saída') _stockMovement(row, 'Saída');
            if (stock && action == 'Ajuste') _stockMovement(row, 'Ajuste');
          },
          itemBuilder: (context) => [
            if (_canWrite && stock) ...[
              const PopupMenuItem(
                value: 'Entrada',
                child: Text('Entrada estoque'),
              ),
              const PopupMenuItem(value: 'Saída', child: Text('Saída estoque')),
              const PopupMenuItem(
                value: 'Ajuste',
                child: Text('Ajustar estoque'),
              ),
            ],
            if (_canWrite)
              const PopupMenuItem(value: 'edit', child: Text('Editar')),
            if (_canWrite)
              const PopupMenuItem(value: 'delete', child: Text('Excluir')),
          ],
        ),
      ),
    );
  }

  String _label(String key) => switch (key) {
    'data' => 'Data',
    'vencimento' => 'Vencimento',
    'valor' => 'Valor',
    'valor_total' => 'Total',
    'valor_unitario' => 'Unitário',
    'quantidade' => 'Qtd.',
    'quantidade_minima' => 'Mínimo',
    'forma_pagamento' => 'Pagamento',
    'saldo_diario' => 'Saldo diário',
    'saldo_acumulado' => 'Saldo acumulado',
    'status' => 'Status',
    _ => key,
  };

  Widget _buildCashflow() => FutureBuilder<List<Map<String, Object?>>>(
    future: _rows,
    builder: (context, snapshot) {
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final rows = _filtered(snapshot.data!);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: ['Dia', 'Semana', 'Mês', 'Ano'].map((label) {
              return ActionChip(
                label: Text(label),
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    switch (label) {
                      case 'Dia':
                        _startDate = DateFormat('yyyy-MM-dd').format(now);
                        _endDate = _startDate;
                        break;
                      case 'Semana':
                        _startDate = DateFormat(
                          'yyyy-MM-dd',
                        ).format(now.subtract(const Duration(days: 6)));
                        _endDate = DateFormat('yyyy-MM-dd').format(now);
                        break;
                      case 'Mês':
                        _startDate = DateFormat('yyyy-MM-01').format(now);
                        _endDate = DateFormat('yyyy-MM-dd').format(now);
                        break;
                      case 'Ano':
                        _startDate = '${now.year}-01-01';
                        _endDate = DateFormat('yyyy-MM-dd').format(now);
                        break;
                    }
                  });
                },
              );
            }).toList(),
          ),
          ...rows.map((row) => _recordCard(row)),
        ],
      );
    },
  );

  Widget _buildCanteen() => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Vendas'),
            Tab(text: 'Compras'),
            Tab(text: 'Estoque'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Registrar venda',
                      onPressed: _canWrite ? () => _openForm() : null,
                      icon: const Icon(Icons.add_circle),
                    ),
                  ),
                  Expanded(child: _simpleList('vendas_cantina')),
                ],
              ),
              Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Registrar compra',
                      onPressed: _canWrite ? _addPurchase : null,
                      icon: const Icon(Icons.add_circle),
                    ),
                  ),
                  Expanded(child: _simpleList('compras_cantina')),
                ],
              ),
              Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Adicionar item ao estoque',
                      onPressed: _canWrite ? () => _openStockForm() : null,
                      icon: const Icon(Icons.add_circle),
                    ),
                  ),
                  Expanded(child: _stockList()),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _stockList() => FutureBuilder<List<Map<String, Object?>>>(
    future: context.read<AppState>().database.query(
      'estoque',
      orderBy: 'produto ASC',
    ),
    builder: (context, snapshot) {
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final allRows = snapshot.data ?? [];
      final categories =
          allRows
              .map((row) => row['categoria']?.toString().trim() ?? '')
              .where((category) => category.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final selectedCategory = categories.contains(_stockCategory)
          ? _stockCategory
          : null;
      final term = _stockSearch.text.trim().toLowerCase();
      final rows = allRows.where((row) {
        final matchesCategory =
            selectedCategory == null || row['categoria'] == selectedCategory;
        final matchesText =
            term.isEmpty ||
            ['produto', 'codigo', 'categoria'].any(
              (key) =>
                  row[key]?.toString().toLowerCase().contains(term) ?? false,
            );
        return matchesCategory && matchesText;
      }).toList();
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _stockSearch,
                    decoration: const InputDecoration(
                      labelText: 'Produto ou código',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String?>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todas'),
                      ),
                      ...categories.map(
                        (category) => DropdownMenuItem<String?>(
                          value: category,
                          child: Text(
                            category,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _stockCategory = value),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      allRows.isEmpty
                          ? 'Nenhum item em estoque.'
                          : 'Nenhum item corresponde aos filtros.',
                    ),
                  )
                : ListView(
                    children: rows.map((row) {
                      final quantity =
                          (row['quantidade'] as num?)?.toDouble() ?? 0;
                      final minimum =
                          (row['quantidade_minima'] as num?)?.toDouble() ?? 0;
                      final priceCompra =
                          (row['valor_compra'] as num?)?.toDouble() ?? 0;
                      final priceVenda =
                          (row['valor_venda'] as num?)?.toDouble() ?? 0;
                      final lowStock = quantity <= 0 || quantity < minimum;
                      return Card(
                        color: lowStock
                            ? (quantity <= 0
                                  ? Colors.red.withValues(alpha: .12)
                                  : Colors.amber.withValues(alpha: .15))
                            : null,
                        child: ListTile(
                          title: Text('${row['produto']}'),
                          subtitle: Text(
                            'Código: ${row['codigo'] ?? '-'} · Qtd: ${quantity.toStringAsFixed(2)} · Mín: ${minimum.toStringAsFixed(2)} · Compra: R\$ ${priceCompra.toStringAsFixed(2)} · Venda: R\$ ${priceVenda.toStringAsFixed(2)}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'Entrada' ||
                                  action == 'Saída' ||
                                  action == 'Ajuste') {
                                await _stockMovement(row, action);
                              }
                              if (action == 'edit')
                                _openStockForm(initial: row);
                              if (action == 'delete') await _delete(row);
                            },
                            itemBuilder: (context) => [
                              if (_canWrite)
                                const PopupMenuItem(
                                  value: 'Entrada',
                                  child: Text('Entrada manual'),
                                ),
                              if (_canWrite)
                                const PopupMenuItem(
                                  value: 'Saída',
                                  child: Text('Saída manual'),
                                ),
                              if (_canWrite)
                                const PopupMenuItem(
                                  value: 'Ajuste',
                                  child: Text('Ajustar quantidade'),
                                ),
                              if (_canWrite)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                              if (_canWrite)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Excluir'),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      );
    },
  );

  Widget _simpleList(String table) => FutureBuilder<List<Map<String, Object?>>>(
    future: context.read<AppState>().database.query(
      table,
      orderBy: 'data DESC, id DESC',
    ),
    builder: (context, snapshot) {
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      if (snapshot.data!.isEmpty)
        return const Center(child: Text('Nenhum registro.'));
      return ListView(
        children: snapshot.data!.map((row) {
          final heading = '${row['produto']} · ${row['quantidade']} un.';
          final amount = row['valor_total'] ?? row['valor_compra'] ?? 0;
          return Card(
            child: ListTile(
              title: Text(heading),
              subtitle: Text(
                '${row['data']} · Total: R\$ ${amount.toString()}',
              ),
            ),
          );
        }).toList(),
      );
    },
  );

  Future<void> _addPurchase() async {
    final db = context.read<AppState>().database.database;
    final product = TextEditingController();
    final supplier = TextEditingController();
    final quantity = TextEditingController();
    final cost = TextEditingController();
    final form = GlobalKey<FormState>();
    (String, String, String, String)? purchaseValues;
    final saved = await showDialogWithControllers<bool>(
      context: context,
      controllers: [product, supplier, quantity, cost],
      builder: (dialogContext) => AlertDialog(
        title: const Text('Compra para cantina'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in [
                (product, 'Produto'),
                (supplier, 'Fornecedor'),
                (quantity, 'Quantidade'),
                (cost, 'Valor total da compra'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    controller: item.$1,
                    decoration: InputDecoration(labelText: item.$2),
                    keyboardType:
                        item.$2 == 'Quantidade' || item.$2.startsWith('Valor')
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty)
                        return 'Obrigatório';
                      if (item.$2 == 'Quantidade' ||
                          item.$2.startsWith('Valor')) {
                        final number = double.tryParse(
                          value.replaceAll(',', '.'),
                        );
                        if (number == null ||
                            number < 0 ||
                            (item.$2 == 'Quantidade' && number == 0)) {
                          return 'Informe um número válido';
                        }
                      }
                      return null;
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                purchaseValues = (
                  product.text.trim(),
                  supplier.text.trim(),
                  quantity.text.trim(),
                  cost.text.trim(),
                );
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (saved == true) {
      try {
        final values = purchaseValues;
        if (values == null) {
          throw StateError('Os dados da compra não foram capturados.');
        }
        await db.transaction((txn) async {
          final matches = await txn.query(
            'estoque',
            where: 'produto = ?',
            whereArgs: [values.$1],
            limit: 1,
          );
          if (matches.isEmpty)
            throw StateError('Cadastre o produto no estoque antes da compra.');
          final item = matches.first;
          final amount = double.parse(values.$3.replaceAll(',', '.'));
          final costValue = double.parse(values.$4.replaceAll(',', '.'));
          final productId = item['id'] as int;
          await txn.insert('compras_cantina', {
            'data': DateFormat('yyyy-MM-dd').format(DateTime.now()),
            'produto_id': productId,
            'produto': values.$1,
            'fornecedor_id': await _findOrCreateSupplier(txn, values.$2),
            'fornecedor': values.$2,
            'quantidade': amount,
            'valor_compra': costValue,
          });
          await txn.update(
            'estoque',
            {'quantidade': (item['quantidade'] as num).toDouble() + amount},
            where: 'id = ?',
            whereArgs: [productId],
          );
          await txn.insert('movimentacao_estoque', {
            'data': DateFormat('yyyy-MM-dd').format(DateTime.now()),
            'produto_id': productId,
            'tipo': 'Entrada',
            'quantidade': amount,
            'observacao': 'Compra para cantina',
          });
        });
        if (mounted) setState(() {});
      } catch (error) {
        if (mounted) _message('Não foi possível registrar a compra: $error');
      }
    }
  }

  Future<int?> _findOrCreateSupplier(
    Transaction txn,
    String supplierName,
  ) async {
    if (supplierName.isEmpty) return null;
    final rows = await txn.query(
      'fornecedores',
      where: 'nome = ?',
      whereArgs: [supplierName],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;
    return txn.insert('fornecedores', {'nome': supplierName});
  }

  Widget _buildReports() {
    final service = FileService(context.read<AppState>().database);
    final startDate = _startDate;
    final endDate = _endDate;
    final category = _search.text;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Categoria ou texto do relatório',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              tooltip: 'Período',
              onPressed: _filterDates,
              icon: const Icon(Icons.date_range),
            ),
            IconButton(
              tooltip: 'Limpar filtros',
              onPressed: () => setState(() {
                _search.clear();
                _startDate = null;
                _endDate = null;
              }),
              icon: const Icon(Icons.filter_alt_off),
            ),
          ],
        ),
        if (startDate != null || endDate != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Período: ${startDate ?? 'início'} até ${endDate ?? 'hoje'}',
            ),
          ),
        const SizedBox(height: 12),
        Text('Exportar Excel', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final item in [
          ('Entradas.xlsx', 'entradas'),
          ('Despesas.xlsx', 'despesas'),
          ('FluxoCaixa.xlsx', 'fluxocaixa'),
          ('Cantina.xlsx', 'cantina'),
          ('Estoque.xlsx', 'estoque'),
        ])
          ListTile(
            leading: const Icon(Icons.table_chart),
            title: Text(item.$1),
            trailing: IconButton(
              icon: const Icon(Icons.ios_share),
              onPressed: () async => _runFileAction(
                () => item.$2 == 'cantina'
                    ? service.exportCanteen(
                        startDate: startDate,
                        endDate: endDate,
                        category: category,
                      )
                    : service.exportExcel(
                        item.$2,
                        item.$1,
                        startDate: startDate,
                        endDate: endDate,
                        category: category,
                      ),
              ),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.summarize),
          title: const Text('RelatorioConsolidado.xlsx'),
          trailing: IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: () async => _runFileAction(
              () => service.exportConsolidated(
                startDate: startDate,
                endDate: endDate,
                category: category,
              ),
            ),
          ),
        ),
        const Divider(),
        Text('Relatórios PDF', style: Theme.of(context).textTheme.titleLarge),
        for (final item in [
          ('Financeiro Geral', 'entradas'),
          ('Entradas', 'entradas'),
          ('Despesas', 'despesas'),
          ('Fluxo de Caixa', 'fluxocaixa'),
          ('Cantina', 'vendas_cantina'),
          ('Estoque', 'estoque'),
        ])
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: Text(item.$1),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () => _runFileAction(
                () => _printSelectedReport(
                  service,
                  title: item.$1,
                  table: item.$2,
                  startDate: startDate,
                  endDate: endDate,
                  category: category,
                ),
              ),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.calendar_month),
          title: const Text('Relatório mensal'),
          trailing: IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _runFileAction(
              () => _printCurrentPeriod(service, annual: false),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.calendar_today),
          title: const Text('Relatório anual'),
          trailing: IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _runFileAction(
              () => _printCurrentPeriod(service, annual: true),
            ),
          ),
        ),
        if (context.read<AppState>().user?['perfil'] != 'Consulta') ...[
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Importar Excel (XLSX)'),
            subtitle: const Text(
              'Disponível para entradas, despesas, cantina e estoque',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: () => _importExcel(service),
            ),
          ),
        ],
        ListTile(
          leading: const Icon(Icons.backup),
          title: const Text('Backup local'),
          subtitle: const Text('Compartilhar ou salvar o arquivo de backup'),
          trailing: IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: () async => _runFileAction(() => service.shareBackup()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.email_outlined),
          title: const Text('Enviar backup por e-mail'),
          subtitle: const Text(
            'O arquivo será anexado; escolha o app de e-mail e o destinatário',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.send_outlined),
            onPressed: () async =>
                _runFileAction(() => service.shareBackup(email: true)),
          ),
        ),
        if (context.read<AppState>().user?['perfil'] == 'Administrador')
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restaurar backup'),
            trailing: IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: () async =>
                  _runFileAction(() => service.restoreBackup()),
            ),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.security, color: Colors.blue),
          title: const Text('Logs de Auditoria e Segurança (LGPD)'),
          subtitle: const Text(
            'Histórico de autenticações biométricas, operações e dispositivos',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showAuditLogsDialog,
        ),
      ],
    );
  }

  Future<void> _printSelectedReport(
    FileService service, {
    required String title,
    required String table,
    String? startDate,
    String? endDate,
    String? category,
  }) {
    if (title == 'Financeiro Geral') {
      return service.printSummaryPdf(
        title: title,
        startDate: startDate,
        endDate: endDate,
      );
    }
    if (title == 'Cantina') {
      return service.printCanteenPdf(
        startDate: startDate,
        endDate: endDate,
        category: category,
      );
    }
    return service.printPdf(
      table,
      title,
      startDate: startDate,
      endDate: endDate,
      category: category,
    );
  }

  Future<void> _printCurrentPeriod(
    FileService service, {
    required bool annual,
  }) async {
    final now = DateTime.now();
    final start = annual
        ? '${now.year}-01-01'
        : DateFormat('yyyy-MM-01').format(now);
    final end = DateFormat('yyyy-MM-dd').format(now);
    await service.printSummaryPdf(
      title: annual
          ? 'Relatório anual ${now.year}'
          : 'Relatório mensal ${DateFormat('MM/yyyy').format(now)}',
      startDate: start,
      endDate: end,
    );
  }

  Future<void> _importExcel(FileService service) async {
    final targetTable = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('O que deseja importar?'),
        children: [
          for (final option in [
            ('Entradas', 'entradas'),
            ('Despesas', 'despesas'),
            ('Vendas da Cantina', 'vendas_cantina'),
            ('Compras da Cantina', 'compras_cantina'),
            ('Estoque', 'estoque'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option.$2),
              child: Text(option.$1),
            ),
        ],
      ),
    );
    if (targetTable == null) return;
    String title;
    String message;
    try {
      title = 'Importação concluída';
      message = await service.importExcel(targetTable: targetTable);
    } catch (error) {
      title = 'Erros de importação';
      message = error.toString();
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: SelectableText(message)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    if (mounted) setState(_refresh);
  }

  Future<void> _runFileAction(Future<void> Function() action) async {
    final state = context.read<AppState>();
    final bioOk = await state.authenticateBiometric(
      reason: 'Autentique-se por biometria para exportar relatórios ou gerenciar backups',
      operation: 'Exportação / Relatório / Backup',
    );
    if (!bioOk) {
      _message('Ação cancelada: validação biométrica obrigatória.');
      return;
    }
    try {
      await action();
    } catch (error) {
      if (mounted) _message('Operação não concluída: $error');
    }
  }

  Future<void> _showAuditLogsDialog() async {
    final state = context.read<AppState>();
    final bioOk = await state.authenticateBiometric(
      reason: 'Autentique-se por biometria para consultar os logs de auditoria LGPD',
      operation: 'Consulta de Logs de Auditoria LGPD',
    );
    if (!bioOk) {
      _message('Acesso negado: validação biométrica obrigatória.');
      return;
    }
    final logs = await state.auditService.fetchLogs(limit: 150);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logs de Auditoria e Segurança (LGPD)'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: logs.isEmpty
              ? const Center(child: Text('Nenhum registro de auditoria encontrado.'))
              : ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return ListTile(
                      isThreeLine: true,
                      dense: true,
                      leading: const Icon(Icons.shield_outlined, size: 28),
                      title: Text('${log.operation} (${log.userName ?? "Sistema"})'),
                      subtitle: Text(
                        'Autenticação: ${log.authType}\n'
                        'Data/Hora: ${log.dateTime}\n'
                        'Dispositivo: ${log.device ?? "Móvel"} · IP: ${log.ipAddress ?? "127.0.0.1"}\n'
                        'Detalhes: ${log.details ?? "-"}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
