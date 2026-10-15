-- Ponto de entrada. Carrega o jogo protegido: se der qualquer erro
-- (ao carregar ou durante o jogo), mostra a mensagem na tela.

local ok, erro = pcall(require, "main")

Frame = 0

local function quebrar(texto, largura)
  local linhas = {}
  texto = tostring(texto)
  while #texto > 0 do
    linhas[#linhas + 1] = texto:sub(1, largura)
    texto = texto:sub(largura + 1)
  end
  return linhas
end

local function mostrar_erro()
  ui.palset(0, 0x0000)        -- preto
  ui.palset(1, 0x7FFF)        -- branco
  ui.camera(0, 0)
  ui.clip(0, 0, 480, 270)
  ui.cls(0)
  ui.print("ERRO NO JOGO:", 8, 8, 1)
  for i, linha in ipairs(quebrar(erro, 75)) do
    ui.print(linha, 8, 12 + i * 10, 1)
  end
end

function update()
  Frame = Frame + 1
  if ok then
    local ok2, erro2 = pcall(loop, Frame)
    if not ok2 then ok, erro = false, erro2 end
  end
  if not ok then mostrar_erro() end
end