import 'dart:convert';

import 'package:http/http.dart' as http;

/// Endereco basico retornado por https://brasilapi.com.br/api/cep/v1/{cep}
class DadosCepBrasilApi {
  const DadosCepBrasilApi({
    required this.cep,
    required this.logradouro,
    required this.bairro,
    required this.cidade,
    required this.uf,
    this.codigoIbge = '',
  });

  final String cep;
  final String logradouro;
  final String bairro;
  final String cidade;
  final String uf;

  /// Codigo IBGE do municipio (7 digitos), quando disponivel na API.
  final String codigoIbge;

  static DadosCepBrasilApi fromMap(Map<String, dynamic> map) {
    String s(String key) => (map[key] ?? '').toString().trim();
    final ibge = s('city_ibge').replaceAll(RegExp(r'\D'), '');
    if (ibge.isEmpty) {
      final loc = map['location'];
      if (loc is Map) {
        final alt = (loc['city_ibge'] ?? loc['ibge'] ?? '').toString();
        if (alt.isNotEmpty) {
          return DadosCepBrasilApi(
            cep: s('cep').replaceAll(RegExp(r'\D'), ''),
            logradouro: s('street'),
            bairro: s('neighborhood'),
            cidade: s('city'),
            uf: s('state').toUpperCase(),
            codigoIbge: alt.replaceAll(RegExp(r'\D'), ''),
          );
        }
      }
    }

    return DadosCepBrasilApi(
      cep: s('cep').replaceAll(RegExp(r'\D'), ''),
      logradouro: s('street'),
      bairro: s('neighborhood'),
      cidade: s('city'),
      uf: s('state').toUpperCase(),
      codigoIbge: ibge,
    );
  }

  static DadosCepBrasilApi fromMapV1(Map<String, dynamic> map) {
    final base = fromMap(map);
    return DadosCepBrasilApi(
      cep: base.cep,
      logradouro: base.logradouro,
      bairro: base.bairro,
      cidade: base.cidade,
      uf: base.uf,
    );
  }
}

class BrasilApiCepService {
  /// [cep] com 8 digitos. Retorna null se o CEP nao existir (404).
  static Future<DadosCepBrasilApi?> consultar(String cep) async {
    final comIbge = await consultarComIbge(cep);
    if (comIbge != null) return comIbge;
    return _consultarV1(cep);
  }

  /// Preferencia API v2 (inclui codigo IBGE do municipio).
  static Future<DadosCepBrasilApi?> consultarComIbge(String cep) async {
    final digitos = cep.replaceAll(RegExp(r'\D'), '');
    if (digitos.length != 8) {
      return null;
    }
    final uri = Uri.parse('https://brasilapi.com.br/api/cep/v2/$digitos');
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      return _consultarV1(cep);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Resposta da BrasilAPI (CEP v2) em formato inesperado.');
    }
    return DadosCepBrasilApi.fromMap(decoded);
  }

  static Future<DadosCepBrasilApi?> _consultarV1(String cep) async {
    final digitos = cep.replaceAll(RegExp(r'\D'), '');
    if (digitos.length != 8) {
      return null;
    }
    final uri = Uri.parse('https://brasilapi.com.br/api/cep/v1/$digitos');
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw StateError('BrasilAPI CEP retornou HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Resposta da BrasilAPI (CEP) em formato inesperado.');
    }
    return DadosCepBrasilApi.fromMapV1(decoded);
  }
}
