import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../database/app_database.dart';
import '../services/app_state.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _data;
  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _data = _load(context.read<AppState>());
  }

  Future<_DashboardData> _load(AppState state) async {
    final db = state.database;
    final income = await db.sum('entradas', 'valor');
    final expenses = await db.sum('despesas', 'valor', where: "status = 'Pago'");
    final stockRows = await db.query('estoque');
    final totalSales = await db.sum('vendas_cantina', 'valor_total');
    final purchases = await db.sum('compras_cantina', 'valor_compra');
    final canteenProfit = totalSales - purchases;
    final available = income - expenses + canteenProfit;
    final monthlyIncome = <double>[];
    final monthlyExpenses = <double>[];
    final monthlySales = <double>[];
    final now = DateTime.now();
    for (var offset = 5; offset >= 0; offset--) {
      final month = DateTime(now.year, now.month - offset);
      final start = DateFormat('yyyy-MM-01').format(month);
      final end = DateFormat('yyyy-MM-31').format(month);
      monthlyIncome.add(await _sumRange(db, 'entradas', 'valor', start, end));
      monthlyExpenses.add(
        await _sumRange(db, 'despesas', 'valor', start, end, extra: " AND status = 'Pago'"),
      );
      monthlySales.add(await _sumRange(db, 'vendas_cantina', 'valor_total', start, end));
    }
    final categoryRows = await db.database.rawQuery(
      "SELECT categoria, SUM(valor) AS total FROM despesas WHERE status = 'Pago' GROUP BY categoria ORDER BY total DESC",
    );
    final expensesByCategory = <String, double>{
      for (final row in categoryRows)
        row['categoria']?.toString() ?? 'Outros': (row['total'] as num).toDouble(),
    };
    return _DashboardData(
      income: income,
      expenses: expenses,
      balance: available,
      canteenProfit: canteenProfit,
      stockCount: stockRows
          .where((row) => ((row['quantidade'] as num?)?.toDouble() ?? 0) > 0)
          .length
          .toDouble(),
      monthlyIncome: monthlyIncome,
      monthlyExpenses: monthlyExpenses,
      monthlySales: monthlySales,
      expensesByCategory: expensesByCategory,
    );
  }

  Future<double> _sumRange(
    AppDatabase db,
    String table,
    String column,
    String start,
    String end, {
    String extra = '',
  }) async {
    final rows = await db.database.rawQuery(
      'SELECT COALESCE(SUM($column), 0) AS total FROM $table WHERE data >= ? AND data <= ?$extra',
      [start, end],
    );
    return (rows.first['total'] as num).toDouble();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_DashboardData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Não foi possível carregar o painel: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          final monthLabel = DateFormat('MMMM', 'pt_BR').format(DateTime.now());
          final yearLabel = DateTime.now().year.toString();

          return RefreshIndicator(
            onRefresh: () async => setState(_refresh),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Painel financeiro',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Resumo da igreja · $monthLabel $yearLabel',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        DateFormat('dd/MM', 'pt_BR').format(DateTime.now()),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryCard(
                      title: 'Saldo Geral',
                      value: _currency.format(data.balance),
                      icon: Icons.account_balance,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    _SummaryCard(
                      title: 'Entradas',
                      value: _currency.format(data.income),
                      icon: Icons.south_west,
                      color: Colors.green.shade700,
                    ),
                    _SummaryCard(
                      title: 'Despesas pagas',
                      value: _currency.format(data.expenses),
                      icon: Icons.north_east,
                      color: Colors.red.shade700,
                    ),
                    _SummaryCard(
                      title: 'Lucro cantina',
                      value: _currency.format(data.canteenProfit),
                      icon: Icons.storefront,
                      color: Colors.orange.shade800,
                    ),
                    _SummaryCard(
                      title: 'Caixa disponível',
                      value: _currency.format(data.balance),
                      icon: Icons.wallet,
                      color: Colors.teal.shade700,
                    ),
                    _SummaryCard(
                      title: 'Produtos em estoque',
                      value: data.stockCount.toStringAsFixed(0),
                      icon: Icons.inventory_2,
                      color: Colors.blue.shade700,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Entradas x despesas · 6 meses', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 220,
                          child: BarChart(
                            BarChartData(
                              barGroups: List.generate(
                                6,
                                (i) => BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: data.monthlyIncome[i],
                                      color: Colors.green.shade600,
                                      width: 10,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                    ),
                                    BarChartRodData(
                                      toY: data.monthlyExpenses[i],
                                      color: Colors.red.shade400,
                                      width: 10,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                    ),
                                  ],
                                ),
                              ),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              gridData: const FlGridData(show: true),
                              alignment: BarChartAlignment.spaceAround,
                              maxY: _maxValue(data.monthlyIncome, data.monthlyExpenses) * 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('Verde: entradas · Vermelho: despesas pagas'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Evolução financeira', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 180,
                          child: LineChart(
                            LineChartData(
                              lineBarsData: [
                                LineChartBarData(
                                  spots: List.generate(
                                    6,
                                    (i) => FlSpot(
                                      i.toDouble(),
                                      data.monthlyIncome[i] - data.monthlyExpenses[i],
                                    ),
                                  ),
                                  color: Theme.of(context).colorScheme.primary,
                                  isCurved: true,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                                  ),
                                ),
                              ],
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              gridData: const FlGridData(show: true),
                              minY: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vendas da cantina · 6 meses', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 180,
                          child: LineChart(
                            LineChartData(
                              lineBarsData: [
                                LineChartBarData(
                                  spots: List.generate(
                                    6,
                                    (i) => FlSpot(i.toDouble(), data.monthlySales[i]),
                                  ),
                                  color: Colors.orange,
                                  isCurved: true,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Colors.orange.withValues(alpha: 0.12),
                                  ),
                                ),
                              ],
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              gridData: const FlGridData(show: true),
                              minY: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (data.expensesByCategory.isNotEmpty)
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Despesas por categoria', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 220,
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 4,
                                centerSpaceRadius: 36,
                                sections: data.expensesByCategory.entries
                                    .map(
                                      (entry) => PieChartSectionData(
                                        value: entry.value,
                                        title: entry.key,
                                        radius: 72,
                                        titleStyle: const TextStyle(fontSize: 10, color: Colors.white),
                                        color: _categoryColor(entry.key),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );

  double _maxValue(List<double> income, List<double> expenses) {
    final allValues = [...income, ...expenses];
    if (allValues.isEmpty) return 1;
    return allValues.reduce((a, b) => a > b ? a : b);
  }

  Color _categoryColor(String category) {
    final palette = [
      Colors.green.shade600,
      Colors.blue.shade600,
      Colors.orange.shade600,
      Colors.purple.shade600,
      Colors.red.shade500,
      Colors.teal.shade600,
      Colors.amber.shade700,
      Colors.indigo.shade500,
      Colors.pink.shade500,
    ];
    final index = category.hashCode % palette.length;
    return palette[index];
  }
}

class _DashboardData {
  const _DashboardData({
    required this.income,
    required this.expenses,
    required this.balance,
    required this.canteenProfit,
    required this.stockCount,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.monthlySales,
    required this.expensesByCategory,
  });

  final double income;
  final double expenses;
  final double balance;
  final double canteenProfit;
  final double stockCount;
  final List<double> monthlyIncome;
  final List<double> monthlyExpenses;
  final List<double> monthlySales;
  final Map<String, double> expensesByCategory;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 210,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.18),
                color.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
