---
name: claude-extension-install
description: Install a third-party extension into a Claude Code setup — a plugin, skill, MCP server, hook, or language package — without the silent failure modes. Use this whenever someone asks to install, add, set up, wire up, or update something from a GitHub repo, a marketplace, npm/PyPI, or a vendor's setup docs, even when they name it casually ("install X", "add this MCP", "set up that plugin") and even when the install looks like a single command. Covers determining what category of thing is actually being installed, checking what is already on disk, confirming the upstream is the original rather than a fork, auditing instruction files before they start steering future sessions, separating project-scoped changes from global ones and from ones that touch a live authenticated session, and proving the install works by exercising it instead of reading a version string.
---

# Installing an extension

An install request arrives looking like one action. It is usually six, and what
makes them worth separating is that their failure modes are all quiet. Nothing
throws. You get a clean-looking install that points at a stale fork, or a global
config file the user did not know they now maintain, or a "verified" package
whose version string came from a different component entirely.

The phases below are ordered because each one's output is the next one's input.
Skipping ahead is where the quiet failures come from.

## 1. Classify the artifact before touching anything

Treat the category the user gave you as a hypothesis, not a fact. "Install this
plugin" is a reasonable thing to say about a skill, an MCP server, or a hook —
the word is used loosely, and each of those installs to a different place by a
different mechanism with different activation requirements. An install that
assumes the wrong category does not fail loudly; it succeeds at doing nothing.

Work out which of these you actually have:

| Category | Lives in | Activated by |
|---|---|---|
| Plugin | marketplace cache, registered in settings | `enabledPlugins` entry |
| Skill | `~/.claude/skills/<name>/SKILL.md` or a project's `.claude/skills/` | presence on disk; sometimes a config line |
| MCP server | `.mcp.json`, or settings, or a plugin that bundles one | config entry + a running command or reachable URL |
| Hook | `settings.json` under `hooks` | event + matcher wiring |
| Language package | a venv, a global tool dir, `node_modules` | import path or PATH |

The tell is usually the repo layout. A `SKILL.md` at the root means skill. A
`.claude-plugin/marketplace.json` means plugin or marketplace. A `pyproject.toml`
or `package.json` with a console entry point means language package — which may
*also* ship a skill, so check for both rather than stopping at the first match.

## 2. Read the disk, not your memory

Before installing, look at what is already there: the settings file, the skills
directory, the marketplace manifests, the package registry for the relevant
ecosystem. Session memory and earlier summaries are not evidence — they describe
what was true when they were written.

Sweep every category location for the name, not just the one matching what you
are installing. A package and an unrelated skill can share a name — same vendor,
even — and a check scoped to the package registry will never see the skill. That
collision breaks nothing, which is why nothing signals it; what it breaks is the
user's ability to know which thing a future instruction reaches. When you find a
match in another category, report both and say plainly how they differ.

This catches the three cheapest mistakes available: reinstalling something
already present, installing a second copy alongside a first that is now shadowed,
and handing the user two different artifacts answering to one name.

## 3. Find the real upstream

The first repository you find may be a copy. Forks and mirrors of popular skills
are common, they look identical at a glance, and they drift. Before downloading,
check the repo for fork markers, compare the README against whatever the vendor's
own docs or the package registry point to, and prefer the source the author
maintains.

Installing from a stale fork produces something that works today and quietly
diverges from every future fix.

## 4. Prepare the environment, and read its errors carefully

Package and version managers fail in two different ways: the artifact is broken,
or the manager's own index of the artifact is broken. The error messages do not
distinguish them, and they often name a path as missing when the path is present
and functional — the break is in a symlink, alias, or version-resolution layer
sitting in front of it.

So when a manager reports a path-related failure, look at that path on disk
before doing anything else. If the artifact is there and works, bypass the
resolution layer by referencing it directly. Only if it is genuinely absent or
broken does retrying or reinstalling make sense.

What matters here is what you must *not* do reflexively: fall back to a different
version because the requested one "failed". That hands the user an environment
they did not ask for, and they will not find out until something subtle breaks.

## 5. Audit instruction files before the install counts as done

Skills, hooks, and agent-facing config are instruction documents. They are
executable in the sense that matters — they steer model behaviour in every
future session, with no further review gate. Reading them is part of installing
them.

Read the file in full before it lands in a config directory, and look for:

- outbound network calls, telemetry, and what they carry
- credential, `.env`, or keychain access
- destructive or wide-scope commands
- instructions that would auto-authenticate, auto-purchase, or auto-send
- vendor marketing that steers you toward a paid product, especially one that
  bills continuously while running
- flags that widen the file's own reach (arbitrary-file-reading modes, plugin
  auto-loading), and whether they default on or off

Then say in your report what you checked. An audit nobody hears about is
indistinguishable from no audit, and the user cannot calibrate their trust in a
check whose scope they never learned. Finding nothing malicious is a normal and
common outcome — report it plainly and note anything they should know they are
now living with.

## 6. Classify blast radius, then act in order

A vendor's setup sequence is written to reach a working state. It has no reason
to mark where the scope boundaries are, so it will walk you from a project
directory into global config into the user's live session without a pause.
Segment it yourself before running any of it.

Three tiers, each needing more than the last:

1. **Project-scoped** — files inside a project directory, a venv, a local
   config. Inert and reversible. Proceed on the original request.
2. **Global-scoped** — anything in `~/.claude/`, a machine-wide tool install, a
   shell profile. Changes behaviour in every future session. Confirm separately,
   and note specifically when you would be *creating* a config file that did not
   exist before — the user gains a permanent instruction surface they were not
   previously maintaining, which is a larger change than appending to one they
   were.
3. **Live authenticated session** — attaching to a running browser, a logged-in
   shell, an active cloud context. Always its own decision, always described
   concretely before you ask.

What puts an action in tier 3 is what it can *reach* — the user's credentials,
cookies, and in-progress work — not which kind of program it starts. A fresh
isolated profile, a scratch container, a throwaway account: tier 1, however
alarming the verb. Launching a browser on a disposable profile is not touching
the user's browser.

This distinction is load-bearing because phase 7 still applies in full at tier 1.
When a verification step looks like it falls under tier 3, first look for a
tier-1 way to run it; escalate to asking only if there genuinely isn't one.
Skipping the check because the word "browser" appeared buys nothing and costs
the proof.

Approval for an outcome is not approval for every action that produces it.

### Prefer decomposing a vendor installer to invoking it

When a single vendor command bundles several changes — writing a config file,
installing a tool globally, starting a daemon — perform the changes as separate
explicit steps instead. This is not a workaround; it is better on the merits:
each change becomes individually visible, individually approvable, and the file
that lands in the config directory is byte-for-byte the one you audited rather
than whatever the installer chose to write.

Decomposition preserves visibility but not fidelity, so it carries an obligation
the vendor's installer discharges for you: the artefact you place by hand must be
**byte-identical** to its source. Every step that reads and rewrites content can
transform it — a shell redirect that writes UTF-8 with a BOM, an editor that
normalises line endings — and encoding damage is the pure invisible failure.
Nothing errors, nothing looks different, and the host silently stops parsing the
file's frontmatter. Copy the file directly from wherever the package already
contains it rather than capturing a command's output, then verify against the
source hash in phase 7.

**The carve-out that matters:** decomposition applies to the actions a tool
performs. It never applies to the configuration that governs whether actions are
permitted. Permission files, policy settings, and allowlists are user-edited
only. If one needs to change, the deliverable is the exact diff and the file
path, handed over for the user to apply — including when the user has already
enthusiastically agreed, because the question there is not whether the rule is
wanted but who is allowed to write it. A safeguard the agent can reconfigure is
not a safeguard, and the user's yes does not transfer that authority.

### Backups

When you back up an installed artefact before overwriting it, put the backup
outside every directory the host scans, then list what the host considers loaded
and confirm the backup is absent. A backup left inside the skills directory is
loaded as a second live skill with a near-identical description — two entries
competing for the same triggers, the stale one indistinguishable from the current
one. Naming conventions do not save you here: the scanner reads directories, not
prefixes. A safety artefact stored inside the system it protects is part of that
system.

### Credentials

Never type an API key, token, or password into a file or field. Prepare
everything around it — create the config file with the variable present and
empty, add it to `.gitignore`, name the exact page the key comes from, write a
checker that confirms it without printing it — and let the user paste. Ask them
not to paste it into the conversation either.

## 7. Verify by exercising, not by reading

Two habits will lie to you here.

**Version strings are self-reports.** A CLI's `--version` may print the version
of a wrapper package several majors below the one you installed, and a module's
`__version__` may not exist at all. Query the installed-distribution metadata
instead — `importlib.metadata.version()`, `npm ls`, the registry for whatever
ecosystem you are in. A mismatch between CLI version and package version is
ordinary for wrapper entry points and is not a failure signal, but you can only
know that once you have the authoritative number to compare against.

**Prose about an artifact lags the artifact.** A registry's rendered page can sit
several versions behind its own structured API, so query the API. A vendor's
quickstart can demonstrate model identifiers, constructor arguments, and module
attributes that the shipped package no longer has, so derive example code from
runtime introspection of what you installed — `__all__`, constructor signatures,
field validators — rather than from the README. Every layer between the thing and
its description lags independently; the closer your check sits to the artifact,
the fewer ways it can be quietly wrong.

**Listings describe what exists somewhere, not what works here.** A provider's
catalogue of models, endpoints, or capabilities is generic to the product; the
account, tier, and deprecation state are yours. A listing will happily include
the exact identifier that just returned 404. Use listings to choose what to try,
never as evidence that it will work.

**A file that exists is not a file that parsed.** After placing an instruction
file, compare its hash against the source and check its first bytes for a BOM
(`ef bb bf`). Then confirm the host actually understood it: check that the
artefact's own *description* — not merely its name — appears in the loaded
listing. A name with an empty or garbled description is the signature of a
frontmatter parse failure, and it means the router cannot tell when to invoke the
thing you just installed. It will never raise an error; it will simply never fire.

So finish with one real, minimal, cheap invocation end to end. Nothing counts as
verified until something has actually run.

When that invocation fails, read *which* failure it is — an authorisation error
and a not-found error separate a bad credential from a bad target, and that
distinction turns one failed call into a diagnosis. Relatedly: never validate a
credential by its format or prefix. Providers change issuance formats without
notice, and a format check will reject a working key while telling you it is
protecting you.

### When the checks aren't enough

Everything above is a list, and a list directs attention to what it names. That
raises the floor — the listed failures get caught — and it lowers the ceiling,
because hitting every mark feels like finishing. The defects a checklist never
names are the ones it hides, and the most consequential class it cannot reach is
behaviour that is only visible in code: a resource-selection path that silently
falls back to something on the user's machine, a safety guard that
false-positives and disables itself, a default that the documentation describes
accurately and the implementation does not honour. An install carrying all three
still passes every check above.

So before reporting done, ask what would only be visible in the source — and
actually go read it when any of these hold:

- the artefact will **run unattended**, taking actions without someone watching
- it **selects resources on the user's machine by probing** — searching for a
  browser binary, a config directory, a credential store, a profile
- you are **relying on a safety property** to justify a decision you already
  made: that a profile is isolated, that a sandbox contains it, that a scope
  limits it. Anything you told the user was safe, you should have read.

That last one is the sharpest, because it is where an unread implementation turns
your reassurance into a false one. The claim is yours; the code is where it is
either true or not.

This is a judgement call, not a box. Most installs need none of it. The trigger
is not "is this important" — it is whether the thing can act on its own, choose
for itself, or is load-bearing for something you have promised.

## Before you report the install complete

Run through this. Each line corresponds to a way an install has actually gone
quietly wrong.

- [ ] Category confirmed from the repo layout, not from what it was called
- [ ] Existing state read from disk, not recalled
- [ ] Upstream confirmed to be the original, not a fork
- [ ] No silent version fallback — the user got the environment they asked for
- [ ] Instruction files read in full, and the report says what was checked
- [ ] Global-scope and live-session steps confirmed separately from the rest
- [ ] Nothing was written to a permission or policy file by you
- [ ] Version confirmed from package metadata, not a `--version` self-report
- [ ] One real invocation actually succeeded
- [ ] Anything left for the user to do is stated plainly, with the command

## A closing note on tone

Two of the checks above exist because a *cautious* statement was wrong, not a
confident one. Hedging does not lower the evidence bar: a warning changes what
the user does just as forcefully as a promise does, and it is wrong in the same
way when it is wrong. If you are about to tell the user that a tool will touch
something, cost something, or require something, and they would act differently
for having heard it — verify it first. Saying it tentatively was never a
substitute for checking.
