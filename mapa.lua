-- ============================================================
-- MAPA DA FASE — prédio vertical, 7 andares (telhado -> subsolo)
-- Cada caractere = 1 bloco de 16x16 px. Largura: 30 blocos (480 px).
--
--   #  parede / piso (sólido)
--   =  viga de metal (sólido)
--   w  janela (decoração; acende quando a energia volta)
--   ^  fios soltos soltando faísca (perigo)
--   P  peça do gerador (3 no total)
--   G  gerador (objetivo final)
--   S  início do jogador
-- ============================================================

MAPA = {
  -- ANDAR 1: TELHADO -----------------------------------------
  "                              ",
  "                              ",
  "                              ",
  "                              ",
  "                              ",
  "                              ",
  "  S                ==         ",
  "                              ",
  "#######################   ####",
  -- ANDAR 2: escritórios (peça 1 no alto, à esquerda) --------
  "#                            #",
  "#   w    w    w    w    w    #",
  "#                            #",
  "#   P                        #",
  "#  =======                   #",
  "#           ===              #",
  "#                ===         #",
  "#                            #",
  "#   ##########################",
  -- ANDAR 3: corredor eletrificado ---------------------------
  "#                            #",
  "#   w    w    w    w    w    #",
  "#                            #",
  "#                            #",
  "#                            #",
  "#                            #",
  "#           ====             #",
  "#         ^^^^^^^^           #",
  "#########################   ##",
  -- ANDAR 4: peça 2 no fundo, à esquerda ---------------------
  "#                            #",
  "#   w    w    w    w    w    #",
  "#                            #",
  "#                            #",
  "#                            #",
  "#               ====         #",
  "#                            #",
  "# P     ^^                   #",
  "############   ###############",
  -- ANDAR 5: piso rachado -------------------------------------
  "#                            #",
  "#   w    w    w    w    w    #",
  "#                            #",
  "#                            #",
  "#                            #",
  "#                ====        #",
  "#                            #",
  "#    ^^                      #",
  "#  ###########################",
  -- ANDAR 6: escada de vigas até a peça 3 --------------------
  "#                            #",
  "#   w    w    w    w    w    #",
  "#                            #",
  "#                     P      #",
  "#                   ====     #",
  "#              ===           #",
  "#         ===                #",
  "#                            #",
  "###########################  #",
  -- ANDAR 7: SUBSOLO — gerador -------------------------------
  "#                            #",
  "#                            #",
  "#   ======                   #",
  "#                            #",
  "#                            #",
  "#                            #",
  "#                            #",
  "#  G          ^^             #",
  "##############################",
}

ALTURA_ANDAR = 9   -- linhas por andar (para o HUD saber em que andar está)