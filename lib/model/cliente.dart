import 'dart:convert';

import 'package:objectbox/objectbox.dart';

import '../domain/cliente_cadastro.dart';

class EnderecoCliente {
  EnderecoCliente({
    this.tipo = 'principal',
    this.rotulo = '',
    this.nomeObra = '',
    this.padraoCarreto = false,
    this.cep = '',
    this.endereco = '',
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.referencia = '',
    this.codigoIbge = '',
  });

  /// principal | obra | entrega | cobranca
  final String tipo;
  final String rotulo;
  final String nomeObra;
  final bool padraoCarreto;
  final String cep;
  final String endereco;
  final String numero;
  final String bairro;
  final String cidade;
  final String uf;
  final String referencia;

  /// Codigo IBGE do municipio (7 digitos) para NF-e.
  final String codigoIbge;

  factory EnderecoCliente.fromMap(Map<String, dynamic> map) {
    return EnderecoCliente(
      tipo: ClienteCadastro.normalizarTipoEndereco(
        (map['tipo'] ?? map['rotulo'] ?? '').toString(),
      ),
      rotulo: (map['rotulo'] ?? '').toString(),
      nomeObra: (map['nomeObra'] ?? '').toString(),
      padraoCarreto: map['padraoCarreto'] == true,
      cep: (map['cep'] ?? '').toString(),
      endereco: (map['endereco'] ?? '').toString(),
      numero: (map['numero'] ?? '').toString(),
      bairro: (map['bairro'] ?? '').toString(),
      cidade: (map['cidade'] ?? '').toString(),
      uf: (map['uf'] ?? '').toString(),
      referencia: (map['referencia'] ?? '').toString(),
      codigoIbge: (map['codigoIbge'] ?? '').toString().replaceAll(
        RegExp(r'\D'),
        '',
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo,
      'rotulo': rotulo,
      'nomeObra': nomeObra,
      'padraoCarreto': padraoCarreto,
      'cep': cep,
      'endereco': endereco,
      'numero': numero,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'referencia': referencia,
      if (codigoIbge.trim().isNotEmpty) 'codigoIbge': codigoIbge,
    };
  }

  bool get temDados =>
      cep.trim().isNotEmpty ||
      endereco.trim().isNotEmpty ||
      numero.trim().isNotEmpty ||
      bairro.trim().isNotEmpty ||
      cidade.trim().isNotEmpty ||
      uf.trim().isNotEmpty ||
      referencia.trim().isNotEmpty ||
      nomeObra.trim().isNotEmpty;

  String tituloExibicao() {
    final tipoRotulo = ClienteCadastro.rotuloTipoEndereco(tipo);
    if (nomeObra.trim().isNotEmpty) {
      return '$tipoRotulo — ${nomeObra.trim()}';
    }
    if (rotulo.trim().isNotEmpty && rotulo.trim().toLowerCase() != tipo) {
      return '$tipoRotulo — ${rotulo.trim()}';
    }
    return tipoRotulo;
  }

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
    this.rg = '',
    this.dataNascimento,
    this.sexo = '',
    this.inscricaoEstadual = '',
    this.inscricaoMunicipal = '',
    this.indicadorIe = '',
    this.telefone = '',
    this.whatsapp = '',
    this.email = '',
    this.contatoPrincipalNome = '',
    this.contatoPrincipalCargo = '',
    this.cep = '',
    this.endereco = '',
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.referencia = '',
    this.enderecosJson = '',
    this.codigoInterno = '',
    this.segmento = '',
    this.categoriaComercial = '',
    this.vendedorResponsavelId = 0,
    this.tabelaPrecoPadrao = 'preco1',
    this.prazoPagamentoDias = 0,
    this.bloqueadoFiado = false,
    this.motivoBloqueio = '',
    this.limiteCredito = 0,
    this.observacoes = '',
    this.ocupacao = '',
    this.origemCadastro = '',
    this.ativo = true,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
  })  : criadoEm = criadoEm ?? DateTime.now(),
        atualizadoEm = atualizadoEm ?? DateTime.now();

  @Id(assignable: true)
  int id;

  String tipoPessoa; // fisica | juridica

  @Index()
  String codigoInterno;

  /// consumidor | construtor | revenda | governo
  @Index()
  String segmento;

  String categoriaComercial; // A | B | C

  int vendedorResponsavelId;

  /// preco1 | preco2 | preco3
  String tabelaPrecoPadrao;

  int prazoPagamentoDias;

  bool bloqueadoFiado;

  String motivoBloqueio;

  @Index()
  String nomeRazao;

  @Index()
  String nomeFantasia;

  @Index()
  String documento;

  @Index()
  String rg;

  @Property(type: PropertyType.dateUtc)
  DateTime? dataNascimento;

  String sexo;
  String inscricaoEstadual;
  String inscricaoMunicipal;

  /// contribuinte | isento | nao_contribuinte
  String indicadorIe;

  @Index()
  String telefone;

  @Index()
  String whatsapp;

  @Index()
  String email;

  String contatoPrincipalNome;
  String contatoPrincipalCargo;

  String cep;
  String endereco;
  String numero;
  String bairro;

  @Index()
  String cidade;

  String uf;
  String referencia;
  String enderecosJson;
  double limiteCredito;
  String observacoes;

  @Index()
  String ocupacao;

  String origemCadastro;

  bool ativo;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;

  @Property(type: PropertyType.dateUtc)
  DateTime atualizadoEm;

  String get documentoFormatado => documento;

  String rotuloExibicao() {
    final fantasia = nomeFantasia.trim();
    if (fantasia.isNotEmpty && fantasia != nomeRazao.trim()) {
      return '$nomeRazao ($fantasia)';
    }
    return nomeRazao.trim();
  }

  List<EnderecoCliente> listarEnderecos() {
    final result = <EnderecoCliente>[];
    if (enderecosJson.trim().isNotEmpty) {
      try {
        final raw = jsonDecode(enderecosJson);
        if (raw is List) {
          for (final item in raw) {
            if (item is Map<String, dynamic>) {
              final endereco = EnderecoCliente.fromMap(item);
              if (endereco.temDados) result.add(endereco);
            } else if (item is Map) {
              final endereco = EnderecoCliente.fromMap(
                item.map((key, value) => MapEntry(key.toString(), value)),
              );
              if (endereco.temDados) result.add(endereco);
            }
          }
        }
      } catch (_) {
        // Mantem fallback legado quando json estiver invalido.
      }
    }
    if (result.isEmpty) {
      final legado = EnderecoCliente(
        tipo: 'principal',
        cep: cep,
        endereco: endereco,
        numero: numero,
        bairro: bairro,
        cidade: cidade,
        uf: uf,
        referencia: referencia,
      );
      if (legado.temDados) result.add(legado);
    }
    return result;
  }

  /// Endereco usado no PDV para carreto: padraoCarreto, senao tipo entrega, senao principal.
  EnderecoCliente? enderecoPadraoEntrega() {
    final lista = listarEnderecos();
    if (lista.isEmpty) return null;
    for (final e in lista) {
      if (e.padraoCarreto) return e;
    }
    for (final e in lista) {
      if (e.tipo == 'entrega') return e;
    }
    for (final e in lista) {
      if (e.tipo == 'principal') return e;
    }
    return lista.first;
  }

  int indiceEnderecoPadraoEntrega() {
    final lista = listarEnderecos();
    if (lista.isEmpty) return 0;
    final padrao = enderecoPadraoEntrega();
    if (padrao == null) return 0;
    final idx = lista.indexOf(padrao);
    return idx < 0 ? 0 : idx;
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

    // Garante no maximo um padraoCarreto.
    var marcouPadrao = false;
    final normalizados = <EnderecoCliente>[];
    for (final e in filtrados) {
      var padrao = e.padraoCarreto;
      if (padrao) {
        if (marcouPadrao) {
          padrao = false;
        } else {
          marcouPadrao = true;
        }
      }
      normalizados.add(
        EnderecoCliente(
          tipo: ClienteCadastro.normalizarTipoEndereco(e.tipo),
          rotulo: e.rotulo.trim(),
          nomeObra: e.nomeObra.trim(),
          padraoCarreto: padrao,
          cep: e.cep.trim(),
          endereco: e.endereco.trim(),
          numero: e.numero.trim(),
          bairro: e.bairro.trim(),
          cidade: e.cidade.trim(),
          uf: e.uf.trim().toUpperCase(),
          referencia: e.referencia.trim(),
          codigoIbge: e.codigoIbge.trim(),
        ),
      );
    }
    if (!marcouPadrao) {
      final idxEntrega = normalizados.indexWhere((e) => e.tipo == 'entrega');
      final idx = idxEntrega >= 0
          ? idxEntrega
          : normalizados.indexWhere((e) => e.tipo == 'principal');
      if (idx >= 0) {
        final e = normalizados[idx];
        normalizados[idx] = EnderecoCliente(
          tipo: e.tipo,
          rotulo: e.rotulo,
          nomeObra: e.nomeObra,
          padraoCarreto: true,
          cep: e.cep,
          endereco: e.endereco,
          numero: e.numero,
          bairro: e.bairro,
          cidade: e.cidade,
          uf: e.uf,
          referencia: e.referencia,
          codigoIbge: e.codigoIbge,
        );
      }
    }

    final principal = normalizados.firstWhere(
      (e) => e.tipo == 'principal',
      orElse: () => normalizados.first,
    );
    cep = principal.cep;
    endereco = principal.endereco;
    numero = principal.numero;
    bairro = principal.bairro;
    cidade = principal.cidade;
    uf = principal.uf;
    referencia = principal.referencia;
    enderecosJson = jsonEncode(normalizados.map((e) => e.toMap()).toList());
  }
}
