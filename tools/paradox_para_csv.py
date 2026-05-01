#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Converte tabela PARADOX nativa para CSV UTF-8 (cabecalho + dados).
Usa pypxlib (pxlib) — le o formato binario do Paradox, nao e o mesmo que DBF dBase.

Instalacao:
  pip install -r tools/requirements-paradox.txt

Exemplos:
  python tools/paradox_para_csv.py -i "C:\\WINSIC\\TABEST1.DB" -o "C:\\tabest1.csv"
  python tools/paradox_para_csv.py -i "C:\\tmp\\TABEST1.DB" --listar-tipos

Correcao importante (precos vazios no CSV):
  O pypxlib trata campos tipo BCD (muito usados para dinheiro no Paradox) como "bytes".
  Ao exportar, esses bytes eram decodificados como texto — PrecoVenda/PrecoCusto ficavam
  em branco no CSV e o import Flutter caia em R$ 0,01. Este script substitui esses campos
  pela leitura correta via PX_get_data_bcd do pxlib.

  Muitos TabEst antigos nao gravam PrecoVenda no campo estruturado, mas colocam valores
  no texto de Obs (ex.: "MARCA 60,00 PDEDIDO 58,00"). Quando PrecoVenda sai vazio na leitura,
  o script pode copiar o primeiro preço encontrado em Obs para a coluna PrecoVenda no CSV.

  Textos com Enter dentro (Obs/Memo) sao normalizados para espaco — senao o arquivo teria
  linhas soltas no Notepad e o numero de colunas por linha ficaria errado no import.

O caminho do arquivo deve conter apenas caracteres ASCII (evite pastas com acento no nome),
ou o pxlib pode falhar ao abrir.

Encoding de textos alfanumericos no Paradox (Brasil): tente cp1252 (padrao aqui) ou cp850.
"""

from __future__ import annotations

import argparse
import ctypes
import csv
import re
import sys
from datetime import date, datetime, time
from pathlib import Path


def _sanitizar_texto_celula(s: str) -> str:
    """
    Quebras de linha / CR / LF dentro de Alfa, Obs, Memo etc. viram linhas extras no arquivo.
    O Notepad mostra como texto solto (ex.: PDEDIDO 58,00) e o importador desloca colunas.
    """
    if not s:
        return ""
    s = s.replace("\x00", "")
    s = s.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
    s = s.replace("\t", " ")
    while "  " in s:
        s = s.replace("  ", " ")
    return s.strip()


def _celula_para_csv(val: object, enc_fallback: str) -> str:
    if val is None:
        return ""
    if isinstance(val, bool):
        return "1" if val else "0"
    if isinstance(val, (date, datetime, time)):
        return _sanitizar_texto_celula(val.isoformat())
    if isinstance(val, bytes):
        return _sanitizar_texto_celula(val.decode(enc_fallback, errors="replace"))
    if isinstance(val, float):
        s = repr(val) if val == val else ""  # NaN
        return _sanitizar_texto_celula(s) if s else ""
    return _sanitizar_texto_celula(str(val))


_re_preco_no_texto = re.compile(
    r"\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2}|\d+\.\d{2}"
)


def _parse_float_br_ou_ponto(s: str) -> float | None:
    s = s.strip().replace(" ", "")
    if not s:
        return None
    try:
        if "," in s and "." in s:
            return float(s.replace(".", "").replace(",", "."))
        if "," in s:
            return float(s.replace(",", "."))
        return float(s)
    except ValueError:
        return None


def _extrair_primeiro_preco_para_celula_csv(texto: str) -> str:
    """
    Primeiro valor monetario plausivel em texto livre (Obs TabEst).
    Retorna string com ponto decimal para o CSV / import Flutter (ex.: '60.0').
    """
    raw = texto.strip()
    if not raw:
        return ""
    m = _re_preco_no_texto.search(raw)
    if m:
        v = _parse_float_br_ou_ponto(m.group(0))
        if v is not None and v == v and abs(v) < 1e7:
            return repr(v)
    m2 = re.search(r"\b(\d{2,6})\b", raw)
    if m2:
        try:
            iv = float(m2.group(1))
            if 10 <= iv <= 999999:
                return repr(iv)
        except ValueError:
            pass
    return ""


def _indice_coluna_ci(names: list[str], candidatos: tuple[str, ...]) -> int:
    norm = [n.strip().lower().replace(" ", "").replace("_", "") for n in names]
    for c in candidatos:
        cc = c.strip().lower().replace(" ", "").replace("_", "")
        try:
            return norm.index(cc)
        except ValueError:
            continue
    return -1


def _celula_paradox_segura(row, name: str, enc: str, erros: list[int]) -> str:
    """Le um campo; se a data/valor for invalida no Paradox, exporta vazio e segue."""
    try:
        return _celula_para_csv(row[name], enc)
    except Exception:
        erros[0] += 1
        return ""


def _px_doc_free(pxdoc, ptr) -> None:
    if not ptr:
        return
    free_fn = pxdoc.contents.free
    if free_fn:
        free_fn(pxdoc, ctypes.cast(ptr, ctypes.c_void_p))


def _bcd_packed_fallback(data: bytes, decimals: int) -> float | None:
    """
    Ultimo recurso: BCD empacotado (2 digitos por byte, nibble final pode ser sinal).
    Usado quando PX_get_data_bcd falha mas o buffer tem digitos validos.
    """
    if not data:
        return None
    digits: list[int] = []
    for b in data:
        hi = (b >> 4) & 0x0F
        lo = b & 0x0F
        if hi <= 9:
            digits.append(hi)
        if lo <= 9:
            digits.append(lo)
        elif lo in (0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F):
            break
        else:
            break
    while digits and digits[0] == 0:
        digits.pop(0)
    if not digits:
        return None
    dec = max(0, min(int(decimals), 12))
    if dec > len(digits):
        digits = [0] * (dec - len(digits)) + digits
    split = len(digits) - dec
    if split <= 0:
        int_part = "0"
        frac = "".join(map(str, digits))
    else:
        int_part = "".join(map(str, digits[:split])) or "0"
        frac = "".join(map(str, digits[split:]))
    try:
        return float(int_part + "." + frac) if frac else float(int_part)
    except ValueError:
        return None


def _bcd_via_pxlib(pxdoc, px_get_data_bcd, buf, decimals: int) -> str | None:
    """
    PX_get_data_bcd espera char** na ultima posicao; pypxlib usa POINTER(POINTER(c_char)).
    Padrao correto: POINTER(c_char)() + byref -> pxlib preenche o ponteiro alocado.
    """
    out = ctypes.POINTER(ctypes.c_char)()
    rc = px_get_data_bcd(pxdoc, buf, int(decimals), ctypes.byref(out))
    if rc != 1:
        return None
    ptr_val = ctypes.cast(out, ctypes.c_void_p).value
    if not ptr_val:
        return None
    try:
        raw = ctypes.string_at(out)
        if not raw:
            return None
        return raw.decode("ascii", errors="replace").strip() or None
    finally:
        _px_doc_free(pxdoc, ptr_val)


def _bcd_money_field_factory(px_get_data_bcd):
    """Constroi classe Field para BCD usando PX_get_data_bcd + fallbacks."""
    from pypxlib import Field
    from pypxlib.pxlib_ctypes import pxfCurrency, pxfNumber

    class BCDMoneyField(Field):
        """Equivalente monetario BCD; substitui BytesField que quebrava export."""

        def __init__(self, pxdoc, index: int, type_: int, decimals: int, flen: int):
            super().__init__(index, type_)
            self._pxdoc = pxdoc
            self._decimals = int(decimals)
            self._flen = max(0, int(flen))

        def deserialize(self, pxval):
            if pxval.isnull == b"\x01":
                return None
            # PX_retrieve_record as vezes ja preenche o valor como Number/$ no px_val.
            tv = int(pxval.type)
            if tv in (pxfNumber, pxfCurrency):
                dv = float(pxval.value.dval)
                if dv == dv and abs(dv) < 1e13:
                    return dv

            vu = pxval.value.str
            ln = int(vu.len)
            if ln <= 0 and self._flen > 0:
                ln = self._flen
            if ln <= 0:
                return None
            raw = vu.val.data
            if raw is None:
                return None
            data_bytes = ctypes.string_at(raw, ln)
            buf = (ctypes.c_ubyte * ln)()
            ctypes.memmove(buf, data_bytes, ln)

            dec_candidates = []
            for d in (
                self._decimals,
                2,
                0,
                4,
                self._decimals + 2,
                max(0, self._decimals - 2),
                6,
                8,
            ):
                if 0 <= d <= 15:
                    dec_candidates.append(d)
            seen: set[int] = set()
            dec_candidates = [x for x in dec_candidates if not (x in seen or seen.add(x))]

            for dec in dec_candidates:
                txt = _bcd_via_pxlib(self._pxdoc, px_get_data_bcd, buf, dec)
                if txt:
                    try:
                        return float(txt.replace(",", "."))
                    except ValueError:
                        continue

            for dec in dec_candidates:
                packed = _bcd_packed_fallback(data_bytes, dec)
                if packed is not None:
                    return packed

            return None

    return BCDMoneyField


def _struct_ou_contents(v):
    """Compat: algumas builds expõem ponteiro, outras struct direto."""
    return v.contents if hasattr(v, "contents") else v


def _tipo_campo_num(px_ftype) -> int:
    if isinstance(px_ftype, (bytes, bytearray)):
        return ord(px_ftype)
    if isinstance(px_ftype, str):
        return ord(px_ftype)
    return int(px_ftype)


def _nome_campo_monetario_bytes_tabest(fname: str) -> bool:
    """
    Campos Alfa/Bytes com nome de dinheiro (TabEst as vezes marca Bytes onde e BCD).
    Nao inclui preco1/2/3: costumam ser Number no Paradox; forcar BCD quebraria.
    """
    n = fname.lower().replace(" ", "").replace("_", "")
    return any(
        x in n
        for x in (
            "precovenda",
            "valorvenda",
            "vrvenda",
            "precocusto",
            "customedio",
            "custmedio",
        )
    )


def _substituir_campos_bcd(table, stderr) -> int:
    """
    pypxlib mapeia pxfBCD para BytesField; corrige para valores numericos no CSV.
    Retorna quantidade de campos substituidos.
    """
    from pypxlib.pxlib_ctypes import PX_get_data_bcd, pxfBCD, pxfBytes

    if PX_get_data_bcd is None:
        print(
            "Aviso: PX_get_data_bcd indisponivel neste pxlib; campos BCD podem sair vazios.",
            file=stderr,
        )
        return 0

    BCDMoneyField = _bcd_money_field_factory(PX_get_data_bcd)

    head = table.pxdoc.contents.px_head.contents
    nomes: list[str] = []
    for fname, fld in list(table.fields.items()):
        pf = _struct_ou_contents(head.px_fields[fld.index])
        t = _tipo_campo_num(pf.px_ftype)
        if t == pxfBCD or (t == pxfBytes and _nome_campo_monetario_bytes_tabest(fname)):
            dec = int(pf.px_fdc)
            flen = int(pf.px_flen)
            table.fields[fname] = BCDMoneyField(
                table.pxdoc, fld.index, fld.type, dec, flen
            )
            nomes.append(fname)

    if nomes:
        print(
            f"Campos monetarios tratados como BCD ({len(nomes)}): {', '.join(nomes)}",
            file=stderr,
        )
    return len(nomes)


def _listar_tipos_campos(table, stderr) -> None:
    """Mostra nome, tipo Paradox e decimais de cada campo (debug TabEst)."""
    head = table.pxdoc.contents.px_head.contents
    for i in range(head.px_numfields):
        pf = _struct_ou_contents(head.px_fields[i])
        nome = pf.px_fname.data.decode("ascii", errors="replace")
        tipo = _tipo_campo_num(pf.px_ftype)
        print(f"  {i + 1:3}  {nome:32}  type={tipo:3}  len={pf.px_flen:3}  dec={pf.px_fdc}", file=stderr)


def _apply_pypxlib_correcoes() -> None:
    """
    Paradox guarda muitas datas 'em branco' como SDN invalido; pxlib devolve ano < 1
    e pypxlib estoura ValueError. Tratamos como None (celula vazia no CSV).
    """
    from datetime import datetime

    from pypxlib import DateField, TimeField, TimestampField

    _orig_days = DateField._deserialize_days.__func__

    @classmethod
    def _deserialize_days_seguro(cls, days: int):
        try:
            return _orig_days(cls, days)
        except ValueError:
            return None

    DateField._deserialize_days = _deserialize_days_seguro

    @classmethod
    def _deserialize_timestamp_seguro(cls, pxval_value):
        try:
            days = int(pxval_value.dval / 86400000)
            ms_rem = int(pxval_value.dval % 86400000)
            d = DateField._deserialize_days(days)
            t = TimeField._deserialize_ms(ms_rem)
            if d is None or t is None:
                return None
            return datetime.combine(d, t)
        except (ValueError, TypeError, OverflowError):
            return None

    TimestampField._deserialize = _deserialize_timestamp_seguro


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Paradox (.DB / tabela nativa) -> CSV UTF-8 para import no sistema_vendas"
    )
    parser.add_argument(
        "-i",
        "--entrada",
        required=True,
        help="Arquivo de tabela Paradox (ex.: TABEST1.DB ou .DBF se for paradox nativo)",
    )
    parser.add_argument(
        "-o",
        "--saida",
        help="CSV de saida (padrao: mesmo nome com extensao .csv)",
    )
    parser.add_argument(
        "-e",
        "--encoding",
        default="cp1252",
        help="Encoding dos campos texto Alfa no Paradox (cp1252, cp850, latin1)",
    )
    parser.add_argument(
        "--listar-tipos",
        action="store_true",
        help="Lista tipos dos campos no stderr e sai (sem gerar CSV).",
    )
    parser.add_argument(
        "--sem-preco-de-obs",
        action="store_true",
        help="Nao preenche PrecoVenda a partir do texto Obs quando o campo vier vazio.",
    )
    args = parser.parse_args()

    entrada = Path(args.entrada)
    if not entrada.is_file():
        print(f"Arquivo nao encontrado: {entrada}", file=sys.stderr)
        return 1

    saida = Path(args.saida) if args.saida else entrada.with_suffix(".csv")

    try:
        from pypxlib import PXError, Table
    except ImportError:
        print("Instale: pip install -r tools/requirements-paradox.txt", file=sys.stderr)
        return 1

    _apply_pypxlib_correcoes()

    # Caminho como string — pxlib usa encoding ascii no Windows para o path
    path_str = str(entrada.resolve())
    try:
        path_str.encode("ascii")
    except UnicodeEncodeError:
        print(
            "ERRO: o caminho do arquivo contem caracteres nao-ASCII (ex.: acentos na pasta).\n"
            "Copie o .DB para uma pasta simples, ex.: C:\\tmp\\TABEST1.DB e tente de novo.",
            file=sys.stderr,
        )
        return 1

    try:
        erros_celula = [0]
        with Table(path_str, encoding=args.encoding) as table:
            _ = table.fields  # materializa cache antes do patch BCD
            if args.listar_tipos:
                print(f"Tipos de campos: {entrada.name}", file=sys.stderr)
                _listar_tipos_campos(table, sys.stderr)
                return 0
            _substituir_campos_bcd(table, sys.stderr)
            names = list(table.fields.keys())
            idx_pv = _indice_coluna_ci(
                names,
                ("precovenda", "valorvenda", "vrvenda"),
            )
            idx_obs = _indice_coluna_ci(
                names,
                ("obs", "observacao", "observacoes", "complemento"),
            )
            linhas_precovenda_de_obs = 0
            with open(saida, "w", newline="", encoding="utf-8") as f:
                # QUOTE_ALL: nomes tipo "ARCO ... 12,8" ou texto com virgula devem ficar entre aspas,
                # senao o importador interpreta virgula como separador e PrecoVenda desloca (vira 0,01).
                w = csv.writer(
                    f,
                    quoting=csv.QUOTE_ALL,
                    doublequote=True,
                    lineterminator="\r\n",
                )
                w.writerow(names)
                n = 0
                for row in table:
                    vals = [
                        _celula_paradox_segura(row, name, args.encoding, erros_celula)
                        for name in names
                    ]
                    if (
                        not args.sem_preco_de_obs
                        and idx_pv >= 0
                        and idx_obs >= 0
                        and idx_pv < len(vals)
                        and idx_obs < len(vals)
                    ):
                        cel_pv = vals[idx_pv].strip()
                        if not cel_pv:
                            obs_txt = vals[idx_obs]
                            inj = _extrair_primeiro_preco_para_celula_csv(obs_txt)
                            if inj:
                                vals[idx_pv] = inj
                                linhas_precovenda_de_obs += 1
                    if len(vals) != len(names):
                        raise RuntimeError(
                            f"Linha {n + 1}: esperado {len(names)} colunas, veio {len(vals)}."
                        )
                    w.writerow(vals)
                    n += 1
    except PXError as ex:
        print(f"PXLib/pypxlib: {ex}", file=sys.stderr)
        print(
            "\nDicas:\n"
            "  - Use o arquivo de TABELA na pasta original (ex.: TABEST1.DB + indices .PX etc.).\n"
            "  - Se faltar arquivo memo/BLOB, copie tambem o .MB com o mesmo nome base.\n"
            "  - Arquivo 'DBF dBase' de outro programa nao e Paradox; use tools/dbf_para_csv.py.\n",
            file=sys.stderr,
        )
        return 1
    except PermissionError as ex:
        print(f"Sem permissao para gravar: {saida}", file=sys.stderr)
        print(
            "No Windows, evite salvar na raiz C:\\ (ex.: C:\\tabest1.csv).\n"
            "Use Documentos, Area de Trabalho ou a pasta do projeto, por exemplo:\n"
            '  -o "%USERPROFILE%\\Desktop\\tabest1.csv"\n'
            '  -o "C:\\Projetos\\sistema_vendas\\tabest1.csv"',
            file=sys.stderr,
        )
        return 1

    print(f"OK: {n} linhas -> {saida}")
    if linhas_precovenda_de_obs > 0:
        print(
            f"PrecoVenda preenchido a partir de Obs em {linhas_precovenda_de_obs} linha(s).",
            file=sys.stderr,
        )
    if erros_celula[0]:
        print(
            f"Aviso: {erros_celula[0]} celula(s) com valor ilegivel "
            "(ex.: data corrompida no Paradox) foram exportadas em branco.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
