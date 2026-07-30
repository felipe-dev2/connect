#!/usr/bin/env python3
# Gera o header C com a GIF full-screen animada do "Modo Suporte" para macOS.
# No Mac o overlay e um NSImageView que anima a GIF nativamente, por isso basta
# uma GIF full-screen (fundo escuro + textos + slot logo<->gear com giro).
# Reusa support_base.png + slot.gif ja gerados por gen_support_anim.py.
# Emite src/platform/mac_support_screen.h com g_mac_support_gif[] + _len.
#
# Uso: python3 gen_mac_support.py  (a partir de res/privacy_mode/, apos gen_support_anim.py)
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
MW, MH = 960, 540                        # NSImageView escala p/ o ecra; menor => header menor
SLOT_X, SLOT_Y = 810, 150

base = Image.open(os.path.join(HERE, 'support_base.png')).convert('RGB')  # 1920x1080 sem logo
slot = Image.open(os.path.join(HERE, 'slot.gif'))

frames = []
# Mantem TODOS os frames e os delays por-frame do slot (o NSImageView respeita-os
# nativamente -> logo ~8s, giro rapido, gear ~8s, igual ao Windows).
from PIL import ImageSequence
durations = []
for fr in ImageSequence.Iterator(slot):
    f = base.copy()
    f.paste(fr.convert('RGB'), (SLOT_X, SLOT_Y))
    frames.append(f.resize((MW, MH), Image.LANCZOS))
    durations.append(fr.info.get('duration', 90))

gif_path = os.path.join(HERE, 'mac_support.gif')
# Paleta PARTILHADA por todos os frames -> o GIF guarda so as diferencas entre
# frames (a maioria muda so na regiao do slot) => ficheiro muito menor.
# A paleta e' construida de uma amostra com logo E com gear, para ter tanto os
# verdes/logo como o azul/amarelo do gear (senao o gear sairia cinzento).
sample = Image.new('RGB', (MW, MH * 2))
sample.paste(frames[0], (0, 0))                    # fase logo
sample.paste(frames[len(frames) // 2], (0, MH))    # fase gear
pal = sample.quantize(colors=256, method=Image.FASTOCTREE)
q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
q[0].save(gif_path, save_all=True, append_images=q[1:], duration=durations,
          loop=0, optimize=True, disposal=1)

data = open(gif_path, 'rb').read()
lines = ['// GERADO por res/privacy_mode/gen_mac_support.py -- NAO editar a mao.',
         '#pragma once', '',
         'static const unsigned char g_mac_support_gif[] = {']
for i in range(0, len(data), 20):
    lines.append(''.join('0x%02x, ' % b for b in data[i:i+20]).rstrip())
lines += ['};',
          'static const unsigned long g_mac_support_gif_len = sizeof(g_mac_support_gif);', '']
out = os.path.join(REPO, 'src', 'platform', 'mac_support_screen.h')
open(out, 'w').write('\n'.join(lines))
print('gif', len(data), 'bytes | frames', len(frames), '| header', os.path.getsize(out), 'bytes ->', out)
