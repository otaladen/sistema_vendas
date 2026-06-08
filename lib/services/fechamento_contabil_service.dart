import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../config/fiscal_config.dart';
import '../config/focus_nfe_runtime.dart';
import '../services/fiscal_config_store.dart';
import '../data/fechamento_fiscal_local_source.dart';
import '../data/nfe_inutilizacao_store.dart';
import '../domain/fiscal/nota_fiscal_entrada_fechamento_item.dart';
import '../domain/fiscal/nota_fiscal_fechamento_item.dart';
import 'fechamento_xlsx_builder.dart';
import 'focus_nfe_service.dart';

typedef FechamentoContabilProgressoCallback = void Function(
  int atual,
  int total,
  String mensagem,
);

class FechamentoContabilTotais {
  const FechamentoContabilTotais({
    required this.quantidadeSaidas,
    required this.quantidadeSaidasCanceladas,
    required this.valorSaidasAutorizadas,
    required this.valorSaidasCanceladas,
    required this.quantidadeEntradas,
    required this.valorEntradas,
    required this.xmlsBaixados,
    required this.xmlsFalha,
    required this.alertasVendaOperacional,
  });

  final int quantidadeSaidas;
  final int quantidadeSaidasCanceladas;
  final double valorSaidasAutorizadas;
  final double valorSaidasCanceladas;
  final int quantidadeEntradas;
  final double valorEntradas;
  final int xmlsBaixados;
  final int xmlsFalha;
  final int alertasVendaOperacional;
}

class FechamentoContabilResultado {
  const FechamentoContabilResultado({
    required this.mes,
    required this.ano,
    required this.saidas,
    required this.entradas,
    required this.totais,
    required this.zipBytes,
    required this.excelBytes,
    required this.errosDownload,
  });

  final int mes;
  final int ano;
  final List<NotaFiscalFechamentoItem> saidas;
  final List<NotaFiscalEntradaFechamentoItem> entradas;
  final FechamentoContabilTotais totais;
  final Uint8List zipBytes;
  final Uint8List excelBytes;
  final List<String> errosDownload;

  String get nomeBaseArquivo {
    final mm = mes.toString().padLeft(2, '0');
    return 'fechamento_contabilidade_${mm}_$ano';
  }
}

/// Exportacao contabil completa: saidas (autorizadas/canceladas), entradas, ZIP + Excel.
class FechamentoContabilService {
  FechamentoContabilService({
    required FechamentoFiscalLocalSource localSource,
    http.Client? httpClient,
    FocusNfeService? focusNfe,
  })  : _local = localSource,
        _http = httpClient ?? http.Client(),
        _focusNfe = focusNfe;

  final FechamentoFiscalLocalSource _local;
  final http.Client _http;
  final FocusNfeService? _focusNfe;

  static final DateFormat _fmtData = DateFormat('dd/MM/yyyy HH:mm');
  static final NumberFormat _fmtMoeda = NumberFormat('#,##0.00', 'pt_BR');

  ({DateTime inicio, DateTime fim}) periodoDoMesAno(int mes, int ano) {
    final m = mes.clamp(1, 12);
    final inicio = DateTime(ano, m, 1);
    final fim = DateTime(ano, m + 1, 0);
    return (inicio: inicio, fim: fim);
  }

  FechamentoContabilPacote listarPacoteFiscal(int mes, int ano) {
    final p = periodoDoMesAno(mes, ano);
    final saidas = _local.listarSaidasNoPeriodo(inicio: p.inicio, fim: p.fim);
    final entradas =
        _local.listarEntradasNoPeriodo(inicio: p.inicio, fim: p.fim);
    return FechamentoContabilPacote(saidas: saidas, entradas: entradas);
  }

  Future<FechamentoContabilResultado> gerarFechamento({
    required int mes,
    required int ano,
    FechamentoContabilProgressoCallback? onProgresso,
  }) async {
    final pacote = listarPacoteFiscal(mes, ano);
    if (pacote.saidas.isEmpty && pacote.entradas.isEmpty) {
      throw FechamentoContabilException(
        'Nenhum documento fiscal encontrado para ${_rotuloMesAno(mes, ano)}.',
      );
    }

    final periodo = periodoDoMesAno(mes, ano);
    final cceLocais = _local.listarCceLocaisNoPeriodo(
      inicio: periodo.inicio,
      fim: periodo.fim,
    );
    final inutilizacoes = _local.listarInutilizacoesNoPeriodo(
      inicio: periodo.inicio,
      fim: periodo.fim,
    );

    final erros = <String>[];
    final arquivosZip = <ArchiveFile>[];
    var xmlsOk = 0;
    var xmlsFalha = 0;

    final saidasEnriquecidas = <NotaFiscalFechamentoItem>[];
    final inutSucesso =
        inutilizacoes.where((i) => i.sucesso).length;
    final totalPassos = pacote.saidas.length +
        pacote.entradas.length +
        pacote.saidas.where((s) => s.urlXmlEventoCancelamento.isNotEmpty).length +
        cceLocais.length +
        inutSucesso;
    var passo = 0;

    for (final nota in pacote.saidas) {
      passo++;
      onProgresso?.call(
        passo,
        totalPassos > 0 ? totalPassos : 1,
        'Saida: baixando XML ${passo} de ${pacote.saidas.length}...',
      );

      var item = await _enriquecerSaidaComFocus(nota);
      final nome = item.nomeArquivoXml(canceladaSuffix: item.cancelada);
      try {
        final local = _local.arquivoXmlSaidaLocal(
          item.chaveAcesso,
          cancelada: item.cancelada,
        );
        List<int> bytes;
        var xmlTexto = '';
        if (local != null) {
          bytes = await local.readAsBytes();
          xmlTexto = String.fromCharCodes(bytes);
        } else {
          final url = await _resolverUrlXmlSaida(item);
          if (url.isEmpty) {
            xmlsFalha++;
            erros.add(
              '${item.modelo} nº ${item.numero.isEmpty ? "?" : item.numero} '
              '(${item.status}): URL do XML indisponivel.',
            );
            saidasEnriquecidas.add(item);
            continue;
          }
          final response = await _http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 90));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            xmlsFalha++;
            erros.add(
              '$nome: HTTP ${response.statusCode}',
            );
            saidasEnriquecidas.add(item);
            continue;
          }
          bytes = response.bodyBytes;
          xmlTexto = response.body;
        }
        if (xmlTexto.isNotEmpty) {
          item = _local.comTributosDoXml(item, xmlTexto);
        }
        arquivosZip.add(
          ArchiveFile('xml/$nome', bytes.length, bytes),
        );
        xmlsOk++;

        if (item.urlXmlEventoCancelamento.trim().isNotEmpty) {
          passo++;
          onProgresso?.call(
            passo,
            totalPassos,
            'Evento cancelamento: ${item.numero}...',
          );
          final ev = await _baixarBytes(item.urlXmlEventoCancelamento);
          if (ev != null && ev.isNotEmpty) {
            arquivosZip.add(
              ArchiveFile(
                'xml/eventos/${item.nomeArquivoEventoCancelamento}',
                ev.length,
                ev,
              ),
            );
            xmlsOk++;
          } else {
            xmlsFalha++;
            erros.add(
              'Evento cancelamento ${item.chaveAcesso}: falha no download.',
            );
          }
        }
      } catch (e) {
        xmlsFalha++;
        erros.add(
          '${item.nomeArquivoXml(canceladaSuffix: item.cancelada)}: $e',
        );
      }
      saidasEnriquecidas.add(item);
    }

    for (final entrada in pacote.entradas) {
      passo++;
      onProgresso?.call(
        passo,
        totalPassos > 0 ? totalPassos : 1,
        'Entrada: ${entrada.numero.isNotEmpty ? entrada.numero : entrada.chaveAcesso.substring(0, 8)}...',
      );
      final f = _local.arquivoXmlEntradaLocal(entrada.chaveAcesso);
      if (f == null) {
        xmlsFalha++;
        erros.add(
          'Entrada ${entrada.chaveAcesso}: XML nao arquivado no sistema '
          '(importe novamente ou copie o XML manualmente).',
        );
        continue;
      }
      try {
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) {
          xmlsFalha++;
          erros.add('Entrada ${entrada.nomeArquivoXml}: arquivo vazio.');
          continue;
        }
        arquivosZip.add(
          ArchiveFile(
            'xml_entradas/${entrada.nomeArquivoXml}',
            bytes.length,
            bytes,
          ),
        );
        xmlsOk++;
      } catch (e) {
        xmlsFalha++;
        erros.add('Entrada ${entrada.nomeArquivoXml}: $e');
      }
    }

    for (final cce in cceLocais) {
      passo++;
      onProgresso?.call(
        passo,
        totalPassos > 0 ? totalPassos : 1,
        'CC-e: ${cce.chave.substring(0, 8)} seq ${cce.sequencia}...',
      );
      try {
        final bytes = await cce.arquivo.readAsBytes();
        if (bytes.isEmpty) {
          xmlsFalha++;
          erros.add(
            'CC-e ${cce.chave} seq ${cce.sequencia}: arquivo vazio.',
          );
          continue;
        }
        arquivosZip.add(
          ArchiveFile(
            'xml/cce/${cce.chave}_cce_${cce.sequencia}.xml',
            bytes.length,
            bytes,
          ),
        );
        xmlsOk++;
      } catch (e) {
        xmlsFalha++;
        erros.add('CC-e ${cce.chave} seq ${cce.sequencia}: $e');
      }
    }

    for (final inut in inutilizacoes.where((i) => i.sucesso)) {
      passo++;
      onProgresso?.call(
        passo,
        totalPassos > 0 ? totalPassos : 1,
        'Inutilizacao: serie ${inut.serie} ${inut.numeroInicial}-${inut.numeroFinal}...',
      );
      try {
        List<int>? bytes;
        final local = _local.arquivoXmlInutilizacaoLocal(inut.id);
        if (local != null) {
          bytes = await local.readAsBytes();
        } else if (inut.urlXml.trim().isNotEmpty) {
          bytes = await _baixarBytes(inut.urlXml);
        }
        if (bytes == null || bytes.isEmpty) {
          xmlsFalha++;
          erros.add(
            'Inutilizacao serie ${inut.serie} ${inut.numeroInicial}-'
            '${inut.numeroFinal}: XML indisponivel (regrave na Focus ou '
            'refaca a inutilizacao em homologacao).',
          );
          continue;
        }
        arquivosZip.add(
          ArchiveFile(
            'xml/inutilizacao/${inut.nomeArquivoXml}',
            bytes.length,
            bytes,
          ),
        );
        xmlsOk++;
      } catch (e) {
        xmlsFalha++;
        erros.add(
          'Inutilizacao serie ${inut.serie} ${inut.numeroInicial}-'
          '${inut.numeroFinal}: $e',
        );
      }
    }

    onProgresso?.call(totalPassos, totalPassos, 'Compactando ZIP...');
    final archive = Archive();
    for (final f in arquivosZip) {
      archive.addFile(f);
    }
    if (archive.files.isEmpty) {
      final aviso =
          'Nenhum XML foi incluido. Consulte a aba de erros na planilha Excel.';
      archive.addFile(
        ArchiveFile(
          'LEIA-ME.txt',
          aviso.length,
          aviso.codeUnits,
        ),
      );
    }
    final zipEncoded = ZipEncoder().encode(archive);
    if (zipEncoded.isEmpty) {
      throw FechamentoContabilException('Falha ao gerar arquivo ZIP.');
    }

    final totais = _calcularTotais(
      saidasEnriquecidas,
      pacote.entradas,
      xmlsOk: xmlsOk,
      xmlsFalha: xmlsFalha,
    );

    onProgresso?.call(totalPassos, totalPassos, 'Gerando planilha Excel...');
    final excelBytes = _montarPlanilhaExcel(
      mes: mes,
      ano: ano,
      saidas: saidasEnriquecidas,
      entradas: pacote.entradas,
      inutilizacoes: inutilizacoes,
      totais: totais,
      errosDownload: erros,
    );

    return FechamentoContabilResultado(
      mes: mes,
      ano: ano,
      saidas: saidasEnriquecidas,
      entradas: pacote.entradas,
      totais: totais,
      zipBytes: Uint8List.fromList(zipEncoded),
      excelBytes: excelBytes,
      errosDownload: erros,
    );
  }

  Future<NotaFiscalFechamentoItem> _enriquecerSaidaComFocus(
    NotaFiscalFechamentoItem nota,
  ) async {
    if (!FiscalConfigStore.configurado || nota.referenciaFocus.trim().isEmpty) {
      return nota;
    }
    final focus = _focusNfe ?? FocusNfeService(config: criarFocusNfeConfigPadrao());
    try {
      final r = nota.modelo == '65'
          ? await focus.consultarNfce(nota.referenciaFocus)
          : await focus.consultarNfe(nota.referenciaFocus);
      var statusFocus = r.statusFocus;
      var status = nota.status;
      if (r.cancelada) {
        statusFocus = 'cancelado';
        status = 'Cancelada';
      } else if (r.autorizada) {
        status = 'Autorizada';
      }
      return NotaFiscalFechamentoItem(
        modelo: nota.modelo,
        dataEmissao: nota.dataEmissao,
        numero: r.numero.isNotEmpty ? r.numero : nota.numero,
        serie: r.serie.isNotEmpty ? r.serie : nota.serie,
        chaveAcesso: r.chaveNfe.isNotEmpty ? r.chaveNfe : nota.chaveAcesso,
        documentoDestinatario: nota.documentoDestinatario,
        valorTotal: nota.valorTotal,
        status: status,
        statusFocus: statusFocus,
        urlXml: r.urlXml.isNotEmpty ? r.urlXml : nota.urlXml,
        referenciaFocus: nota.referenciaFocus,
        vendaId: nota.vendaId,
        razaoSocialDestinatario: nota.razaoSocialDestinatario,
        protocoloSefaz: r.protocolo.isNotEmpty ? r.protocolo : nota.protocoloSefaz,
        mensagemSefaz: r.mensagem.isNotEmpty ? r.mensagem : nota.mensagemSefaz,
        urlXmlEventoCancelamento: r.urlXmlCancelamento.isNotEmpty
            ? r.urlXmlCancelamento
            : nota.urlXmlEventoCancelamento,
        tributos: nota.tributos,
        vendaOperacionalCancelada: nota.vendaOperacionalCancelada,
        incluirNoZip: nota.incluirNoZip,
      );
    } catch (_) {
      return nota;
    }
  }

  Future<String> _resolverUrlXmlSaida(NotaFiscalFechamentoItem nota) async {
    if (nota.urlXml.trim().isNotEmpty) return nota.urlXml.trim();
    if (!FiscalConfigStore.configurado || nota.referenciaFocus.trim().isEmpty) {
      return '';
    }
    final focus = _focusNfe ?? FocusNfeService(config: criarFocusNfeConfigPadrao());
    try {
      final r = nota.modelo == '65'
          ? await focus.consultarNfce(nota.referenciaFocus)
          : await focus.consultarNfe(nota.referenciaFocus);
      return r.urlXml.trim();
    } catch (_) {
      return '';
    }
  }

  Future<List<int>?> _baixarBytes(String url) async {
    final u = url.trim();
    if (u.isEmpty) return null;
    try {
      final response =
          await _http.get(Uri.parse(u)).timeout(const Duration(seconds: 90));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  FechamentoContabilTotais _calcularTotais(
    List<NotaFiscalFechamentoItem> saidas,
    List<NotaFiscalEntradaFechamentoItem> entradas, {
    required int xmlsOk,
    required int xmlsFalha,
  }) {
    var qtdCancel = 0;
    var valorAut = 0.0;
    var valorCanc = 0.0;
    var alertas = 0;
    for (final s in saidas) {
      if (s.cancelada) {
        qtdCancel++;
        valorCanc += s.valorTotal;
      } else if (s.autorizada) {
        valorAut += s.valorTotal;
      }
      if (s.vendaOperacionalCancelada) alertas++;
    }
    var valorEnt = 0.0;
    for (final e in entradas) {
      valorEnt += e.valorTotal;
    }
    return FechamentoContabilTotais(
      quantidadeSaidas: saidas.length,
      quantidadeSaidasCanceladas: qtdCancel,
      valorSaidasAutorizadas: valorAut,
      valorSaidasCanceladas: valorCanc,
      quantidadeEntradas: entradas.length,
      valorEntradas: valorEnt,
      xmlsBaixados: xmlsOk,
      xmlsFalha: xmlsFalha,
      alertasVendaOperacional: alertas,
    );
  }

  Uint8List _montarPlanilhaExcel({
    required int mes,
    required int ano,
    required List<NotaFiscalFechamentoItem> saidas,
    required List<NotaFiscalEntradaFechamentoItem> entradas,
    required List<NfeInutilizacaoRegistro> inutilizacoes,
    required FechamentoContabilTotais totais,
    required List<String> errosDownload,
  }) {
    final inutRows = _linhasAbaInutilizacoes(
      mes: mes,
      ano: ano,
      inutilizacoes: inutilizacoes,
    );
    return FechamentoXlsxBuilder.build(
      sheet1Name: 'Saidas',
      sheet1Rows: _linhasAbaSaidas(
        mes: mes,
        ano: ano,
        saidas: saidas,
        totais: totais,
        errosDownload: errosDownload,
      ),
      sheet2Name: 'Entradas',
      sheet2Rows: _linhasAbaEntradas(
        mes: mes,
        ano: ano,
        entradas: entradas,
        totais: totais,
      ),
      sheet3Name: inutRows.isNotEmpty ? 'Inutilizacoes' : null,
      sheet3Rows: inutRows.isNotEmpty ? inutRows : null,
    );
  }

  List<List<String>> _linhasAbaInutilizacoes({
    required int mes,
    required int ano,
    required List<NfeInutilizacaoRegistro> inutilizacoes,
  }) {
    if (inutilizacoes.isEmpty) return const [];
    final rows = <List<String>>[..._cabecalhoEmitenteRows(mes, ano)];
    rows.add([
      'Data',
      'Serie',
      'Numero Inicial',
      'Numero Final',
      'Quantidade',
      'Sucesso',
      'Protocolo SEFAZ',
      'Usuario',
      'Justificativa',
      'Mensagem SEFAZ',
    ]);
    for (final inut in inutilizacoes) {
      final qtd = inut.numeroFinal - inut.numeroInicial + 1;
      rows.add([
        _fmtData.format(inut.registradaEm.toLocal()),
        inut.serie,
        inut.numeroInicial.toString(),
        inut.numeroFinal.toString(),
        qtd.toString(),
        inut.sucesso ? 'Sim' : 'Nao',
        inut.protocolo,
        inut.usuarioLogin,
        inut.justificativa,
        inut.mensagemSefaz,
      ]);
    }
    rows.add([]);
    rows.add([
      'Total inutilizacoes no periodo',
      inutilizacoes.length.toString(),
    ]);
    return rows;
  }

  List<List<String>> _cabecalhoEmitenteRows(int mes, int ano) => [
        ['Emitente', FiscalConfigStore.efetivo.razaoSocialEmitente],
        ['CNPJ', FiscalConfigStore.efetivo.cnpjEmitente],
        ['Inscricao Estadual', FiscalConfigStore.efetivo.inscricaoEstadualEmitente],
        ['Periodo', _rotuloMesAno(mes, ano)],
        [],
      ];

  List<List<String>> _linhasAbaSaidas({
    required int mes,
    required int ano,
    required List<NotaFiscalFechamentoItem> saidas,
    required FechamentoContabilTotais totais,
    required List<String> errosDownload,
  }) {
    final rows = <List<String>>[..._cabecalhoEmitenteRows(mes, ano)];
    rows.add([
      'Data de Emissao',
      'Numero',
      'Serie',
      'Modelo',
      'Chave de Acesso',
      'Razao Social Cliente',
      'CNPJ/CPF Destinatario',
      'Valor Total',
      'Status',
      'Protocolo SEFAZ',
      'CFOP Padrao',
      'Base ICMS',
      'Valor ICMS',
      'PIS',
      'COFINS',
      'Ref Focus / ID Venda',
      'Alerta Venda Operacional Cancelada',
    ]);
    for (final n in saidas) {
      rows.add([
        _fmtData.format(n.dataEmissao),
        n.numero,
        n.serie,
        n.modelo,
        n.chaveAcesso,
        n.razaoSocialDestinatario,
        n.documentoDestinatario,
        n.valorTotal.toStringAsFixed(2),
        n.status,
        n.protocoloSefaz,
        n.cfopExibicao.isNotEmpty
            ? n.cfopExibicao
            : FiscalConfig.cfopPadraoVendaInterna,
        n.tributos.baseIcms.toStringAsFixed(2),
        n.tributos.valorIcms.toStringAsFixed(2),
        n.tributos.valorPis.toStringAsFixed(2),
        n.tributos.valorCofins.toStringAsFixed(2),
        n.referenciaFocus.isNotEmpty
            ? n.referenciaFocus
            : (n.vendaId > 0 ? 'venda_id_${n.vendaId}' : ''),
        n.alertaVendaOperacional,
      ]);
    }
    rows.addAll([
      [],
      ['TOTAIS DO MES', ''],
      ['Quantidade de notas de saida', '${totais.quantidadeSaidas}'],
      ['Quantidade canceladas', '${totais.quantidadeSaidasCanceladas}'],
      [
        'Valor faturado (autorizadas)',
        _fmtMoeda.format(totais.valorSaidasAutorizadas),
      ],
      [
        'Valor notas canceladas',
        _fmtMoeda.format(totais.valorSaidasCanceladas),
      ],
      ['XMLs incluidos no ZIP', '${totais.xmlsBaixados}'],
      ['Falhas de download XML', '${totais.xmlsFalha}'],
      [
        'Alertas venda operacional cancelada',
        '${totais.alertasVendaOperacional}',
      ],
    ]);
    if (errosDownload.isNotEmpty) {
      rows.add(['Erros de download', '']);
      for (final e in errosDownload) {
        rows.add([e]);
      }
    }
    return rows;
  }

  List<List<String>> _linhasAbaEntradas({
    required int mes,
    required int ano,
    required List<NotaFiscalEntradaFechamentoItem> entradas,
    required FechamentoContabilTotais totais,
  }) {
    final rows = <List<String>>[..._cabecalhoEmitenteRows(mes, ano)];
    rows.add([
      'Data de Emissao',
      'Chave de Acesso',
      'CNPJ Fornecedor',
      'Razao Social Fornecedor',
      'Numero',
      'Serie',
      'Valor Total',
      'Data de Entrada no Sistema',
      'XML Local',
    ]);
    for (final e in entradas) {
      rows.add([
        _fmtData.format(e.dataEmissao),
        e.chaveAcesso,
        e.cnpjFornecedor,
        e.razaoSocialFornecedor,
        e.numero,
        e.serie,
        e.valorTotal.toStringAsFixed(2),
        _fmtData.format(e.dataEntradaSistema),
        e.temXmlLocal ? 'Sim' : 'Nao - reimportar XML',
      ]);
    }
    rows.addAll([
      [],
      ['TOTAIS ENTRADAS', ''],
      ['Quantidade de NF-e de entrada', '${totais.quantidadeEntradas}'],
      ['Valor total compras', _fmtMoeda.format(totais.valorEntradas)],
    ]);
    return rows;
  }

  static String _rotuloMesAno(int mes, int ano) {
    const nomes = [
      '',
      'janeiro',
      'fevereiro',
      'marco',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];
    final nome = mes >= 1 && mes <= 12 ? nomes[mes] : 'mes $mes';
    return '$nome de $ano';
  }
}

class FechamentoContabilPacote {
  const FechamentoContabilPacote({
    required this.saidas,
    required this.entradas,
  });

  final List<NotaFiscalFechamentoItem> saidas;
  final List<NotaFiscalEntradaFechamentoItem> entradas;

  int get totalDocumentos => saidas.length + entradas.length;
}

class FechamentoContabilException implements Exception {
  FechamentoContabilException(this.message);
  final String message;
  @override
  String toString() => message;
}
