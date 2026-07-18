import 'package:intl/intl.dart';

final _money = NumberFormat.decimalPattern('ru');

/// The backend serializes money as a decimal string (e.g. "150000.00").
/// Format it for display as grouped digits + currency.
String formatMoney(String? raw, {String currency = 'сом'}) {
  final value = double.tryParse(raw ?? '') ?? 0;
  return '${_money.format(value)} $currency';
}

String formatInt(int value) => _money.format(value);
