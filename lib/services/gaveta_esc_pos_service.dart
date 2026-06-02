import 'dart:io';
import 'dart:typed_data';

import '../data/app_config_repository.dart';
import 'gaveta_raw_io.dart';

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

/// Pulso ESC/POS na gaveta (Epson, Bematech, Elgin) via impressora termica USB no Windows.
///
/// Usa [EmpresaConfig.impressoraPadrao] — a mesma impressora do cupom PDF, quando for termica.
class GavetaEscPosService {
  GavetaEscPosService(this._configRepository);

  final AppConfigRepository _configRepository;

  /// Comando `ESC p m t1 t2` (padrao Epson; compativel com Bematech/Elgin).
  static Uint8List comandoPulseGaveta({
    int pino = 0,
    int tempoOnMs = 50,
    int tempoOffMs = 250,
  }) {
    final m = pino.clamp(0, 1);
    final t1 = (tempoOnMs ~/ 2).clamp(1, 255);
    final t2 = (tempoOffMs ~/ 2).clamp(1, 255);
    return Uint8List.fromList([0x1B, 0x70, m, t1, t2]);
  }

  /// Abre apos pagamento no caixa ([forcar] ignora o interruptor automatico).
  Future<GavetaAbrirResultado> abrirAposPagamento({bool forcar = false}) async {
    if (!Platform.isWindows) {
      return const GavetaAbrirResultado(
        sucesso: false,
        mensagem: 'Gaveta automatica: use o app no Windows com impressora USB.',
        codigo: GavetaResultadoCodigo.plataforma,
      );
    }

    final config = await _configRepository.carregarEmpresaConfig();
    if (!forcar && !config.abrirGavetaAutomatica) {
      return const GavetaAbrirResultado(
        sucesso: false,
        mensagem: 'Abertura automatica da gaveta desativada.',
        codigo: GavetaResultadoCodigo.desativada,
      );
    }

    final impressora = config.impressoraPadrao.trim();
    if (impressora.isEmpty) {
      return const GavetaAbrirResultado(
        sucesso: false,
        mensagem:
            'Configure a impressora termica (USB) em Configuracoes > Impressora.',
        codigo: GavetaResultadoCodigo.semImpressora,
      );
    }

    try {
      final bytes = comandoPulseGaveta(pino: config.gavetaPino);
      await enviarRawParaImpressora(impressora, bytes);
      return const GavetaAbrirResultado(
        sucesso: true,
        mensagem: 'Comando de gaveta enviado para a impressora.',
        codigo: GavetaResultadoCodigo.sucesso,
      );
    } catch (e) {
      return GavetaAbrirResultado(
        sucesso: false,
        mensagem:
            'Nao foi possivel abrir a gaveta ($impressora). '
            'Verifique USB, driver e nome exato na lista do Windows. Detalhe: $e',
        codigo: GavetaResultadoCodigo.erro,
      );
    }
  }

  Future<GavetaAbrirResultado> testarAbrir() => abrirAposPagamento(forcar: true);
}
