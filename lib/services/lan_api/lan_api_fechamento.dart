import 'dart:typed_data';

import '../../data/fechamento_fiscal_local_source.dart';
import '../../domain/fiscal/fechamento_fiscal_resumo.dart';
import '../../domain/fiscal/fiscal_bloqueios_fechamento.dart';
import '../../services/fechamento_contabil_service.dart';
import '../../services/fechamento_email_service.dart';
import '../../services/fiscal_config_store.dart';
import 'lan_api_deps.dart';

FechamentoContabilService lanApiFechamentoService(LanApiDeps d) {
  return FechamentoContabilService(
    localSource: FechamentoFiscalLocalSource(
      storeDirectoryPath: d.objectBox.storeDirectoryPath,
      vendaRepository: d.vendaRepository,
      entradaRepository: d.nfeEntradaRepository,
    ),
  );
}

/// Pacote fiscal mensal (JSON) — calculado no PC servidor.
Map<String, dynamic> lanApiPacoteFechamento({
  required LanApiDeps d,
  required int mes,
  required int ano,
}) {
  final m = mes.clamp(1, 12);
  final a = ano <= 0 ? DateTime.now().year : ano;
  final service = lanApiFechamentoService(d);
  final pacote = service.listarPacoteFiscal(m, a);
  final resumo = FechamentoFiscalResumo.calcular(m, a, pacote);
  final bloqueios = FiscalBloqueiosFechamentoService.avaliar(
    vendaRepository: d.vendaRepository,
    mes: m,
    ano: a,
  );
  return {
    'ok': true,
    'mes': m,
    'ano': a,
    'resumo': resumo.toJson(),
    'pacote': pacote.toJson(),
    'bloqueios': _bloqueiosParaMap(bloqueios),
  };
}

/// Relatorio mensal leve (KPIs + bloqueios) — sem serializar o pacote completo.
Map<String, dynamic> lanApiRelatorioFiscalMensal({
  required LanApiDeps d,
  required int mes,
  required int ano,
}) {
  final m = mes.clamp(1, 12);
  final a = ano <= 0 ? DateTime.now().year : ano;
  final service = lanApiFechamentoService(d);
  final pacote = service.listarPacoteFiscal(m, a);
  final resumo = FechamentoFiscalResumo.calcular(m, a, pacote);
  final bloqueios = FiscalBloqueiosFechamentoService.avaliar(
    vendaRepository: d.vendaRepository,
    mes: m,
    ano: a,
  );
  return {
    'ok': true,
    'mes': m,
    'ano': a,
    'resumo': resumo.toJson(),
    'bloqueios': _bloqueiosParaMap(bloqueios),
  };
}

Map<String, dynamic> _bloqueiosParaMap(FiscalBloqueiosFechamento bloqueios) => {
      'bloqueiaExportacao': bloqueios.bloqueiaExportacao,
      'temBloqueioCritico': bloqueios.temBloqueioCritico,
      'temAviso': bloqueios.temAviso,
      'qtdNfceProcessando': bloqueios.qtdNfceProcessando,
      'qtdNfeProcessando': bloqueios.qtdNfeProcessando,
      'qtdNfeRejeitadas': bloqueios.qtdNfeRejeitadas,
      'vendasNfceProcessandoIds':
          bloqueios.vendasNfceProcessando.map((v) => v.id).toList(),
      'nfceProcessandoPreview': [
        for (final p in bloqueios.nfcePreviewEfetivo.take(10)) p.toJson(),
      ],
    };

final Map<String, _FechamentoCacheEntry> _fechamentoCache = {};

class _FechamentoCacheEntry {
  _FechamentoCacheEntry(this.result, this.criadoEm);
  final Map<String, dynamic> result;
  final DateTime criadoEm;
}

Future<Map<String, dynamic>> lanApiGerarFechamentoArquivos({
  required LanApiDeps d,
  required int mes,
  required int ano,
  bool forcar = false,
}) async {
  final m = mes.clamp(1, 12);
  final a = ano <= 0 ? DateTime.now().year : ano;

  // Mesma regra da UI: NFC-e processando bloqueia exportacao no servidor tambem.
  final bloqueios = FiscalBloqueiosFechamentoService.avaliar(
    vendaRepository: d.vendaRepository,
    mes: m,
    ano: a,
  );
  if (bloqueios.bloqueiaExportacao) {
    return {
      'ok': false,
      'error':
          '${bloqueios.qtdNfceProcessando} NFC-e aguardando SEFAZ — '
          'regularize em Pendencias fiscais antes de exportar.',
      'status': 409,
      'bloqueios': _bloqueiosParaMap(bloqueios),
    };
  }

  final cacheKey = '$m-$a';
  if (!forcar) {
    final cached = _fechamentoCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.criadoEm) <
            const Duration(minutes: 3)) {
      return cached.result;
    }
  }

  final service = lanApiFechamentoService(d);
  try {
    final resultado = await service.gerarFechamento(mes: m, ano: a);
    final result = <String, dynamic>{
      'ok': true,
      'mes': resultado.mes,
      'ano': resultado.ano,
      'nomeBaseArquivo': resultado.nomeBaseArquivo,
      'zipBytes': resultado.zipBytes,
      'excelBytes': resultado.excelBytes,
      'errosDownload': resultado.errosDownload,
      'totais': {
        'quantidadeSaidas': resultado.totais.quantidadeSaidas,
        'quantidadeSaidasCanceladas':
            resultado.totais.quantidadeSaidasCanceladas,
        'valorSaidasAutorizadas': resultado.totais.valorSaidasAutorizadas,
        'valorSaidasCanceladas': resultado.totais.valorSaidasCanceladas,
        'quantidadeEntradas': resultado.totais.quantidadeEntradas,
        'valorEntradas': resultado.totais.valorEntradas,
        'xmlsBaixados': resultado.totais.xmlsBaixados,
        'xmlsFalha': resultado.totais.xmlsFalha,
        'alertasVendaOperacional': resultado.totais.alertasVendaOperacional,
      },
    };
    _fechamentoCache[cacheKey] = _FechamentoCacheEntry(result, DateTime.now());
    return result;
  } on FechamentoContabilException catch (e) {
    return {'ok': false, 'error': e.message, 'status': 400};
  } catch (e) {
    return {'ok': false, 'error': '$e', 'status': 500};
  }
}

/// Tipagem auxiliar para bytes do cache.
typedef FechamentoBytes = Uint8List;

/// Gera o pacote e envia ZIP+Excel ao e-mail do contador (SMTP no PC servidor).
Future<Map<String, dynamic>> lanApiEnviarFechamentoContador({
  required LanApiDeps d,
  required int mes,
  required int ano,
  bool forcar = false,
}) async {
  await FiscalConfigStore.carregar();
  final cfg = FiscalConfigStore.efetivo;
  if (!cfg.emailContadorConfigurado) {
    return {
      'ok': false,
      'error':
          'E-mail do contador nao configurado. Cadastre em Configuracoes > Fiscal.',
      'status': 400,
    };
  }
  if (!cfg.smtpConfigurado) {
    return {
      'ok': false,
      'error':
          'SMTP nao configurado no PC servidor. Informe host, usuario e senha '
          'em Configuracoes > Fiscal.',
      'status': 400,
    };
  }

  final arquivos = await lanApiGerarFechamentoArquivos(
    d: d,
    mes: mes,
    ano: ano,
    forcar: forcar,
  );
  if (arquivos['ok'] != true) {
    return arquivos;
  }
  final zip = arquivos['zipBytes'];
  final excel = arquivos['excelBytes'];
  final nome = (arquivos['nomeBaseArquivo'] ?? 'fechamento').toString();
  if (zip is! List<int> || excel is! List<int>) {
    return {'ok': false, 'error': 'Pacote fiscal vazio', 'status': 500};
  }

  try {
    await FechamentoEmailService.enviarParaContador(
      mes: mes.clamp(1, 12),
      ano: ano <= 0 ? DateTime.now().year : ano,
      zipBytes: Uint8List.fromList(zip),
      excelBytes: Uint8List.fromList(excel),
      nomeBaseArquivo: nome,
    );
    return {
      'ok': true,
      'destinatario': cfg.emailContador,
      'mes': mes,
      'ano': ano,
      'nomeBaseArquivo': nome,
    };
  } on FechamentoEmailException catch (e) {
    return {'ok': false, 'error': e.message, 'status': 400};
  } catch (e) {
    return {'ok': false, 'error': '$e', 'status': 500};
  }
}
