import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/fiscal/nfe_carta_correcao_registro.dart';

/// Registro local de NF-e de saida (modelo 55) — painel fiscal, sem estoque.
class NfeSaidaFiscalRegistro {
  NfeSaidaFiscalRegistro({
    required this.id,
    required this.vendaId,
    required this.numeroOrcamento,
    required this.clienteNome,
    required this.referenciaFocus,
    required this.statusFocus,
    required this.emitidaEm,
    this.statusSefaz = '',
    this.chaveNfe = '',
    this.numero = '',
    this.serie = '',
    this.protocolo = '',
    this.urlDanfe = '',
    this.urlXml = '',
    this.urlXmlEventoCancelamento = '',
    this.mensagemSefaz = '',
    this.modalidadeFrete = 0,
    this.placaVeiculo = '',
    this.volumes = 0,
    this.pesoBrutoKg = 0,
    this.valorTotal = 0,
    List<NfeCartaCorrecaoRegistro>? cartasCorrecao,
  }) : cartasCorrecao = List<NfeCartaCorrecaoRegistro>.from(
          cartasCorrecao ?? const [],
        );

  final String id;
  final int vendaId;
  final int numeroOrcamento;
  final String clienteNome;
  final String referenciaFocus;
  final String statusFocus;
  final DateTime emitidaEm;
  final String statusSefaz;
  final String chaveNfe;
  final String numero;
  final String serie;
  final String protocolo;
  final String urlDanfe;
  final String urlXml;
  final String urlXmlEventoCancelamento;
  final String mensagemSefaz;
  final int modalidadeFrete;
  final String placaVeiculo;
  final int volumes;
  final double pesoBrutoKg;
  final double valorTotal;
  final List<NfeCartaCorrecaoRegistro> cartasCorrecao;

  NfeCartaCorrecaoRegistro? get ultimaCartaCorrecao =>
      cartasCorrecao.isEmpty ? null : cartasCorrecao.last;

  int get numeroCartaCorrecao => ultimaCartaCorrecao?.numeroSequencia ?? 0;

  String get urlPdfCartaCorrecao => ultimaCartaCorrecao?.urlPdf ?? '';

  String get urlXmlCartaCorrecao => ultimaCartaCorrecao?.urlXml ?? '';

  int get totalCartasCorrecao => cartasCorrecao.length;

  int get cartasCorrecaoProcessando =>
      cartasCorrecao.where((c) => c.processando).length;

  bool get cancelada =>
      statusFocus == 'cancelado' ||
      statusSefaz == '135' ||
      statusSefaz == '101' ||
      mensagemSefaz.toLowerCase().contains('cancelad');

  bool get autorizada =>
      !cancelada &&
      (statusFocus == 'autorizado' || statusSefaz == '100');

  bool get processando => statusFocus == 'processando_autorizacao';

  bool get rejeitada =>
      !autorizada &&
      !cancelada &&
      !processando &&
      (statusFocus == 'erro_autorizacao' || statusFocus == 'denegado');

  /// Incluida no fechamento contabil (autorizada, cancelada, rejeitada ou evento).
  bool get incluirNoFechamentoContabil =>
      autorizada ||
      cancelada ||
      rejeitada ||
      urlXmlEventoCancelamento.trim().isNotEmpty ||
      cartasCorrecao.isNotEmpty;

  String get rotuloStatus {
    if (cancelada) return 'Cancelada';
    if (autorizada) return 'Autorizada';
    if (processando) return 'Processando';
    if (rejeitada) return 'Rejeitada';
    if (statusFocus.isNotEmpty) return statusFocus;
    return 'Desconhecido';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'vendaId': vendaId,
        'numeroOrcamento': numeroOrcamento,
        'clienteNome': clienteNome,
        'referenciaFocus': referenciaFocus,
        'statusFocus': statusFocus,
        'emitidaEm': emitidaEm.toUtc().toIso8601String(),
        'statusSefaz': statusSefaz,
        'chaveNfe': chaveNfe,
        'numero': numero,
        'serie': serie,
        'protocolo': protocolo,
        'urlDanfe': urlDanfe,
        'urlXml': urlXml,
        'urlXmlEventoCancelamento': urlXmlEventoCancelamento,
        'mensagemSefaz': mensagemSefaz,
        'modalidadeFrete': modalidadeFrete,
        'placaVeiculo': placaVeiculo,
        'volumes': volumes,
        'pesoBrutoKg': pesoBrutoKg,
        'valorTotal': valorTotal,
        if (cartasCorrecao.isNotEmpty)
          'cartasCorrecao': cartasCorrecao.map((c) => c.toJson()).toList(),
        if (numeroCartaCorrecao > 0) 'numeroCartaCorrecao': numeroCartaCorrecao,
        if (urlPdfCartaCorrecao.trim().isNotEmpty)
          'urlPdfCartaCorrecao': urlPdfCartaCorrecao,
        if (urlXmlCartaCorrecao.trim().isNotEmpty)
          'urlXmlCartaCorrecao': urlXmlCartaCorrecao,
      };

  factory NfeSaidaFiscalRegistro.fromJson(Map<String, dynamic> json) {
    var cartas = <NfeCartaCorrecaoRegistro>[];
    final rawCartas = json['cartasCorrecao'];
    if (rawCartas is List) {
      cartas = rawCartas
          .whereType<Map>()
          .map(
            (m) => NfeCartaCorrecaoRegistro.fromJson(
              m.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList();
    }
    final legadoSeq = ((json['numeroCartaCorrecao'] as num?) ?? 0).toInt();
    if (cartas.isEmpty && legadoSeq > 0) {
      cartas.add(
        NfeCartaCorrecaoRegistro(
          numeroSequencia: legadoSeq,
          textoCorrecao: '',
          urlPdf: (json['urlPdfCartaCorrecao'] ?? '').toString(),
          urlXml: (json['urlXmlCartaCorrecao'] ?? '').toString(),
        ),
      );
    }
    cartas.sort((a, b) => a.numeroSequencia.compareTo(b.numeroSequencia));

    return NfeSaidaFiscalRegistro(
      id: (json['id'] ?? '').toString(),
      vendaId: ((json['vendaId'] as num?) ?? 0).toInt(),
      numeroOrcamento: ((json['numeroOrcamento'] as num?) ?? 0).toInt(),
      clienteNome: (json['clienteNome'] ?? '').toString(),
      referenciaFocus: (json['referenciaFocus'] ?? '').toString(),
      statusFocus: (json['statusFocus'] ?? '').toString(),
      emitidaEm: DateTime.tryParse((json['emitidaEm'] ?? '').toString()) ??
          DateTime.now(),
      statusSefaz: (json['statusSefaz'] ?? '').toString(),
      chaveNfe: (json['chaveNfe'] ?? '').toString(),
      numero: (json['numero'] ?? '').toString(),
      serie: (json['serie'] ?? '').toString(),
      protocolo: (json['protocolo'] ?? '').toString(),
      urlDanfe: (json['urlDanfe'] ?? '').toString(),
      urlXml: (json['urlXml'] ?? '').toString(),
      urlXmlEventoCancelamento:
          (json['urlXmlEventoCancelamento'] ?? '').toString(),
      mensagemSefaz: (json['mensagemSefaz'] ?? '').toString(),
      modalidadeFrete: ((json['modalidadeFrete'] as num?) ?? 0).toInt(),
      placaVeiculo: (json['placaVeiculo'] ?? '').toString(),
      volumes: ((json['volumes'] as num?) ?? 0).toInt(),
      pesoBrutoKg: ((json['pesoBrutoKg'] as num?) ?? 0).toDouble(),
      valorTotal: ((json['valorTotal'] as num?) ?? 0).toDouble(),
      cartasCorrecao: cartas,
    );
  }

  NfeSaidaFiscalRegistro comNovaCartaCorrecao(NfeCartaCorrecaoRegistro cce) {
    final lista = [...cartasCorrecao];
    final idx = lista.indexWhere((c) => c.numeroSequencia == cce.numeroSequencia);
    if (idx >= 0) {
      lista[idx] = cce;
    } else {
      lista.add(cce);
    }
    lista.sort((a, b) => a.numeroSequencia.compareTo(b.numeroSequencia));
    return _copiar(cartasCorrecao: lista);
  }

  NfeSaidaFiscalRegistro comCartaCorrecao({
    required int numeroSequencia,
    String? urlPdf,
    String? urlXml,
    String textoCorrecao = '',
    String protocolo = '',
    String statusFocus = 'autorizado',
  }) {
    return comNovaCartaCorrecao(
      NfeCartaCorrecaoRegistro(
        numeroSequencia: numeroSequencia > 0 ? numeroSequencia : 1,
        textoCorrecao: textoCorrecao,
        urlPdf: urlPdf ?? '',
        urlXml: urlXml ?? '',
        protocolo: protocolo,
        statusFocus: statusFocus,
      ),
    );
  }

  NfeSaidaFiscalRegistro _copiar({
    List<NfeCartaCorrecaoRegistro>? cartasCorrecao,
  }) {
    return NfeSaidaFiscalRegistro(
      id: id,
      vendaId: vendaId,
      numeroOrcamento: numeroOrcamento,
      clienteNome: clienteNome,
      referenciaFocus: referenciaFocus,
      statusFocus: statusFocus,
      emitidaEm: emitidaEm,
      statusSefaz: statusSefaz,
      chaveNfe: chaveNfe,
      numero: numero,
      serie: serie,
      protocolo: protocolo,
      urlDanfe: urlDanfe,
      urlXml: urlXml,
      urlXmlEventoCancelamento: urlXmlEventoCancelamento,
      mensagemSefaz: mensagemSefaz,
      modalidadeFrete: modalidadeFrete,
      placaVeiculo: placaVeiculo,
      volumes: volumes,
      pesoBrutoKg: pesoBrutoKg,
      valorTotal: valorTotal,
      cartasCorrecao: cartasCorrecao ?? this.cartasCorrecao,
    );
  }
}

/// Persistencia JSON do historico de NF-e de saida (sem ObjectBox / sem estoque).
class NfeSaidaFiscalStore {
  NfeSaidaFiscalStore(this._storeDirectoryPath);

  final String _storeDirectoryPath;

  String get storeDirectoryPath => _storeDirectoryPath;
  static const String _arquivo = 'nfe_saida_emitidas_v1.json';

  File get _file => File(p.join(_storeDirectoryPath, _arquivo));

  List<NfeSaidaFiscalRegistro> listar() {
    if (!_file.existsSync()) return [];
    try {
      final raw = jsonDecode(_file.readAsStringSync());
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map(
            (e) => NfeSaidaFiscalRegistro.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList()
        ..sort((a, b) => b.emitidaEm.compareTo(a.emitidaEm));
    } catch (_) {
      return [];
    }
  }

  void gravar(NfeSaidaFiscalRegistro registro) {
    final todos = listar();
    final idx = todos.indexWhere((r) => r.id == registro.id);
    if (idx >= 0) {
      todos[idx] = registro;
    } else {
      todos.insert(0, registro);
    }
    _file.writeAsStringSync(
      jsonEncode(todos.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  NfeSaidaFiscalRegistro? obterPorReferencia(String referencia) {
    final ref = referencia.trim();
    if (ref.isEmpty) return null;
    for (final r in listar()) {
      if (r.referenciaFocus == ref) return r;
    }
    return null;
  }

  NfeSaidaFiscalRegistro? ultimaPorVenda(int vendaId) {
    for (final r in listar()) {
      if (r.vendaId == vendaId) return r;
    }
    return null;
  }

  /// Ultima NF-e 55 autorizada vinculada a [vendaId], se existir.
  NfeSaidaFiscalRegistro? ultimaAutorizadaPorVenda(int vendaId) {
    for (final r in listar()) {
      if (r.vendaId == vendaId && r.autorizada) return r;
    }
    return null;
  }

  /// IDs de vendas cuja NF-e 55 bate com numero, chave ou referencia Focus.
  List<int> buscarVendaIdsPorTexto(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return [];
    final lower = t.toLowerCase();
    final digitos = t.replaceAll(RegExp(r'\D'), '');
    final ids = <int>{};
    for (final r in listar()) {
      var ok = r.numero.contains(t) ||
          r.referenciaFocus.toLowerCase().contains(lower) ||
          r.chaveNfe.toLowerCase().contains(lower);
      if (!ok && digitos.length >= 4) {
        ok = r.numero.replaceAll(RegExp(r'\D'), '').contains(digitos) ||
            r.chaveNfe.replaceAll(RegExp(r'\D'), '').contains(digitos);
      }
      if (ok && r.vendaId > 0) ids.add(r.vendaId);
    }
    return ids.toList();
  }
}
