import '../data/app_config_repository.dart';
import 'configuracoes_service.dart';
import '../model/config_layout_impressao.dart';
import 'esc_pos_commands.dart';
import 'fiscal_config_store.dart';

/// Regras unificadas de bobina termica (servidor e terminais).
class BobinaTermicaSpec {
  const BobinaTermicaSpec({
    required this.larguraPaginaPdfMm,
    required this.margemPaginaMm,
    required this.margemCorteMm,
    required this.larguraColunaValorMm,
    required this.comprimentoDivisoria,
    required this.colunasEscPos,
  });

  final double larguraPaginaPdfMm;
  final double margemPaginaMm;
  final double margemCorteMm;
  final double larguraColunaValorMm;
  final LayoutComprimentoDivisoria comprimentoDivisoria;
  final int colunasEscPos;

  static BobinaTermicaSpec paraLarguraConfig(String escPosLargura) {
    final bobina = EscPosLarguraBobina.fromConfig(escPosLargura);
    if (bobina == EscPosLarguraBobina.mm58) {
      return const BobinaTermicaSpec(
        larguraPaginaPdfMm: 52,
        margemPaginaMm: 2,
        margemCorteMm: 2,
        larguraColunaValorMm: 24,
        comprimentoDivisoria: LayoutComprimentoDivisoria.curto,
        colunasEscPos: 32,
      );
    }
    return const BobinaTermicaSpec(
      larguraPaginaPdfMm: 72,
      margemPaginaMm: 2,
      margemCorteMm: 2,
      larguraColunaValorMm: 32,
      comprimentoDivisoria: LayoutComprimentoDivisoria.medio,
      colunasEscPos: 48,
    );
  }
}

/// Layout efetivo no papel: estilo sincronizado da loja + dimensao da bobina local.
class ImpressoesService {
  ImpressoesService(this._configuracoes);

  final ConfiguracoesService _configuracoes;

  /// Aplica [BobinaTermicaSpec] sobre o layout global (nao altera campos de conteudo).
  static ConfigLayoutImpressao layoutParaBobinaLocal({
    required ConfigLayoutImpressao layoutGlobal,
    required String escPosLargura,
  }) {
    final spec = BobinaTermicaSpec.paraLarguraConfig(escPosLargura);
    return layoutGlobal.copyWith(
      larguraPaginaPdfMm: spec.larguraPaginaPdfMm,
      margemPaginaMm: spec.margemPaginaMm,
      margemCorteMm: spec.margemCorteMm,
      larguraColunaValorMm: spec.larguraColunaValorMm,
      comprimentoDivisoria: spec.comprimentoDivisoria,
    );
  }

  static ConfigLayoutImpressao layoutCupomEfetivo(EmpresaConfig config) {
    return layoutParaBobinaLocal(
      layoutGlobal: config.layoutImpressao.cupom,
      escPosLargura: config.escPosLargura,
    );
  }

  static ConfigLayoutImpressao layoutOrcamentoEfetivo(EmpresaConfig config) {
    return layoutParaBobinaLocal(
      layoutGlobal: config.layoutImpressao.orcamento,
      escPosLargura: config.escPosLargura,
    );
  }

  Future<ConfigLayoutImpressao> carregarLayoutCupomEfetivo() async {
    final c = await _configuracoes.carregarEfetiva();
    return layoutCupomEfetivo(c);
  }

  Future<ConfigLayoutImpressao> carregarLayoutOrcamentoEfetivo() async {
    final c = await _configuracoes.carregarEfetiva();
    return layoutOrcamentoEfetivo(c);
  }

  /// Focus/emitente global (API no terminal leve ou prefs no servidor).
  Future<FiscalConfigDados> carregarFiscalParaImpressao() =>
      _configuracoes.carregarFiscalGlobal();

  /// Cache apos [carregarFiscalParaImpressao] / [ConfiguracoesService.carregarFiscalGlobal].
  static FiscalConfigDados fiscalDeCache({FiscalConfigDados? explicit}) {
    if (explicit != null) return explicit;
    return ConfiguracoesService.tryGlobal?.fiscalEmCache ??
        FiscalConfigDados.fromConstantes();
  }
}
