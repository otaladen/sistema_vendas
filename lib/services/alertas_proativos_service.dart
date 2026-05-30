import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_config_repository.dart';
import '../data/caixa_sessao_repository.dart';
import '../data/mensageria_repository.dart';
import '../data/produto_repository.dart';
import '../data/objectbox.dart';
import '../data/venda_repository.dart';
import '../domain/dashboard_alertas.dart';

/// Envia alertas proativos via WhatsApp para o numero do dono configurado.
class AlertasProativosService {
  AlertasProativosService({
    AppConfigRepository? configRepository,
    MensageriaRepository? mensageriaRepository,
    this.produtoRepository,
    VendaRepository? vendaRepository,
    ObjectBox? objectBox,
  })  : _configRepository = configRepository ?? AppConfigRepository(),
        _mensageria = mensageriaRepository ?? MensageriaRepository(),
        _vendaRepository = vendaRepository ??
            (objectBox != null
                ? VendaRepository(objectBox)
                : throw ArgumentError(
                    'vendaRepository ou objectBox e obrigatorio',
                  ));

  final AppConfigRepository _configRepository;
  final MensageriaRepository _mensageria;
  final ProdutoRepository? produtoRepository;
  final VendaRepository _vendaRepository;

  static const _kUltimoFiado = 'alertas_proativos_ultimo_fiado_ms';
  static const _kUltimoEstoque = 'alertas_proativos_ultimo_estoque_ms';
  static const _kUltimoCaixa = 'alertas_proativos_ultimo_caixa_ms';

  Future<void> verificarEEnviarSeDevido() async {
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.alertasProativosWhatsappAtivos) return;
    final destino =
        _mensageria.normalizarDestinoWhatsapp(config.whatsappDonoNumero);
    if (destino.isEmpty) return;
    if (!_mensageriaWhatsAppConfigurado(config)) return;

    final prefs = await SharedPreferences.getInstance();
    final agora = DateTime.now();
    final intervalo = Duration(
      minutes: config.alertasProativosIntervaloMinutos.clamp(15, 1440),
    );

    _vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    final titulos = _vendaRepository.titulos.listarTodosAbertos();
    final fiadoVencido = titulos
        .where(ContasReceberHelper.ehVencido)
        .fold<double>(0, (s, l) => s + l.titulo.saldo);
    if (fiadoVencido > 0.001 &&
        _passouIntervalo(prefs, _kUltimoFiado, agora, intervalo)) {
      await _mensageria.enfileirarWhatsappTextoLivre(
        destino: destino,
        texto:
            '[${config.nomeLoja}] Alerta: fiado vencido total '
            'R\$ ${fiadoVencido.toStringAsFixed(2).replaceAll('.', ',')}.',
      );
      await prefs.setInt(_kUltimoFiado, agora.millisecondsSinceEpoch);
    }

    final prodRepo = produtoRepository;
    if (prodRepo != null) {
      final zerados = prodRepo
          .listarTodos()
          .where((p) => p.ativo && p.estoqueReal <= 0)
          .length;
      if (zerados > 0 &&
          _passouIntervalo(prefs, _kUltimoEstoque, agora, intervalo)) {
        await _mensageria.enfileirarWhatsappTextoLivre(
          destino: destino,
          texto:
              '[${config.nomeLoja}] Alerta: $zerados produto(s) com estoque zerado.',
        );
        await prefs.setInt(_kUltimoEstoque, agora.millisecondsSinceEpoch);
      }
    }

    if (agora.hour >= 18) {
      final sessoes = await CaixaSessaoRepository().listarTodasSessoes();
      final abertos = sessoes.entries.where((e) => e.value.aberto).toList();
      if (abertos.isNotEmpty &&
          _passouIntervalo(prefs, _kUltimoCaixa, agora, intervalo)) {
        final lista = abertos
            .map((e) => '${e.value.operador} (${e.key})')
            .join(', ');
        await _mensageria.enfileirarWhatsappTextoLivre(
          destino: destino,
          texto:
              '[${config.nomeLoja}] Alerta: caixa ainda aberto as '
              '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}. '
              'Sessoes: $lista',
        );
        await prefs.setInt(_kUltimoCaixa, agora.millisecondsSinceEpoch);
      }
    }

    await _mensageria.processarFilaPendente(limite: 5);
  }

  bool _passouIntervalo(
    SharedPreferences prefs,
    String key,
    DateTime agora,
    Duration intervalo,
  ) {
    final ultimo = prefs.getInt(key) ?? 0;
    if (ultimo <= 0) return true;
    return agora.difference(
      DateTime.fromMillisecondsSinceEpoch(ultimo),
    ) >= intervalo;
  }

  bool _mensageriaWhatsAppConfigurado(EmpresaConfig config) {
    return config.mensageriaBackendUrl.trim().isNotEmpty ||
        (config.whatsappAccessToken.trim().isNotEmpty &&
            config.whatsappPhoneNumberId.trim().isNotEmpty);
  }
}
