#!/usr/bin/env python3
# Gera a imagem do ecra "Modo Suporte" (mostrado no lado controlado quando o
# tecnico ativa o Modo Privado) e emite img.cpp no formato que a DLL
# WindowInjection (RustDeskTempTopMostWindow) espera: um PNG embutido como
# `const unsigned char g_img[]`.
#
# Fundo = o mesmo motivo do sistema (flutter/assets/pcnet_bg.jpg), bem clareado.
# Uso: python3 gen_support_screen.py   (corre a partir de res/privacy_mode/)
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
W, H = 1920, 1080

TITLE = "Modo Suporte"
SUBTITLE = "O Suporte está analisando seu computador"

bg = Image.open(os.path.join(REPO, 'flutter/assets/pcnet_bg.jpg')).convert('RGB')
scale = max(W / bg.width, H / bg.height)
bg = bg.resize((int(bg.width * scale) + 1, int(bg.height * scale) + 1), Image.LANCZOS)
bg = bg.crop(((bg.width - W) // 2, (bg.height - H) // 2,
             (bg.width - W) // 2 + W, (bg.height - H) // 2 + H))
# fundo ESCURO do sistema, como no arranque (nao clareado); leve escurecimento
# so para dar contraste ao texto, mantendo o padrao visivel. Um desfoque suave
# ajuda a legibilidade do texto e reduz muito o tamanho do PNG embutido.
bg = ImageEnhance.Brightness(bg).enhance(0.82)
bg = bg.filter(ImageFilter.GaussianBlur(1.4))

canvas = bg.copy()
draw = ImageDraw.Draw(canvas)

logo = Image.open(os.path.join(HERE, 'logo.png')).convert('RGBA').resize((300, 300), Image.LANCZOS)
canvas.paste(logo, ((W - 300) // 2, 150), logo)

FB = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
FR = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
f_title = ImageFont.truetype(FB, 120)
f_sub = ImageFont.truetype(FR, 60)

def center(text, font, y, fill):
    b = draw.textbbox((0, 0), text, font=font)
    draw.text(((W - (b[2] - b[0])) / 2, y), text, font=font, fill=fill)

# cores para fundo escuro: titulo verde vivo, subtitulo quase branco
center(TITLE, f_title, 500, (140, 220, 90))
draw.line([(W/2 - 380, 690), (W/2 + 380, 690)], fill=(140, 220, 90), width=3)
center(SUBTITLE, f_sub, 760, (235, 240, 235))

png_path = os.path.join(HERE, 'support_screen.png')
canvas.save(png_path, optimize=True)

data = open(png_path, 'rb').read()
lines = ['#include "pch.h"', '#include "./img.h"', '', 'const unsigned char g_img[] = {']
for i in range(0, len(data), 20):
    lines.append(''.join(f'0x{b:02x}, ' for b in data[i:i+20]).rstrip())
lines += ['};', '', 'const long long g_imgLen = sizeof(g_img);', '']
open(os.path.join(HERE, 'img.cpp'), 'w').write('\n'.join(lines))
print('PNG', len(data), 'bytes; img.cpp', os.path.getsize(os.path.join(HERE, 'img.cpp')), 'bytes')
