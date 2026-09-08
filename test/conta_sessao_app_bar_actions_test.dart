import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/ui/app_global_error_handler.dart';
import 'package:sistema_vendas/ui/widgets/conta_sessao_app_bar_actions.dart';

void main() {
  Future<void> pumpConta(WidgetTester tester, VoidCallback onLogout) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Scaffold(
          appBar: AppBar(
            actions: [
              ContaSessaoAppBarActions(
                login: 'admin',
                onLogout: onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('Sair agenda logout sem travar o navigator', (tester) async {
    var logout = 0;
    await pumpConta(tester, () => logout++);

    await tester.tap(find.byTooltip('Conta e sessão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();
    expect(logout, 1);
  });

  testWidgets('Mudar de usuario confirma e agenda logout', (tester) async {
    var logout = 0;
    await pumpConta(tester, () => logout++);

    await tester.tap(find.byTooltip('Conta e sessão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mudar de usuário'));
    await tester.pumpAndSettle();
    expect(
      find.text('Voce será desconectado e poderá entrar com outra conta.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(logout, 0);

    await tester.tap(find.byTooltip('Conta e sessão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mudar de usuário'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mudar'));
    await tester.pumpAndSettle();
    expect(logout, 1);
  });
}
