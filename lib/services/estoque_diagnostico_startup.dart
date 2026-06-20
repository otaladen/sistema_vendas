import '../data/objectbox.dart';
import '../domain/estoque/estoque_diagnostico_models.dart';
import 'estoque_diagnostico_service.dart';

/// Executa diagnostico de estoque na abertura do app (silencioso).
abstract final class EstoqueDiagnosticoStartup {
  EstoqueDiagnosticoStartup._();

  static EstoqueDiagnosticoResultado? ultimoResultado;

  static Future<void> executarSePossivel({
    required ObjectBox objectBox,
  }) async {
    try {
      ultimoResultado = EstoqueDiagnosticoService(objectBox).executar();
    } catch (_) {
      // Nao impede abertura do app.
    }
  }
}
