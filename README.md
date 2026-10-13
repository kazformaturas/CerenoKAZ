# CerenoKAZ

Pacote da KAZ para o Claude Code: skills e ferramentas de design de interface, animação, automação de navegador e Figma, instaladas com um comando e atualizadas sozinhas.

## O que vem dentro

| Plugin | O que faz | Origem |
|---|---|---|
| `emil` | 15 skills de Emil Kowalski: polimento de interface, animação (web e Expo), performance de animação, stress-test de UI, protótipos | [emilkowalski/skills](https://github.com/emilkowalski/skills) |
| `taste` | 11 skills Taste: frontends que não parecem template, estilos minimalista, brutalista e high-end, redesign, imagens de referência | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) |
| `kaz` | `web-motion` (animação em sites), `task-observer` (melhoria contínua de skills) e `claude-extension-install` (instalar extensões sem erro silencioso) | KAZ; `task-observer` é de [Eoghan Henn](https://github.com/rebelytics/one-skill-to-rule-them-all) |
| `impeccable` | `/impeccable` com 24 comandos de design e um detector que revisa cada edição de HTML/CSS | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) |
| `playwright` | O Claude abre páginas, clica, preenche formulários e tira screenshots | [microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp) |
| `chrome-devtools-mcp` | Traces de performance, rede, console e acessibilidade, com 7 skills de depuração | [ChromeDevTools/chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) |
| `figma` | Lê arquivos, componentes e tokens do Figma e transforma design em código, com 14 skills | [figma/mcp-server-guide](https://github.com/figma/mcp-server-guide) |
| `kit` | Instala todos os 7 acima de uma vez | — |

No menu `/` do Claude Code, as skills aparecem com o nome do plugin na frente, por exemplo `emil:animate` ou `taste:minimalist-ui`.

## Antes de instalar

Cada máquina precisa de:

- **Claude Code**, no app desktop ou no terminal
- **Git**. No Windows: `winget install Git.Git`
- **Node.js LTS**, para o Playwright e o Chrome DevTools. No Windows: `winget install OpenJS.NodeJS.LTS`
- **Google Chrome**

## Instalar

**Windows**: abra o PowerShell e rode

```powershell
irm https://raw.githubusercontent.com/OWNER/CerenoKAZ/main/install.ps1 | iex
```

**macOS**: abra o Terminal e rode

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/CerenoKAZ/main/install.sh | bash
```

Depois, feche e abra o Claude (app ou terminal). Para conferir, digite `/plugin` e veja os plugins de `cerenokaz`.

Rodar o instalador de novo é seguro: ele não duplica nada.

### O que o instalador muda na máquina

1. Registra o marketplace `cerenokaz` e instala os 8 plugins no escopo do usuário.
2. No `~/.claude/settings.json`, com backup em `settings.json.bak-cerenokaz-<data>`:
   - `skillListingBudgetFraction: 0.02`. Com tantas skills, o limite padrão (1% do contexto) corta descrições, e o Claude deixa de lembrar de usar algumas sozinho.
   - `autoUpdate: true` no marketplace, para as mudanças deste repositório chegarem sozinhas.
   - `IMPECCABLE_NO_TELEMETRY=1` e `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1`. Os dois enviam estatísticas anônimas por padrão. Para manter ligado, rode o instalador com `CERENOKAZ_KEEP_TELEMETRY=1`.
3. Baixa o motor do Impeccable (cerca de 19 MB, conferido por hash) para `~/.impeccable/bin`.

Ele não mexe em permissões nem no `CLAUDE.md`.

### Instalação manual

Se o script não rodar na máquina:

```bash
claude plugin marketplace add https://github.com/OWNER/CerenoKAZ.git
```

```bash
claude plugin install kit@cerenokaz
```

Depois, faça os **ajustes manuais**: acrescente ao `~/.claude/settings.json`

```json
{
  "skillListingBudgetFraction": 0.02,
  "env": {
    "IMPECCABLE_NO_TELEMETRY": "1",
    "CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS": "1"
  }
}
```

e ligue a atualização automática em `/plugin` > Marketplaces > `cerenokaz` > Enable auto-update. Também dá para pedir ao próprio Claude: "ajuste meu ~/.claude/settings.json conforme a seção Ajustes manuais do README do CerenoKAZ".

## Primeiro uso

- **Figma**: no primeiro uso, o Claude pede login na sua conta do Figma. Dá para fazer antes, em `/mcp` > `figma`.
- **Impeccable**: em cada projeto novo, comece com o comando `init` do Impeccable. Ele grava um `PRODUCT.md` com o contexto do produto.
- **Playwright e Chrome DevTools**: usam o Chrome instalado, com um perfil próprio, separado do seu Chrome pessoal. O perfil do Playwright é um por pasta de projeto: se você fizer login num site por ele, o login vale naquela pasta.
- **task-observer**: funciona melhor com uma instrução no `~/.claude/CLAUDE.md` pedindo para invocá-lo no início de toda sessão de trabalho. É opcional, e o instalador não mexe nesse arquivo.

## Bom saber

- **Os hooks do Impeccable rodam em todo projeto.** Depois de cada edição de arquivo de interface, eles apontam problemas de design. Em arquivos que não são de interface, ficam em silêncio. Em projetos com interface, criam uma pasta `.impeccable/`. Para desligar, use `/plugin` > desabilitar `impeccable`.
- **Navegadores:** no app desktop, o navegador embutido é o padrão. Quando quiser o Playwright ou o Chrome DevTools, peça pelo nome ("use o Playwright para...").
- **Dependências de algumas skills:**
  - `taste:gpt-taste` usa Python.
  - `taste:imagegen-*`, `taste:image-to-code` e `taste:brandkit` precisam de uma ferramenta de geração de imagem conectada ao Claude.
- **Máquina que já tinha algo instalado avulso:** remova a versão avulsa para não ficar em dobro. Isso vale para skills com o mesmo nome em `~/.claude/skills`, para um MCP `playwright` adicionado com `claude mcp add` e para o plugin `impeccable@impeccable`.

## Atualizar

Com a atualização automática ligada (o instalador liga), o Claude Code busca as mudanças sozinho ao iniciar. Para forçar na hora:

```bash
claude plugin marketplace update cerenokaz
```

Depois, rode `/reload-plugins` numa sessão aberta.

## Desinstalar

```bash
claude plugin marketplace remove cerenokaz
```

Isso remove o marketplace e todos os plugins dele. O backup do `settings.json` fica ao lado do original, se quiser voltar as três configurações.

## Para quem mantém este repositório

- **Tudo que entra na branch `main` chega a todo mundo** pela atualização automática. Revise antes de publicar e restrinja quem tem permissão de escrita no repositório.
- **Skills copiadas** (`emil`, `taste`, `kaz`): são cópias sem alteração dos repositórios de origem, no commit indicado em [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Para atualizar, copie de novo a pasta `skills/` da origem e atualize o commit no aviso.
- **Plugins externos** (`impeccable`, `chrome-devtools-mcp`, `figma`): estão travados por `sha` no `.claude-plugin/marketplace.json`. Para subir de versão, troque o `sha` pelo commit novo depois de ler o que mudou.
- **Antes de publicar**, valide:

```bash
claude plugin validate .
```
