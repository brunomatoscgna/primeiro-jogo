# Fim dos Tempos — jogo para a game jam do Lupi

Contexto para continuar o trabalho. Leia inteiro antes de mexer.

## A jam
- 4 horas, em dupla, para o **Lupi** (videogame brasileiro). Jogo em **Lua**.
- Vence o jogo **mais bem resolvido**, não o mais ambicioso.
- **Regra: toda a arte deve vir de assets gratuitos do itch.io.** Formas desenhadas com
  `ui.rectfill`/`ui.line` contam só como provisórias (confirmar com a organização se
  HUD e texto com `ui.print`/`ui.rectfill` são aceitos).

## O jogo
- Tema: **falha no sistema**. Plataforma 2D, estilo Prince of Persia antigo.
- Cidade vertical sem energia após uma catástrofe. O jogador começa no **telhado**,
  desce **7 andares** pegando **3 peças** e religa o **gerador** no subsolo.
- Com energia: janelas do prédio e da cidade acendem, faíscas param.
- Uma fase só. Controles: setas andam; Z ou CIMA pula.

## Repositório
- Fork: `github.com/brunomatoscgna/primeiro-jogo` (original: `lupi-org-br/primeiro-jogo`).
- **O Lupi baixa o jogo do GitHub a cada push.**
- **A cada push, AUMENTE `version` no `lupi.yaml`** (ex.: 1.25 → 1.26). Sem isso o Lupi
  continua com a versão em cache (isso já nos enganou: ficamos testando código antigo).
- Jogo de referência que funciona: `github.com/lupi-org-br/caio-pernocas`.

```
primeiro-jogo/
├── game.lua      entrada: update() -> loop(Frame), protegido por pcall (mostra erros na tela)
├── main.lua      todo o jogo: física, câmera, desenho, HUD
├── mapa.lua      a fase em texto (MAPA), 30 colunas x 63 linhas, 9 linhas por andar
├── lupi.yaml     name / public / version
├── db32.png      paleta DawnBringer 32 (gera o módulo "palette")
└── img/
    ├── t/0.png .. 31.png        um PNG 16x16 por tile -> Sprites.img.t["5"]
    ├── fundo_off/1..12.png      cidade apagada, 12 pedaços 80x136 (opcional)
    └── fundo_on/1..12.png       cidade acesa
```

Fora do repositório: `assets_tools/montar_folha.py` (gera `img/` a partir do pack).

## API do Lupi (o que já sabemos)
- Tela 480x270, 60 FPS. `update()` chamado a cada frame (o `game.lua` conta os frames).
- Paleta registrada **todo frame**: `for i=1,#Palette do ui.palset(i-1, Palette[i]) end`.
- Cores por hex: `Palette.hex(0xFFFFFF)` → índice (precisa ser cor da DB32).
- Desenho: `ui.cls`, `ui.rectfill(x0,y0,x1,y1,c)`, `ui.line`, `ui.circfill`, `ui.print(t,x,y,c)`,
  `ui.camera(x,y)`, `ui.clip`. Entrada: `ui.btn(LEFT)`, `ui.btnp(BTN_Z)`.
  Utilitário: `ui.mid(a,b,c)`, `ui.stat(7)` = FPS.
- `require` funciona com módulos em pastas (`require "poi.pad.pad"`).
- **Sprites (descoberto no Caio Pernocas):** `require "sprites"` cria a tabela `Sprites`,
  que espelha as pastas do repositório: `poi/pad/tiles.png` → `Sprites.poi.pad.tiles`.
  Nomes numéricos com string: `Sprites.poi.cherry[tostring(n)]`.
  A tabela é preguiçosa: `pairs(Sprites)` mostra vazia, mas o acesso direto funciona.
- `ui.spr(ref, x, y, flip_x, flip_y)` desenha a **imagem inteira**.
- `ui.tile(ref, id, x, y)` exige folha com **margem de "régua"** (corner cinza no topo-esquerdo,
  régua em cima e à esquerda, de 1 tile de tamanho) que indica o tamanho do tile.
  Por isso usamos **um PNG por tile com `ui.spr`**, sem `ui.tile`.
- `ui.tile`/`ui.spr` exigem **tabela** como referência (string dá "table expected").
- Possível limite de **~11.000 px por imagem** (não confirmado; o Caio tem imagem de 40.960 px).
  Nossas imagens: maior 10.880 px.

## Estado atual do código (main.lua)
- Física: gravidade 0.35, pulo -5.6 (sobe ~47 px ≈ 3 blocos), velocidade 2.2,
  colisão por eixo, encaixe exato na borda do bloco, `no_chao` testando 1 px abaixo.
- Mapa (`mapa.lua`): `#` parede, `=` viga, `w` janela, `^` faíscas (só os 5 px de baixo dão
  choque), `P` peça, `G` gerador, `S` início. Choque → volta ao checkpoint (início do andar).
- Auto-tile das paredes (9-slice + barras) calculado uma vez em `AUTOTILE`.
- Câmera vertical suave. HUD: andar, peças, FPS, energia.
- Chaves no topo: `USAR_SPRITES`, `USAR_FUNDO`. Sem sprites → desenhos provisórios.
- Diagnóstico na tela quando `img/t/0.png` não é encontrado.
- Fase validada por um "robô" numa imitação da API: termina em ~23 s jogando perfeito.

### IDs dos tiles (img/t/N.png)
0–8 parede 3x3 · 9 parede solta · 10–12 barra de parede (esq/meio/dir) ·
13–15 viga (esq/meio/dir) · 31 viga solta · 16 fundo interno · 24 fundo aceso ·
17/18 janela (cima/baixo) · 19/20 janela acesa · 21 peça (turbina) ·
22/23 gerador (cima/baixo) · 25–30 raio de neon 2x3.

## PROBLEMA EM ABERTO
Desde que os sprites passaram a ser carregados de verdade, **o Lupi mostra tela preta**,
mesmo sem a pasta do fundo. Último passo enviado: `game.lua` com `pcall` que escreve
"ERRO NO JOGO:" e a mensagem na tela + FPS no HUD.
- Se aparecer erro → corrigir pela linha indicada.
- Se abrir com FPS baixo → otimizar (hoje ~600 `ui.spr` por frame; o fundo interno usa
  510 sozinho — trocar por `ui.rectfill` de uma cor ou desenhar só onde precisa).
- Se continuar preto sem texto → o Lupi trava antes do Lua: testar `USAR_SPRITES = false`,
  depois remover `img/`. Comparar com os PNGs do Caio (RGBA ou indexado com a paleta dele).
- Rollback seguro se precisar: `git checkout ae5908f -- .` (versão só com desenhos
  provisórios), aumentar a versão, commit, push.

## Assets
- Pack em uso: **Cyberpunk Tileset - 16X16** (itch.io): Tileset, Props, Light Props,
  Modular Buildings, Parallax background (Night). Cores convertidas para DB32 pelo
  `montar_folha.py` (com ajustes manuais em `FORCAR`).
- **Faltam:** personagem 16x16 com animação (andar/pular) e um sprite de perigo
  (faíscas/fios/espinhos). Baixar do itch.io (grátis) e incluir no `montar_folha.py`.
- `CREDITOS.txt`: preencher autor, link e licença de cada pack.

## Próximos passos
1. Resolver a tela preta (ver acima).
2. Personagem com sprite e animação; sprite de perigo.
3. Telas de início e fim; sons (`sfx.fx`, `sfx.music`).
4. Polimento e créditos. Não adicionar recursos novos na última meia hora.

## Preferências do Bruno
Respostas curtas, linguagem simples, em português.