#!/usr/bin/env bash
# CerenoKAZ - instalador para macOS e Linux
#
# Uso, no Terminal:
#   curl -fsSL https://raw.githubusercontent.com/OWNER/CerenoKAZ/main/install.sh | bash
#
# Faz o mesmo que o install.ps1: registra o marketplace, instala o kit,
# ajusta o ~/.claude/settings.json (limite de skills, atualizacao automatica,
# telemetria; com backup) e baixa o motor do Impeccable.
#
# Opcoes (variaveis de ambiente):
#   CERENOKAZ_SOURCE=...        outra origem do marketplace (pasta local ou URL git)
#   CERENOKAZ_KEEP_TELEMETRY=1  nao desligar a telemetria do Impeccable e do Chrome DevTools MCP

set -euo pipefail
SOURCE="${CERENOKAZ_SOURCE:-https://github.com/OWNER/CerenoKAZ.git}"
MARKETPLACE="cerenokaz"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
export CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1

step() { printf '\n==> %s\n' "$1"; }
warn() { printf 'AVISO: %s\n' "$1" >&2; }

step "Verificando requisitos"
command -v git >/dev/null 2>&1 || { echo "Git nao encontrado. Instale o git e rode de novo." >&2; exit 1; }
HAS_NODE=0; command -v node >/dev/null 2>&1 && HAS_NODE=1
if [ "$HAS_NODE" = 0 ]; then
  warn "Node.js nao encontrado. Os MCPs do Playwright e do Chrome DevTools precisam dele (https://nodejs.org)."
fi
if command -v claude >/dev/null 2>&1; then
  claude_cli() { claude "$@"; }
elif [ "$HAS_NODE" = 1 ]; then
  claude_cli() { npx -y @anthropic-ai/claude-code "$@"; }
else
  echo "Nem o comando 'claude' nem o Node.js foram encontrados. Instale o Claude Code (https://claude.com/claude-code)." >&2
  exit 1
fi

step "Registrando o marketplace $MARKETPLACE"
KNOWN="$CONFIG_DIR/plugins/known_marketplaces.json"
if [ -f "$KNOWN" ] && grep -q "\"$MARKETPLACE\"" "$KNOWN"; then
  claude_cli plugin marketplace update "$MARKETPLACE"
else
  claude_cli plugin marketplace add "$SOURCE"
fi

step "Instalando o kit (e os 7 plugins que ele puxa)"
claude_cli plugin install "kit@$MARKETPLACE" --scope user

step "Ajustando o settings.json"
if [ "$HAS_NODE" = 1 ]; then
  node - "$CONFIG_DIR/settings.json" "${CERENOKAZ_KEEP_TELEMETRY:-0}" <<'JS' || warn "Nao consegui ajustar o settings.json. Veja \"Ajustes manuais\" no README."
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
JS
else
  warn "Sem Node.js, pulei este passo. Veja \"Ajustes manuais\" no README."
fi

step "Baixando o motor do Impeccable"
LAUNCHER="$(find "$CONFIG_DIR/plugins/cache/$MARKETPLACE/impeccable" -type f -path '*/scripts/impeccable' 2>/dev/null | head -1 || true)"
if [ -n "$LAUNCHER" ]; then
  sh "$LAUNCHER" engine-probe || warn "O motor do Impeccable nao baixou agora; ele tenta de novo no primeiro uso."
else
  warn "Nao achei o Impeccable no cache de plugins; ele baixa o motor no primeiro uso."
fi

printf '\nPronto. Feche e abra o Claude (app ou terminal) para carregar tudo.\n'
printf 'Figma: no primeiro uso, o Claude pede login na sua conta do Figma.\n'
printf 'Para conferir: no Claude Code, digite /plugin e veja os plugins de "cerenokaz".\n'
