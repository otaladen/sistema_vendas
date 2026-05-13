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
  });

  final String cep;
  final String logradouro;
  final String bairro;
  final String cidade;
  final String uf;

  static DadosCepBrasilApi fromMap(Map<String, dynamic> map) {
    String s(String key) => (map[key] ?? '').toString().trim();

    return DadosCepBrasilApi(
      cep: s('cep').replaceAll(RegExp(r'\D'), ''),
      logradouro: s('street'),
      bairro: s('neighborhood'),
      cidade: s('city'),
      uf: s('state').toUpperCase(),
    );
  }
}

class BrasilApiCepService {
  /// [cep] com 8 digitos. Retorna null se o CEP nao existir (404).
  static Future<DadosCepBrasilApi?> consultar(String cep) async {
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
    return DadosCepBrasilApi.fromMap(decoded);
  }
}
