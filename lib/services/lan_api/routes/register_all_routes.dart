import 'package:shelf_router/shelf_router.dart';

import '../lan_api_deps.dart';
import 'auth_routes.dart';
import 'backup_routes.dart';
import 'cadastros_routes.dart';
import 'caixa_routes.dart';
import 'chat_routes.dart';
import 'estoque_routes.dart';
import 'inventario_routes.dart';
import 'financeiro_routes.dart';
import 'fiscal_routes.dart';
import 'recados_routes.dart';
import 'relatorios_routes.dart';
import 'vales_routes.dart';
import 'vendas_routes.dart';

void registerAllLanApiRoutes(Router router, LanApiDeps d) {
  registerAuthRoutes(router, d);
  registerBackupRoutes(router, d);
  registerCadastrosRoutes(router, d);
  registerVendasRoutes(router, d);
  registerCaixaRoutes(router, d);
  registerFinanceiroRoutes(router, d);
  registerEstoqueRoutes(router, d);
  registerInventarioRoutes(router, d);
  registerFiscalRoutes(router, d);
  registerRelatoriosRoutes(router, d);
  registerRecadosRoutes(router, d);
  registerValesRoutes(router, d);
  registerChatRoutes(router, d);
}
