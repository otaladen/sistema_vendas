import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/via_cep_endereco_similaridade.dart';

/// Resultado de busca por logradouro na ViaCEP
/// (https://viacep.com.br/ws/{UF}/{Cidade}/{Logradouro}/json/).
class ViaCepEnderecoResultado {
  const ViaCepEnderecoResultado({
    required this.cep,
    required this.logradouro,
    required this.bairro,
    required this.cidade,
    required this.uf,
    this.complemento = '',
    this.codigoIbge = '',
  });

  final String cep;
  final String logradouro;
  final String bairro;
  final String cidade;
  final String uf;
  final String complemento;
  final String codigoIbge;

  static ViaCepEnderecoResultado fromMap(Map<String, dynamic> map) {
    String s(String key) => (map[key] ?? '').toString().trim();
    final ibge = s('ibge').replaceAll(RegExp(r'\D'), '');
    return ViaCepEnderecoResultado(
      cep: s('cep').replaceAll(RegExp(r'\D'), ''),
      logradouro: s('logradouro'),
      bairro: s('bairro'),
      cidade: s('localidade'),
      uf: s('uf').toUpperCase(),
      complemento: s('complemento'),
      codigoIbge: ibge,
    );
  }

  String get rotuloLista {
    final cepFmt = cep.length == 8
        ? '${cep.substring(0, 5)}-${cep.substring(5)}'
        : cep;
    final partes = <String>[
      if (logradouro.isNotEmpty) logradouro,
      if (bairro.isNotEmpty) bairro,
      cepFmt,
    ];
    return partes.join(' · ');
  }
}

class ViaCepEnderecoService {
  /// Busca CEPs pelo logradouro. [uf] com 2 letras; [cidade] e [logradouro]
  /// com pelo menos 3 caracteres (regra da ViaCEP).
  static Future<List<ViaCepEnderecoResultado>> buscarPorLogradouro({
    required String uf,
    required String cidade,
    required String logradouro,
  }) async {
    final ufNorm = uf.trim().toUpperCase();
    final cidadeNorm = cidade.trim();
    final logNorm = logradouro.trim();
    if (ufNorm.length != 2) {
      throw ArgumentError('UF invalida.');
    }
    if (cidadeNorm.length < 3) {
      throw ArgumentError('Informe pelo menos 3 letras da cidade.');
    }
    if (logNorm.length < 3) {
      throw ArgumentError('Informe pelo menos 3 letras do endereco/rua.');
    }

    final path =
        '${Uri.encodeComponent(ufNorm)}/'
        '${Uri.encodeComponent(cidadeNorm)}/'
        '${Uri.encodeComponent(logNorm)}/json/';
    final uri = Uri.parse('https://viacep.com.br/ws/$path');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode == 400) {
      throw StateError('Parametros invalidos para busca de CEP por endereco.');
    }
    if (response.statusCode != 200) {
      throw StateError('ViaCEP retornou HTTP ${response.statusCode}.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      if (decoded['erro'] == true) {
        return [];
      }
      return [ViaCepEnderecoResultado.fromMap(decoded)];
    }
    if (decoded is! List) {
      throw StateError('Resposta da ViaCEP em formato inesperado.');
    }
    final out = <ViaCepEnderecoResultado>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      if (item['erro'] == true) continue;
      out.add(ViaCepEnderecoResultado.fromMap(item));
    }
    return out;
  }

  /// Varias tentativas de termo + ordenacao pelo endereco que o vendedor digitou.
  static Future<List<ViaCepEnderecoResultado>> buscarOpcoesParecidas({
    required String uf,
    required String cidade,
    required String logradouroReferencia,
    String bairroReferencia = '',
  }) async {
    final termos = termosBuscaLogradouroViaCep(logradouroReferencia);
    final vistos = <String>{};
    final acumulado = <ViaCepEnderecoResultado>[];

    for (final termo in termos) {
      final parte = await buscarPorLogradouro(
        uf: uf,
        cidade: cidade,
        logradouro: termo,
      );
      for (final r in parte) {
        final chave = '${r.cep}|${r.logradouro}|${r.bairro}';
        if (vistos.add(chave)) acumulado.add(r);
      }
      if (acumulado.length >= 50) break;
    }

    return ordenarEnderecosPorSimilaridade(
      lista: acumulado,
      logradouroReferencia: logradouroReferencia,
      bairroReferencia: bairroReferencia,
    );
  }
}
