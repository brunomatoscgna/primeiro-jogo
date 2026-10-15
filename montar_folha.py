import sys, os
from PIL import Image

DB32 = ['000000','222034','45283c','663931','8f563b','df7126','d9a066','eec39a',
        'fbf236','99e550','6abe30','37946e','4b692f','524b24','323c39','3f3f74',
        '306082','5b6ee1','639bff','5fcde4','cbdbfc','ffffff','9badb7','847e87',
        '696a6a','595652','76428a','ac3232','d95763','d77bba','8f974a','8a6f30']
PAL = [tuple(int(h[i:i+2], 16) for i in (0, 2, 4)) for h in DB32]

def mais_proxima(c):
    r, g, b = c
    def dist(p):  # distância com peso perceptual simples
        dr, dg, db = r - p[0], g - p[1], b - p[2]
        return 2*dr*dr + 4*dg*dg + 3*db*db
    return min(PAL, key=dist)

# Ajustes manuais: cores do pack que a conversão automática deixaria feias
FORCAR = {
    (0x2c, 0x31, 0x4f): (0x45, 0x28, 0x3c),   # recheio da parede -> roxo escuro
    (0x40, 0x47, 0x72): (0x3f, 0x3f, 0x74),   # borda da parede
    (0x47, 0x48, 0x6c): (0x22, 0x20, 0x34),   # fundo interno do prédio -> azul-noite
}
cache = dict(FORCAR)
def para_db32(im):
    im = im.convert('RGBA'); px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 128:
                px[x, y] = (0, 0, 0, 0)
            else:
                k = (r, g, b)
                if k not in cache: cache[k] = mais_proxima(k)
                px[x, y] = cache[k] + (255,)
    return im

def tile(im, idx, larg_tiles):
    x, y = (idx % larg_tiles) * 16, (idx // larg_tiles) * 16
    return im.crop((x, y, x + 16, y + 16))

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
tileset = Image.open(f'{src}/Tileset/Tileset.png')
modular = Image.open(f'{src}/Modular Buildings/Modular_Building_tileset.png')
props   = Image.open(f'{src}/Props/Props.png')
luzes   = Image.open(f'{src}/Props/Light_Props.png')

# (id na folha) -> (imagem de origem, id do tile na origem, tiles por linha)
MAPA_FOLHA = {
    # parede 9-slice (Tileset 17..51) -> 0..8
    0: (tileset, 17, 16), 1: (tileset, 18, 16), 2: (tileset, 19, 16),
    3: (tileset, 33, 16), 4: (tileset, 34, 16), 5: (tileset, 35, 16),
    6: (tileset, 49, 16), 7: (tileset, 50, 16), 8: (tileset, 51, 16),
    # parede: bloco solto e barra horizontal
    9: (tileset, 25, 16), 10: (tileset, 21, 16), 11: (tileset, 22, 16), 12: (tileset, 23, 16),
    # viga cinza: barra e bloco solto
    13: (tileset, 117, 16), 14: (tileset, 118, 16), 15: (tileset, 119, 16),
    # fundo interno do prédio (16 apagado; 24 = aceso, gerado abaixo)
    16: (modular, 86, 32),
    # janela (2 blocos de altura)
    17: (modular, 41, 32), 18: (modular, 73, 32),
    # peça (turbina) e gerador (máquina verde, 2 de altura)
    21: (props, 98, 16), 22: (props, 39, 16), 23: (props, 55, 16),
    # raio de neon (2 de largura x 3 de altura)
    25: (luzes, 61, 16), 26: (luzes, 62, 16), 27: (luzes, 77, 16),
    28: (luzes, 78, 16), 29: (luzes, 93, 16), 30: (luzes, 94, 16),
    # viga cinza: bloco solto
    31: (tileset, 121, 16),
}

folha = Image.new('RGBA', (256, 32), (0, 0, 0, 0))
for dst, (im, idx, lt) in MAPA_FOLHA.items():
    folha.paste(tile(im, idx, lt), ((dst % 16) * 16, (dst // 16) * 16))

# cópias que serão recoloridas: janela acesa (19,20) e fundo aceso (24)
for dst, srcid in ((19, 17), (20, 18), (24, 16)):
    t = folha.crop(((srcid % 16) * 16, (srcid // 16) * 16, (srcid % 16) * 16 + 16, (srcid // 16) * 16 + 16)).convert('RGBA')
    folha.paste(t, ((dst % 16) * 16, (dst // 16) * 16))

folha = para_db32(folha)

def recolorir(dst, de, para):
    box = ((dst % 16) * 16, (dst // 16) * 16, (dst % 16) * 16 + 16, (dst // 16) * 16 + 16)
    t = folha.crop(box); px = t.load()
    for y in range(16):
        for x in range(16):
            if px[x, y][:3] == de and px[x, y][3]:
                px[x, y] = para + (255,)
    folha.paste(t, box[:2])

VIDRO = mais_proxima((0x37, 0x20, 0x4d))           # cor do vidro após a conversão
for dst in (19, 20): recolorir(dst, VIDRO, (0xfb, 0xf2, 0x36))
recolorir(24, (0x22, 0x20, 0x34), (0x3f, 0x3f, 0x74))

folha.save(f'{out}/folha.png')

# fundo: junta as 4 camadas Night e completa a altura para 272 (múltiplo de 16)
fundo = Image.new('RGBA', (480, 272), (0, 0, 0, 255))
for i in (1, 2, 3, 4):
    fundo.alpha_composite(Image.open(f'{src}/Parallax background/Night/Layer{i}.png').convert('RGBA'), (0, 0))
fundo = para_db32(fundo)
fundo.save(f'{out}/fundo_on.png')

# versão apagada: janelas claras viram escuras
px = fundo.load()
for y in range(fundo.height):
    for x in range(fundo.width):
        r, g, b, a = px[x, y]
        if r + g + b > 450:
            px[x, y] = (0x22, 0x20, 0x34, 255)
fundo.save(f'{out}/fundo_off.png')
print('ok:', folha.size, fundo.size)