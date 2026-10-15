require "palette"
require "sprites"
require "mapa"

-- ============================================================
-- FALHA NO SISTEMA — cidade vertical sem energia
-- Desça o prédio, pegue as 3 peças e religue o gerador.
-- Setas: andar | Z ou CIMA: pular
-- ============================================================

TILE = 16
TELA_L, TELA_A = 480, 270
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

-- ------------------------------------------------------------
-- SPRITES — pack "Cyberpunk Tileset 16x16" (itch.io), convertido p/ DB32
--
-- O Lupi expõe cada PNG do repositório pelo caminho da pasta:
--   img/t/5.png       -> Sprites.img.t["5"]   (um PNG por tile)
--   img/fundo_off.png -> Sprites.img.fundo_off
-- ui.spr desenha a imagem inteira. Se os PNGs não forem achados,
-- o jogo usa os desenhos provisórios.
-- ------------------------------------------------------------
local cache_tiles = {}

local function sprite_tile(id)
  local r = cache_tiles[id]
  if r == nil then
    local ok, v = pcall(function() return Sprites.img.t[tostring(id)] end)
    r = (ok and type(v) == "table") and v or false
    cache_tiles[id] = r
  end
  return r or nil
end

local function sprite_img(nome)
  local ok, v = pcall(function() return Sprites.img[nome] end)
  if ok and type(v) == "table" then return v end
  return nil
end

-- desenha o tile <id> da folha (mesma numeração da folha.png)
local function desenha(id, x, y, flip_x)
  local r = sprite_tile(id)
  if r then ui.spr(r, x, y, flip_x or false, false) end
end

local function carregar_sprites()
  cache_tiles = {}
  FOLHA     = sprite_tile(0) ~= nil       -- true = sprites disponíveis
  FUNDO_OFF = sprite_img("fundo_off")
  FUNDO_ON  = sprite_img("fundo_on")
  if not FOLHA then FOLHA = nil end
end
carregar_sprites()

SPR = {
  parede_solta = 9,                          -- 0..8 = parede 3x3 (9-slice)
  barra_e = 10, barra_m = 11, barra_d = 12,  -- parede de 1 bloco de altura
  viga_e = 13, viga_m = 14, viga_d = 15, viga_solta = 31,
  fundo = 16, fundo_on = 24,
  janela = 17, janela_on = 19,               -- +1 = parte de baixo
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

for lin = 1, MAPA_A do
  for col = 1, MAPA_L do
    local c = MAPA[lin]:sub(col, col)
    local x, y = (col - 1) * TILE, (lin - 1) * TILE
    if c == "P" then table.insert(pecas, { x = x, y = y, pega = false }) end
    if c == "G" then gerador = { x = x, y = y } end
    if c == "S" then inicio = { x = x, y = y } end
  end
end

TOTAL_PECAS = #pecas

player = {
  x = inicio.x, y = inicio.y, w = 10, h = 14,
  vx = 0, vy = 0, no_chao = false, dir = 1,
  pecas = 0,
}
checkpoint = { x = inicio.x, y = inicio.y }
camera_y = 0
energia = false
mensagem, mensagem_t = nil, 0

-- Física
GRAVIDADE  = 0.35
PULO       = -5.6
VEL        = 2.2
VEL_QUEDA  = 7

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

local function mover_player()
  local p = player

  p.vx = 0
  if ui.btn(LEFT)  then p.vx = -VEL; p.dir = -1 end
  if ui.btn(RIGHT) then p.vx =  VEL; p.dir =  1 end

  if p.no_chao and (ui.btnp(BTN_Z) or ui.btnp(UP)) then
    p.vy = PULO
  end

  if not p.no_chao then p.vy = math.min(p.vy + GRAVIDADE, VEL_QUEDA) end

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
  end
  p.y = ny

  -- está no chão se houver algo sólido logo abaixo dos pés
  p.no_chao = colide_em(p.x, p.y + 1, p.w, p.h)
  if p.no_chao and p.vy > 0 then p.vy = 0 end
end

local function andar_atual(y)
  return math.min(7, math.floor((y + player.h) / (ALTURA_ANDAR * TILE)) + 1)
end

-- ------------------------------------------------------------
-- Interações: peças, perigos, gerador
-- ------------------------------------------------------------
local function toca(p, x, y, w, h)
  return p.x < x + w and x < p.x + p.w and p.y < y + h and y < p.y + p.h
end

local ultimo_andar = 1

local function interagir()
  local p = player

  -- novo andar alcançado = novo checkpoint
  local a = andar_atual(p.y)
  if p.no_chao and a > ultimo_andar then
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

  -- faíscas: volta ao checkpoint
  -- só a parte de baixo do bloco "^" dá choque (onde estão os fios)
  local pe = math.floor(p.y + p.h - 1)
  local cx1, cx2 = p.x // TILE, (p.x + p.w - 1) // TILE
  for col = cx1, cx2 do
    if bloco(col, pe // TILE) == "^" and pe % TILE >= 11 and not energia then
      p.x, p.y, p.vx, p.vy = checkpoint.x, checkpoint.y, 0, 0
      avisar("CHOQUE! Cuidado com os fios.", 90)
      return
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
  if FOLHA then
    local col, lin = x // TILE, y // TILE
    if c == "#" or c == "=" then
      desenha(AUTOTILE[lin][col], x, y)
      return
    elseif c == "w" then
      local id = energia and SPR.janela_on or SPR.janela
      desenha(id, x, y)
      desenha(id + 1, x, y + TILE)
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
      ui.spr(energia and FUNDO_ON or FUNDO_OFF, 0, fy, false, false)
    end
    -- parede interna do prédio
    local id_fundo = energia and SPR.fundo_on or SPR.fundo
    for lin = math.max(lin_ini, ALTURA_ANDAR), lin_fim do
      for col = 0, MAPA_L - 1 do
        desenha(id_fundo, col * TILE, lin * TILE)
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
        desenha(SPR.peca, pc.x, pc.y + ((frame // 15) % 2) * 2 - 1)
      end
    end
    if gerador then
      local g = gerador
      desenha(SPR.gerador, g.x, g.y - TILE)
      desenha(SPR.gerador + 1, g.x, g.y)
      -- raio de neon: aceso com energia; sem energia, só "falha" de vez em quando
      if energia or frame % 120 < 5 then
        for ty = 0, 2 do
          for tx = 0, 1 do
            desenha(SPR.raio + ty * 2 + tx, g.x + 24 + tx * TILE, g.y - 2 * TILE + ty * TILE)
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

local function desenhar_player(frame)
  local p = player
  local x, y = math.floor(p.x), math.floor(p.y)
  ui.rectfill(x, y + 4, x + p.w - 1, y + p.h - 1, cor("player"))
  ui.rectfill(x + 1, y, x + p.w - 2, y + 4, cor("pele"))
  -- lanterna do capacete
  local lx = p.dir > 0 and (x + p.w) or (x - 1)
  ui.line(lx, y + 1, lx + p.dir * 2, y + 1, cor("lanterna"))
end

-- Aviso quando os PNGs não foram encontrados
local function diagnostico_sprites()
  if FOLHA then return end
  ui.print("SPRITES NAO ENCONTRADOS: confira se existe img/t/0.png", 4, 20, cor("vermelho"))
end

local function desenhar_hud()
  ui.rectfill(0, 0, TELA_L - 1, 13, cor("ceu"))
  ui.print("ANDAR " .. andar_atual(player.y) .. "/7", 6, 3, cor("texto"))
  ui.print("PECAS " .. player.pecas .. "/" .. TOTAL_PECAS, 200, 3, cor("peca_l"))
  ui.print(energia and "ENERGIA: ON" or "ENERGIA: OFF", 390, 3,
           energia and cor("verde") or cor("vermelho"))
  if mensagem and mensagem_t > 0 then
    ui.print(mensagem, TELA_L / 2 - #mensagem * 2, 250, cor("branco"))
  end
end

-- ------------------------------------------------------------
-- Loop principal (chamado por game.lua a cada frame)
-- ------------------------------------------------------------
function loop(frame)
  if not FOLHA then carregar_sprites() end   -- caso o Lupi carregue depois
  for i = 1, #Palette do
    ui.palset(i - 1, Palette[i])
  end

  mover_player()
  interagir()
  atualizar_camera()
  if mensagem_t > 0 then mensagem_t = mensagem_t - 1 end

  ui.clip(0, 0, TELA_L, TELA_A)
  ui.cls(cor("ceu"))

  ui.camera(0, math.floor(camera_y))
  desenhar_cenario(frame)
  desenhar_objetos(frame)
  desenhar_player(frame)

  ui.camera(0, 0)
  desenhar_hud()
  diagnostico_sprites()
end