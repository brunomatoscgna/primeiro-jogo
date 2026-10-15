require "palette"
local MOD_SPRITES = require "sprites"
require "mapa"

-- ============================================================
-- FALHA NO SISTEMA — cidade vertical sem energia
-- Desça os 20 andares, pegue as peças e religue o gerador.
-- Setas: andar | Z ou CIMA: pular | CIMA/BAIXO na escada: subir/descer
-- Desvie das caveiras e dos fantasmas.
-- Comprimido (TADALA): por alguns segundos, encostar num inimigo o derruba.
-- Tomar outro com o TADALA ligado: o coração não aguenta.
-- ============================================================

TILE = 16
TELA_L, TELA_A = 480, 270
VERSAO = "1.34"   -- manter igual ao "version" do lupi.yaml
MAPA_L = #MAPA[1]
MAPA_A = #MAPA

-- Cores (paleta DawnBringer 32 do db32.png)
C = {
  ceu       = 0x000000,
  estrela   = 0x9badb7,
  fundo     = 0x222034,   -- parede interna escura
  fundo_on  = 0x3f3f74,
  tijolo    = 0x45283c,
  tijolo_l  = 0x663931,
  viga      = 0x595652,
  rebite    = 0x847e87,
  janela    = 0x323c39,
  janela_on = 0xfbf236,
  fio       = 0x696a6a,
  faisca    = 0x5fcde4,
  branco    = 0xffffff,
  peca      = 0x6abe30,
  peca_l    = 0x99e550,
  gerador   = 0x847e87,
  vermelho  = 0xac3232,
  verde     = 0x6abe30,
  player    = 0xdf7126,
  pele      = 0xeec39a,
  lanterna  = 0xfbf236,
  texto     = 0xcbdbfc,
}

local function cor(nome) return Palette.hex(C[nome]) end

-- ------------------------------------------------------------
-- Mapa: leitura de blocos
-- ------------------------------------------------------------
local function bloco(col, lin)          -- col/lin começam em 0
  col, lin = math.floor(col), math.floor(lin)
  if lin < 0 then return " " end
  if col < 0 or col >= MAPA_L or lin >= MAPA_A then return "#" end
  return MAPA[lin + 1]:sub(col + 1, col + 1)
end

local function solido(c) return c == "#" or c == "=" end

local function solido_px(x, y)
  return solido(bloco(x // TILE, y // TILE))
end

-- topo de escada: dá para ficar em pé em cima (como uma plataforma)
local function topo_escada(col, lin)
  return bloco(col, lin) == "H" and bloco(col, lin - 1) ~= "H"
end

-- ------------------------------------------------------------
-- SPRITES — pack "Cyberpunk Tileset 16x16" (itch.io), convertido p/ DB32
--   folha.png    : todos os tiles do jogo (ids abaixo)
--   fundo_off.png: cidade apagada | fundo_on.png: cidade acesa
--
-- >>> AJUSTE AQUI: aponte para as referências de sprite do Lupi. <<<
-- Enquanto FOLHA for nil, o jogo usa os desenhos provisórios.
-- ------------------------------------------------------------
-- Procura a referência de cada PNG da pasta Sprites/ pelos nomes mais prováveis.
local function achar_sprite(nome)
  local Maiusc = nome:sub(1, 1):upper() .. nome:sub(2)
  local candidatos = {
    function() return Sprites.Sprites[nome] end,   -- Sprites/<nome>.png
    function() return MOD_SPRITES[nome] end,
    function() return Sprites[nome] end,
    function() return sprites[nome] end,
    function() return SPRITES[nome] end,
    function() return _G[nome] end,
    function() return _G[Maiusc] end,
    function() return _G[nome:upper()] end,
    function() return Sprites[nome .. ".png"] end,
    function() return MOD_SPRITES[nome .. ".png"] end,
  }
  for _, f in ipairs(candidatos) do
    local ok, v = pcall(f)
    if ok and type(v) == "table" then return v end
  end
  return nil
end

FOLHA     = achar_sprite("folha")       -- Sprites/folha.png
FUNDO_OFF = achar_sprite("fundo_off")   -- Sprites/fundo_off.png
FUNDO_ON  = achar_sprite("fundo_on")    -- Sprites/fundo_on.png
FOLHA_COLS = 16                -- tiles por linha na folha.png

-- Personagens (GIFs de Sprites/Characters convertidos p/ PNG, 4 quadros cada):
--   Sprites/grandpa_walk/1.png -> Sprites.Sprites.grandpa_walk["1"]
local function quadros(nome)
  local ok, q = pcall(function()
    local pasta, q = Sprites.Sprites[nome], {}
    for i = 1, 4 do
      q[i] = pasta[tostring(i)]
      if type(q[i]) ~= "table" then return nil end
    end
    return q
  end)
  if ok then return q end
  return nil
end

ANIM = {
  grandpa = { parado = quadros("grandpa_idle"), andando = quadros("grandpa_walk") },
  skull   = { parado = quadros("skull_idle"),   andando = quadros("skull_walk") },
  ghost   = { parado = quadros("ghost_idle"),   andando = quadros("ghost_walk") },
}

SPR = {
  parede_solta = 9,                          -- 0..8 = parede 3x3 (9-slice)
  barra_e = 10, barra_m = 11, barra_d = 12,  -- parede de 1 bloco de altura
  viga_e = 13, viga_m = 14, viga_d = 15, viga_solta = 31,
  fundo = 16, fundo_on = 24,
  janela = 17, janela_on = 19,               -- +16 = parte de baixo
  peca = 21,
  gerador = 22,                              -- +1 = parte de baixo
  raio = 25,                                 -- 2x3 tiles: 25..30
}

-- Escolhe o tile de cada bloco pelos vizinhos (auto-tile), uma vez só.
local function vizinhos(col, lin, igual)
  return igual(bloco(col, lin - 1)), igual(bloco(col, lin + 1)),
         igual(bloco(col - 1, lin)), igual(bloco(col + 1, lin))
end

local function tile_parede(col, lin)
  local cima, baixo, esq, dir = vizinhos(col, lin, function(c) return c == "#" end)
  if not cima and not baixo then                      -- piso fino
    if not esq and not dir then return SPR.parede_solta end
    if not esq then return SPR.barra_e end
    if not dir then return SPR.barra_d end
    return SPR.barra_m
  end
  if not esq and not dir then return SPR.parede_solta end -- coluna fina
  local l = (not cima) and 0 or ((not baixo) and 2 or 1)
  local c = (not esq) and 0 or ((not dir) and 2 or 1)
  return l * 3 + c
end

local function tile_viga(col, lin)
  local _, _, esq, dir = vizinhos(col, lin, function(c) return c == "=" end)
  if not esq and not dir then return SPR.viga_solta end
  if not esq then return SPR.viga_e end
  if not dir then return SPR.viga_d end
  return SPR.viga_m
end

AUTOTILE = {}
for lin = 0, MAPA_A - 1 do
  AUTOTILE[lin] = {}
  for col = 0, MAPA_L - 1 do
    local c = bloco(col, lin)
    if c == "#" then AUTOTILE[lin][col] = tile_parede(col, lin)
    elseif c == "=" then AUTOTILE[lin][col] = tile_viga(col, lin) end
  end
end


-- ------------------------------------------------------------
-- Estado do jogo
-- ------------------------------------------------------------
pecas = {}           -- peças ainda no mapa
gerador = nil
inicio = { x = 32, y = 32 }
inimigos = {}
comprimidos = {}

for lin = 1, MAPA_A do
  for col = 1, MAPA_L do
    local c = MAPA[lin]:sub(col, col)
    local x, y = (col - 1) * TILE, (lin - 1) * TILE
    if c == "P" then table.insert(pecas, { x = x, y = y, pega = false }) end
    if c == "G" then gerador = { x = x, y = y } end
    if c == "S" then inicio = { x = x, y = y } end
    if c == "C" then table.insert(comprimidos, { x = x, y = y, pego = false }) end
    local fundo = (lin - 1) // ALTURA_ANDAR      -- 0 no telhado: mais fundo, mais rápido
    if c == "K" then   -- caveira: anda no chão e vira nas paredes/beiradas
      table.insert(inimigos, { tipo = "skull", x0 = x + 2, y0 = y + TILE - 16,
                               w = 11, h = 16, v0 = 0.5 + fundo * 0.03 })
    end
    if c == "F" then   -- fantasma: atravessa tudo, vai e volta flutuando
      table.insert(inimigos, { tipo = "ghost", x0 = x, y0 = y,
                               w = 14, h = 16, v0 = 0.6 + fundo * 0.04, fase = col })
    end
  end
end
ANDARES = MAPA_A // ALTURA_ANDAR

-- põe cada inimigo vivo no lugar de origem
local function reiniciar_inimigos()
  for i, e in ipairs(inimigos) do
    e.x, e.y, e.base_y = e.x0, e.y0, e.y0
    e.vx = (i % 2 == 0) and e.v0 or -e.v0
    e.morto, e.sumiu = false, false
  end
end
reiniciar_inimigos()

TOTAL_PECAS = #pecas

player = {
  x = inicio.x, y = inicio.y, w = 10, h = 19,   -- altura do desenho (cabeça não entra na viga)
  vx = 0, vy = 0, no_chao = false, dir = 1,
  escada = false,             -- true enquanto está pendurado na escada
  pecas = 0,
  vida = 3, invencivel = 0,   -- invencivel: frames piscando após um choque
  tadala = 0,                 -- frames restantes do efeito do comprimido
}
VIDA_MAX = 3
TADALA_FRAMES = 8 * 60        -- 8 segundos
checkpoint = { x = inicio.x, y = inicio.y }
camera_y = 0
energia = false
mensagem, mensagem_t = nil, 0

-- Física
GRAVIDADE  = 0.35
PULO       = -6.0   -- sobe ~51 px (3 blocos)
VEL        = 2.2
VEL_QUEDA  = 7
VEL_ESCADA = 1.6

local function avisar(txt, frames)
  mensagem, mensagem_t = txt, frames or 120
end

-- ------------------------------------------------------------
-- Física do jogador (colisão eixo por eixo)
-- ------------------------------------------------------------
local function colide_em(x, y, w, h)
  return solido_px(x, y) or solido_px(x + w - 1, y)
      or solido_px(x, y + h - 1) or solido_px(x + w - 1, y + h - 1)
      or solido_px(x, y + h // 2) or solido_px(x + w - 1, y + h // 2)
end

-- corpo encostando numa escada (coluna do meio do jogador)
local function na_escada(p)
  local col = (p.x + p.w / 2) // TILE
  for lin = p.y // TILE, (p.y + p.h - 1) // TILE do
    if bloco(col, lin) == "H" then return true end
  end
  return false
end

-- pés exatamente em cima do topo de uma escada
local function sobre_escada(p)
  local pe = p.y + p.h
  if math.abs(pe - math.floor(pe / TILE + 0.5) * TILE) > 0.01 then return false end
  local lin = math.floor(pe / TILE + 0.5)
  return topo_escada(p.x // TILE, lin) or topo_escada((p.x + p.w - 1) // TILE, lin)
end

local function mover_player()
  local p = player
  local cima, baixo = ui.btn(UP), ui.btn(DOWN)

  p.vx = 0
  if ui.btn(LEFT)  then p.vx = -VEL; p.dir = -1 end
  if ui.btn(RIGHT) then p.vx =  VEL; p.dir =  1 end

  -- agarrar a escada: CIMA encostado nela, ou BAIXO em cima dela
  if not p.escada and p.vx == 0 and
     ((cima and na_escada(p)) or (baixo and (sobre_escada(p) or (na_escada(p) and not p.no_chao)))) then
    p.escada = true
    p.x = ((p.x + p.w / 2) // TILE) * TILE + (TILE - p.w) / 2   -- centraliza
  end

  if p.escada then
    p.vy = cima and -VEL_ESCADA or (baixo and VEL_ESCADA or 0)
    if p.vx ~= 0 then p.escada = false end            -- solta para o lado
    if ui.btnp(BTN_Z) then p.escada = false; p.vy = PULO end
  else
    if p.no_chao and (ui.btnp(BTN_Z) or ui.btnp(UP)) then p.vy = PULO end
    if not p.no_chao then p.vy = math.min(p.vy + GRAVIDADE, VEL_QUEDA) end
  end

  -- eixo X: se bater, encosta exatamente na borda do bloco
  local nx = p.x + p.vx
  if colide_em(nx, p.y, p.w, p.h) then
    if p.vx > 0 then
      nx = (math.floor(nx + p.w - 1) // TILE) * TILE - p.w
    else
      nx = (math.floor(nx) // TILE + 1) * TILE
    end
  end
  p.x = nx

  -- eixo Y: idem (chão ou teto)
  local ny = p.y + p.vy
  if colide_em(p.x, ny, p.w, p.h) then
    if p.vy > 0 then
      ny = (math.floor(ny + p.h - 1) // TILE) * TILE - p.h
    else
      ny = (math.floor(ny) // TILE + 1) * TILE
    end
    p.vy = 0
  elseif not p.escada and p.vy > 0 then
    -- caindo: o topo da escada segura como uma plataforma
    local antes, depois = p.y + p.h, ny + p.h
    local lin = math.floor(depois / TILE)
    local t = lin * TILE
    if antes <= t and depois > t and
       (topo_escada(p.x // TILE, lin) or topo_escada((p.x + p.w - 1) // TILE, lin)) then
      ny, p.vy = t - p.h, 0
    end
  end
  p.y = ny

  -- saiu da escada (chegou no topo ou no fim)
  if p.escada and not na_escada(p) then p.escada = false end

  -- está no chão se houver algo sólido logo abaixo dos pés
  p.no_chao = colide_em(p.x, p.y + 1, p.w, p.h) or sobre_escada(p)
  if p.no_chao and p.vy > 0 then p.vy = 0 end
end

local function andar_atual(y)
  return math.min(ANDARES, math.floor((y + player.h - 1) / (ALTURA_ANDAR * TILE)) + 1)
end

-- ------------------------------------------------------------
-- Interações: peças, perigos, gerador
-- ------------------------------------------------------------
local function toca(p, x, y, w, h)
  return p.x < x + w and x < p.x + p.w and p.y < y + h and y < p.y + p.h
end

local ultimo_andar = 1

-- Sem vida: recomeça do telhado, com as peças de volta no lugar
local function recomecar()
  local p = player
  p.x, p.y, p.vx, p.vy = inicio.x, inicio.y, 0, 0
  p.vida, p.pecas, p.escada, p.tadala = VIDA_MAX, 0, false, 0
  for _, pc in ipairs(pecas) do pc.pega = false end
  for _, cp in ipairs(comprimidos) do cp.pego = false end
  reiniciar_inimigos()
  checkpoint = { x = inicio.x, y = inicio.y }
  ultimo_andar = 1
end

-- tira vida (1 por padrão) e volta ao checkpoint (início do andar)
local function levar_dano(texto, quanto)
  local p = player
  p.vida = p.vida - (quanto or 1)
  p.escada = false
  if p.vida <= 0 then
    recomecar()
    avisar(quanto and texto or "SEM VIDA! Recomecando do telhado.", 180)
  else
    p.x, p.y, p.vx, p.vy = checkpoint.x, checkpoint.y, 0, 0
    avisar(texto, 90)
  end
  p.invencivel = 60
end

-- caveiras andam e viram; fantasmas flutuam de parede a parede
local function mover_inimigos(frame)
  for _, e in ipairs(inimigos) do
    if e.sumiu then
      -- nada
    elseif e.morto then
      -- derrubado pelo TADALA: desliza até bater em algo e some
      e.x = e.x + e.vx
      local fx = e.vx > 0 and (e.x + e.w) or e.x
      if solido_px(fx, e.y + e.h // 2) or fx < TILE or fx > (MAPA_L - 1) * TILE then
        e.sumiu = true
      end
    elseif e.tipo == "skull" then
      local nx = e.x + e.vx
      local fx = e.vx > 0 and (nx + e.w) or (nx - 1)       -- ponto da frente
      local col, lin_pe = fx // TILE, (e.y + e.h) // TILE
      local tem_chao = solido(bloco(col, lin_pe)) or bloco(col, lin_pe) == "H"
      local barreira = solido_px(fx, e.y + e.h - 1) or bloco(col, lin_pe - 1) == "^"
      if barreira or not tem_chao then e.vx = -e.vx else e.x = nx end
    else
      e.x = e.x + e.vx
      if e.x < TILE or e.x + e.w > (MAPA_L - 1) * TILE then e.vx = -e.vx end
      e.y = e.base_y + math.sin(frame * 0.04 + e.fase) * 20
    end
  end
end

local function interagir()
  local p = player

  -- mudou de andar (descendo ou subindo) = novo checkpoint
  local a = andar_atual(p.y)
  if p.no_chao and not p.escada and a ~= ultimo_andar then
    ultimo_andar = a
    checkpoint = { x = p.x, y = p.y }
  end

  -- peças
  for _, pc in ipairs(pecas) do
    if not pc.pega and toca(p, pc.x + 3, pc.y + 3, 10, 10) then
      pc.pega = true
      p.pecas = p.pecas + 1
      avisar("PECA " .. p.pecas .. "/" .. TOTAL_PECAS .. " COLETADA!")
    end
  end

  -- comprimidos: liga o TADALA (dois de uma vez: o coração não aguenta)
  if p.tadala > 0 then p.tadala = p.tadala - 1 end
  for _, cp in ipairs(comprimidos) do
    if not cp.pego and toca(p, cp.x + 3, cp.y + 8, 10, 8) then
      cp.pego = true
      if p.tadala > 0 then
        levar_dano("OVERDOSE! O coracao nao aguentou.", VIDA_MAX)
        return
      end
      p.tadala = TADALA_FRAMES
      avisar("TADALA ON! Nao tome outro agora.", 120)
    end
  end

  -- faíscas: tira 1 de vida e volta ao checkpoint
  -- só a parte de baixo do bloco "^" dá choque (onde estão os fios)
  if p.invencivel > 0 then p.invencivel = p.invencivel - 1 end
  local pe = math.floor(p.y + p.h - 1)
  local cx1, cx2 = p.x // TILE, (p.x + p.w - 1) // TILE
  for col = cx1, cx2 do
    if bloco(col, pe // TILE) == "^" and pe % TILE >= 11 and not energia
       and p.invencivel == 0 then
      levar_dano("CHOQUE! Cuidado com os fios.")
      return
    end
  end

  -- inimigos (a caixa de toque é um pouco menor que o desenho)
  for _, e in ipairs(inimigos) do
    if not e.morto and not e.sumiu and toca(p, e.x + 2, e.y + 2, e.w - 4, e.h - 4) then
      if p.tadala > 0 then
        -- TADALA: derruba o inimigo, que sai deslizando para longe
        e.morto = true
        e.vx = (e.x + e.w / 2 >= p.x + p.w / 2) and 5 or -5
      elseif p.invencivel == 0 then
        levar_dano(e.tipo == "skull" and "Uma caveira te pegou!" or "Um fantasma te assustou!")
        return
      end
    end
  end

  -- gerador
  if gerador and not energia and toca(p, gerador.x, gerador.y, TILE, TILE) then
    if p.pecas >= TOTAL_PECAS then
      energia = true
      avisar("ENERGIA RESTAURADA!", 100000)
    elseif mensagem_t <= 0 then
      avisar("Faltam " .. (TOTAL_PECAS - p.pecas) .. " pecas.", 60)
    end
  end
end

-- ------------------------------------------------------------
-- Câmera (segue o jogador na vertical, suave)
-- ------------------------------------------------------------
local function atualizar_camera()
  local alvo = player.y + player.h / 2 - TELA_A / 2
  alvo = ui.mid(0, alvo, MAPA_A * TILE - TELA_A)
  camera_y = camera_y + (alvo - camera_y) * 0.15
end

-- ------------------------------------------------------------
-- Desenho do cenário
-- ------------------------------------------------------------
local function desenhar_bloco(c, x, y, frame)
  if c == "H" then
    ui.rectfill(x + 2, y, x + 3, y + 15, cor("rebite"))
    ui.rectfill(x + 12, y, x + 13, y + 15, cor("rebite"))
    ui.line(x + 4, y + 3, x + 11, y + 3, cor("viga"))
    ui.line(x + 4, y + 11, x + 11, y + 11, cor("viga"))
    return
  end
  if FOLHA then
    local col, lin = x // TILE, y // TILE
    if c == "#" or c == "=" then
      ui.tile(FOLHA, AUTOTILE[lin][col], x, y)
      return
    elseif c == "w" then
      local id = energia and SPR.janela_on or SPR.janela
      ui.tile(FOLHA, id, x, y)
      ui.tile(FOLHA, id + FOLHA_COLS, x, y + TILE)
      return
    end
    -- "^" (faíscas) ainda sem sprite: cai no desenho provisório abaixo
  end

  if c == "#" then
    ui.rectfill(x, y, x + 15, y + 15, cor("tijolo"))
    ui.line(x, y, x + 15, y, cor("tijolo_l"))
    ui.line(x, y + 8, x + 15, y + 8, cor("tijolo_l"))
    ui.line(x + 4, y, x + 4, y + 7, cor("tijolo_l"))
    ui.line(x + 12, y + 8, x + 12, y + 15, cor("tijolo_l"))

  elseif c == "=" then
    -- viga treliçada (ocupa o bloco todo, igual à colisão)
    ui.rectfill(x, y, x + 15, y + 3, cor("viga"))
    ui.rectfill(x, y + 12, x + 15, y + 15, cor("viga"))
    ui.line(x, y + 4, x + 15, y + 11, cor("viga"))
    ui.line(x, y + 11, x + 15, y + 4, cor("viga"))
    ui.circfill(x + 3, y + 1, 1, cor("rebite"))
    ui.circfill(x + 12, y + 1, 1, cor("rebite"))

  elseif c == "w" then
    local c_vidro = energia and cor("janela_on") or cor("janela")
    ui.rectfill(x, y, x + 15, y + 23, c_vidro)
    ui.rect(x, y, x + 15, y + 23, cor("tijolo"))
    ui.line(x + 8, y, x + 8, y + 23, cor("tijolo"))

  elseif c == "^" then
    ui.line(x, y + 15, x + 15, y + 12, cor("fio"))
    if not energia and (frame + x) % 12 < 6 then
      local fx = x + (frame * 7 + x) % 14
      ui.line(fx, y + 13, fx + 2, y + 8, cor("faisca"))
      ui.line(fx + 2, y + 8, fx - 1, y + 5, cor("branco"))
    end
  end
end

local function desenhar_cenario(frame)
  local cam = math.floor(camera_y)
  local lin_ini = math.max(0, cam // TILE)
  local lin_fim = math.min(MAPA_A - 1, (cam + TELA_A) // TILE + 1)

  if FOLHA then
    -- cidade ao fundo (só aparece perto do telhado), com leve parallax
    if cam < ALTURA_ANDAR * TILE and FUNDO_OFF then
      local fy = cam // 2   -- topo da imagem no topo da fase
      ui.spr(energia and FUNDO_ON or FUNDO_OFF, 0, fy, false, false)  -- imagem inteira, sem régua
    end
    -- parede interna do prédio
    local id_fundo = energia and SPR.fundo_on or SPR.fundo
    for lin = math.max(lin_ini, ALTURA_ANDAR), lin_fim do
      for col = 0, MAPA_L - 1 do
        ui.tile(FOLHA, id_fundo, col * TILE, lin * TILE)
      end
    end
    for lin = lin_ini, lin_fim do
      for col = 0, MAPA_L - 1 do
        local c = bloco(col, lin)
        if c ~= " " then desenhar_bloco(c, col * TILE, lin * TILE, frame) end
      end
    end
    return
  end

  -- céu com estrelas (só aparece no topo)
  for i = 0, 40 do
    local sx = (i * 97) % TELA_L
    local sy = (i * 53) % 130
    if (frame // 20 + i) % 9 ~= 0 then
      ui.circfill(sx, sy, 0, cor("estrela"))
    end
  end

  -- silhueta da cidade ao fundo (prédios apagados)
  if cam < ALTURA_ANDAR * TILE then
    local base = ALTURA_ANDAR * TILE - TILE
    for i = 0, 11 do
      local px = i * 42 - 6
      local alt = 40 + (i * 37) % 60
      ui.rectfill(px, base - alt, px + 34, base, cor("fundo"))
      for jy = base - alt + 6, base - 8, 10 do
        for jx = px + 5, px + 28, 9 do
          local acesa = energia and ((jx + jy) % 3 ~= 0)
          ui.rectfill(jx, jy, jx + 3, jy + 4, acesa and cor("janela_on") or cor("ceu"))
        end
      end
    end
  end

  -- parede interna do prédio (do andar 2 para baixo)
  local topo_predio = ALTURA_ANDAR * TILE
  ui.rectfill(0, math.max(topo_predio, cam), TELA_L - 1, cam + TELA_A,
              energia and cor("fundo_on") or cor("fundo"))

  for lin = lin_ini, lin_fim do
    for col = 0, MAPA_L - 1 do
      local c = bloco(col, lin)
      if c ~= " " then desenhar_bloco(c, col * TILE, lin * TILE, frame) end
    end
  end
end

local function desenhar_objetos(frame)
  if FOLHA then
    -- peças: turbina flutuando
    for _, pc in ipairs(pecas) do
      if not pc.pega then
        ui.tile(FOLHA, SPR.peca, pc.x, pc.y + ((frame // 15) % 2) * 2 - 1)
      end
    end
    if gerador then
      local g = gerador
      ui.tile(FOLHA, SPR.gerador, g.x, g.y - TILE)
      ui.tile(FOLHA, SPR.gerador + FOLHA_COLS, g.x, g.y)
      -- raio de neon: aceso com energia; sem energia, só "falha" de vez em quando
      if energia or frame % 120 < 5 then
        for ty = 0, 2 do
          for tx = 0, 1 do
            ui.tile(FOLHA, SPR.raio + ty * 2 + tx, g.x + 24 + tx * TILE, g.y - 2 * TILE + ty * TILE)
          end
        end
      end
    end
    return
  end

  -- peças (bateria piscando e flutuando)
  for _, pc in ipairs(pecas) do
    if not pc.pega then
      local by = pc.y + 4 + ((frame // 15) % 2)
      ui.rectfill(pc.x + 4, by, pc.x + 11, by + 9, cor("peca"))
      ui.rectfill(pc.x + 6, by - 2, pc.x + 9, by - 1, cor("peca_l"))
      if (frame // 10) % 2 == 0 then
        ui.rect(pc.x + 2, by - 4, pc.x + 13, by + 11, cor("peca_l"))
      end
    end
  end

  -- gerador
  if gerador then
    local g = gerador
    ui.rectfill(g.x - 8, g.y - 16, g.x + 23, g.y + 15, cor("gerador"))
    ui.rect(g.x - 8, g.y - 16, g.x + 23, g.y + 15, cor("viga"))
    local luz = energia and cor("verde")
             or (((frame // 20) % 2 == 0) and cor("vermelho") or cor("tijolo"))
    ui.circfill(g.x + 8, g.y - 6, 4, luz)
    ui.rectfill(g.x - 4, g.y + 4, g.x + 19, g.y + 8, cor("viga"))
  end
end

-- desenha um personagem pelos pés, centralizado na caixa de colisão
local function desenhar_boneco(anim, movendo, frame, x, y, w, h, virado, de_ponta)
  local q = anim and (movendo and anim.andando or anim.parado)
  if not q then return false end
  local i = (frame // 8) % 4 + 1
  ui.spr(q[i], math.floor(x + w / 2 - 8), math.floor(y + h - 20), virado, de_ponta or false)
  return true
end

local function desenhar_comprimidos(frame)
  for _, cp in ipairs(comprimidos) do
    if not cp.pego then
      local x, y = cp.x + 4, cp.y + 10 + ((frame // 20) % 2)
      ui.circfill(x + 2, y + 2, 2, cor("vermelho"))
      ui.rectfill(x + 2, y, x + 4, y + 4, cor("vermelho"))
      ui.rectfill(x + 5, y, x + 6, y + 4, cor("branco"))
      ui.circfill(x + 7, y + 2, 2, cor("branco"))
    end
  end
end

local function desenhar_inimigos(frame)
  local cam = math.floor(camera_y)
  for _, e in ipairs(inimigos) do
    if not e.sumiu and e.y + e.h > cam and e.y < cam + TELA_A then
      if not desenhar_boneco(ANIM[e.tipo], not e.morto, frame, e.x, e.y, e.w, e.h,
                             e.vx < 0, e.morto) then
        ui.rectfill(e.x, e.y, e.x + e.w - 1, e.y + e.h - 1,
                    e.tipo == "skull" and cor("branco") or cor("estrela"))
      end
    end
  end
end

local function desenhar_player(frame)
  local p = player
  if p.invencivel > 0 and (frame // 4) % 2 == 0 then return end  -- pisca
  local movendo = p.vx ~= 0 or (p.escada and p.vy ~= 0) or not p.no_chao
  if desenhar_boneco(ANIM.grandpa, movendo, frame, p.x, p.y, p.w, p.h, p.dir < 0) then
    return
  end
  local x, y = math.floor(p.x), math.floor(p.y)
  ui.rectfill(x, y + 4, x + p.w - 1, y + p.h - 1, cor("player"))
  ui.rectfill(x + 1, y, x + p.w - 2, y + 4, cor("pele"))
end

-- Se a folha não foi encontrada, lista as tabelas globais (para descobrir o nome)
local function diagnostico_sprites()
  if FOLHA then return end
  local padrao = { ui=1, sfx=1, string=1, table=1, math=1, os=1, io=1,
    coroutine=1, utf8=1, package=1, debug=1, _G=1, Palette=1, MAPA=1,
    C=1, SPR=1, AUTOTILE=1, player=1, pecas=1, gerador=1, checkpoint=1,
    inicio=1, inimigos=1, ANIM=1, comprimidos=1 }
  local y = 20
  ui.print("SPRITES NAO ENCONTRADOS. Tabelas globais:", 4, y, cor("vermelho"))
  for nome, v in pairs(_G) do
    if type(v) == "table" and not padrao[nome] then
      local campos = {}
      for k in pairs(v) do
        campos[#campos + 1] = tostring(k)
        if #campos >= 6 then break end
      end
      y = y + 10
      ui.print(nome .. ": " .. table.concat(campos, ", "), 4, y, cor("branco"))
    end
  end
  if type(MOD_SPRITES) == "table" then
    local campos = {}
    for k in pairs(MOD_SPRITES) do campos[#campos + 1] = tostring(k) end
    y = y + 10
    ui.print("require sprites: " .. table.concat(campos, ", "), 4, y, cor("branco"))
  end
end

-- coração 9x8: dois círculos em cima e um "V" embaixo
function desenhar_coracao(x, y, c)
  ui.circfill(x + 2, y + 2, 2, c)
  ui.circfill(x + 6, y + 2, 2, c)
  for i = 0, 4 do
    ui.line(x + i, y + 3 + i, x + 8 - i, y + 3 + i, c)
  end
end

local function desenhar_hud()
  ui.rectfill(0, 0, TELA_L - 1, 13, cor("ceu"))
  ui.print("ANDAR " .. andar_atual(player.y) .. "/" .. ANDARES, 6, 3, cor("texto"))
  -- vida em corações
  ui.print("VIDA", 100, 3, cor("texto"))
  for i = 1, VIDA_MAX do
    desenhar_coracao(130 + (i - 1) * 12, 3, i <= player.vida and cor("vermelho") or cor("viga"))
  end
  ui.print("PECAS " .. player.pecas .. "/" .. TOTAL_PECAS, 200, 3, cor("peca_l"))
  ui.print(energia and "ENERGIA: ON" or "ENERGIA: OFF", 340, 3,
           energia and cor("verde") or cor("vermelho"))
  ui.print("v" .. VERSAO, TELA_L - 36, 3, cor("estrela"))
  if player.tadala > 0 then
    local seg = (player.tadala + 59) // 60
    local txt = "TADALA ON  " .. seg
    local c = (player.tadala > 120 or (player.tadala // 8) % 2 == 0) and cor("branco") or cor("vermelho")
    ui.print(txt, TELA_L / 2 - #txt * 3, 22, c)
  end
  if mensagem and mensagem_t > 0 then
    ui.print(mensagem, TELA_L / 2 - #mensagem * 2, 250, cor("branco"))
  end
end

-- ------------------------------------------------------------
-- Loop principal (chamado por game.lua a cada frame)
-- ------------------------------------------------------------
-- Cores da paleta são 15 bits (5 por canal). Descobre de que lado fica o
-- vermelho olhando a cor 0xac3232 (vermelho forte = 21, azul = 6).
local VERMELHO_EM_BAIXO = true
do
  local ok, v = pcall(function() return Palette[Palette.hex(0xac3232) + 1] end)
  if ok and type(v) == "number" then VERMELHO_EM_BAIXO = (v % 32) > ((v // 1024) % 32) end
end

local function avermelhar(v)
  if type(v) ~= "number" then return v end
  local a, b, c = v % 32, (v // 32) % 32, (v // 1024) % 32
  local r, g, bl
  if VERMELHO_EM_BAIXO then r, g, bl = a, b, c else r, g, bl = c, b, a end
  r = math.min(31, r + 8)
  g, bl = g * 2 // 5, bl * 2 // 5
  if VERMELHO_EM_BAIXO then return r + g * 32 + bl * 1024 end
  return bl + g * 32 + r * 1024
end

function loop(frame)
  local tadala = player.tadala > 0
  for i = 1, #Palette do
    ui.palset(i - 1, tadala and avermelhar(Palette[i]) or Palette[i])
  end

  mover_player()
  mover_inimigos(frame)
  interagir()
  atualizar_camera()
  if mensagem_t > 0 then mensagem_t = mensagem_t - 1 end

  ui.clip(0, 0, TELA_L, TELA_A)
  ui.cls(cor("ceu"))

  ui.camera(0, math.floor(camera_y))
  desenhar_cenario(frame)
  desenhar_objetos(frame)
  desenhar_comprimidos(frame)
  desenhar_inimigos(frame)
  desenhar_player(frame)

  ui.camera(0, 0)
  desenhar_hud()
  diagnostico_sprites()
end