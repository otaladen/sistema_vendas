#!/usr/bin/env python3
import sqlite3
import sys
from pathlib import Path

path = Path(sys.argv[1] if len(sys.argv) > 1 else "tools/chacal_backup.s3db")
conn = sqlite3.connect(path)
cur = conn.cursor()
tables = [r[0] for r in cur.execute(
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY 1"
)]
print(f"TABLES {len(tables)}")
for t in tables:
    print(t)

keywords = ("prod", "estoque", "item", "merc", "tab", "cad")
print("\n--- MATCH ---")
for t in tables:
    low = t.lower()
    if any(k in low for k in keywords):
        try:
            n = cur.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
            cols = [r[1] for r in cur.execute(f'PRAGMA table_info("{t}")')]
            print(f"{t}: rows={n} cols={len(cols)}")
            print("  " + ", ".join(cols[:25]))
            if len(cols) > 25:
                print(f"  ... +{len(cols)-25} more")
        except Exception as e:
            print(f"{t}: ERR {e}")

conn.close()
