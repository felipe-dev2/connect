#!/usr/bin/env python3
# Gera res/mac-tray-color-x2.png, o icone a cores da barra de menus do macOS.
#
# Nao e arte nova: e derivado do que ja existe no repositorio.
#   . a forma  -> canal alfa de res/mac-tray-dark-x2.png (o glifo de dois
#                 rectangulos ligados que ja usamos em modo template)
#   . a cor    -> o verde da marca PCNET-IT (#8cc63f), o mesmo do console
#   . o disco  -> a silhueta circular de res/mac-icon.png, sem a legenda
#                 "PCNET IT solutions", que a 18pt fica ilegivel
#
# O crate tray-icon escala a imagem para 18pt de altura, por isso o ficheiro
# tem de ser quadrado; 44x44 iguala o icone template que ja la esta.
#
# Correr (nao e preciso Pillow na maquina):
#   docker run --rm -v "$PWD/res:/res" python:3.12-slim \
#     sh -lc "pip install -q pillow && python -I /res/gen_mac_tray_color.py"

from PIL import Image, ImageDraw
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GLYPH = os.path.join(HERE, "mac-tray-dark-x2.png")
OUT = os.path.join(HERE, "mac-tray-color-x2.png")

SIZE = 44          # igual ao icone template
GLYPH_SIZE = 32    # cabe dentro do disco com folga
LIME = (140, 198, 63, 255)   # #8cc63f - verde da marca
RIM = (42, 87, 17, 255)      # #2a5711 - aro escuro, da contorno na barra clara
INK = (17, 23, 15, 255)      # #11170f - glifo, 8.9:1 de contraste sobre o verde

alpha = Image.open(GLYPH).convert("RGBA").getchannel("A")
if alpha.size != (SIZE, SIZE):
    raise SystemExit("mac-tray-dark-x2.png deixou de ser %dx%d" % (SIZE, SIZE))

icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ImageDraw.Draw(icon).ellipse(
    [1, 1, SIZE - 2, SIZE - 2], fill=LIME, outline=RIM, width=2
)

glyph = Image.new("RGBA", (GLYPH_SIZE, GLYPH_SIZE), INK)
glyph.putalpha(alpha.resize((GLYPH_SIZE, GLYPH_SIZE), Image.LANCZOS))
icon.alpha_composite(glyph, ((SIZE - GLYPH_SIZE) // 2, (SIZE - GLYPH_SIZE) // 2))

icon.save(OUT, optimize=True)
print("escrito", OUT, icon.size)
