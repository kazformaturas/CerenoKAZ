# Text reveals — line, word, and letter

Load for: any heading or copy that animates in by line, word, or letter.

Text animation is the one kind that **cannot** be done with the generic reveal
primitive, because the unit being animated does not exist in the DOM until you
create it. Splitting is most of the work; the motion is the easy part.

---

## The clipped-descender trap — and why "1.1" is wrong

A slide-up line reveal works by clipping: each line sits in a wrapper with
`overflow: hidden`, and the inner span translates from `100%` to `0%`. The
wrapper's height comes from **`line-height`**. If the glyphs' ink extends past
that box, the reveal permanently shaves descenders (`g y p j`) and accented
capitals (`Á Ç Ã`) — in **Portuguese copy this hits constantly**, since accented
capitals are everywhere.

Common guidance says "keep leading at 1.1". Measured, that is not sufficient.
Ink extent for the worst-case string `Ág` at 32px:

| Font | ink extent | clips at 1.0 | clips at 1.1 |
|---|---|---|---|
| system-ui | **1.125 em** | yes | **yes** |
| Georgia | **1.156 em** | yes | **yes** |
| Arial | 1.094 em | yes | no |
| Times New Roman | 1.094 em | yes | no |

**Every** font clips at `line-height: 1`. Whether 1.1 is enough depends on the
font — and Tailwind's `text-5xl` and above ship `line-height: 1`, so the size
utility itself introduces the bug.

**Rules:**

1. **Never `line-height: 1` with a clipped reveal.** Not conditionally — never.
2. **Blind-safe floor is 1.2**, not 1.1. Use it unless you have measured.
3. **Or measure your actual font** and use the number:

```js
const c = document.createElement('canvas').getContext('2d');
c.font = `${fontSizePx}px ${fontFamily}`;
const m = c.measureText('Ágj');            // accented cap + two descenders
const minLeading = (m.actualBoundingBoxAscent + m.actualBoundingBoxDescent) / fontSizePx;
```

4. **If the design genuinely needs tighter visual leading**, do not shrink the
   clip box. Give it room and pull the layout back:

```css
.line > span { padding: 0.15em 0; margin: -0.15em 0; }
```

5. Set leading on the **container** — it inherits to every wrapper, so one
   declaration fixes all lines.

## The alignment trap

Split-text containers end up `display: flex; flex-wrap: wrap` (each word is an
inline-block that must wrap naturally). In a flex container **`text-align` does
not position the items** — only `justify-content` does. A lone `text-center`
silently does nothing.

| Intent | Classes on the container |
|---|---|
| Left | `text-left justify-start` |
| Centre | `text-center justify-center` |
| Right | `text-right justify-end` |

Set both: `justify-*` does the work, `text-*` keeps the SEO fallback copy and any
nested inline content aligned.

> **Never `justify-between`.** The flex items are *words*, not lines. It spreads
> the words of every line edge-to-edge — including the last — which reads as
> broken justified text.

---

## Splitting into lines

Lines do not exist until layout runs, so they must be **measured**, not guessed.
Wrap each word, read its vertical position, group by position. Verified working:

```js
function splitLines(el) {
  const text = el.textContent;
  el.textContent = '';

  // 1. Probe: one inline-block span per word, whitespace preserved as text.
  const probes = text.split(/(\s+)/).map(tok => {
    if (!tok.trim()) { el.appendChild(document.createTextNode(tok)); return null; }
    const s = document.createElement('span');
    s.textContent = tok;
    s.style.display = 'inline-block';
    el.appendChild(s);
    return s;
  }).filter(Boolean);

  // 2. Group words by their rendered top — that grouping IS the line break.
  const rows = new Map();
  for (const s of probes) {
    const t = Math.round(s.getBoundingClientRect().top);
    if (!rows.has(t)) rows.set(t, []);
    rows.get(t).push(s.textContent);
  }
  const lines = [...rows.entries()].sort((a, b) => a[0] - b[0]).map(([, w]) => w.join(' '));

  // 3. Rebuild as clip-wrapper + animated inner span.
  el.textContent = '';
  for (const txt of lines) {
    const clip = document.createElement('span');
    clip.style.cssText = 'display:block;overflow:hidden';
    const inner = document.createElement('span');
    inner.style.cssText = 'display:inline-block;transform:translateY(100%);opacity:0';
    inner.textContent = txt;
    clip.appendChild(inner);
    el.appendChild(clip);
  }
  return [...el.children].map(c => c.firstChild);
}
```

**Must re-run on resize.** Lines are a function of container width — a heading
split at desktop width keeps desktop line breaks at mobile width, producing
overflow or absurd breaks. Debounce a resize handler that re-splits from the
original text (keep it in a `data-` attribute or a closure; after splitting,
`textContent` still reads correctly but the DOM is destroyed on each re-split).

**Must run after fonts load.** Splitting before the webfont arrives measures the
fallback font's metrics and produces wrong line breaks. Gate on
`document.fonts.ready`.

```js
await document.fonts.ready;
const lines = splitLines(el);
```

## Words and letters

Words: same probe pass, skip the grouping — each word span *is* the unit.
Letters: split each word into per-character spans but **keep the word wrapper**,
so words still break as units rather than characters wrapping mid-word.

**Letters are almost always the wrong choice.** A per-letter reveal on more than
a few words reads as a novelty and delays comprehension. Reserve it for short
display type (one to three words). Body copy is words; headings are lines.

## Animating

Once split, drive each unit with the spring or a CSS transition:

```js
lines.forEach((inner, i) => {
  inner.style.transition =
    'transform 900ms cubic-bezier(.215,.61,.355,1) ' + (i * 120) + 'ms,' +
    'opacity 900ms cubic-bezier(.215,.61,.355,1) ' + (i * 120) + 'ms';
  inner.style.transform = 'translateY(0)';
  inner.style.opacity = '1';
});
```

Working values, measured against production reveals:

| Unit | translate | duration | easing | stagger |
|---|---|---|---|---|
| line | `100%` → `0%` (clipped) | 900ms | `cubic-bezier(.215,.61,.355,1)` (easeOutCubic) | 100–120ms |
| word | `24px` → `0` + opacity | 700ms | `cubic-bezier(.165,.84,.44,1)` (easeOutQuart) | 35ms |
| letter | `0.4em` → `0` | 600ms | easeOutQuart | 15–25ms |

Line reveals use a **percentage** translate because the clip box's height is the
line — `100%` is exactly "one line below", at any font size, on any breakpoint.
Using pixels here breaks the moment the type scale changes.

> Clipped line reveal is the one case where a CSS transition beats a spring:
> the motion is a one-shot entrance that nothing will interrupt, and a
> transition costs no per-frame JS. Springs earn their cost when motion is
> interruptible. (A spring key must not mix `0` with `'100%'` — see the hard
> rules; the transition sidesteps that entirely.)

## Accessibility and SEO

Splitting text destroys it for anything that reads the DOM as text:

- **Screen readers** announce a per-letter split character by character. Put the
  original string on the container as `aria-label` and mark the split spans
  `aria-hidden="true"`.
- **Crawlers and copy-paste** lose word boundaries when whitespace is dropped.
  Keep whitespace as real text nodes (the splitter above does), or render a
  visually-hidden copy of the original string.
- **Reduced motion:** skip splitting entirely and render the plain text. A split
  heading with animation disabled is strictly worse than an unsplit one — same
  appearance, more DOM, broken selection.

```js
if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;  // leave as-is
```
