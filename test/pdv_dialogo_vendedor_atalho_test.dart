import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/vendedor.dart';
import 'package:sistema_vendas/ui/pdv/pdv_dialogo_vendedor_atalho.dart';

List<Vendedor> _vendedoresExemplo() {
  return [
    Vendedor(id: 10, codigoInterno: '2', nomeCompleto: 'Antonio', apelido: 'Antonio'),
    Vendedor(id: 11, codigoInterno: '1', nomeCompleto: 'May', apelido: 'May'),
    Vendedor(id: 12, codigoInterno: '3', nomeCompleto: 'Otavio', apelido: 'Otavio'),
  ];
}

KeyDownEvent _keyDown(LogicalKeyboardKey logicalKey) {
  final physicalKey = switch (logicalKey) {
    LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 =>
      PhysicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 =>
      PhysicalKeyboardKey.digit1,
    _ => PhysicalKeyboardKey.digit0,
  };
  return KeyDownEvent(
    physicalKey: physicalKey,
    logicalKey: logicalKey,
    timeStamp: Duration.zero,
  );
}

void main() {
  group('pdvResolverVendedorPorCodigoInterno', () {
    test('resolve codigo exato e numerico V03', () {
      final lista = _vendedoresExemplo()
        ..add(
          Vendedor(
            id: 13,
            codigoInterno: 'V03',
            nomeCompleto: 'Outro',
          ),
        );
      expect(
        pdvResolverVendedorPorCodigoInterno(lista, '3')?.id,
        12,
      );
      expect(
        pdvResolverVendedorPorCodigoInterno(lista, '1')?.apelido,
        'May',
      );
    });
  });

  group('pdvProcessarTeclaDialogoVendedor', () {
    test('primeira tecla 3 confirma Otavio quando callback ja registrado', () {
      int? confirmado;
      final ok = pdvProcessarTeclaDialogoVendedor(
        event: _keyDown(LogicalKeyboardKey.digit3),
        buscaPorNomeAtiva: false,
        vendedoresAtivos: _vendedoresExemplo(),
        onConfirmarPorCodigo: (id) => confirmado = id,
        onCancelar: () {},
      );
      expect(ok, isTrue);
      expect(confirmado, 12);
    });

    test('tecla numerica do teclado numerico confirma na primeira', () {
      int? confirmado;
      pdvProcessarTeclaDialogoVendedor(
        event: _keyDown(LogicalKeyboardKey.numpad3),
        buscaPorNomeAtiva: false,
        vendedoresAtivos: _vendedoresExemplo(),
        onConfirmarPorCodigo: (id) => confirmado = id,
        onCancelar: () {},
      );
      expect(confirmado, 12);
    });

    test('modo busca por nome ignora atalho numerico', () {
      int? confirmado;
      final ok = pdvProcessarTeclaDialogoVendedor(
        event: _keyDown(LogicalKeyboardKey.digit3),
        buscaPorNomeAtiva: true,
        vendedoresAtivos: _vendedoresExemplo(),
        onConfirmarPorCodigo: (id) => confirmado = id,
        onCancelar: () {},
      );
      expect(ok, isFalse);
      expect(confirmado, isNull);
    });
  });

  testWidgets('dialogo fecha na primeira tecla 3 com fluxo igual ao PDV', (
    tester,
  ) async {
    final vendedores = _vendedoresExemplo();
    int? confirmado;
    var dialogoAberto = false;
    var buscaPorNome = false;
    void Function(int)? confirmarPorTecla;
    void Function()? cancelarPorTecla;

    bool handler(KeyEvent event) {
      if (!dialogoAberto) return false;
      return pdvProcessarTeclaDialogoVendedor(
        event: event,
        buscaPorNomeAtiva: buscaPorNome,
        vendedoresAtivos: vendedores,
        onConfirmarPorCodigo: confirmarPorTecla,
        onCancelar: () => cancelarPorTecla?.call(),
      );
    }

    HardwareKeyboard.instance.addHandler(handler);
    addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    dialogoAberto = true;
                    buscaPorNome = false;
                    final nav = Navigator.of(context);
                    confirmarPorTecla = (id) {
                      confirmado = id;
                      nav.pop(true);
                    };
                    cancelarPorTecla = () => nav.pop(false);
                    await showDialog<bool>(
                      context: context,
                      builder: (_) => const AlertDialog(
                        title: Text('Quem esta vendendo?'),
                      ),
                    );
                    dialogoAberto = false;
                  },
                  child: const Text('Abrir'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Quem esta vendendo?'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();

    expect(confirmado, 12);
    expect(find.text('Quem esta vendendo?'), findsNothing);
  });

  test('digito pendente confirma quando teclado do dialogo fica ativo', () {
    final vendedores = _vendedoresExemplo();
    int? confirmado;
    var tecladoAtivo = false;
    String? digitoPendente;

    void confirmarPorCodigo(String codigo) {
      final v = pdvResolverVendedorPorCodigoInterno(vendedores, codigo);
      if (v != null) confirmado = v.id;
    }

    void aoDigito(String digito) {
      if (tecladoAtivo) {
        confirmarPorCodigo(digito);
      } else {
        digitoPendente = digito;
      }
    }

    aoDigito('3');
    expect(confirmado, isNull);
    expect(digitoPendente, '3');

    tecladoAtivo = true;
    confirmarPorCodigo(digitoPendente!);
    digitoPendente = null;

    expect(confirmado, 12);
  });
}
