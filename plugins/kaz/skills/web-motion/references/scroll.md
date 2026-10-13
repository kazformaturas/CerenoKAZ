# Scroll-linked motion — trigger grammar, parallax, pinning, smooth scroll

Load for: parallax, scrub animation, sticky/pinned sections, scroll-driven
count-up, progress bars, smooth scrolling, and scroll locking.

---

## Trigger positions — the grammar

Every scroll-linked animation is defined by two points on the scroll timeline.
Both use the same two-word string:

```
"<element-edge> <viewport-edge>"
```

Element edge: `top` | `center` | `bottom`. Viewport edge: `top` | `center` |
`bottom`. Read `"top bottom"` as *"the element's top meets the viewport's
bottom"* — the moment it first becomes visible.

| Pair | The moment |
|---|---|
| `"top bottom"` | element first enters from below — the usual **start** |
| `"center center"` | element centre is vertically centred — the usual **end** for entrance-style scrub |
| `"bottom top"` | element has fully left upward — the usual **end** for a full-pass parallax |
| `"top top"` | element top reaches viewport top — the pin point for sticky |

Choosing `start`/`end` *is* the animation design. `"top bottom" → "center
center"` completes while the element is arriving (good for count-ups and
entrance scrub). `"top bottom" → "bottom top"` spans the element's entire
visible life (good for parallax, which must not finish early).

## The progress computation

```js
function scrollProgress(el, start = 'top bottom', end = 'bottom top') {
  const bb = el.getBoundingClientRect();
  const vh = window.innerHeight;
  const pos = {
    top_top:       bb.top,
    center_top:    bb.top + bb.height / 2,
    bottom_top:    bb.bottom,
    top_center:    bb.top - vh / 2,
    center_center: bb.top + bb.height / 2 - vh / 2,
    bottom_center: bb.bottom - vh / 2,
    top_bottom:    bb.top - vh,
    center_bottom: bb.top + bb.height / 2 - vh,
    bottom_bottom: bb.bottom - vh,
  };
  const s = pos[start.replace(' ', '_')];
  const e = pos[end.replace(' ', '_')];
  const len = Math.abs(s - e);
  return Math.min(Math.max(0, 1 - (s + len) / len), 1);   // === clamp(-s/len)
}
```

Verified against a 400px element in an 800px viewport, `"top bottom" → "center
center"`:

| element top | element centre | progress |
|---|---|---|
| 900 | 1100 | 0.000 |
| **800** | 1000 | **0.000** ← top meets viewport bottom |
| 600 | 800 | 0.333 |
| 400 | 600 | 0.667 |
| **200** | **400** | **1.000** ← centre meets viewport centre |
| 0 | 200 | 1.000 (clamped) |

Both endpoints land exactly where the grammar promises. `len` is recomputed from
a **live rect every call** — which is what makes the animation survive a resize,
a font load, or an image finally arriving and changing the element's height.
Caching it is a bug that only appears on resize.

## Driving it

Subscribe to the shared ticker (`references/springs.md`), throttled, and only
while the element is in view:

```js
function onScrollProgress(el, { start, end, onChange, framerate = 10 }) {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return () => {};

  let inView = false, last = -1, unsub = null;

  const tick = () => {
    if (!inView) return;
    const p = scrollProgress(el, start, end);
    if (p !== last) { last = p; onChange(p); }
  };

  const io = new IntersectionObserver(([e]) => {
    inView = e.isIntersecting;
    if (inView && !unsub) unsub = subscribeToTicker(tick, () => framerate);
    else if (!inView && unsub) { tick(); unsub(); unsub = null; }
  }, { threshold: 0 });

  io.observe(el);
  return () => { io.disconnect(); unsub?.(); };
}
```

Three things this gets right:

- **`framerate: 10`** — ~100 samples/sec. `getBoundingClientRect()` forces
  layout; running it on every frame for every scroll-driven element on the page
  is the standard cause of scroll jank. 10ms is imperceptible and roughly halves
  the layout cost versus every-frame.
- **One final `tick()` on leaving view** — without it, scrolling past fast
  leaves the element frozen at 0.94 instead of 1. The defect only appears at
  high scroll speed, which is why it survives manual testing.
- **`p !== last`** — skips the write when the page is not scrolling.

### Two modes

**Scrub** — interpolate continuously. This is parallax, progress bars, anything
that must track the scrollbar:

```js
onScrollProgress(bg, { start: 'top bottom', end: 'bottom top',
  onChange: p => { bg.style.transform = `translateY(${(p - 0.5) * 120}px)`; } });
```

**Toggle** — snap to a state past a point. Feed the progress into a spring
rather than setting the value, so the snap is physical:

```js
const s = createSpring({ tension: 240, friction: 26, onChange: p => { … } });
onScrollProgress(el, { start: 'top top', end: 'top top',
  onChange: p => s.set(p > 0 ? 1 : 0) });
```

> Never spring a **scrub**. A spring lagging behind the scrollbar on a scrub
> animation reads as broken, not smooth — the element drifts after the user
> stops. Scrub is a direct mapping; springs are for discrete state changes.

## Parallax that does not expose its edges

Parallax moves an element against the scroll, so its travel must be covered by
extra size or it reveals a gap at one end.

```
required overscale = 1 + (2 · maxTravelPx) / elementHeightPx
```

A 600px-tall background moving ±60px needs `height: 720px` (or `scale(1.2)`)
and centring. Getting this wrong shows a hairline of background at the top or
bottom of the section — and only at certain viewport heights, which is why it
reaches production.

**Keep travel small.** ±40–80px over a full section read as depth; ±200px reads
as the layout being broken. The eye detects the *rate difference*, not the
distance.

## Scroll-driven count-up

```js
onScrollProgress(el, { start: 'top bottom', end: 'center center',
  onChange: p => { el.textContent = Math.round(p * target); },
  framerate: 30 });
```

- `"top bottom" → "center center"` — the number finishes counting as the stat
  arrives at the centre of the screen. `"bottom top"` would leave it still
  counting as it exits.
- `framerate: 30` — a number changing 100×/sec is unreadable smear. ~33/sec
  reads as counting.
- Use **tabular figures** (`font-variant-numeric: tabular-nums`). Proportional
  digits change width as the number climbs and the whole layout jitters.
- The value is scroll-position-derived, so scrolling **back up counts down** —
  correct behaviour for a scrub. If it must only ever go up, latch it:
  `p => el.textContent = Math.round(Math.max(p, last) * target)`.

## Smooth scroll and the lock

Smooth-scroll libraries (Lenis and equivalents) replace native scrolling with an
interpolated position. Two consequences that are always underestimated:

1. **Native scroll APIs partly stop working.** `scrollIntoView`,
   anchor navigation, and browser find-in-page fight the library.
2. **Locking scroll requires locking both.** Setting `overflow: hidden` alone
   leaves the library still processing wheel events underneath.

One gate for the whole app — every modal, drawer, and loader calls this and
nothing else touches scroll:

```js
let locked = false;
export function stopScroll() {
  if (locked) return;                       // idempotent — nested opens
  locked = true;
  lenis.stop();
  const html = document.documentElement;
  html.style.position = 'relative';
  html.style.overflow = 'hidden';
  html.style.height = '100%';
}
export function startScroll() {
  if (!locked) return;
  locked = false;
  lenis.start();
  const html = document.documentElement;
  html.style.removeProperty('position');
  html.style.removeProperty('overflow');
  html.style.removeProperty('height');
}
```

**Idempotence is the point.** Without the guard, opening a modal from inside an
already-open nav overlay locks twice and the first close unlocks — leaving the
page scrollable behind a modal. Use `removeProperty`, not `= ''`, so any
stylesheet rule for those properties is restored rather than shadowed by an
empty inline value.

Programmatic scrolling has to route around the library:

```js
export function scrollTo(id, immediate = false) {
  const el = document.getElementById(id);
  if (!el) return;
  const wasEnabled = !locked;
  if (wasEnabled) stopScroll();
  setTimeout(() => {
    window.scrollTo({
      top: el.getBoundingClientRect().top + window.pageYOffset,
      behavior: immediate ? 'instant' : 'smooth',
    });
  }, 50);
  if (wasEnabled) setTimeout(startScroll, 100);
}
```

The two timeouts are not superstition: the 50ms lets the lock settle before the
scroll starts, and the 100ms re-enables after the native smooth scroll has
taken over. Removing them makes the library cancel the scroll it was asked to
perform.

## Sticky and pinning

Prefer `position: sticky` over a scroll-driven fake pin. It is one CSS line, it
cannot desync from the scroll position, and it survives resize for free.

```css
.panel { position: sticky; top: 0; }
```

Sticky silently does nothing if **any** ancestor has `overflow: hidden`,
`overflow: auto`, or `overflow: clip`. This is the most common "sticky isn't
working" cause and it is invisible in the element's own styles — an
`overflow-x: hidden` added on a wrapper to stop horizontal scroll kills every
sticky inside it. Fix by moving the overflow guard to the element that actually
overflows, or `overflow-x: clip` on the body only.

Reach for a scroll-driven pin only when the pinned element must also *animate*
through its pinned range (horizontal scroll galleries, scroll-scrubbed
sequences). Then: a tall spacer section, a `sticky` inner wrapper, and the
inner content scrubbed by the spacer's progress.

## Viewport height on mobile

`100vh` on iOS includes the space under the collapsing URL bar, so a `100vh`
hero is taller than the screen and its bottom content is cut off — then the bar
collapses and the layout jumps mid-scroll.

Use `100lvh`/`100svh`/`100dvh` with a `vh` fallback:

```css
.hero { height: 100vh; height: 100lvh; }
```

`svh` = smallest (bar visible), `lvh` = largest (bar hidden), `dvh` = dynamic
(changes as it collapses). `dvh` on a full-screen hero relayouts on every
scroll — expensive and visibly janky. Use `svh` when nothing may be cut off,
`lvh` when the section may extend past the fold.
