#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Converte arquivo DBF (DBase III/IV, FoxPro, etc.) para CSV UTF-8 com cabecalho,
sem limite de linhas — para importar em Produtos > importar CSV.

Tenta duas bibliotecas: dbfread e, se falhar, dbf (ethanfurman), que aceita
mais variantes de arquivo.

Requisitos:
  pip install -r tools/requirements-dbf.txt

Exemplo:
  python tools/dbf_para_csv.py -i "C:\\dados\\TABEST1.DBF" -o "C:\\dados\\tabest1.csv"

Se acentos ficarem errados:
  python tools/dbf_para_csv.py -i arquivo.dbf -o saida.csv -e cp1252
  python tools/dbf_para_csv.py -i arquivo.dbf -o saida.csv -e latin1
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


def _hex_preview(path: Path, n: int = 48) -> str:
    with open(path, "rb") as f:
        data = f.read(n)
    return " ".join(f"{b:02x}" for b in data)


def _diag_cabecalho(path: Path) -> str:
    """Primeiro byte do DBF dBase costuma ser 0x03, 0x83, 0x8B, 0xF5, etc."""
    with open(path, "rb") as f:
        b0 = f.read(1)
    if not b0:
        return "arquivo vazio"
    v = b0[0]
    comuns = {
        0x03: "dBASE III/IV (sem .fpt memo) — formato DBF classico",
        0x83: "dBASE III+ com memo",
        0x8B: "dBASE IV com memo",
        0xF5: "FoxPro com memo",
        0x30: "Visual FoxPro",
    }
    desc = comuns.get(v, None)
    if desc:
        return f"primeiro byte 0x{v:02x}: {desc}"
    return (
        f"primeiro byte 0x{v:02x}: nao parece cabecalho DBF dBase usual — "
        "pode ser Paradox nativo (.db), outro formato, ou arquivo corrompido/renomeado"
    )


def _celula_csv(val: object, encoding_fallback: str) -> str:
    if val is None:
        return ""
    if isinstance(val, (bytes, bytearray)):
        return val.decode(encoding_fallback, errors="replace")
    s = str(val)
    return s


def _export_dbfread(path: Path, encoding: str, saida: Path) -> int:
    from dbfread import DBF

    table = DBF(
        str(path),
        encoding=encoding,
        char_decode_errors="replace",
        ignore_missing_memofile=True,
    )
    names = table.field_names
    with open(saida, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        w.writerow(names)
        n = 0
        for record in table:
            row = [_celula_csv(record.get(name), encoding) for name in names]
            w.writerow(row)
            n += 1
    return n


def _export_ethan_dbf(path: Path, encoding: str, saida: Path) -> int:
    import dbf

    # codepage do pacote dbf: nomes como 'cp1252', 'latin1'
    table = dbf.Table(str(path), codepage=encoding)
    with table:
        names = list(table.field_names)
        with open(saida, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
            w.writerow(names)
            n = 0
            for record in table:
                row = []
                for name in names:
                    try:
                        v = record[name]
                    except (KeyError, AttributeError):
                        v = getattr(record, name.replace(" ", "_"), None)
                    row.append(_celula_csv(v, encoding))
                w.writerow(row)
                n += 1
    return n


def main() -> int:
    parser = argparse.ArgumentParser(
        description="DBF -> CSV UTF-8 (gratuito). Tenta dbfread e depois dbf (ethanfurman)."
    )
    parser.add_argument(
        "-i",
        "--entrada",
        required=True,
        help="Caminho do arquivo .dbf",
    )
    parser.add_argument(
        "-o",
        "--saida",
        help="Caminho do .csv de saida (padrao: mesmo nome da entrada com extensao .csv)",
    )
    parser.add_argument(
        "-e",
        "--encoding",
        default="cp1252",
        help="Encoding / codepage dos textos no DBF (cp1252, latin1, ...)",
    )
    parser.add_argument(
        "--so-dbf",
        action="store_true",
        help="Usar somente a biblioteca dbf (ethanfurman), sem tentar dbfread",
    )
    args = parser.parse_args()

    entrada = Path(args.entrada)
    if not entrada.is_file():
        print(f"Arquivo nao encontrado: {entrada}", file=sys.stderr)
        return 1

    saida = Path(args.saida) if args.saida else entrada.with_suffix(".csv")

    print(f"Diagnostico: {_diag_cabecalho(entrada)}", file=sys.stderr)
    print(f"Primeiros bytes: {_hex_preview(entrada)}", file=sys.stderr)

    erros: list[str] = []

    if not args.so_dbf:
        try:
            n = _export_dbfread(entrada, args.encoding, saida)
            print(f"OK (dbfread): {n} linhas de dados -> {saida}")
            return 0
        except Exception as ex:
            erros.append(f"dbfread: {type(ex).__name__}: {ex}")

    try:
        n = _export_ethan_dbf(entrada, args.encoding, saida)
        print(f"OK (dbf/ethanfurman): {n} linhas de dados -> {saida}")
        return 0
    except ImportError:
        print(
            "Instale as dependencias: pip install -r tools/requirements-dbf.txt",
            file=sys.stderr,
        )
        return 1
    except Exception as ex:
        erros.append(f"dbf: {type(ex).__name__}: {ex}")

    print("\nNao foi possivel ler como DBF dBase/FoxPro.", file=sys.stderr)
    for line in erros:
        print(f"  - {line}", file=sys.stderr)
    print(
        "\nCausas comuns:\n"
        "  - O arquivo e tabela PARADOX nativa (.db), nao DBase — renomear para .dbf nao ajuda.\n"
        "    Solucao: no conversor, exportar de novo como 'Arquivo DBase III' ou CSV.\n"
        "  - O arquivo esta corrompido ou incompleto (falta .DBT memo junto).\n"
        "  - Copie o .dbf da pasta original do sistema (ex.: C:\\WINSIC) e tente de novo.\n",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
