class FinanceRecord {
  const FinanceRecord(this.values);

  final Map<String, Object?> values;

  int? get id => values['id'] as int?;
  String? get date => values['data']?.toString();

  factory FinanceRecord.fromMap(Map<String, Object?> values) =>
      FinanceRecord(Map<String, Object?>.unmodifiable(values));
}
