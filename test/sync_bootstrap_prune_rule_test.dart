import 'package:flutter_test/flutter_test.dart';

/// Espelha a regra SQL do `/sync/pull?bootstrap=1` (documentacao viva).
bool produtoEntraNoBootstrap({
  required String op,
  required Map<String, dynamic> payload,
}) {
  if (op == 'delete') return true;
  final ativo = payload['ativo'];
  if (ativo == null) return true;
  if (ativo == false || ativo == 0 || ativo == 'false' || ativo == '0') {
    return false;
  }
  return true;
}

bool vendaEntraNoBootstrap({
  required String op,
  required Map<String, dynamic> payload,
  required DateTime cutoffUtc,
}) {
  if (op == 'delete') return false;
  final status = (payload['status'] ?? '').toString();
  if (status == 'orcamento') return true;
  final data = DateTime.tryParse((payload['data'] ?? '').toString())?.toUtc();
  if (data == null) return false;
  return !data.isBefore(cutoffUtc);
}

void main() {
  final cutoff = DateTime.utc(2026, 7, 13);

  test('produto: so ativos (e deletes)', () {
    expect(
      produtoEntraNoBootstrap(op: 'upsert', payload: {'ativo': true}),
      isTrue,
    );
    expect(
      produtoEntraNoBootstrap(op: 'upsert', payload: {'ativo': false}),
      isFalse,
    );
    expect(
      produtoEntraNoBootstrap(op: 'delete', payload: {'ativo': false}),
      isTrue,
    );
  });

  test('venda: orcamento aberto em qualquer data', () {
    expect(
      vendaEntraNoBootstrap(
        op: 'upsert',
        payload: {
          'status': 'orcamento',
          'data': '2025-01-01T00:00:00.000Z',
        },
        cutoffUtc: cutoff,
      ),
      isTrue,
    );
  });

  test('venda: finalizada so se criada nos ultimos 7 dias', () {
    expect(
      vendaEntraNoBootstrap(
        op: 'upsert',
        payload: {
          'status': 'finalizada',
          'data': '2026-07-15T12:00:00.000Z',
        },
        cutoffUtc: cutoff,
      ),
      isTrue,
    );
    expect(
      vendaEntraNoBootstrap(
        op: 'upsert',
        payload: {
          'status': 'finalizada',
          'data': '2026-06-01T12:00:00.000Z',
        },
        cutoffUtc: cutoff,
      ),
      isFalse,
    );
  });
}
