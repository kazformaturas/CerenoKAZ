# Springs — the physics model, the ticker, and reveals

Load for: any entrance reveal, any hover, choosing a spring config, or building
the animation foundation of a page.

---

## Why springs and not durations

A duration-based animation answers "how long"; a spring answers "how does it
move". The practical difference is **interruptibility**. A 400ms ease-out that
gets reversed at 200ms either snaps or restarts — a spring carries its current
position *and velocity* into the new target and reads as continuous. Hover
states, drag, and anything a user can interrupt need that. It is also why
`@keyframes` are banned: a keyframe cannot be re-targeted mid-flight.

## The only two numbers, and how to read them

A spring is `tension` (stiffness, pulls toward target) and `friction` (damping,
resists velocity). Everything you need to predict is in one derived number:

```
ζ (damping ratio) = friction / (2 · √tension)      [mass = 1]
```

| ζ | Behaviour |
|---|---|
| < 1 | underdamped — overshoots and settles back (bouncy) |
| = 1 | critically damped — fastest approach with no overshoot |
| > 1 | overdamped — slow, no overshoot |

**Measured**, by integrating at dt = 1/60 with react-spring's default precision
of 0.01. `t95` is the perceptual duration — where the motion visually reads as
finished. Total settle time is roughly double it, which is why quoting a spring
as "≈0.7s" is misleading in both directions.

| tension/friction | ζ | overshoot | t95 | settle | Use for |
|---|---|---|---|---|---|
| 320 / 18 | 0.50 | **13.1%** | 117ms | 567ms | hover pop, badge rotate — visible bounce |
| 320 / 22 | 0.61 | 5.3% | 133ms | 433ms | link/label lift, small nudges |
| 300 / 28 | 0.81 | 0% | 217ms | 400ms | content swap in a carousel |
| 240 / 26 | 0.84 | 0% | 250ms | 483ms | row/background fill on hover |
| 200 / 24 | 0.85 | 0% | 283ms | 533ms | card entrance |
| 260 / 30 | 0.93 | 0% | 283ms | 617ms | modal enter/exit |
| 280 / 32 | 0.96 | 0% | 283ms | 633ms | overlay fade |
| 210 / 26 | 0.90 | 0% | 300ms | 617ms | standard entrance reveal |
| 180 / 26 | 0.97 | 0% | 367ms | 767ms | large panel entrance |
| 220 / 30 | 1.01 | 0% | 350ms | 767ms | loader exit — no bounce by design |
| 120 / 30 | 1.37 | 0% | 700ms | 1400ms | slow drift (watermark, background) |

**How to choose:** pick ζ from the feel you want (bouncy ≈ 0.5–0.65, clean
≈ 0.85–1.0, heavy > 1.2), then pick tension for speed — higher tension is
faster at the same ζ. Do not tune two numbers by trial and error; tune ζ, then
speed.

> An overshoot of 13% means the element travels 13% *past* its target. If it
> slides up by 40px, it overshoots to 45px. That is fine for a badge and wrong
> for anything that must align to a grid line or sit flush against an edge.

---

## The shared ticker

One `requestAnimationFrame` loop for the whole page, reference-counted: it
starts on the first subscriber and stops on the last, so an idle page costs
nothing. Each subscriber throttles itself.

Twenty scroll-driven components each calling `requestAnimationFrame` is twenty
callbacks the browser schedules separately, and every one of them can force
layout. One loop makes the frame cost inspectable and bounded.

```js
const subs = new Set();
let rafId = null;

function frame(t) {
  // Snapshot: a callback may subscribe or unsubscribe during iteration.
  for (const s of [...subs]) {
    if (!subs.has(s)) continue;
    if (t - s.last <= s.getFramerate()) continue;
    s.last = t;
    try {
      s.cb(t);
    } catch (e) {
      // Isolate failures — one bad subscriber must not kill the shared loop.
      console.error('[ticker] subscriber threw:', e);
    }
  }
  rafId = requestAnimationFrame(frame);
}

export function subscribeToTicker(cb, getFramerate = () => 0) {
  const s = { cb, getFramerate, last: performance.now() };
  subs.add(s);
  if (rafId === null) rafId = requestAnimationFrame(frame);
  return () => {
    subs.delete(s);
    if (subs.size === 0 && rafId !== null) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
  };
}
```

Three details that are load-bearing, not style:

- **`[...subs]` snapshot** — a callback that unsubscribes itself mid-iteration
  mutates the Set being iterated.
- **`try/catch` per subscriber** — without it, one thrown error kills the loop
  for every animation on the page, and the symptom is "the whole site froze".
- **`getFramerate` as a function, not a value** — read live each frame so a
  changed throttle takes effect without re-subscribing.

---

## The spring stepper (vanilla, zero dependencies)

Verified: settles exactly on target, reverses mid-flight carrying velocity, and
releases the ticker when it comes to rest.

```js
export function createSpring({
  tension = 170,
  friction = 26,
  precision = 0.01,
  from = 0,
  onChange,
}) {
  let x = from, v = 0, target = from, running = false, unsub = null;

  const stop = () => {
    running = false;
    if (unsub) { unsub(); unsub = null; }
  };

  const step = () => {
    const dt = 1 / 60;
    const a = tension * (target - x) - friction * v;
    v += a * dt;
    x += v * dt;
    if (Math.abs(target - x) < precision && Math.abs(v) < precision) {
      x = target; v = 0;
      onChange(x);
      stop();               // release the ticker — at rest costs nothing
      return;
    }
    onChange(x);
  };

  return {
    set(next) {                       // animate to `next`, carrying velocity
      target = next;
      if (!running) { running = true; unsub = subscribeToTicker(step); }
    },
    jump(next) {                      // no animation — for reduced-motion
      target = x = next; v = 0;
      stop(); onChange(x);
    },
    get value() { return x; },
    stop,
  };
}
```

**Fixed `dt = 1/60`, not real elapsed time** — deliberate. Variable dt in an
explicit Euler integrator makes the spring behave differently on a 144Hz display
and can go unstable after a long frame (a tab regaining focus produces a
multi-second dt and the element flies off-screen). Fixed dt trades exact
real-time duration for stability. Do not "fix" this by passing real dt.

Drive any property from the 0→1 value:

```js
const s = createSpring({
  tension: 210, friction: 26,
  onChange: p => {
    el.style.opacity = p;
    el.style.transform = `translateY(${(1 - p) * 24}px)`;
  },
});
s.set(1);
```

### React binding

With `@react-spring/web`, the same configs map directly — it uses the identical
`{ tension, friction }` model, so the measured table above applies unchanged:

```jsx
const [style, api] = useSpring(() => ({
  opacity: 0, y: 24, config: { tension: 210, friction: 26 },
}));
api.start({ opacity: 1, y: 0 });
return <animated.div style={style}>…</animated.div>;
```

Without a library, wrap `createSpring` in a `useRef` + `useEffect` and write to
the DOM node directly — never to React state. A spring writing to state
re-renders 60 times a second and is the single most common cause of "the
animation made the app slow".

---

## Reveal on scroll-into-view

```js
function reveal(el, { from, to, config, mode = 'once', delay = 0 }) {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
    Object.assign(el.style, to);        // land visible, skip the motion
    return () => {};
  }

  Object.assign(el.style, from);
  const s = createSpring({
    ...config,
    onChange: p => {
      el.style.opacity = from.opacity + (to.opacity - from.opacity) * p;
      el.style.transform = `translateY(${from.y + (to.y - from.y) * p}px)`;
    },
  });

  let lastY = window.scrollY;
  const io = new IntersectionObserver(([e]) => {
    const down = window.scrollY >= lastY;
    lastY = window.scrollY;
    if (e.isIntersecting) {
      setTimeout(() => s.set(1), delay);
      if (mode === 'once') io.disconnect();
    } else if (mode === 'always') {
      s.set(0);
    } else if (mode === 'forward' && !down) {
      s.set(0);
    }
  }, { threshold: 0 });

  io.observe(el);
  return () => io.disconnect();
}
```

**Modes.** `once` — play and stay; the default, and the right answer for
roughly every content reveal. `always` — reverse on leave; only for elements a
user will scroll past repeatedly on purpose. `forward` — play on downward
scroll only; use when reversing on an upward scroll feels like the page is
undoing itself.

`mode: 'once'` must `disconnect()`. An observer left attached for an animation
that will never play again is a leak on a long page.

### Staggering siblings

Stagger with a **delay per index**, not per-element observers with different
thresholds:

```js
items.forEach((el, i) => reveal(el, { …, delay: i * 90 }));
```

Working stagger steps: **80–120ms** between siblings. Below 60ms it reads as
simultaneous; above 150ms the last item arrives after attention has moved on.
For a list longer than ~8 items, cap total stagger at ~600ms — clamp with
`Math.min(i, 6) * 90` rather than letting item 20 wait 1.8 seconds.

### Gating on a page loader

If an intro loader covers the page, above-the-fold reveals fire behind it and
finish unseen. One flag, set once:

```js
let ready = false;
const pending = [];
export const onReady = fn => (ready ? fn() : pending.push(fn));
export const setReady = () => { ready = true; pending.splice(0).forEach(f => f()); };
```

The loader calls `setReady()` when its exit transition ends — not when its
counter reaches 100, which is one animation earlier.

---

## Hover

See `references/pointer.md` for magnetic/cursor effects. For a plain hover
spring, the rules are short:

```js
if (matchMedia('(hover: hover) and (pointer: fine)').matches) {
  el.addEventListener('pointerenter', () => s.set(1));
  el.addEventListener('pointerleave', () => s.set(0));
}
```

- Gate on `(hover: hover) and (pointer: fine)` — not on viewport width. A
  touchscreen laptop is wide and has no usable hover; a tablet with a mouse
  attached does.
- **A hover that only changes colour, opacity, or border is CSS**, not a
  spring — `transition-colors duration-[var(--duration-fast)]`. Reach for a
  spring when the motion is physical, animates a transform, or must be triggered
  by a *parent* element (a card lifting its own arrow badge).
- `pointerenter`/`pointerleave`, not `mouseover`/`mouseout` — the latter fire
  again for every child element crossed.
