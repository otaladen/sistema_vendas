import 'dart:io';

import '../domain/fiscal/nota_fiscal_entrada_fechamento_item.dart';
import '../model/cliente.dart';
import '../domain/fiscal/nota_fiscal_fechamento_item.dart';
import '../services/fechamento_xml_tributos_parser.dart';
import '../services/focus_nfe_service.dart';
import '../services/xml_nfe_parser_service.dart';
import 'nfe_entrada_repository.dart';
import 'nfe_entrada_xml_store.dart';
import 'nfce_saida_xml_store.dart';
import 'nfe_saida_fiscal_store.dart';
import 'nfe_saida_xml_store.dart';
import 'venda_repository.dart';
import '../objectbox.g.dart';

/// Leitura local do cenario fiscal do mes (saidas + entradas). Sem estoque/caixa.
class FechamentoFiscalLocalSource {
  FechamentoFiscalLocalSource({
    required String storeDirectoryPath,
    VendaRepository? vendaRepository,
    NfeEntradaRepository? entradaRepository,
  })  : _nfeStore = NfeSaidaFiscalStore(storeDirectoryPath),
        _xmlEntradaStore = NfeEntradaXmlStore(storeDirectoryPath),
        _xmlSaidaStore = NfeSaidaXmlStore(storeDirectoryPath),
        _xmlNfceSaidaStore = NfceSaidaXmlStore(storeDirectoryPath),
        _vendaRepository = vendaRepository,
        _entradaRepository = entradaRepository;

  factory FechamentoFiscalLocalSource.fromVendaRepository(
    VendaRepository vendaRepository,
  ) {
    return FechamentoFiscalLocalSource(
      storeDirectoryPath: vendaRepository.objectBox.storeDirectoryPath,
      vendaRepository: vendaRepository,
      entradaRepository: NfeEntradaRepository(vendaRepository.objectBox),
    );
  }

  final NfeSaidaFiscalStore _nfeStore;
  final NfeEntradaXmlStore _xmlEntradaStore;
  final NfeSaidaXmlStore _xmlSaidaStore;
  final NfceSaidaXmlStore _xmlNfceSaidaStore;
  final VendaRepository? _vendaRepository;
  final NfeEntradaRepository? _entradaRepository;

  /// Saidas fiscais do periodo (autorizadas, canceladas e com evento).
  List<NotaFiscalFechamentoItem> listarSaidasNoPeriodo({
    required DateTime inicio,
    required DateTime fim,
  }) {
    final inicioUtc = DateTime(inicio.year, inicio.month, inicio.day).toUtc();
    final fimUtc = DateTime(
      fim.year,
      fim.month,
      fim.day,
      23,
      59,
      59,
      999,
    ).toUtc();

    final notas = <NotaFiscalFechamentoItem>[];
    notas.addAll(_listarNfe55NoPeriodo(inicioUtc, fimUtc));
    notas.addAll(_listarNfce65NoPeriodo(inicioUtc, fimUtc));
    notas.sort((a, b) => b.dataEmissao.compareTo(a.dataEmissao));
    return notas;
  }

  /// NF-e de compra importadas no periodo ([dataHoraImportacao]).
  List<NotaFiscalEntradaFechamentoItem> listarEntradasNoPeriodo({
    required DateTime inicio,
    required DateTime fim,
  }) {
    final repo = _entradaRepository;
    if (repo == null) return [];

    final inicioUtc = DateTime(inicio.year, inicio.month, inicio.day).toUtc();
    final fimUtc = DateTime(
      fim.year,
      fim.month,
      fim.day,
      23,
      59,
      59,
      999,
    ).toUtc();

    final lista = <NotaFiscalEntradaFechamentoItem>[];
    for (final reg in repo.listarImportacoesNoPeriodo(
      inicioUtc: inicioUtc,
      fimUtc: fimUtc,
    )) {
      final chave = reg.chaveAcesso.replaceAll(RegExp(r'\D'), '');
      final xmlPath = _xmlEntradaStore.arquivoDaChave(chave).path;
      var valor = 0.0;
      var serie = '';
      final xml = _xmlEntradaStore.lerXml(chave);
      if (xml != null && xml.isNotEmpty) {
        try {
          final parsed = XmlParserService.parseNfeXmlString(xml);
          valor = parsed.valorTotalNota;
          if (chave.length >= 25) {
            serie = chave.substring(22, 25);
          }
        } catch (_) {}
      }

      lista.add(
        NotaFiscalEntradaFechamentoItem(
          dataEmissao: reg.dataEmissao.toLocal(),
          chaveAcesso: reg.chaveAcesso,
          cnpjFornecedor: reg.cnpjFornecedor,
          razaoSocialFornecedor: reg.nomeFornecedor,
          numero: reg.numeroNota > 0 ? reg.numeroNota.toString() : '',
          serie: serie,
          valorTotal: valor,
          dataEntradaSistema: reg.dataHoraImportacao.toLocal(),
          caminhoXmlLocal: _xmlEntradaStore.existe(chave) ? xmlPath : '',
        ),
      );
    }
    return lista;
  }

  List<NotaFiscalFechamentoItem> _listarNfe55NoPeriodo(
    DateTime inicioUtc,
    DateTime fimUtc,
  ) {
    final lista = <NotaFiscalFechamentoItem>[];
    for (final reg in _nfeStore.listar()) {
      if (!reg.incluirNoFechamentoContabil) continue;
      final em = reg.emitidaEm.toUtc();
      if (em.isBefore(inicioUtc) || em.isAfter(fimUtc)) continue;

      lista.add(
        NotaFiscalFechamentoItem(
          modelo: '55',
          dataEmissao: reg.emitidaEm,
          numero: reg.numero,
          serie: reg.serie,
          chaveAcesso: reg.chaveNfe,
          documentoDestinatario: _documentoDestinatarioVenda(reg.vendaId),
          valorTotal: reg.valorTotal,
          status: reg.rotuloStatus,
          statusFocus: reg.statusFocus,
          urlXml: reg.urlXml.trim(),
          referenciaFocus: reg.referenciaFocus,
          vendaId: reg.vendaId,
          razaoSocialDestinatario: reg.clienteNome,
          protocoloSefaz: reg.protocolo,
          mensagemSefaz: reg.mensagemSefaz,
          urlXmlEventoCancelamento: reg.urlXmlEventoCancelamento.trim(),
          vendaOperacionalCancelada: _vendaOperacionalCancelada(reg.vendaId),
          incluirNoZip: reg.urlXml.trim().isNotEmpty ||
              reg.urlXmlEventoCancelamento.trim().isNotEmpty ||
              (reg.chaveNfe.replaceAll(RegExp(r'\D'), '').length == 44 &&
                  _xmlSaidaStore.existe(reg.chaveNfe)),
        ),
      );
    }
    return lista;
  }

  List<NotaFiscalFechamentoItem> _listarNfce65NoPeriodo(
    DateTime inicioUtc,
    DateTime fimUtc,
  ) {
    final repo = _vendaRepository;
    if (repo == null) return [];

    final lista = <NotaFiscalFechamentoItem>[];
    final db = repo.objectBox;
    final q = db.vendaBox
        .query(
          Venda_.nfceChaveAcesso
              .notEquals('')
              .and(Venda_.nfceEmitidaEm.notNull())
              .and(Venda_.nfceEmitidaEm.greaterOrEqualDate(inicioUtc))
              .and(Venda_.nfceEmitidaEm.lessOrEqualDate(fimUtc)),
        )
        .build();
    try {
      for (final venda in q.find()) {
        if (venda.nfceChaveAcesso.trim().isEmpty) continue;
        final em = venda.nfceEmitidaEm;
        if (em == null) continue;
        final cliente = venda.cliente.target;
        final statusFocus = venda.nfceStatusFocus.trim().isNotEmpty
            ? venda.nfceStatusFocus.trim()
            : 'autorizado';

        lista.add(
          NotaFiscalFechamentoItem(
            modelo: '65',
            dataEmissao: em.toLocal(),
            numero: venda.nfceNumero,
            serie: venda.nfceSerie,
            chaveAcesso: venda.nfceChaveAcesso,
            documentoDestinatario: _documentoCliente(cliente),
            valorTotal: venda.total,
            status: _rotuloStatusNfce(statusFocus),
            statusFocus: statusFocus,
            urlXml: venda.nfceUrlXml.trim(),
            referenciaFocus: FocusNfeService.referenciaVendaNfce(venda),
            vendaId: venda.id,
            razaoSocialDestinatario: cliente?.nomeRazao ?? '',
            protocoloSefaz: venda.nfceProtocolo,
            urlXmlEventoCancelamento: venda.nfceUrlXmlCancelamento.trim(),
            vendaOperacionalCancelada: venda.cancelada,
            incluirNoZip: _xmlNfceSaidaStore.existe(venda.nfceChaveAcesso) ||
                venda.nfceUrlXml.trim().isNotEmpty,
          ),
        );
      }
    } finally {
      q.close();
    }
    return lista;
  }

  /// Aplica tributos parseados do XML ao item (apos download).
  NotaFiscalFechamentoItem comTributosDoXml(
    NotaFiscalFechamentoItem item,
    String xmlText,
  ) {
    return NotaFiscalFechamentoItem(
      modelo: item.modelo,
      dataEmissao: item.dataEmissao,
      numero: item.numero,
      serie: item.serie,
      chaveAcesso: item.chaveAcesso,
      documentoDestinatario: item.documentoDestinatario,
      valorTotal: item.valorTotal,
      status: item.status,
      statusFocus: item.statusFocus,
      urlXml: item.urlXml,
      referenciaFocus: item.referenciaFocus,
      vendaId: item.vendaId,
      razaoSocialDestinatario: item.razaoSocialDestinatario,
      protocoloSefaz: item.protocoloSefaz,
      mensagemSefaz: item.mensagemSefaz,
      urlXmlEventoCancelamento: item.urlXmlEventoCancelamento,
      tributos: FechamentoXmlTributosParser.parse(xmlText),
      vendaOperacionalCancelada: item.vendaOperacionalCancelada,
      incluirNoZip: item.incluirNoZip,
    );
  }

  File? arquivoXmlEntradaLocal(String chaveAcesso) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final f = _xmlEntradaStore.arquivoDaChave(chave);
    return f.existsSync() ? f : null;
  }

  File? arquivoXmlNfceSaidaLocal(
    String chaveAcesso, {
    bool cancelada = false,
  }) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44) return null;
    final f = _xmlNfceSaidaStore.arquivoDaChave(chave, cancelada: cancelada);
    return f.existsSync() ? f : null;
  }

  File? arquivoXmlSaidaLocal(
    String chaveAcesso, {
    bool cancelada = false,
  }) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44) return null;
    final f = _xmlSaidaStore.arquivoDaChave(chave, cancelada: cancelada);
    return f.existsSync() ? f : null;
  }

  static String _rotuloStatusNfce(String statusFocus) {
    final s = statusFocus.toLowerCase();
    if (s == 'cancelado') return 'Cancelada';
    if (s == 'erro_autorizacao' || s == 'denegado') return 'Rejeitada';
    return 'Autorizada';
  }

  bool _vendaOperacionalCancelada(int vendaId) {
    final repo = _vendaRepository;
    if (repo == null || vendaId <= 0) return false;
    return repo.obterPorId(vendaId)?.cancelada ?? false;
  }

  String _documentoDestinatarioVenda(int vendaId) {
    final repo = _vendaRepository;
    if (repo == null || vendaId <= 0) return '';
    final venda = repo.obterPorId(vendaId);
    return _documentoCliente(venda?.cliente.target);
  }

  static String _documentoCliente(Cliente? cliente) {
    if (cliente == null) return '';
    return cliente.documento.replaceAll(RegExp(r'\D'), '');
  }
}
