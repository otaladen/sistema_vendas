import 'dart:io';
import 'dart:typed_data';

import '../data/app_config_repository.dart';
import 'esc_pos_commands.dart';
import 'esc_pos_transport.dart';

enum GavetaResultadoCodigo {
  sucesso,
  desativada,
  semImpressora,
  plataforma,
  erro,
}

class GavetaAbrirResultado {
  const GavetaAbrirResultado({
    required this.sucesso,
    required this.mensagem,
    required this.codigo,
  });

  final bool sucesso;
  final String mensagem;
  final GavetaResultadoCodigo codigo;
}

/// Pulso ESC/POS na gaveta via destino configurado (Windows RAW / TCP / COM).
class GavetaEscPosService {
  GavetaEscPosService(this._configRepository);

  final AppConfigRepository _configRepository;

  /// Comando `ESC p m t1 t2` (padrao Epson; compativel com Bematech/Elgin).
  static Uint8List comandoPulseGaveta({
    int pino = 0,
    int tempoOnMs = 50,
    int tempoOffMs = 250,
  }) =>
      EscPosCommands.drawerPulse(
        pino: pino,
        tempoOnMs: tempoOnMs,
        tempoOffMs: tempoOffMs,
      );

  /// Abre apos pagamento no caixa ([forcar] ignora o interruptor automatico).
  Future<GavetaAbrirResultado> abrirAposPagamento({bool forcar = false}) async {
    final config = await _configRepository.carregarEmpresaConfig();
    if (!forcar && !config.abrirGavetaAutomatica) {
      return const GavetaAbrirResultado(
        sucesso: false,
        mensagem: 'Abertura automatica da gaveta desativada.',
        codigo: GavetaResultadoCodigo.desativada,
      );
    }

    final destino = EscPosDestino.fromConfig(
      tipo: config.escPosDestino,
      impressoraWindows: config.impressoraPadrao,
      host: config.escPosHost,
      portaTcp: config.escPosPortaTcp,
      portaCom: config.escPosPortaCom,
    );

    if ((destino.tipo == EscPosDestinoTipo.windows ||
            destino.tipo == EscPosDestinoTipo.com) &&
        !Platform.isWindows) {
      return const GavetaAbrirResultado(
        sucesso: false,
        mensagem: 'Gaveta USB/COM: use o app no Windows.',
        codigo: GavetaResultadoCodigo.plataforma,
      );
    }

    if (destino.tipo == EscPosDestinoTipo.windows &&
        config.impressoraPadrao.trim().isEmpty) {
      return const GavetaAbrirResultado(
        sucesso: false,
        mensagem:
            'Configure a impressora termica em Configuracoes > Impressora.',
        codigo: GavetaResultadoCodigo.semImpressora,
      );
    }

    try {
      final bytes = comandoPulseGaveta(pino: config.gavetaPino);
      await EscPosTransport.enviar(destino, bytes);
      return const GavetaAbrirResultado(
        sucesso: true,
        mensagem: 'Comando de gaveta enviado para a impressora.',
        codigo: GavetaResultadoCodigo.sucesso,
      );
    } catch (e) {
      return GavetaAbrirResultado(
        sucesso: false,
        mensagem: 'Nao foi possivel abrir a gaveta. Detalhe: $e',
        codigo: GavetaResultadoCodigo.erro,
      );
    }
  }

  Future<GavetaAbrirResultado> testarAbrir() => abrirAposPagamento(forcar: true);
}
