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
MW, MH = 1280, 720                       # NSImageView escala p/ o ecra; menor => header menor
SLOT_X, SLOT_Y = 810, 150

base = Image.open(os.path.join(HERE, 'support_base.png')).convert('RGB')  # 1920x1080 sem logo
slot = Image.open(os.path.join(HERE, 'slot.gif'))

frames = []
for i in range(0, slot.n_frames, 2):      # subamostra p/ ~metade (header menor)
    slot.seek(i)
    f = base.copy()
    f.paste(slot.convert('RGB'), (SLOT_X, SLOT_Y))
    frames.append(f.resize((MW, MH), Image.LANCZOS))

gif_path = os.path.join(HERE, 'mac_support.gif')
q = [f.quantize(colors=256, method=Image.FASTOCTREE) for f in frames]
q[0].save(gif_path, save_all=True, append_images=q[1:], duration=90, loop=0, optimize=True)

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
