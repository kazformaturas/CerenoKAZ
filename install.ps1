# CerenoKAZ - instalador para Windows (PowerShell 5.1 ou mais novo)
#
# Uso, numa janela do PowerShell:
#   irm https://raw.githubusercontent.com/OWNER/CerenoKAZ/main/install.ps1 | iex
#
# O que ele faz:
#   1. registra o marketplace "cerenokaz" no Claude Code
#   2. instala o plugin "kit", que puxa os outros 7 plugins
#   3. no ~/.claude/settings.json: sobe o limite de descricoes de skills para 2%,
#      liga a atualizacao automatica do marketplace
#      e desliga a telemetria do Impeccable e do Chrome DevTools MCP (faz backup antes)
#   4. baixa o motor do Impeccable, para o primeiro uso nao estourar o tempo do hook
#
# Opcoes (variaveis de ambiente, definidas antes de rodar):
#   $env:CERENOKAZ_SOURCE = '...'       outra origem do marketplace (pasta local ou URL git)
#   $env:CERENOKAZ_KEEP_TELEMETRY = '1'  nao desligar a telemetria

$ErrorActionPreference = 'Stop'
$Source = if ($env:CERENOKAZ_SOURCE) { $env:CERENOKAZ_SOURCE } else { 'https://github.com/OWNER/CerenoKAZ.git' }
$Marketplace = 'cerenokaz'
$ConfigDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
# Clona via HTTPS mesmo sem chave SSH do GitHub na maquina.
$env:CLAUDE_CODE_PLUGIN_PREFER_HTTPS = '1'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "AVISO: $msg" -ForegroundColor Yellow }

Write-Step 'Verificando requisitos'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git nao encontrado. Instale com:  winget install Git.Git  e abra um PowerShell novo.'
}
$HasNode = [bool](Get-Command node -ErrorAction SilentlyContinue)
if (-not $HasNode) {
    Write-Warn 'Node.js nao encontrado. Os MCPs do Playwright e do Chrome DevTools precisam dele.'
    Write-Warn 'Instale com:  winget install OpenJS.NodeJS.LTS  e rode este instalador de novo.'
}
# Pega o .exe/.cmd, nunca o atalho .ps1 do npm: a politica de execucao padrao do Windows bloqueia scripts .ps1.
$ClaudeCmd = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$NpxCmd = Get-Command npx -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ClaudeCmd -and -not $NpxCmd) {
    throw 'Nem o comando "claude" nem o Node.js foram encontrados. Instale o Claude Code (https://claude.com/claude-code) ou o Node.js e tente de novo.'
}

# Funcao simples (sem param): repassa argumentos como --scope direto para o CLI.
function Invoke-Claude {
    if ($ClaudeCmd) { & $ClaudeCmd.Source @args } else { & $NpxCmd.Source -y '@anthropic-ai/claude-code' @args }
    if ($LASTEXITCODE -ne 0) { throw "Falhou: claude $($args -join ' ')" }
}

Write-Step "Registrando o marketplace $Marketplace"
$known = Join-Path $ConfigDir 'plugins\known_marketplaces.json'
$already = (Test-Path $known) -and ((Get-Content $known -Raw) -match ('"' + $Marketplace + '"'))
if ($already) {
    Invoke-Claude plugin marketplace update $Marketplace
} else {
    Invoke-Claude plugin marketplace add $Source
}

Write-Step 'Instalando o kit (e os 7 plugins que ele puxa)'
Invoke-Claude plugin install "kit@$Marketplace" --scope user

Write-Step 'Ajustando o settings.json'
if ($HasNode) {
    $js = @'
const fs = require('fs'), path = require('path');
const [file, keepTelemetry] = process.argv.slice(2);
let s = {};
if (fs.existsSync(file)) {
  let raw = fs.readFileSync(file, 'utf8'); if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
  try { s = raw.trim() ? JSON.parse(raw) : {}; }
  catch (e) { console.error('settings.json invalido; nada foi alterado: ' + e.message); process.exit(2); }
}
const changes = [];
if (!(typeof s.skillListingBudgetFraction === 'number' && s.skillListingBudgetFraction >= 0.02)) {
  s.skillListingBudgetFraction = 0.02; changes.push('skillListingBudgetFraction = 0.02');
}
if (keepTelemetry !== '1') {
  s.env = s.env || {};
  for (const k of ['IMPECCABLE_NO_TELEMETRY', 'CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS']) {
    if (s.env[k] !== '1') { s.env[k] = '1'; changes.push('env.' + k + ' = 1'); }
  }
}
const mk = s.extraKnownMarketplaces && s.extraKnownMarketplaces.cerenokaz;
if (mk && mk.autoUpdate !== true) {
  mk.autoUpdate = true; changes.push('extraKnownMarketplaces.cerenokaz.autoUpdate = true');
}
if (changes.length) {
  if (fs.existsSync(file)) {
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    fs.copyFileSync(file, file + '.bak-cerenokaz-' + stamp);
  } else {
    fs.mkdirSync(path.dirname(file), { recursive: true });
  }
  fs.writeFileSync(file, JSON.stringify(s, null, 2) + '\n');
  console.log('Alterado: ' + changes.join(', '));
} else {
  console.log('Nada a alterar.');
}
'@
    $tmp = Join-Path ([IO.Path]::GetTempPath()) 'cerenokaz-settings.js'
    [IO.File]::WriteAllText($tmp, $js, (New-Object Text.UTF8Encoding($false)))
    $keep = if ($env:CERENOKAZ_KEEP_TELEMETRY -eq '1') { '1' } else { '0' }
    & node $tmp (Join-Path $ConfigDir 'settings.json') $keep
    if ($LASTEXITCODE -ne 0) { Write-Warn 'Nao consegui ajustar o settings.json. Veja a secao "Ajustes manuais" no README.' }
    Remove-Item $tmp -ErrorAction SilentlyContinue
} else {
    Write-Warn 'Sem Node.js, pulei este passo. Veja a secao "Ajustes manuais" no README.'
}

Write-Step 'Baixando o motor do Impeccable'
$impCache = Join-Path $ConfigDir "plugins\cache\$Marketplace\impeccable"
$launcher = Get-ChildItem $impCache -Recurse -Filter 'impeccable.cmd' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($launcher) {
    & $launcher.FullName engine-probe
    if ($LASTEXITCODE -ne 0) { Write-Warn 'O motor do Impeccable nao baixou agora; ele tenta de novo no primeiro uso.' }
} else {
    Write-Warn 'Nao achei o Impeccable no cache de plugins; ele baixa o motor no primeiro uso.'
}

Write-Host "`nPronto. Feche e abra o Claude (app ou terminal) para carregar tudo." -ForegroundColor Green
Write-Host 'Figma: no primeiro uso, o Claude pede login na sua conta do Figma.'
Write-Host 'Para conferir: no Claude Code, digite /plugin e veja os plugins de "cerenokaz".'
