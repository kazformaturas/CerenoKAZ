# Pointer-driven motion — hover, magnetic, cursor, canvas painting

Load for: hover springs beyond a colour change, magnetic buttons, custom
cursors, and canvas effects painted by the pointer (brush reveals, trails,
liquid distortion).

---

## The rule that governs all of it

**Pointer motion must be additive.** If the effect is the only way to discover
something — a label revealed on hover, an image revealed by painting, a link
target shown by a custom cursor — then on a touchscreen that content does not
exist. Every effect here needs a defined non-pointer state that is complete on
its own.

Gate on capability, never on width:

```js
const canHover = matchMedia('(hover: hover) and (pointer: fine)').matches;
```

A touchscreen laptop is 1400px wide with no usable hover. A tablet with a mouse
has both. Width tells you neither.

---

## Magnetic elements

The element leans toward the cursor within a radius, then springs home.

```js
function magnetic(el, { radius = 80, strength = 0.35, tension = 320, friction = 22 } = {}) {
  if (!canHover) return () => {};
  let tx = 0, ty = 0;
  const sx = createSpring({ tension, friction, onChange: v => write(v, 'x') });
  const sy = createSpring({ tension, friction, onChange: v => write(v, 'y') });
  let cx = 0, cy = 0;
  const write = (v, axis) => {
    if (axis === 'x') cx = v; else cy = v;
    el.style.transform = `translate3d(${cx}px, ${cy}px, 0)`;
  };

  const onMove = e => {
    const r = el.getBoundingClientRect();
    const dx = e.clientX - (r.left + r.width / 2);
    const dy = e.clientY - (r.top + r.height / 2);
    if (Math.hypot(dx, dy) > radius + Math.max(r.width, r.height) / 2) {
      sx.set(0); sy.set(0); return;
    }
    sx.set(dx * strength); sy.set(dy * strength);
  };
  const onLeave = () => { sx.set(0); sy.set(0); };

  window.addEventListener('pointermove', onMove, { passive: true });
  el.addEventListener('pointerleave', onLeave);
  return () => { window.removeEventListener('pointermove', onMove); el.removeEventListener('pointerleave', onLeave); };
}
```

- **`strength` 0.25–0.4.** Above 0.5 the element outruns the cursor and the
  button no longer sits where it can be clicked.
- **Listen on `window`, not the element.** Listening on the element means the
  effect only starts once the cursor is already on top of it — there is no lean.
- **Springs, not direct assignment.** The return-to-home is what sells it, and
  that needs velocity.
- `{ passive: true }` on `pointermove` — the listener never calls
  `preventDefault`, and saying so lets the browser skip a scroll-blocking check.

## Custom cursors

A custom cursor is a fixed-position element following the pointer with a lag:

```js
const lerp = (a, b, t) => a * (1 - t) + b * t;
let px = 0, py = 0, mx = 0, my = 0;
window.addEventListener('pointermove', e => { mx = e.clientX; my = e.clientY; }, { passive: true });
subscribeToTicker(() => {
  px = lerp(px, mx, 0.15); py = lerp(py, my, 0.15);
  dot.style.transform = `translate3d(${px}px, ${py}px, 0)`;
});
```

`lerp` factor 0.1–0.2 gives a followed-with-weight feel; 1.0 is instant. Note
this is frame-rate dependent — at 144Hz it catches up faster. Acceptable for a
cursor; not acceptable for anything measured.

**Do not hide the native cursor** unless the replacement is at least as legible
over every background on the page, and never hide it over text inputs — losing
the I-beam makes forms hard to use. `cursor: none` on `body` with a custom dot
is a frequent accessibility regression.

---

## Canvas painted by the pointer (brush reveal)

The signature "liquid reveal": a base image is always visible; moving the
pointer paints a second image over it along a soft trail that fades out. The
mechanics are exact — each step matters.

**Layers.** A base `<img>` (`object-fit: cover`, always visible — this is the
LCP image, so it must be a real `<img>`, not a canvas draw). Above it a
`<canvas aria-hidden pointer-events:none>` that paints the reveal image.
Off-screen: a **cover canvas** holding the reveal image pre-drawn at canvas
resolution, and a small square **brush canvas**.

**Sizing.** Canvas backing store = container rect × `dpr`, where
`dpr = Math.min(devicePixelRatio, 2)`. Capping at 2 is not a nicety: a 3x phone
paints 2.25× more pixels per frame for no visible gain. CSS size stays the rect
size. Re-measure with a `ResizeObserver` on the container.

**Pre-draw the reveal image with cover math** — verified:

```js
function drawCover(ctx, img, cw, ch) {
  const s = Math.max(cw / img.width, ch / img.height);
  const w = img.width * s, h = img.height * s;
  ctx.drawImage(img, (cw - w) / 2, (ch - h) / 2, w, h);
}
```

Checked against a 1600×900 source: fills 1920×1080, 800×1200, and 1000×500
canvases with no gap in every case.

**The stamp** — three composite operations, in this order:

```js
function stamp(x, y) {
  const c = diam / 2;
  bc.clearRect(0, 0, diam, diam);
  bc.globalCompositeOperation = 'source-over';
  const g = bc.createRadialGradient(c, c, 0, c, c, radius);
  g.addColorStop(0,    'rgba(255,255,255,1)');
  g.addColorStop(0.55, 'rgba(255,255,255,.82)');
  g.addColorStop(1,    'rgba(255,255,255,0)');
  bc.fillStyle = g;
  bc.fillRect(0, 0, diam, diam);

  bc.globalCompositeOperation = 'source-in';        // keep only under the gradient
  bc.drawImage(cover, x - c, y - c, diam, diam, 0, 0, diam, diam);

  ctx.globalCompositeOperation = 'source-over';     // composite onto the trail
  ctx.drawImage(brush, x - c, y - c);
}
```

Measured alpha falloff from the centre of one stamp (radius 60):

| distance | 0 | 15 | 30 | 45 | 55 | 59 | 70 |
|---|---|---|---|---|---|---|---|
| alpha | 254 | 233 | 212 | 112 | 35 | 4 | 0 |

Soft through the outer third, zero outside — which is what makes overlapping
stamps read as one continuous brushstroke rather than a row of discs.

The `source-in` step is the whole trick: it clips the reveal image to the soft
gradient so the *image itself* carries the soft edge. Drawing the image and then
masking on the main canvas instead would erase the trail already painted there.

**Interpolate between pointer events.** Pointer events arrive far apart during
a fast sweep; without interpolation the trail is a dotted line.

```js
const step = Math.max(radius * 0.3, 1);
const n = Math.min(Math.ceil(dist / step), 60);
```

`radius * 0.3` guarantees ~70% overlap between consecutive stamps. The cap of 60
bounds the cost of one enormous jump (a pointer re-entering the window) to a
fixed budget.

**The decay — and why decay alone is not enough.** Each frame, fade the whole
trail:

```js
ctx.globalCompositeOperation = 'destination-out';
ctx.fillStyle = `rgba(0,0,0,${fade})`;
ctx.fillRect(0, 0, w, h);
ctx.globalCompositeOperation = 'source-over';
```

This is **geometric**: remaining alpha after N frames is `(1 - fade)^N`. At
`fade = 0.016`, measured:

| frames | 0 | 20 | 120 |
|---|---|---|---|
| centre alpha | 254 | 186 | **36** |

After 120 frames — two seconds — 14% of the trail is still there, and it never
reaches zero. Reaching invisibility (alpha < 1) would take **~342 frames, about
5.7 seconds** of visible ghosting.

So the decay must be paired with a **hard clear**:

```js
if (queued.length) { idle = 0; }
else if (++idle > 120) { ctx.clearRect(0, 0, w, h); return; }   // hard clear, then idle
const fade = drawing ? decay : Math.min(decay + idle * 0.004, 0.5);
```

An implementation with only the decay looks correct in every short test and
leaves permanent smudges on a page left alone — which is precisely the bug that
survives review.

**Working parameters:** `brushRadius` 120–160 CSS px (143 is a good default —
smaller reads as a pencil, larger stops reading as a brush), `decay` 0.016,
`idle` threshold 120 frames, idle fade ramp `+idle * 0.004` capped at 0.5 so an
abandoned trail accelerates away instead of lingering.

**Reduced motion:** skip the canvas entirely — do not create it, do not attach
listeners. The base image alone is the complete, correct state.

```js
if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
```

**Cost control.** This effect runs a full-canvas `fillRect` every frame while
active. Stop the loop when the section leaves the viewport (`IntersectionObserver`)
and on `document.hidden` — a painted hero still burning frames three sections
down is invisible and expensive.
