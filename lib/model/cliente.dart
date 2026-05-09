import 'dart:convert';

import 'package:objectbox/objectbox.dart';

class EnderecoCliente {
  EnderecoCliente({
    this.rotulo = '',
    this.cep = '',
    this.endereco = '',
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.referencia = '',
  });

  final String rotulo;
  final String cep;
  final String endereco;
  final String numero;
  final String bairro;
  final String cidade;
  final String uf;
  final String referencia;

  factory EnderecoCliente.fromMap(Map<String, dynamic> map) {
    return EnderecoCliente(
      rotulo: (map['rotulo'] ?? '').toString(),
      cep: (map['cep'] ?? '').toString(),
      endereco: (map['endereco'] ?? '').toString(),
      numero: (map['numero'] ?? '').toString(),
      bairro: (map['bairro'] ?? '').toString(),
      cidade: (map['cidade'] ?? '').toString(),
      uf: (map['uf'] ?? '').toString(),
      referencia: (map['referencia'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rotulo': rotulo,
      'cep': cep,
      'endereco': endereco,
      'numero': numero,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'referencia': referencia,
    };
  }

  bool get temDados =>
      rotulo.trim().isNotEmpty ||
      cep.trim().isNotEmpty ||
      endereco.trim().isNotEmpty ||
      numero.trim().isNotEmpty ||
      bairro.trim().isNotEmpty ||
      cidade.trim().isNotEmpty ||
      uf.trim().isNotEmpty ||
      referencia.trim().isNotEmpty;

  String resumo() {
    final partes = <String>[];
    final ruaNumero = [
      endereco.trim(),
      numero.trim(),
    ].where((parte) => parte.isNotEmpty).join(', ');
    if (ruaNumero.isNotEmpty) partes.add(ruaNumero);
    if (bairro.trim().isNotEmpty) partes.add(bairro.trim());
    final cidadeUf = [
      cidade.trim(),
      uf.trim(),
    ].where((parte) => parte.isNotEmpty).join(' - ');
    if (cidadeUf.isNotEmpty) partes.add(cidadeUf);
    if (cep.trim().isNotEmpty) partes.add('CEP: ${cep.trim()}');
    return partes.join(' | ');
  }
}

@Entity()
class Cliente {
  Cliente({
    this.id = 0,
    this.tipoPessoa = 'fisica',
    required this.nomeRazao,
    this.nomeFantasia = '',
    this.documento = '',
    this.inscricaoEstadual = '',
    this.telefone = '',
    this.whatsapp = '',
    this.email = '',
    this.cep = '',
    this.endereco = '',
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.referencia = '',
    this.enderecosJson = '',
    this.limiteCredito = 0,
    this.observacoes = '',
    this.ativo = true,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();

  @Id()
  int id;

  String tipoPessoa; // fisica | juridica
  String nomeRazao;
  String nomeFantasia;
  String documento; // CPF/CNPJ
  String inscricaoEstadual;
  String telefone;
  String whatsapp;
  String email;
  String cep;
  String endereco;
  String numero;
  String bairro;
  String cidade;
  String uf;
  String referencia;
  String enderecosJson;
  double limiteCredito;
  String observacoes;
  bool ativo;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  List<EnderecoCliente> listarEnderecos() {
    final result = <EnderecoCliente>[];
    if (enderecosJson.trim().isNotEmpty) {
      try {
        final raw = jsonDecode(enderecosJson);
        if (raw is List) {
          for (final item in raw) {
            if (item is Map<String, dynamic>) {
              final endereco = EnderecoCliente.fromMap(item);
              if (endereco.temDados) {
                result.add(endereco);
              }
            } else if (item is Map) {
              final endereco = EnderecoCliente.fromMap(
                item.map((key, value) => MapEntry(key.toString(), value)),
              );
              if (endereco.temDados) {
                result.add(endereco);
              }
            }
          }
        }
      } catch (_) {
        // Mantem fallback legado quando json estiver invalido.
      }
    }
    if (result.isEmpty) {
      final legado = EnderecoCliente(
        cep: cep,
        endereco: endereco,
        numero: numero,
        bairro: bairro,
        cidade: cidade,
        uf: uf,
        referencia: referencia,
      );
      if (legado.temDados) {
        result.add(legado);
      }
    }
    return result;
  }

  void definirEnderecos(List<EnderecoCliente> enderecos) {
    final filtrados = enderecos.where((e) => e.temDados).toList();
    if (filtrados.isEmpty) {
      enderecosJson = '';
      cep = '';
      endereco = '';
      numero = '';
      bairro = '';
      cidade = '';
      uf = '';
      referencia = '';
      return;
    }
    final principal = filtrados.first;
    cep = principal.cep.trim();
    endereco = principal.endereco.trim();
    numero = principal.numero.trim();
    bairro = principal.bairro.trim();
    cidade = principal.cidade.trim();
    uf = principal.uf.trim().toUpperCase();
    referencia = principal.referencia.trim();
    enderecosJson = jsonEncode(
      filtrados
          .map(
            (e) => EnderecoCliente(
              rotulo: e.rotulo.trim(),
              cep: e.cep.trim(),
              endereco: e.endereco.trim(),
              numero: e.numero.trim(),
              bairro: e.bairro.trim(),
              cidade: e.cidade.trim(),
              uf: e.uf.trim().toUpperCase(),
              referencia: e.referencia.trim(),
            ).toMap(),
          )
          .toList(),
    );
  }
}
