import 'dart:convert';

import 'package:http/http.dart' as http;

/// Dados publicos de CNPJ retornados por https://brasilapi.com.br/api/cnpj/v1/{cnpj}
class DadosCnpjBrasilApi {
  const DadosCnpjBrasilApi({
    required this.razaoSocial,
    required this.nomeFantasia,
    required this.cep,
    required this.logradouro,
    required this.numero,
    required this.bairro,
    required this.municipio,
    required this.uf,
  });

  final String razaoSocial;
  final String nomeFantasia;
  final String cep;
  final String logradouro;
  final String numero;
  final String bairro;
  final String municipio;
  final String uf;

  static DadosCnpjBrasilApi fromMap(Map<String, dynamic> map) {
    String s(String key) => (map[key] ?? '').toString().trim();

    var logradouro = s('logradouro');
    final tipoLog = s('descricao_tipo_de_logradouro');
    if (tipoLog.isNotEmpty &&
        logradouro.isNotEmpty &&
        !logradouro.toUpperCase().startsWith(tipoLog.toUpperCase())) {
      logradouro = '$tipoLog $logradouro';
    }

    final complemento = s('complemento');
    if (complemento.isNotEmpty) {
      logradouro = logradouro.isEmpty
          ? complemento
          : '$logradouro, $complemento';
    }

    return DadosCnpjBrasilApi(
      razaoSocial: s('razao_social'),
      nomeFantasia: s('nome_fantasia'),
      cep: s('cep').replaceAll(RegExp(r'\D'), ''),
      logradouro: logradouro,
      numero: s('numero'),
      bairro: s('bairro'),
      municipio: s('municipio'),
      uf: s('uf').toUpperCase(),
    );
  }
}

class BrasilApiCnpjService {
  /// [cnpj] deve conter exatamente 14 digitos. Retorna null se o CNPJ nao existir (404).
  static Future<DadosCnpjBrasilApi?> consultar(String cnpj) async {
    final digitos = cnpj.replaceAll(RegExp(r'\D'), '');
    if (digitos.length != 14) {
      return null;
    }
    final uri = Uri.parse('https://brasilapi.com.br/api/cnpj/v1/$digitos');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw StateError('BrasilAPI retornou HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Resposta da BrasilAPI em formato inesperado.');
    }
    return DadosCnpjBrasilApi.fromMap(decoded);
  }
}
