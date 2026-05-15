from pathlib import Path

p = Path(__file__).resolve().parent.parent / "lib" / "ui" / "ponto_de_venda_page.dart"
lines = p.read_text(encoding="utf-8").splitlines()
chunk = lines[3297:3559]
first = chunk[0]
prefix_len = len(first) - len(first.lstrip())
dedented = []
for line in chunk:
    if line.strip():
        if len(line) >= prefix_len and line.startswith(first[:prefix_len]):
            dedented.append(line[prefix_len:])
        else:
            dedented.append(line.lstrip())
    else:
        dedented.append("")
body = "\n".join("    " + (ln if ln else "") for ln in dedented)
method = "  Widget _buildColunaCatalogoPdV(BuildContext context) {\n" + body + "\n  }\n"
anchor = "  String _rotuloParcela(int parcelas) {"
text = p.read_text(encoding="utf-8")
if anchor not in text:
    raise SystemExit("anchor missing")
if "_buildColunaCatalogoPdV" in text:
    raise SystemExit("already exists")
text = text.replace(anchor, method + "\n" + anchor, 1)
p.write_text(text, encoding="utf-8")
print("inserted", len(method.splitlines()), "lines")
