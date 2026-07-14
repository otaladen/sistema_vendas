#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Extrai cadastro de produtos de um backup Chacal (.s3db, SQLite) para CSV UTF-8
compativel com Produtos > Importar CSV no sistema de vendas.

Requisitos: Python 3.9+ (stdlib apenas: sqlite3, csv, argparse)

Exemplo:
  python tools/chacal_s3db_para_csv.py ^
    -i "C:\\Users\\...\\Backup_12.07.2026.s3db" ^
    -o "C:\\Users\\...\\produtos_chacal.csv"

Depois, no app: Produtos > Importar CSV > escolher o arquivo gerado.
"""

from __future__ import annotations

import argparse
import csv
import sqlite3
import sys
from pathlib import Path


SQL_PRODUTOS = """
SELECT
    p.ID_PRODUTO,
    COALESCE(NULLIF(TRIM(p.CODIGO_INTERNO), ''), TRIM(CAST(p.GTIN AS TEXT)), CAST(p.ID_PRODUTO AS TEXT)) AS codigo,
    TRIM(CAST(p.GTIN AS TEXT)) AS gtin,
    TRIM(p.NOME) AS nome,
    TRIM(COALESCE(p.NOME_PDV, '')) AS nome_pdv,
    TRIM(COALESCE(p.NCM, '')) AS ncm,
    COALESCE(p.PRECO1, 0) AS preco1,
    COALESCE(p.PRECO2, 0) AS preco2,
    COALESCE(p.PRECO3, 0) AS preco3,
    COALESCE(p.VALOR_COMPRA, p.VALOR_COMPRA_LIQUIDO, 0) AS precocusto,
    COALESCE(p.CUSTO_MEDIO_LIQUIDO, 0) AS customedio,
    COALESCE(p.ESTOQUE_MINIMO, 0) AS estminimo,
    COALESCE(p.INATIVO, 'N') AS inativo,
    TRIM(COALESCE(u.SIGLA, p.SIGLA, p.UNIDADE_COMPRA, 'UN')) AS unidade,
    TRIM(COALESCE(m.NOME, '')) AS marca,
    TRIM(COALESCE(f.NOME, '')) AS familia,
    TRIM(COALESCE(g.NOME, '')) AS grupo,
    TRIM(COALESCE(sg.NOME, '')) AS subgrupo,
    COALESCE(es.estoque, 0) AS estoque
FROM produto p
LEFT JOIN produto_unidade u ON u.ID_PRODUTO_UNIDADE = p.ID_PRODUTO_UNIDADE
LEFT JOIN produto_marca m ON m.ID_PRODUTO_MARCA = p.ID_PRODUTO_MARCA
LEFT JOIN produto_familia f ON f.ID_PRODUTO_FAMILIA = p.ID_PRODUTO_FAMILIA
LEFT JOIN produto_grupo g ON g.ID_PRODUTO_GRUPO = p.ID_PRODUTO_GRUPO
LEFT JOIN produto_sub_grupo sg ON sg.ID_PRODUTO_SUB_GRUPO = p.ID_PRODUTO_SUB_GRUPO
LEFT JOIN (
    SELECT ID_PRODUTO, SUM(COALESCE(SALDO, 0)) AS estoque
    FROM produto_estoque
    GROUP BY ID_PRODUTO
) es ON es.ID_PRODUTO = p.ID_PRODUTO
WHERE (? = 1 OR COALESCE(p.INATIVO, 'N') <> 'S')
ORDER BY p.ID_PRODUTO
"""

CABECALHO = [
    "codigo",
    "nome",
    "precovenda",
    "preco1",
    "preco2",
    "preco3",
    "precocusto",
    "customedio",
    "estoque",
    "estminimo",
    "unidade",
    "marca",
    "familia",
    "grupo",
    "subgrupo",
    "ncm",
    "gtin",
    "inativo",
]


def _fmt_num(val: object) -> str:
    if val is None:
        return ""
    try:
        n = float(val)
    except (TypeError, ValueError):
        return str(val).strip()
    if abs(n - round(n)) < 1e-9:
        return str(int(round(n)))
    return f"{n:.4f}".rstrip("0").rstrip(".")


def _fmt_txt(val: object) -> str:
    if val is None:
        return ""
    return str(val).strip()


def exportar(
    entrada: Path,
    saida: Path,
    incluir_inativos: bool,
) -> tuple[int, int]:
    if not entrada.is_file():
        raise FileNotFoundError(f"Arquivo nao encontrado: {entrada}")

    con = sqlite3.connect(str(entrada))
    con.row_factory = sqlite3.Row
    try:
        tables = {
            r[0]
            for r in con.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        if "produto" not in tables:
            raise ValueError(
                "Arquivo .s3db sem tabela 'produto' — nao parece backup Chacal."
            )

        rows = con.execute(
            SQL_PRODUTOS, (1 if incluir_inativos else 0,)
        ).fetchall()
    finally:
        con.close()

    saida.parent.mkdir(parents=True, exist_ok=True)
    exportados = 0
    pulados = 0

    with open(saida, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        w.writerow(CABECALHO)
        for row in rows:
            codigo = _fmt_txt(row["codigo"])
            nome = _fmt_txt(row["nome"])
            if not codigo or not nome:
                pulados += 1
                continue
            preco1 = float(row["preco1"] or 0)
            preco2 = float(row["preco2"] or 0)
            preco3 = float(row["preco3"] or 0)
            precovenda = preco1 if preco1 > 0 else (preco2 if preco2 > 0 else preco3)
            w.writerow(
                [
                    codigo,
                    nome,
                    _fmt_num(precovenda),
                    _fmt_num(preco1),
                    _fmt_num(preco2),
                    _fmt_num(preco3),
                    _fmt_num(row["precocusto"]),
                    _fmt_num(row["customedio"]),
                    _fmt_num(row["estoque"]),
                    _fmt_num(row["estminimo"]),
                    _fmt_txt(row["unidade"]) or "UN",
                    _fmt_txt(row["marca"]),
                    _fmt_txt(row["familia"]),
                    _fmt_txt(row["grupo"]),
                    _fmt_txt(row["subgrupo"]),
                    _fmt_txt(row["ncm"]),
                    _fmt_txt(row["gtin"]),
                    _fmt_txt(row["inativo"]),
                ]
            )
            exportados += 1

    return exportados, pulados


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Converte backup Chacal (.s3db) em CSV para importacao de produtos."
    )
    ap.add_argument(
        "-i",
        "--entrada",
        required=True,
        type=Path,
        help="Caminho do arquivo .s3db do Chacal",
    )
    ap.add_argument(
        "-o",
        "--saida",
        type=Path,
        help="CSV de saida (padrao: mesmo nome do .s3db com extensao .csv)",
    )
    ap.add_argument(
        "--incluir-inativos",
        action="store_true",
        help="Incluir produtos marcados como inativos (INATIVO = S)",
    )
    args = ap.parse_args()

    entrada: Path = args.entrada.expanduser().resolve()
    saida: Path = (
        args.saida.expanduser().resolve()
        if args.saida
        else entrada.with_suffix(".csv")
    )

    try:
        n, pulados = exportar(entrada, saida, args.incluir_inativos)
    except (OSError, sqlite3.Error, ValueError) as e:
        print(f"Erro: {e}", file=sys.stderr)
        return 1

    print(f"Exportados: {n} produto(s) -> {saida}")
    if pulados:
        print(f"Ignorados (sem codigo ou nome): {pulados}")
    if n == 0:
        print(
            "Aviso: nenhum produto exportado. Confira se este e o backup completo "
            "do Chacal (menu de backup/restauracao), nao apenas um arquivo de teste.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
