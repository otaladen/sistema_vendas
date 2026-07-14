#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Extrai cadastro de produtos de um dump MySQL do Chacal (.sql, MySqlBackup.NET)
para CSV UTF-8 compativel com Produtos > Importar CSV / Importar Chacal.

Exemplo:
  python tools/chacal_mysql_sql_para_csv.py ^
    -i "C:\\Users\\...\\Backup_13.07.202612_51_39.sql" ^
    -o "C:\\Users\\...\\produtos_chacal.csv"
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

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

_RE_INSERT = re.compile(
    r"^INSERT INTO `(?P<table>[^`]+)`\s*\((?P<cols>[^)]+)\)\s*VALUES\s*(?P<body>.*);\s*$",
    re.IGNORECASE | re.DOTALL,
)


def _split_sql_columns(cols: str) -> list[str]:
    return [c.strip().strip("`") for c in cols.split(",") if c.strip()]


def _parse_mysql_values(body: str) -> list[list[object | None]]:
    """Parseia lista de tuplas MySQL: (a,'b',NULL),(...)"""
    rows: list[list[object | None]] = []
    i = 0
    n = len(body)
    while i < n:
        while i < n and body[i] in " \t\r\n,":
            i += 1
        if i >= n:
            break
        if body[i] != "(":
            raise ValueError(f"Esperado '(' em offset {i}")
        i += 1
        row: list[object | None] = []
        while True:
            while i < n and body[i] in " \t\r\n":
                i += 1
            if i >= n:
                raise ValueError("INSERT truncado")
            ch = body[i]
            if ch == ")":
                i += 1
                rows.append(row)
                break
            if ch in "'\"":
                quote = ch
                i += 1
                buf: list[str] = []
                while i < n:
                    c = body[i]
                    if c == "\\" and i + 1 < n:
                        nxt = body[i + 1]
                        escapes = {
                            "0": "\0",
                            "n": "\n",
                            "r": "\r",
                            "t": "\t",
                            "Z": "\x1a",
                            "\\": "\\",
                            "'": "'",
                            '"': '"',
                        }
                        buf.append(escapes.get(nxt, nxt))
                        i += 2
                        continue
                    if c == quote:
                        # '' escape em SQL
                        if i + 1 < n and body[i + 1] == quote:
                            buf.append(quote)
                            i += 2
                            continue
                        i += 1
                        break
                    buf.append(c)
                    i += 1
                row.append("".join(buf))
            elif body.startswith("NULL", i) and (
                i + 4 >= n or body[i + 4] in ",)"
            ):
                row.append(None)
                i += 4
            else:
                start = i
                while i < n and body[i] not in ",)":
                    i += 1
                token = body[start:i].strip()
                if token == "":
                    row.append(None)
                else:
                    try:
                        if "." in token or "e" in token.lower():
                            row.append(float(token))
                        else:
                            row.append(int(token))
                    except ValueError:
                        row.append(token)
            while i < n and body[i] in " \t\r\n":
                i += 1
            if i < n and body[i] == ",":
                i += 1
                continue
            if i < n and body[i] == ")":
                continue
            if i < n and body[i] not in ",)":
                raise ValueError(f"Token inesperado em offset {i}: {body[i:i+20]!r}")
    return rows


def _fmt_num(val: object | None) -> str:
    if val is None:
        return ""
    try:
        n = float(val)
    except (TypeError, ValueError):
        return str(val).strip()
    if abs(n - round(n)) < 1e-9:
        return str(int(round(n)))
    return f"{n:.4f}".rstrip("0").rstrip(".")


def _fmt_txt(val: object | None) -> str:
    if val is None:
        return ""
    return str(val).strip()


def _as_float(val: object | None) -> float:
    if val is None:
        return 0.0
    if isinstance(val, (int, float)):
        return float(val)
    s = str(val).strip().replace(",", ".")
    if not s:
        return 0.0
    try:
        return float(s)
    except ValueError:
        return 0.0


def _as_int(val: object | None) -> int:
    n = int(round(_as_float(val)))
    return n if n > 0 else 0


def _load_lookup_map(
    rows: list[list[object | None]],
    cols: list[str],
    id_col: str,
    name_col: str,
) -> dict[int, str]:
    idx_id = cols.index(id_col)
    idx_nome = cols.index(name_col)
    out: dict[int, str] = {}
    for row in rows:
        if idx_id >= len(row) or idx_nome >= len(row):
            continue
        key = row[idx_id]
        if key is None:
            continue
        try:
            kid = int(key)
        except (TypeError, ValueError):
            continue
        out[kid] = _fmt_txt(row[idx_nome])
    return out


def _consume_insert(line: str) -> tuple[str, list[str], list[list[object | None]]] | None:
    m = _RE_INSERT.match(line.strip())
    if not m:
        return None
    table = m.group("table")
    cols = _split_sql_columns(m.group("cols"))
    body = m.group("body").rstrip()
    if body.endswith(";"):
        body = body[:-1]
    rows = _parse_mysql_values(body)
    return table, cols, rows


def exportar(entrada: Path, saida: Path, incluir_inativos: bool) -> tuple[int, int]:
    if not entrada.is_file():
        raise FileNotFoundError(f"Arquivo nao encontrado: {entrada}")

    marca: dict[int, str] = {}
    familia: dict[int, str] = {}
    grupo: dict[int, str] = {}
    subgrupo: dict[int, str] = {}
    unidade: dict[int, str] = {}
    estoque: dict[int, float] = {}
    produtos_cols: list[str] | None = None
    produtos_rows: list[list[object | None]] = []

    wanted = {
        "produto",
        "produto_marca",
        "produto_familia",
        "produto_grupo",
        "produto_sub_grupo",
        "produto_unidade",
        "produto_estoque",
    }

    with entrada.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.startswith("INSERT INTO `"):
                continue
            # Descartar tabelas irrelevantes rapidamente
            table_guess = line.split("`", 2)[1] if line.count("`") >= 2 else ""
            if table_guess not in wanted:
                continue
            parsed = _consume_insert(line)
            if parsed is None:
                continue
            table, cols, rows = parsed
            if table == "produto_marca":
                marca = _load_lookup_map(rows, cols, "ID_PRODUTO_MARCA", "NOME")
            elif table == "produto_familia":
                familia = _load_lookup_map(rows, cols, "ID_PRODUTO_FAMILIA", "NOME")
            elif table == "produto_grupo":
                grupo = _load_lookup_map(rows, cols, "ID_PRODUTO_GRUPO", "NOME")
            elif table == "produto_sub_grupo":
                subgrupo = _load_lookup_map(
                    rows, cols, "ID_PRODUTO_SUB_GRUPO", "NOME"
                )
            elif table == "produto_unidade":
                # Prefer SIGLA
                if "SIGLA" in cols:
                    unidade = _load_lookup_map(
                        rows, cols, "ID_PRODUTO_UNIDADE", "SIGLA"
                    )
            elif table == "produto_estoque":
                idx_id = cols.index("ID_PRODUTO")
                idx_saldo = cols.index("SALDO") if "SALDO" in cols else -1
                if idx_saldo < 0:
                    continue
                for row in rows:
                    if idx_id >= len(row):
                        continue
                    try:
                        pid = int(row[idx_id])  # type: ignore[arg-type]
                    except (TypeError, ValueError):
                        continue
                    estoque[pid] = estoque.get(pid, 0.0) + _as_float(row[idx_saldo])
            elif table == "produto":
                if produtos_cols is None:
                    produtos_cols = cols
                produtos_rows.extend(rows)

    if not produtos_cols or not produtos_rows:
        raise ValueError(
            "Dump sem INSERT de `produto`. Confira se e o backup MySQL completo do Chacal."
        )

    def col(name: str) -> int:
        assert produtos_cols is not None
        return produtos_cols.index(name)

    idx = {c: col(c) for c in produtos_cols}

    def get(row: list[object | None], name: str, default: object | None = None):
        i = idx.get(name)
        if i is None or i >= len(row):
            return default
        return row[i]

    def lookup_id(row: list[object | None], name: str, mapa: dict[int, str]) -> str:
        raw = get(row, name)
        if raw is None:
            return ""
        try:
            return mapa.get(int(raw), "")
        except (TypeError, ValueError):
            return ""

    saida.parent.mkdir(parents=True, exist_ok=True)
    exportados = 0
    pulados = 0

    with open(saida, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        w.writerow(CABECALHO)
        for row in produtos_rows:
            inativo = _fmt_txt(get(row, "INATIVO", "N")) or "N"
            if not incluir_inativos and inativo.upper() == "S":
                pulados += 1
                continue

            codigo = _fmt_txt(get(row, "CODIGO_INTERNO"))
            if not codigo:
                codigo = _fmt_txt(get(row, "GTIN"))
            if not codigo:
                codigo = _fmt_txt(get(row, "ID_PRODUTO"))
            nome = _fmt_txt(get(row, "NOME"))
            if not codigo or not nome:
                pulados += 1
                continue

            preco1 = _as_float(get(row, "PRECO1"))
            preco2 = _as_float(get(row, "PRECO2"))
            preco3 = _as_float(get(row, "PRECO3"))
            precovenda = preco1 if preco1 > 0 else (preco2 if preco2 > 0 else preco3)

            valor_compra = _as_float(get(row, "VALOR_COMPRA"))
            if valor_compra <= 0:
                valor_compra = _as_float(get(row, "VALOR_COMPRA_LIQUIDO"))

            und = lookup_id(row, "ID_PRODUTO_UNIDADE", unidade)
            if not und:
                und = _fmt_txt(get(row, "SIGLA")) or _fmt_txt(get(row, "UNIDADE_COMPRA")) or "UN"

            try:
                pid = int(get(row, "ID_PRODUTO"))  # type: ignore[arg-type]
            except (TypeError, ValueError):
                pid = -1
            est = estoque.get(pid, 0.0)

            w.writerow(
                [
                    codigo,
                    nome,
                    _fmt_num(precovenda),
                    _fmt_num(preco1),
                    _fmt_num(preco2),
                    _fmt_num(preco3),
                    _fmt_num(valor_compra),
                    _fmt_num(get(row, "CUSTO_MEDIO_LIQUIDO")),
                    _fmt_num(est),
                    _fmt_num(get(row, "ESTOQUE_MINIMO")),
                    und,
                    lookup_id(row, "ID_PRODUTO_MARCA", marca),
                    lookup_id(row, "ID_PRODUTO_FAMILIA", familia),
                    lookup_id(row, "ID_PRODUTO_GRUPO", grupo),
                    lookup_id(row, "ID_PRODUTO_SUB_GRUPO", subgrupo),
                    _fmt_txt(get(row, "NCM")),
                    _fmt_txt(get(row, "GTIN")),
                    inativo,
                ]
            )
            exportados += 1

    return exportados, pulados


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Converte dump MySQL Chacal (.sql) em CSV de produtos."
    )
    ap.add_argument("-i", "--entrada", required=True, type=Path)
    ap.add_argument("-o", "--saida", type=Path)
    ap.add_argument("--incluir-inativos", action="store_true")
    args = ap.parse_args()

    entrada = args.entrada.expanduser().resolve()
    saida = (
        args.saida.expanduser().resolve()
        if args.saida
        else entrada.with_name(entrada.stem + "_produtos.csv")
    )

    try:
        n, pulados = exportar(entrada, saida, args.incluir_inativos)
    except (OSError, ValueError) as e:
        print(f"Erro: {e}", file=sys.stderr)
        return 1

    print(f"Exportados: {n} produto(s) -> {saida}")
    if pulados:
        print(f"Ignorados/pulados: {pulados}")
    if n == 0:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
