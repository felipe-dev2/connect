#!/usr/bin/env python3
# Gera o asset ANIMADO do ecra "Modo Suporte" para a DLL WindowInjection:
#   - g_base : PNG 1920x1080 (fundo escuro do sistema + textos, SEM logo) 24-bit
#   - g_slot : GIF 300x300 OPACO, loop que alterna a logo PCNET <-> servico-tecnico.gif
#             com efeito de giro (flip). Opaco (inclui o pedaco do fundo) => sem
#             quadrado branco e sem serrilhado; desenhado por cima da base no slot.
# Emite img.cpp (g_base + g_slot) e img.h. A DLL percorre os frames do GIF com
# Gdiplus::SelectActiveFrame num timer.
#
# Uso: python3 gen_support_anim.py   (a partir de res/privacy_mode/)
import os, math
from PIL import Image, ImageDraw, ImageFont, ImageEnhance, ImageFilter, ImageSequence

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
W, H = 1920, 1080
SLOT_X, SLOT_Y, SLOT = 810, 150, 300          # posicao/tamanho do slot (== logo atual)
TITLE = "Modo Suporte"
SUBTITLE = "O Suporte está analisando seu computador"
FB = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
FR = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'

# ---- base (fundo escuro + textos, sem logo) ----
bg = Image.open(os.path.join(REPO, 'flutter/assets/pcnet_bg.jpg')).convert('RGB')
s = max(W / bg.width, H / bg.height)
bg = bg.resize((int(bg.width * s) + 1, int(bg.height * s) + 1), Image.LANCZOS)
bg = bg.crop(((bg.width - W) // 2, (bg.height - H) // 2, (bg.width - W) // 2 + W, (bg.height - H) // 2 + H))
bg = ImageEnhance.Brightness(bg).enhance(0.82).filter(ImageFilter.GaussianBlur(1.4))
base = bg.convert('RGB')
d = ImageDraw.Draw(base)
def center(t, f, y, fill):
    b = d.textbbox((0, 0), t, font=f); d.text(((W - (b[2] - b[0])) / 2, y), t, font=f, fill=fill)
center(TITLE, ImageFont.truetype(FB, 120), 500, (140, 220, 90))
d.line([(W/2 - 380, 690), (W/2 + 380, 690)], fill=(140, 220, 90), width=3)
center(SUBTITLE, ImageFont.truetype(FR, 60), 760, (235, 240, 235))

# pedaco do fundo por tras do slot (para os frames opacos casarem com a base)
bgcrop = base.crop((SLOT_X, SLOT_Y, SLOT_X + SLOT, SLOT_Y + SLOT)).convert('RGBA')

# ---- elementos do slot ----
logo = Image.open(os.path.join(HERE, 'logo.png')).convert('RGBA').resize((SLOT, SLOT), Image.LANCZOS)
gif = Image.open(os.path.join(HERE, 'servico-tecnico.gif'))   # animacao-fonte versionada no repo
gear = [fr.convert('RGBA').resize((SLOT, SLOT), Image.LANCZOS)
        for i, fr in enumerate(ImageSequence.Iterator(gif)) if i % 4 == 0]   # ~45 frames

def opaque(elem_rgba):
    """funde o elemento (RGBA) sobre o pedaco do fundo -> RGB opaco 300x300."""
    f = bgcrop.copy(); f.alpha_composite(elem_rgba); return f.convert('RGB')

def flip(A, B, K=6):
    """giro em Y: A encolhe (0->90), troca p/ B e cresce (90->180)."""
    out = []
    for k in range(K):
        th = math.pi * k / (K - 1); cx = math.cos(th)
        src = A if cx >= 0 else B
        w = max(2, int(SLOT * abs(cx)))
        sq = src.resize((w, SLOT), Image.LANCZOS)
        c = Image.new('RGBA', (SLOT, SLOT), (0, 0, 0, 0)); c.alpha_composite(sq, ((SLOT - w) // 2, 0))
        out.append(c)
    return out

# Sequencia com tempos POR-FRAME (o giro e' rapido; a logo e o gear ficam ~8s cada).
# No Windows a DLL le estes delays do GIF (PropertyTagFrameDelay); no macOS o
# NSImageView respeita-os nativamente.
HOLD_MS = 8000          # tempo que a logo (e o gear) ficam visiveis
FLIP_MS = 55            # cada frame do giro (transicao rapida)
frames, durations = [], []
fl1 = flip(logo, gear[0])
fl2 = flip(gear[-1], logo)
gear_ms = max(40, HOLD_MS // len(gear))   # gear distribui ~8s pelos seus frames

frames.append(logo);          durations.append(HOLD_MS)      # logo fixa 8s
frames += fl1;                durations += [FLIP_MS] * len(fl1)   # gira -> gear
frames += gear;               durations += [gear_ms] * len(gear)  # gear anima ~8s
frames += fl2;                durations += [FLIP_MS] * len(fl2)   # gira -> logo
frames_rgb = [opaque(f) for f in frames]

# ---- guardar GIF do slot (opaco, com delays por-frame) ----
slot_path = os.path.join(HERE, 'slot.gif')
q = [f.quantize(colors=256, method=Image.FASTOCTREE) for f in frames_rgb]
q[0].save(slot_path, save_all=True, append_images=q[1:], duration=durations, loop=0, optimize=True)

# ---- guardar base PNG ----
base_path = os.path.join(HERE, 'support_base.png')
base.save(base_path, optimize=True)

# ---- emitir img.cpp + img.h ----
def emit_array(name, data):
    lines = [f'const unsigned char {name}[] = {{']
    for i in range(0, len(data), 20):
        lines.append(''.join(f'0x{b:02x}, ' for b in data[i:i+20]).rstrip())
    lines.append('};')
    return '\n'.join(lines)

base_bytes = open(base_path, 'rb').read()
slot_bytes = open(slot_path, 'rb').read()
cpp = ['#include "pch.h"', '#include "./img.h"', '',
       emit_array('g_base', base_bytes), '',
       'const long long g_baseLen = sizeof(g_base);', '',
       emit_array('g_slot', slot_bytes), '',
       'const long long g_slotLen = sizeof(g_slot);',
       '', '// posicao/tamanho do slot no espaco 1920x1080 da base',
       'const int g_slotX = %d;' % SLOT_X, 'const int g_slotY = %d;' % SLOT_Y,
       'const int g_slotW = %d;' % SLOT, 'const int g_slotH = %d;' % SLOT,
       'const int g_slotDelayMs = 90;', '']
open(os.path.join(HERE, 'img.cpp'), 'w').write('\n'.join(cpp))

h = ['#pragma once', '', '#include "framework.h"', '',
     'extern const unsigned char g_base[];', 'extern const long long g_baseLen;',
     'extern const unsigned char g_slot[];', 'extern const long long g_slotLen;',
     'extern const int g_slotX;', 'extern const int g_slotY;',
     'extern const int g_slotW;', 'extern const int g_slotH;',
     'extern const int g_slotDelayMs;', '']
open(os.path.join(HERE, 'img.h'), 'w').write('\n'.join(h))

print('base', len(base_bytes), 'bytes | slot.gif', len(slot_bytes), 'bytes |',
      len(frames_rgb), 'frames | img.cpp', os.path.getsize(os.path.join(HERE, 'img.cpp')), 'bytes')
