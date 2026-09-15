import '../data/caixa_sessao_repository.dart';
import '../data/sync/caixa_status_hub.dart';
import '../model/usuario_sistema.dart';
import '../services/configuracoes_service.dart';
import 'app_boot_log.dart';

/// Falha isolada de uma etapa do boot pos-login (nao derruba o app).
class AppPosLoginAviso {
  const AppPosLoginAviso({
    required this.etapaId,
    required this.tituloAmigavel,
    required this.detalhe,
  });

  final String etapaId;
  final String tituloAmigavel;
  final String detalhe;
}

/// Resultado agregado das etapas pos-login.
class AppPosLoginResultado {
  const AppPosLoginResultado({
    this.falhaFatal,
    this.stackFatal,
    this.avisos = const [],
  });

  final Object? falhaFatal;
  final StackTrace? stackFatal;
  final List<AppPosLoginAviso> avisos;

  bool get ok => falhaFatal == null;
}

/// Etapas defensivas apos credenciais validas e antes/depois do dashboard.
abstract final class AppPosLoginStartup {
  AppPosLoginStartup._();

  static Future<AppPosLoginResultado> executarAntesDoDashboard({
    required UsuarioSistema usuario,
    required bool terminalLeve,
    ConfiguracoesService? configuracoesService,
  }) async {
    final avisos = <AppPosLoginAviso>[];

    await _etapa(
      avisos: avisos,
      etapaId: 'caixa_sessao',
      titulo: 'Erro ao carregar status do caixa',
      acao: () async {
        await sincronizarCaixaDefensivo();
      },
    );

    if (!terminalLeve && configuracoesService != null) {
      await _etapa(
        avisos: avisos,
        etapaId: 'parametros_loja',
        titulo: 'Erro ao carregar parametros da loja',
        acao: () async {
          await configuracoesService.carregarEfetiva();
        },
      );
    }

    AppBootLog.info(
      'pos_login',
      'Antes do dashboard: ${usuario.login} '
      '(terminalLeve=$terminalLeve, avisos=${avisos.length})',
    );
    return AppPosLoginResultado(avisos: avisos);
  }

  static Future<AppPosLoginResultado> executarAoAbrirShell({
    required bool terminalLeve,
  }) async {
    if (terminalLeve) {
      return const AppPosLoginResultado();
    }
    final avisos = <AppPosLoginAviso>[];

    await _etapa(
      avisos: avisos,
      etapaId: 'caixa_sessao_shell',
      titulo: 'Erro ao sincronizar caixa no menu',
      acao: sincronizarCaixaDefensivo,
    );

    return AppPosLoginResultado(avisos: avisos);
  }

  /// Hidrata hub a partir do repositorio e corrige sessoes inconsistentes.
  static Future<void> sincronizarCaixaDefensivo() async {
    final repo = CaixaSessaoRepository();
    final mapa = await repo.listarTodasSessoes(repararInconsistentes: true);
    CaixaStatusHub.instance.publicarDasSessoes(mapa);
  }

  static Future<void> _etapa({
    required List<AppPosLoginAviso> avisos,
    required String etapaId,
    required String titulo,
    required Future<void> Function() acao,
  }) async {
    try {
      await acao();
    } catch (e, st) {
      AppBootLog.registrar(etapaId, e, stack: st);
      avisos.add(
        AppPosLoginAviso(
          etapaId: etapaId,
          tituloAmigavel: titulo,
          detalhe: _detalheCurto(e),
        ),
      );
    }
  }

  static String _detalheCurto(Object e) {
    final s = e.toString().trim();
    if (s.length <= 220) return s;
    return '${s.substring(0, 217)}...';
  }
}
