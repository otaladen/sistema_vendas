import 'dart:convert';

import 'package:http/http.dart' as http;

/// Dados de produto obtidos por GTIN/EAN/ISBN na Brasil API.
class DadosGtinBrasilApi {
  const DadosGtinBrasilApi({
    required this.gtin,
    required this.descricao,
    this.ncm = '',
    this.fonte = '',
    this.dadosBrutos,
  });

  final String gtin;
  final String descricao;
  /// NCM com 8 digitos (sem pontuacao), quando informado pela API.
  final String ncm;
  /// Origem da consulta: `gtin`, `isbn`, etc.
  final String fonte;
  final Map<String, dynamic>? dadosBrutos;

  factory DadosGtinBrasilApi.fromMap(
    Map<String, dynamic> map, {
    required String gtin,
    required String fonte,
  }) {
    String s(dynamic key) => (map[key] ?? '').toString().trim();

    var descricao = s('descricao');
    if (descricao.isEmpty) {
      final titulo = s('title');
      final subtitulo = s('subtitle');
      descricao = titulo;
      if (subtitulo.isNotEmpty) {
        descricao = descricao.isEmpty ? subtitulo : '$descricao — $subtitulo';
      }
    }

    var ncm = s('ncm').replaceAll(RegExp(r'\D'), '');
    if (ncm.length > 8) ncm = ncm.substring(0, 8);

    return DadosGtinBrasilApi(
      gtin: gtin,
      descricao: descricao,
      ncm: ncm,
      fonte: fonte,
      dadosBrutos: map,
    );
  }

  Map<String, dynamic> toMap() => {
        'gtin': gtin,
        'descricao': descricao,
        'ncm': ncm,
        'fonte': fonte,
        if (dadosBrutos != null) 'dadosBrutos': dadosBrutos,
      };
}

/// Dados de NCM retornados por https://brasilapi.com.br/api/ncm/v1/{codigo}
class DadosNcmBrasilApi {
  const DadosNcmBrasilApi({
    required this.codigo,
    required this.descricao,
    this.cest = '',
    this.dataInicio = '',
    this.dataFim = '',
    this.tipoAto = '',
    this.numeroAto = '',
    this.anoAto = '',
    this.dadosBrutos,
  });

  final String codigo;
  final String descricao;
  /// CEST quando presente na resposta (a Brasil API pode nao enviar este campo).
  final String cest;
  final String dataInicio;
  final String dataFim;
  final String tipoAto;
  final String numeroAto;
  final String anoAto;
  final Map<String, dynamic>? dadosBrutos;

  /// Codigo NCM somente digitos (8).
  String get codigoDigitos => codigo.replaceAll(RegExp(r'\D'), '');

  factory DadosNcmBrasilApi.fromMap(Map<String, dynamic> map) {
    String s(dynamic key) => (map[key] ?? '').toString().trim();

    var cest = s('cest');
    if (cest.isEmpty) cest = s('codigo_cest');
    cest = cest.replaceAll(RegExp(r'\D'), '');
    if (cest.length > 7) cest = cest.substring(0, 7);

    return DadosNcmBrasilApi(
      codigo: s('codigo'),
      descricao: s('descricao'),
      cest: cest,
      dataInicio: s('data_inicio'),
      dataFim: s('data_fim'),
      tipoAto: s('tipo_ato'),
      numeroAto: s('numero_ato'),
      anoAto: s('ano_ato'),
      dadosBrutos: map,
    );
  }

  Map<String, dynamic> toMap() => {
        'codigo': codigo,
        'codigoDigitos': codigoDigitos,
        'descricao': descricao,
        'cest': cest,
        'dataInicio': dataInicio,
        'dataFim': dataFim,
        'tipoAto': tipoAto,
        'numeroAto': numeroAto,
        'anoAto': anoAto,
        if (dadosBrutos != null) 'dadosBrutos': dadosBrutos,
      };
}

class BrasilApiException implements Exception {
  BrasilApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode != null ? 'BrasilAPI ($statusCode): $message' : 'BrasilAPI: $message';
}

/// Consultas a https://brasilapi.com.br (GTIN/ISBN e NCM).
class BrasilApiService {
  BrasilApiService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  static const String _baseUrl = 'https://brasilapi.com.br/api';
  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _http;

  /// Consulta GTIN/EAN/codigo de barras.
  ///
  /// Ordem de tentativa:
  /// 1. `/api/gtin/v1/{gtin}` (quando disponivel na Brasil API)
  /// 2. `/api/isbn/v1/{gtin}` para ISBN-10/ISBN-13 (livros)
  ///
  /// Retorna `null` se nao encontrado (HTTP 404 em todas as rotas).
  Future<DadosGtinBrasilApi?> consultarGtin(String gtin) async {
    final digitos = gtin.replaceAll(RegExp(r'\D'), '');
    if (digitos.isEmpty) {
      return null;
    }

    final gtinUri = Uri.parse('$_baseUrl/gtin/v1/$digitos');
    final gtinResult = await _getJsonMap(gtinUri);
    if (gtinResult.statusCode == 200 && gtinResult.body != null) {
      return DadosGtinBrasilApi.fromMap(
        gtinResult.body!,
        gtin: digitos,
        fonte: 'gtin',
      );
    }
    if (gtinResult.statusCode != null &&
        gtinResult.statusCode != 404 &&
        gtinResult.statusCode! >= 400) {
      throw BrasilApiException(
        gtinResult.errorMessage ?? 'Falha ao consultar GTIN.',
        statusCode: gtinResult.statusCode,
      );
    }

    if (_pareceIsbn(digitos)) {
      final isbnUri = Uri.parse('$_baseUrl/isbn/v1/$digitos');
      final isbnResult = await _getJsonMap(isbnUri);
      if (isbnResult.statusCode == 200 && isbnResult.body != null) {
        return DadosGtinBrasilApi.fromMap(
          isbnResult.body!,
          gtin: digitos,
          fonte: 'isbn',
        );
      }
      if (isbnResult.statusCode != null &&
          isbnResult.statusCode != 404 &&
          isbnResult.statusCode! >= 400) {
        throw BrasilApiException(
          isbnResult.errorMessage ?? 'Falha ao consultar ISBN.',
          statusCode: isbnResult.statusCode,
        );
      }
    }

    return null;
  }

  /// Consulta NCM em `/api/ncm/v1/{ncm}`.
  ///
  /// [ncm] aceita formatado (`3305.10.00`) ou 8 digitos.
  /// O campo [DadosNcmBrasilApi.cest] e preenchido apenas se a API enviar
  /// (`cest` ou `codigo_cest` no JSON).
  Future<DadosNcmBrasilApi?> consultarNcm(String ncm) async {
    final digitos = _normalizarNcm(ncm);
    if (digitos.length != 8) {
      return null;
    }

    final uri = Uri.parse('$_baseUrl/ncm/v1/$digitos');
    final result = await _getJsonMap(uri);

    if (result.statusCode == 404) {
      return null;
    }
    if (result.statusCode != 200 || result.body == null) {
      throw BrasilApiException(
        result.errorMessage ?? 'Falha ao consultar NCM.',
        statusCode: result.statusCode,
      );
    }

    return DadosNcmBrasilApi.fromMap(result.body!);
  }

  static String _normalizarNcm(String ncm) {
    final digitos = ncm.replaceAll(RegExp(r'\D'), '');
    if (digitos.isEmpty) return '';
    if (digitos.length >= 8) return digitos.substring(0, 8);
    return digitos.padLeft(8, '0');
  }

  static bool _pareceIsbn(String digitos) {
    if (digitos.length == 10 || digitos.length == 13) {
      if (digitos.length == 13 &&
          (digitos.startsWith('978') || digitos.startsWith('979'))) {
        return true;
      }
      if (digitos.length == 10) return true;
    }
    return false;
  }

  Future<_HttpJsonResult> _getJsonMap(Uri uri) async {
    try {
      final response = await _http.get(uri).timeout(_timeout);
      final status = response.statusCode;

      if (status == 404) {
        return _HttpJsonResult(statusCode: 404);
      }

      if (status < 200 || status >= 300) {
        return _HttpJsonResult(
          statusCode: status,
          errorMessage: _extrairMensagemErro(response.body) ??
              'HTTP $status',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return _HttpJsonResult(statusCode: status, body: decoded);
      }
      if (decoded is List && decoded.isNotEmpty) {
        final first = decoded.first;
        if (first is Map<String, dynamic>) {
          return _HttpJsonResult(statusCode: status, body: first);
        }
      }

      return _HttpJsonResult(
        statusCode: status,
        errorMessage: 'Resposta da BrasilAPI em formato inesperado.',
      );
    } catch (e) {
      if (e is BrasilApiException) rethrow;
      throw BrasilApiException('Erro de rede ao consultar BrasilAPI: $e');
    }
  }

  static String? _extrairMensagemErro(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['message'] ?? decoded['mensagem'];
        if (msg != null) return msg.toString();
      }
    } catch (_) {}
    return null;
  }
}

class _HttpJsonResult {
  const _HttpJsonResult({
    this.statusCode,
    this.body,
    this.errorMessage,
  });

  final int? statusCode;
  final Map<String, dynamic>? body;
  final String? errorMessage;
}
