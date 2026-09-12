import 'dart:typed_data';

import '../data/app_config_repository.dart';
import 'configuracoes_service.dart';
import 'esc_pos_commands.dart';
import 'esc_pos_cupom_builder.dart';
import 'esc_pos_orcamento_builder.dart';
import 'esc_pos_transport.dart';
import 'gaveta_esc_pos_service.dart';

class EscPosImpressaoResultado {
  const EscPosImpressaoResultado({
    required this.sucesso,
    required this.mensagem,
  });

  final bool sucesso;
  final String mensagem;
}

/// Impressao termica direta ESC/POS (balcão / NFC-e).
class EscPosPrinterService {
  EscPosPrinterService(this._configuracoes);

  final ConfiguracoesService _configuracoes;

  EscPosDestino _destinoDe(EmpresaConfig c) => EscPosDestino.fromConfig(
        tipo: c.escPosDestino,
        impressoraWindows: c.impressoraPadrao,
        host: c.escPosHost,
        portaTcp: c.escPosPortaTcp,
        portaCom: c.escPosPortaCom,
      );

  /// Impressao de cupom (usa [dados.config]; nao precisa recarregar prefs).
  static Future<EscPosImpressaoResultado> imprimirCupomDireto(
    CupomBalcaoDados dados, {
    bool cortar = true,
    bool? abrirGaveta,
  }) async {
    final config = dados.config;
    final gaveta = abrirGaveta ?? config.abrirGavetaAutomatica;
    try {
      final bytes = EscPosCupomBuilder.montar(
        dados,
        largura: EscPosLarguraBobina.fromConfig(config.escPosLargura),
        cortar: cortar,
        abrirGaveta: gaveta,
        gavetaPino: config.gavetaPino,
      );
      await EscPosTransport.enviar(
        EscPosDestino.fromConfig(
          tipo: config.escPosDestino,
          impressoraWindows: config.impressoraPadrao,
          host: config.escPosHost,
          portaTcp: config.escPosPortaTcp,
          portaCom: config.escPosPortaCom,
        ),
        bytes,
      );
      return const EscPosImpressaoResultado(
        sucesso: true,
        mensagem: 'Cupom enviado para a impressora termica.',
      );
    } catch (e) {
      return EscPosImpressaoResultado(
        sucesso: false,
        mensagem: 'Falha na impressao ESC/POS: $e',
      );
    }
  }

  Future<EscPosImpressaoResultado> imprimirCupom(
    CupomBalcaoDados dados, {
    bool cortar = true,
    bool? abrirGaveta,
  }) =>
      imprimirCupomDireto(
        dados,
        cortar: cortar,
        abrirGaveta: abrirGaveta,
      );

  /// Orcamento em fonte nativa ESC/POS (Epson TM-T20 e similares).
  static Future<EscPosImpressaoResultado> imprimirOrcamentoDireto(
    OrcamentoEscPosDados dados, {
    bool cortar = true,
  }) async {
    final config = dados.config;
    try {
      final bytes = EscPosOrcamentoBuilder.montar(
        dados,
        largura: EscPosLarguraBobina.fromConfig(config.escPosLargura),
        cortar: cortar,
      );
      await EscPosTransport.enviar(
        EscPosDestino.fromConfig(
          tipo: config.escPosDestino,
          impressoraWindows: config.impressoraPadrao,
          host: config.escPosHost,
          portaTcp: config.escPosPortaTcp,
          portaCom: config.escPosPortaCom,
        ),
        bytes,
      );
      return const EscPosImpressaoResultado(
        sucesso: true,
        mensagem: 'Orcamento enviado para a impressora termica.',
      );
    } catch (e) {
      return EscPosImpressaoResultado(
        sucesso: false,
        mensagem: 'Falha na impressao ESC/POS do orcamento: $e',
      );
    }
  }

  Future<EscPosImpressaoResultado> imprimirTeste() async {
    final config = await _configuracoes.carregarEfetiva();
    final cols =
        EscPosLarguraBobina.fromConfig(config.escPosLargura).colunas;
    final out = BytesBuilder(copy: false);
    out.add(EscPosCommands.init);
    out.add(EscPosCommands.alignCenter);
    out.add(EscPosCommands.boldOn);
    out.add(EscPosCommands.line('TESTE ESC/POS'));
    out.add(EscPosCommands.boldOff);
    out.add(EscPosCommands.line(config.nomeLoja));
    out.add(EscPosCommands.separator(cols));
    out.add(EscPosCommands.alignLeft);
    out.add(EscPosCommands.line('Destino: ${config.escPosDestino}'));
    out.add(EscPosCommands.line('Largura: ${config.escPosLargura}mm'));
    if (config.escPosDestino == 'rede') {
      out.add(EscPosCommands.line('${config.escPosHost}:${config.escPosPortaTcp}'));
    } else if (config.escPosDestino == 'com') {
      out.add(EscPosCommands.line('Porta ${config.escPosPortaCom}'));
    } else {
      out.add(EscPosCommands.line(config.impressoraPadrao));
    }
    out.add(EscPosCommands.feed(3));
    out.add(EscPosCommands.cutPartial);
    if (config.abrirGavetaAutomatica) {
      out.add(EscPosCommands.drawerPulse(pino: config.gavetaPino));
    }
    try {
      await EscPosTransport.enviar(_destinoDe(config), out.toBytes());
      return const EscPosImpressaoResultado(
        sucesso: true,
        mensagem: 'Pagina de teste ESC/POS enviada.',
      );
    } catch (e) {
      return EscPosImpressaoResultado(
        sucesso: false,
        mensagem: 'Falha no teste ESC/POS: $e',
      );
    }
  }

  /// So pulso de gaveta (reutiliza transporte configurado).
  Future<GavetaAbrirResultado> abrirGaveta({bool forcar = false}) async {
    final config = await _configuracoes.carregarEfetiva();
    if (!forcar && !config.abrirGavetaAutomatica) {
      return const GavetaAbrirResultado(
        sucesso: false,
        mensagem: 'Abertura automatica da gaveta desativada.',
        codigo: GavetaResultadoCodigo.desativada,
      );
    }
    try {
      final bytes = EscPosCommands.drawerPulse(pino: config.gavetaPino);
      await EscPosTransport.enviar(_destinoDe(config), bytes);
      return const GavetaAbrirResultado(
        sucesso: true,
        mensagem: 'Comando de gaveta enviado.',
        codigo: GavetaResultadoCodigo.sucesso,
      );
    } catch (e) {
      return GavetaAbrirResultado(
        sucesso: false,
        mensagem: 'Nao foi possivel abrir a gaveta: $e',
        codigo: GavetaResultadoCodigo.erro,
      );
    }
  }
}
