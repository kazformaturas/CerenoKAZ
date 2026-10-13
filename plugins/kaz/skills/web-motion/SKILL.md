---
name: web-motion
description: Build and debug motion on a website — entrance reveals, hover effects, scroll-linked animation, parallax, sticky/pinned sections, count-up numbers, text reveals letter/word/line, cursor and canvas effects, smooth scrolling, page loaders, marquees, carousels. Use whenever a request involves animação, movimento, hover, scroll atrelado, parallax, reveal, transição, "animate this", "make it move", "add motion", "página animada", "landing page com animação", or when motion already exists and is janky, clipped, stuttering, firing at the wrong time, or broken on mobile. Also use before writing the first line of animation code on a new page, to pick the right primitive instead of reaching for a library.
---

# Web Motion

**Created by KAZ / kazformaturas@gmail.com**

A method for building animation-heavy websites where every motion is chosen
deliberately, driven by one physics model, and verified before it ships. The
method is extracted from a production Next.js animation starter released under
the Unlicense (`textura-agency/next16-claude-starter`) and from measuring its
spring configurations directly; the numbers in this skill are measured, not
quoted.

**Licence:** CC BY 4.0 — share and adapt for any purpose with credit.

**Feedback & Support:** If the methodology turns out wrong in practice, say so
and it gets logged as a skill observation for the next review. If the problem is
this skill's rules not being followed, that is a correction to make now, not a
methodology change.

---

## The one decision that matters

Motion work goes wrong at the first step: reaching for a library, or a CSS
keyframe, before deciding **what kind of motion this is**. There are only five
kinds. Pick one, then go to its reference.

| The element… | Kind | Reference |
|---|---|---|
| appears once when it scrolls into view (fade/slide-in) | **reveal** | `references/springs.md` |
| moves continuously as you scroll (parallax, progress bar, scrub) | **scroll-linked** | `references/scroll.md` |
| snaps to a new state past a scroll point (sticky header, pin) | **scroll-toggled** | `references/scroll.md` |
| responds to the pointer (hover, magnetic, cursor trail, canvas paint) | **pointer** | `references/pointer.md` |
| is text revealing itself by line, word, or letter | **text** | `references/text.md` |

If a motion needs two kinds, it is two components, not one clever one.

**Load the reference before writing code.** Each one carries working
implementations in both bindings (React and zero-dependency vanilla) plus the
failure modes specific to that kind. Reading this file alone is not enough to
implement correctly — the traps live in the references.

---

## Hard rules

These are not stylistic preferences. Each one exists because violating it
produces a specific, reproducible defect.

1. **One rAF loop for the whole page.** Every per-frame animation subscribes to
   a single shared ticker, reference-counted so an idle page costs nothing. N
   components must not start N loops — see `references/springs.md` §Ticker.

2. **No `@keyframes`.** An animation long enough to need keyframes is long
   enough to need to be interruptible, and keyframes cannot be interrupted
   mid-flight or driven by scroll. Use a spring.

3. **CSS `transition-*` is allowed for exactly one case:** a discrete
   hover/focus change of **colour, opacity, or border** — with timing from a
   token, never a raw value. Anything scroll-driven, revealing,
   layout-affecting, staggered, or interruptible is a spring. Wiring a spring
   for a link's colour fade costs a client component for no benefit; that is the
   whole reason for the exception, so do not widen it.

4. **A spring key must keep one value type across its from/to states.** `y: 0`
   with `y: '100%'` throws at runtime — animating between a number and a unit
   string is undefined. Clipped line reveal: `'0%'` → `'100%'`. Pixel slide:
   `0` → `60`.

5. **Hover motion is off on touch.** There is no hover on a touchscreen; a
   hover spring there either never fires or fires stuck-on after a tap. Gate it
   on `(hover: hover)` / a viewport check, always.

6. **Honour `prefers-reduced-motion: reduce`.** Not as a global kill switch that
   leaves the page broken — as a defined reduced state: reveals resolve to their
   visible state immediately, scroll-linked motion holds at rest, canvas/pointer
   effects do not initialise. A page where reduced-motion hides content is worse
   than one with no motion.

7. **Animate `transform` and `opacity`.** Animating `width`, `height`, `top`,
   `left`, or `margin` per frame forces layout on every frame. If a layout
   property must animate, that is a design change, not an implementation detail.

8. **Never read layout in an unthrottled loop.** `getBoundingClientRect()` per
   frame per element is the standard cause of scroll jank. Throttle it (10ms is
   the working default) and only run it while the element is in view.

---

## The traps that pass review and break in production

Each has been observed silently shipping. They do not throw.

- **Clipped text with tight leading.** A slide-up line reveal needs
  `overflow: hidden` on a wrapper whose height comes from `line-height`. At
  `line-height: 1` that box is shorter than the glyphs, so descenders (`g y p
  j`) and accented caps get shaved. **Floor is 1.1.** Tailwind's `text-5xl` and
  above ship `line-height: 1` — so the size utility itself introduces the bug.
  Full treatment: `references/text.md`.

- **`text-center` doing nothing.** Split-text containers are
  `display: flex; flex-wrap: wrap` — every word is a flex item, and
  `text-align` does not position flex items. Pair `text-*` with `justify-*`,
  always. Never `justify-between`: it spreads *words*, not lines.

- **Tailwind v4 has no `--duration-*` namespace.** A `--duration-fast` entry in
  `@theme` emits nothing and `duration-fast` silently does nothing. Consume it
  as `duration-[var(--duration-fast)]`. (`--ease-*` *is* a real namespace.)

- **Scroll lock that loses the scroll position.** Locking with
  `overflow: hidden` alone jumps the page to top on unlock in some browsers, and
  a smooth-scroll library keeps running underneath. Lock through one gate that
  both stops the library and sets the overflow — `references/scroll.md`.

- **`will-change` left on permanently.** It promotes a layer forever and
  exhausts GPU memory on long pages. Set it when the animation starts, remove it
  when it settles.

- **Entrance reveals firing behind a loader.** If the page has an intro loader,
  above-the-fold reveals play while hidden and are over before the user sees the
  page. Gate them on a single `ready` flag the loader sets on exit.

---

## Workflow

1. **Inventory the motions first.** Before any code, list every moving thing on
   the page and tag each with one of the five kinds. A page with 20 animations
   and no inventory becomes 20 ad-hoc implementations.
2. **Set the foundation.** Tokens and the responsive scale come first — if
   values get hardcoded now, motion work will hardcode on top of them. See the
   `adaptive-tokens` skill.
3. **Build the shared ticker and spring helper once.** Everything else consumes
   them.
4. **Implement per kind, reference open.**
5. **Run the pre-flight below.** Non-negotiable.

---

## Pre-flight — run before declaring motion work done

Motion is the domain where "it looks right on my machine" is least reliable:
it looks right at 60fps on a desktop with a mouse and no accessibility settings.
Check all seven. Report what was checked and what was found — an unreported
check is indistinguishable from no check.

1. **Reduced motion.** Toggle `prefers-reduced-motion: reduce` and reload. Is
   all content visible and readable? Is anything stuck invisible?
2. **Touch.** Load at mobile width with touch emulation. Do hover-dependent
   elements still reveal their content? Is anything stuck in a hover state?
3. **Frame cost.** Record a scroll through the page in the performance profiler.
   Are there long tasks over 50ms? Is there one rAF loop or many?
4. **Reveal timing.** Scroll fast, then slow. Does anything play while
   off-screen, play twice, or never play?
5. **Text clip.** Find every clipped reveal and check a descender (`g`, `y`,
   `p`) and an accented capital. Shaved = leading below 1.1.
6. **Resize.** Resize across each breakpoint with the page mid-scroll.
   Scroll-linked progress recomputes from live rects, so a stale cached height
   shows up here and nowhere else.
7. **Keyboard.** Tab through. Is focus visible against every animated
   background, and does focusing an off-screen element scroll it into view
   without fighting the smooth-scroll library?

---

## Reference files

| File | Load when |
|---|---|
| `references/springs.md` | any reveal or hover; building the ticker/spring helper; choosing a spring config |
| `references/scroll.md` | parallax, scrub, pin, count-up, smooth scroll, scroll lock |
| `references/text.md` | any text reveal by line, word or letter |
| `references/pointer.md` | hover springs, magnetic/cursor effects, canvas pointer painting |
