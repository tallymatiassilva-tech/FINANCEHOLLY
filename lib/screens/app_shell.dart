import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import 'dashboard_screen.dart';
import 'data_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;

  static const _labels = [
    'Dashboard',
    'Entradas',
    'Despesas',
    'Fluxo de Caixa',
    'Cantina',
    'Estoque',
    'Relatórios',
    'Configurações',
  ];
  static const _icons = [
    Icons.dashboard_outlined,
    Icons.south_west,
    Icons.north_east,
    Icons.account_balance_wallet_outlined,
    Icons.storefront_outlined,
    Icons.inventory_2_outlined,
    Icons.insert_chart_outlined,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardScreen(),
      const DataScreen(title: 'Entradas', table: 'entradas', kind: DataKind.income),
      const DataScreen(title: 'Despesas', table: 'despesas', kind: DataKind.expense),
      const DataScreen(title: 'Fluxo de Caixa', table: 'fluxocaixa', kind: DataKind.cashflow),
      const DataScreen(title: 'Cantina', table: 'vendas_cantina', kind: DataKind.canteen),
      const DataScreen(title: 'Estoque', table: 'estoque', kind: DataKind.stock),
      const DataScreen(title: 'Relatórios', table: 'entradas', kind: DataKind.reports),
      const SettingsScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_labels[_selected]),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(context.watch<AppState>().user?['nome']?.toString() ?? ''),
            ),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: () => context.read<AppState>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(index: _selected, children: pages),
      bottomNavigationBar: SafeArea(
        child: SizedBox(
          height: 68,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_labels.length, (index) {
                final selected = _selected == index;
                return SizedBox(
                  width: 86,
                  child: InkWell(
                    onTap: () => setState(() => _selected = index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_icons[index], color: selected ? Theme.of(context).colorScheme.primary : null),
                        const SizedBox(height: 4),
                        Text(
                          _labels[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: selected ? Theme.of(context).colorScheme.primary : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
