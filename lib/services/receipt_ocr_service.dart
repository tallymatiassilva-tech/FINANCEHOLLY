import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class ReceiptScanResult {
  ReceiptScanResult({
    required this.rawText,
    required this.date,
    required this.amount,
    required this.description,
    required this.category,
    required this.vendor,
    required this.responsible,
  });

  final String rawText;
  final String? date;
  final String? amount;
  final String? description;
  final String? category;
  final String? vendor;
  final String? responsible;

  Map<String, String> toFields({required bool isExpense}) {
    final fields = <String, String>{};
    if (date != null && date!.isNotEmpty) {
      fields['data'] = date!;
    }
    if (amount != null && amount!.isNotEmpty) {
      fields['valor'] = amount!;
    }
    if (isExpense) {
      if (category != null && category!.isNotEmpty) {
        fields['categoria'] = category!;
      }
      if (description != null && description!.isNotEmpty) {
        fields['descricao'] = description!;
      }
      if (vendor != null && vendor!.isNotEmpty) {
        fields['fornecedor'] = vendor!;
      }
    } else {
      if (category != null && category!.isNotEmpty) {
        fields['tipo'] = category!;
      }
      if (description != null && description!.isNotEmpty) {
        fields['descricao'] = description!;
      }
      if (responsible != null && responsible!.isNotEmpty) {
        fields['responsavel'] = responsible!;
      }
    }
    return fields;
  }
}

class ReceiptOcrService {
  ReceiptOcrService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<ReceiptScanResult?> pickFromCamera() => _scan(ImageSource.camera);

  Future<ReceiptScanResult?> pickFromGallery() => _scan(ImageSource.gallery);

  Future<ReceiptScanResult?> _scan(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 3000,
      maxHeight: 3000,
      imageQuality: 90,
    );
    if (picked == null) return null;
    if (await picked.length() > 15 * 1024 * 1024) {
      throw const FormatException('A imagem deve ter no máximo 15 MB.');
    }

    final text = await _recognizeText(picked.path);
    if (text.trim().isEmpty) {
      return null;
    }
    return _parseText(text);
  }

  Future<String> _recognizeText(String path) async {
    final image = InputImage.fromFilePath(path);
    final recognizer = TextRecognizer();
    try {
      final recognized = await recognizer.processImage(image);
      return recognized.text;
    } finally {
      await recognizer.close();
    }
  }

  ReceiptScanResult _parseText(String rawText) {
    final lines = rawText
        .replaceAll('\r', '')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final date = _extractDate(rawText) ?? _extractDateFromLines(lines);
    final amount = _extractAmount(rawText);
    final description = _extractDescription(lines, amount, date);
    final vendor = _extractVendor(lines, description, amount, date);
    final category = _extractCategory(rawText);
    final responsible = _extractResponsible(lines, description);

    return ReceiptScanResult(
      rawText: rawText,
      date: date,
      amount: amount,
      description: description,
      category: category,
      vendor: vendor,
      responsible: responsible,
    );
  }

  String? _extractAmount(String text) {
    final matches = RegExp(
      r'(?:R\$\s*|RS\s*|\b)(\d{1,3}(?:[.\s]\d{3})+|\d+)(?:[.,](\d{1,2}))?',
      caseSensitive: false,
    ).allMatches(text);

    String? bestValue;
    double bestNumber = 0;

    for (final match in matches) {
      final group = match.group(0)?.trim() ?? '';
      final cleaned = group
          .replaceAll(RegExp(r'[^0-9,\.\s]'), '')
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll('.', '')
          .replaceAll(',', '.');
      if (cleaned.isEmpty) continue;
      final parsed = double.tryParse(cleaned);
      if (parsed == null || parsed <= 0) continue;
      if (parsed > bestNumber) {
        bestNumber = parsed;
        bestValue = parsed.toStringAsFixed(2).replaceAll('.', ',');
      }
    }

    return bestValue;
  }

  String? _extractDate(String text) {
    final patterns = [
      RegExp(r'\b\d{2}/\d{2}/\d{4}\b'),
      RegExp(r'\b\d{4}-\d{2}-\d{2}\b'),
      RegExp(r'\b\d{2}-\d{2}-\d{4}\b'),
      RegExp(r'\b\d{2}\.\d{2}\.\d{4}\b'),
      RegExp(r'\b\d{2}/\d{2}/\d{2}\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final raw = match.group(0)!;
      final normalized = _normalizeDate(raw);
      if (normalized != null) return normalized;
    }
    return null;
  }

  String? _extractDateFromLines(List<String> lines) {
    for (final line in lines) {
      final candidate = _extractDate(line);
      if (candidate != null) return candidate;
    }
    return null;
  }

  String? _normalizeDate(String raw) {
    final trimmed = raw.trim();
    if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(trimmed)) {
      final parts = trimmed.split('/');
      return '${parts[2]}-${parts[1]}-${parts[0]}';
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(trimmed)) {
      final parts = trimmed.split('-');
      return '${parts[2]}-${parts[1]}-${parts[0]}';
    }
    if (RegExp(r'^\d{2}\.\d{2}\.\d{4}$').hasMatch(trimmed)) {
      final parts = trimmed.split('.');
      return '${parts[2]}-${parts[1]}-${parts[0]}';
    }
    if (RegExp(r'^\d{2}/\d{2}/\d{2}$').hasMatch(trimmed)) {
      final parts = trimmed.split('/');
      final year = int.parse(parts[2]) >= 50 ? 1900 + int.parse(parts[2]) : 2000 + int.parse(parts[2]);
      return '$year-${parts[1]}-${parts[0]}';
    }
    return null;
  }

  String? _extractCategory(String text) {
    final lower = text.toLowerCase();
    final incomeKeywords = {
      'dizimo': 'Dízimos',
      'oferta': 'Ofertas',
      'doacao': 'Doações',
      'campanha': 'Campanhas',
      'evento': 'Eventos',
      'missao': 'Missões',
      'ofertas': 'Ofertas',
      'doações': 'Doações',
    };
    final expenseKeywords = {
      'agua': 'Água',
      'energia': 'Energia',
      'internet': 'Internet',
      'limpeza': 'Limpeza',
      'manutencao': 'Manutenção',
      'salario': 'Salários',
      'evento': 'Eventos',
      'missao': 'Missões',
      'outros': 'Outros',
    };

    for (final entry in incomeKeywords.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    for (final entry in expenseKeywords.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }

  String? _extractDescription(List<String> lines, String? amount, String? date) {
    for (final line in lines) {
      final normalized = line
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'[^A-Za-zÀ-ÖØ-öø-ÿ0-9\s/\-.,]'), '')
          .trim();
      if (normalized.isEmpty) continue;
      final upper = normalized.toUpperCase();
      if (date != null && upper.contains(date.toUpperCase())) continue;
      if (amount != null && upper.contains(amount.replaceAll(',', '').toUpperCase())) continue;
      if (upper.contains('TOTAL') ||
          upper.contains('SUBTOTAL') ||
          upper.contains('VALOR') ||
          upper.contains('PAGAMENTO') ||
          upper.contains('PIX') ||
          upper.contains('CARTAO') ||
          upper.contains('DINHEIRO') ||
          upper.contains('FORNECEDOR') ||
          upper.contains('EMPRESA')) {
        continue;
      }
      final words = normalized.split(RegExp(r'\s+'));
      if (words.length >= 2) return normalized;
    }
    return null;
  }

  String? _extractVendor(
    List<String> lines,
    String? description,
    String? amount,
    String? date,
  ) {
    for (final line in lines) {
      final normalized = line
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'[^A-Za-zÀ-ÖØ-öø-ÿ0-9\s/\-.,]'), '')
          .trim();
      if (normalized.isEmpty) continue;
      final upper = normalized.toUpperCase();
      if (date != null && upper.contains(date.toUpperCase())) continue;
      if (amount != null && upper.contains(amount.replaceAll(',', '').toUpperCase())) continue;
      if (upper.contains('FORNECEDOR') ||
          upper.contains('EMPRESA') ||
          upper.contains('LOJA') ||
          upper.contains('MERCADO') ||
          upper.contains('SUPERMERCADO')) {
        final value = normalized.replaceFirst(
          RegExp(
            r'(fornecedor|empresa|loja|mercado|supermercado)\s*[:\-]?\s*',
            caseSensitive: false,
          ),
          '',
        ).trim();
        if (value.isNotEmpty) return value;
      }
      if (description != null && normalized == description) {
        return normalized;
      }
    }
    return description;
  }

  String? _extractResponsible(List<String> lines, String? description) {
    for (final line in lines) {
      final normalized = line
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'[^A-Za-zÀ-ÖØ-öø-ÿ0-9\s/\-.,]'), '')
          .trim();
      if (normalized.isEmpty || normalized == description) continue;
      if (normalized.toLowerCase().contains('respons') || normalized.toLowerCase().contains('doacao') || normalized.toLowerCase().contains('dizimo')) {
        return normalized;
      }
    }
    return description;
  }
}
