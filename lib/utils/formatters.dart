import 'package:intl/intl.dart';

final currencyFormatter =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
