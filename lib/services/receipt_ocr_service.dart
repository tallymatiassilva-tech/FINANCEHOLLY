import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class ReceiptScanResult {
  ReceiptScanResult({
    required this.rawText,
    required this.date,
    required this.amount,
    required this.description,
    required this.category,
    required this.vendor,
    required this.responsible,
    required this.entryType,
  });

  final String rawText;
  final String? date;
  final String? amount;
  final String? description;
  final String? category;
  final String? vendor;
  final String? responsible;
  final String entryType; // 'entrada' ou 'despesa'

  Map<String, String> toFields({required bool isExpense}) {
    final fields = <String, String>{};
    if (date != null && date!.isNotEmpty) {
      fields['data'] = date!;
    }
    if (amount != null && amount!.isNotEmpty) {
      fields['valor'] = amount!;
      fields['valor_total'] = amount!;
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

  Future<ReceiptScanResult?> pickFromCamera() => _scanImageSource(ImageSource.camera);

  Future<ReceiptScanResult?> pickFromGallery() => _scanImageSource(ImageSource.gallery);

  Future<ReceiptScanResult?> pickFromPdf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (picked == null) return null;

    final fileBytes = picked.files.single.bytes;
    final filePath = picked.files.single.path;

    Uint8List? bytes = fileBytes;
    if (bytes == null && filePath != null) {
      bytes = await File(filePath).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Não foi possível ler o arquivo PDF selecionado.');
    }

    final rasterStream = Printing.raster(bytes, pages: [0], dpi: 200);
    String? tempImagePath;
    await for (final page in rasterStream) {
      final pngBytes = await page.toPng();
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/pdf_ocr_${DateTime.now().microsecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(pngBytes, flush: true);
      tempImagePath = tempFile.path;
      break;
    }

    if (tempImagePath == null) {
      throw const FormatException('Não foi possível renderizar a página do PDF para leitura OCR.');
    }

    try {
      final text = await _recognizeText(tempImagePath);
      if (text.trim().isEmpty) return null;
      return _parseText(text);
    } finally {
      final tempFile = File(tempImagePath);
      if (await tempFile.exists()) {
        await tempFile.delete().catchError((_) => tempFile);
      }
    }
  }

  Future<ReceiptScanResult?> _scanImageSource(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 3000,
      maxHeight: 3000,
      imageQuality: 90,
    );
    if (picked == null) return null;
    if (await picked.length() > 20 * 1024 * 1024) {
      throw const FormatException('A imagem deve ter no máximo 20 MB.');
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
    final entryType = _classifyEntryType(rawText);
    final category = _extractCategory(rawText, entryType);
    final responsible = _extractResponsible(lines, description);

    return ReceiptScanResult(
      rawText: rawText,
      date: date,
      amount: amount,
      description: description,
      category: category,
      vendor: vendor,
      responsible: responsible,
      entryType: entryType,
    );
  }

  String _classifyEntryType(String text) {
    final lower = text.toLowerCase();
    final incomeKeywords = [
      'dizimo', 'dízimo', 'oferta', 'doacao', 'doação', 'contribuicao', 'contribuição',
      'recebimento', 'pix recebido', 'credito', 'crédito', 'transferencia recebida',
      'deposito', 'depósito', 'entrada', 'receita', 'campanha'
    ];
    final expenseKeywords = [
      'comprovante de pagamento', 'pagamento', 'pix enviado', 'debito', 'débito',
      'nota fiscal', 'nf-e', 'nfe', 'cupom fiscal', 'vencimento', 'boleto', 'fatura',
      'despesa', 'saida', 'saída', 'fornecedor', 'compra', 'valor a pagar'
    ];

    int incomeScore = 0;
    int expenseScore = 0;

    for (final kw in incomeKeywords) {
      if (lower.contains(kw)) incomeScore++;
    }
    for (final kw in expenseKeywords) {
      if (lower.contains(kw)) expenseScore++;
    }

    if (incomeScore > expenseScore) return 'entrada';
    if (expenseScore > incomeScore) return 'despesa';
    return 'despesa';
  }

  String? _extractAmount(String text) {
    final sanitizedText = text
        .replaceAll(RegExp(r'\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}'), '')
        .replaceAll(RegExp(r'\d{3}\.\d{3}\.\d{3}-\d{2}'), '')
        .replaceAll(RegExp(r'\(\d{2}\)\s*\d{4,5}-\d{4}'), '');

    final matches = RegExp(
      r'(?:R\$\s*|RS\s*|\b)(\d{1,3}(?:[.\s]\d{3})+|\d+)(?:[.,](\d{1,2}))?',
      caseSensitive: false,
    ).allMatches(sanitizedText);

    String? bestValue;
    double bestNumber = 0;

    for (final match in matches) {
      final group = match.group(0)?.trim() ?? '';
      final cleaned = group
          .replaceAll(RegExp(r'[^0-9,.\s]'), '')
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll('.', '')
          .replaceAll(',', '.');
      if (cleaned.isEmpty) continue;
      final parsed = double.tryParse(cleaned);
      if (parsed == null || parsed <= 0 || parsed > 1000000) continue;
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

  String? _extractCategory(String text, String entryType) {
    final lower = text.toLowerCase();
    if (entryType == 'entrada') {
      final incomeCategories = {
        'dizimo': 'Dízimos',
        'dízimo': 'Dízimos',
        'oferta': 'Ofertas',
        'doacao': 'Doações',
        'doação': 'Doações',
        'campanha': 'Campanhas',
        'evento': 'Eventos',
        'missao': 'Missões',
        'missão': 'Missões',
      };
      for (final entry in incomeCategories.entries) {
        if (lower.contains(entry.key)) return entry.value;
      }
      return 'Outros';
    } else {
      final expenseCategories = {
        'agua': 'Água',
        'água': 'Água',
        'energia': 'Energia',
        'luz': 'Energia',
        'internet': 'Internet',
        'telefonia': 'Internet',
        'limpeza': 'Limpeza',
        'manutencao': 'Manutenção',
        'manutenção': 'Manutenção',
        'salario': 'Salários',
        'salário': 'Salários',
        'evento': 'Eventos',
        'missao': 'Missões',
        'missão': 'Missões',
      };
      for (final entry in expenseCategories.entries) {
        if (lower.contains(entry.key)) return entry.value;
      }
      return 'Outros';
    }
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
      if (normalized.toLowerCase().contains('respons') ||
          normalized.toLowerCase().contains('doacao') ||
          normalized.toLowerCase().contains('dizimo')) {
        return normalized;
      }
    }
    return description;
  }
}
