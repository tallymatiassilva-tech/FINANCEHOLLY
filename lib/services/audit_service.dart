import 'dart:io';

import '../database/app_database.dart';

class AuditLog {
  AuditLog({
    this.id,
    this.userId,
    this.userName,
    required this.authType,
    required this.dateTime,
    required this.operation,
    this.details,
    this.device,
    this.ipAddress,
  });

  final int? id;
  final int? userId;
  final String? userName;
  final String authType;
  final String dateTime;
  final String operation;
  final String? details;
  final String? device;
  final String? ipAddress;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'usuario_id': userId,
        'usuario_nome': userName,
        'tipo_autenticacao': authType,
        'data_hora': dateTime,
        'operacao': operation,
        'detalhes': details,
        'dispositivo': device,
        'ip_endereco': ipAddress,
      };

  factory AuditLog.fromMap(Map<String, Object?> map) => AuditLog(
        id: map['id'] as int?,
        userId: map['usuario_id'] as int?,
        userName: map['usuario_nome']?.toString(),
        authType: map['tipo_autenticacao']?.toString() ?? 'Biometria / Senha',
        dateTime: map['data_hora']?.toString() ?? DateTime.now().toIso8601String(),
        operation: map['operacao']?.toString() ?? 'Operação',
        details: map['detalhes']?.toString(),
        device: map['dispositivo']?.toString(),
        ipAddress: map['ip_endereco']?.toString(),
      );
}

class AuditService {
  AuditService(this.database);

  final AppDatabase database;

  static String getDeviceInfo() {
    try {
      final os = Platform.operatingSystem;
      final hostname = Platform.localHostname;
      return '${os.toUpperCase()} ($hostname)';
    } catch (_) {
      return 'Dispositivo Móvel/Desktop';
    }
  }

  Future<void> logAction({
    required Map<String, Object?>? user,
    required String authType,
    required String operation,
    String? details,
  }) async {
    try {
      final userId = user?['id'] as int?;
      final userName =
          user?['nome']?.toString() ?? user?['usuario']?.toString() ?? 'Sistema';
      final now = DateTime.now().toIso8601String();
      final device = getDeviceInfo();

      await database.insert('auditoria_logs', {
        'usuario_id': userId,
        'usuario_nome': userName,
        'tipo_autenticacao': authType,
        'data_hora': now,
        'operacao': operation,
        'detalhes': details ?? '',
        'dispositivo': device,
        'ip_endereco': '127.0.0.1',
      });
    } catch (e) {
      // Ignora falhas no log de auditoria para não travar o fluxo
    }
  }

  Future<List<AuditLog>> fetchLogs({int limit = 100}) async {
    final rows = await database.query(
      'auditoria_logs',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(AuditLog.fromMap).toList();
  }
}
