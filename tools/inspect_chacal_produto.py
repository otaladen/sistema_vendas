#!/usr/bin/env python3
import sqlite3
import sys
from pathlib import Path

path = Path(sys.argv[1] if len(sys.argv) > 1 else "tools/chacal_backup.s3db")
conn = sqlite3.connect(path)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

for table in ("produto", "produto_estoque", "backup"):
    print(f"\n=== {table} ===")
    cols = [r[1] for r in cur.execute(f'PRAGMA table_info("{table}")')]
    print(f"cols={len(cols)}")
    rows = cur.execute(f'SELECT * FROM "{table}" LIMIT 3').fetchall()
    print(f"rows_sample={len(rows)}")
    count = cur.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
    print(f"count={count}")
    if rows:
        for r in rows:
            d = dict(r)
            # print key fields only for produto
            if table == "produto":
                keys = [
                    "ID_PRODUTO", "CODIGO_INTERNO", "GTIN", "NOME", "NCM",
                    "PRECO1", "PRECO2", "PRECO3", "PRECO4", "PRECO5",
                    "CUSTO", "CUSTO_MEDIO", "MARGEM_LUCRO_PRECO1",
                    "ID_PRODUTO_MARCA", "ID_PRODUTO_FAMILIA", "ID_PRODUTO_GRUPO",
                    "ID_PRODUTO_SUB_GRUPO", "INATIVO", "ID_PRODUTO_UNIDADE",
                ]
                for k in keys:
                    if k in d:
                        print(f"  {k}: {d[k]}")
            elif table == "produto_estoque":
                print(dict(r))
            else:
                for k, v in list(d.items())[:8]:
                    print(f"  {k}: {str(v)[:120]}")

# list all produto columns with PRECO/CUSTO in name
print("\n=== produto price/cost columns ===")
cols = [r[1] for r in cur.execute('PRAGMA table_info("produto")')]
for c in cols:
    u = c.upper()
    if any(x in u for x in ("PRECO", "CUSTO", "MARGEM", "ESTOQUE", "GTIN", "CODIGO", "NCM", "NOME", "INATIVO", "UNIDADE")):
        print(c)

conn.close()
