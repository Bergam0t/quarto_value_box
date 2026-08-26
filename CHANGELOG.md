# v1.5.0

- Fix: `align` had no effect on local SVG/PNG icons (`icon="*.svg"`/`icon="*.png"`) — they always sat flush left regardless of `align="center"`/`"right"`. `align` was only ever wired to `text-align`, which doesn't position a flex item (the icon); it happened to look like it worked for font icons (Bootstrap Icons/Font Awesome/Tabler/Phosphor/Material) only because those have no explicit size and get stretched to the box's full width, making their glyph content responsive to `text-align`. SVG/PNG icons have an explicit size and were never stretched, so they stayed pinned to the left. Now `align` also drives a real `align-self` on the icon (via a new `--vb-icon-align` custom property), so every icon type honors it consistently. As part of this, the PNG branch's hardcoded `margin:0 auto` was removed — a PNG icon previously always tried to center itself regardless of `align`, including `align="left"`
- Fix: a non-square local SVG/PNG icon set to a large `icon-size` showed a lot of empty space around it. `icon-size` set both width and height to the same value, forcing the icon into a square box; a non-square source image (e.g. a wide logo) was then letterboxed inside that square, and the leftover space was just the box's own background colour showing through. `icon-size` now only constrains the icon's larger natural dimension, with the other scaled proportionally, so the rendered box always matches the icon's actual visible content — determined by reading the PNG's own header / the SVG's own viewBox, with no new dependency
- Add attribute inheritance for `.value-box-row`: styling/layout attributes (`icon-position`, `icon-size`, `icon-color`, `color`, `width`, `height`, `min-height`, `padding`, `align`, `valign`, `font-size`, `font-color`, `value-position`, `value-font-size`, `value-color`, `title-font-size`, `title-color`, `delta-color`, `delta-font-size`, `target`) and the `*-extra-style` escape hatches, set on `.value-box-row`, now become defaults for any `.value-box` child that doesn't set them itself — a child's own value, including an explicit blank override, always wins. Content/identity attributes (`icon`, `value`, `title`, `delta`, `delta-direction`, `href`, `index`, `fragment`) never inherit, and neither does `icon-type`, since it's the only way to opt into Material Symbols and inheriting it would silently coerce every other child's icon onto the Material renderer too

# v1.4.0

- Add support for the div's own `#id` and extra classes, plus `data-*`/`aria-*` attributes and `role`/`tabindex`/`lang`: these now pass through onto the rendered box instead of being silently dropped, so things like `{#kpi .value-box}` with `data-id` (revealjs auto-animate) or ARIA attributes work the same as they would on any other div. Anything outside that set is left off entirely rather than renamed to a `data-` attribute. A literal `style` attribute is dropped (with a warning) rather than colliding with the box's own `style`; a literal `data-fragment-index` attribute is dropped the same way if it would collide with the one generated from `index`
- Fix: every attribute value that reaches an HTML attribute (`href`, `icon`, `color`, `index`, and all six `*-extra-style` attributes, plus the sizing/alignment attributes) is now HTML-escaped. Previously only values in element *content* (`value`, `title`) were ever meant to contain markup, but nothing stopped a quote in, say, `href` or an `*-extra-style` value from breaking out of its attribute and injecting a new one
- Add `delta` option for a small trend indicator next to the `value`, e.g. `delta="+12%"`, with `delta-color`, `delta-font-size`, `delta-extra-style` and `value-row-extra-style` to style it. The arrow glyph is picked by `delta-direction` (`up`/`down`/`flat`, matched case-insensitively) if set, otherwise inferred from a leading `+`/`-` in `delta`; an unrecognised `delta-direction` shows no arrow, with a warning. Colour is never inferred from direction — an "up" delta isn't always good news, so `delta-color` defaults to inheriting the surrounding text colour rather than a green/red guess
- Add `.value-box-row` container: wrap a set of value boxes in `::: {.value-box-row}` for an equal-width, equal-height KPI strip, instead of hand-rolling `.columns`/`.column` scaffolding and hand-setting `height` on every box. With no `columns` attribute set, boxes lay out in a single non-wrapping row; set `columns="N"` to switch to a grid where extra boxes wrap onto further rows, with every row (not just each one individually) kept the same height. `gap` controls spacing (default `1.5rem`, matching a standalone box's own margin), and `extra-style` is an escape hatch for the row wrapper itself. Like `.value-box`, the row passes through its own `#id`, extra classes, and `data-*`/`aria-*`/`role`/`tabindex`/`lang` attributes
- Fix: `color` now accepts a raw CSS colour value (`#hex`, `rgb()`/`rgba()`, `hsl()`/`hsla()`, `var()`), applied as an inline `background-color`, matching what the README already documented. Previously any such value was concatenated straight into the `class` attribute and silently did nothing
- Add a hover lift/shadow for linked boxes (`href` set): `transition: transform 0.2s ease` has been in `value-box.css` since the beginning but had no matching `:hover` rule, so it never did anything. Scoped to `a.value-box` so a static box (no `href`) doesn't wobble under the pointer
- Add `target` option, e.g. `target="_blank"` to open the link in a new tab. Only meaningful alongside `href`. `target="_blank"` automatically also gets `rel="noopener noreferrer"` added, since an opener-less new tab is the whole point of `_blank` and leaving `window.opener` reachable is a reverse-tabnabbing risk that other target values don't share. Setting `target` also adds `data-preview-link="false"`: Reveal.js's `preview-links` option (on by default in this repo's own demo deck) hijacks clicks on every `http(s)` anchor and opens the href in an in-slide iframe overlay instead, regardless of the anchor's own `target` — so without this, `target="_blank"` silently did nothing, and the overlay came up blank for any site that blocks framing (e.g. YouTube)
- Fix: a linked (`href` set) box on a Reveal.js slide silently lost its background and text colour. Quarto's Reveal.js theme ships `.reveal a { background-color: rgba(0,0,0,0); color: ...; }`, a class+tag selector more specific than this extension's plain `.value-box`/`.bg-*` class rules and loaded after `value-box.css`, so it silently won and reset the box back to a plain transparent link — invisible, since the box's own text is white by default. Fixed by restating the affected properties at doubled-class specificity (`a.value-box.value-box`, `a.value-box.bg-*`), which reliably wins regardless of stylesheet load order

# v1.3.0

- Add `value-position` option (`top | bottom | left | right`) to control where the value is rendered relative to the details text, independently of `icon-position`
- Add `content-extra-style` option for the new wrapper around the value and details
- Fix: `icon-position` no longer affects where the value is placed — previously setting `icon-position` to `left`/`right` also pulled the value into a row alongside the icon and details
- Fix: icon-font icons (Bootstrap Icons / Font Awesome) with `icon-position="top"`/`"bottom"` no longer look indented relative to the value/details text under `align="left"`/`"right"` — compensates for the glyphs' built-in optical bearing ([#12](https://github.com/Bergam0t/quarto-value-box/issues/12))
- Add Material Symbols icon support (`icon-type="material"` / `material-outlined` / `material-rounded` / `material-sharp`). Unlike Font Awesome and Bootstrap Icons, the icon name (e.g. `home`) is not auto-detected from the `icon` value — `icon-type` must be set explicitly
- Add Tabler Icons support (`icon-type="tabler"`, auto-detected from a `ti-` prefixed `icon` value, e.g. `icon="ti-star"`)
- Add `title` option: a small label rendered above the `value`, with `title-color`, `title-font-size` and `title-extra-style` to style it. The default size comes from the extension's stylesheet rather than being set inline, so your own CSS can restyle titles without needing `!important`. When `value-position` is `left` or `right`, the title spans the full width above that row rather than becoming a third item in it
- Add Phosphor Icons support (`icon-type="phosphor"`, auto-detected from a `ph`/`ph-<weight>` prefixed `icon` value, e.g. `icon="ph ph-star"` or `icon="ph-bold ph-star"`). Loads the weight-specific stylesheet matching the icon's weight class
- Fix: icon stylesheets are now linked once per document instead of once per value box. A document with many boxes previously repeated the same `<link>` tag dozens of times in its `<head>`
- Fix: icon stylesheet `<link>` tags no longer leak into non-HTML output. Rendering a document containing a value box to PDF previously injected a raw `<link>` tag into the LaTeX preamble, which fails to compile
- Fix: unset or blank attributes no longer emit empty CSS declarations. A box with no `height` produced `height:;`, one with no `font-size` produced `font-size: ;`, and `icon-size=""` produced `font-size:;` on the icon — all invalid, and silently discarded by browsers
- Fix: `icon-size=""` now falls back to the default size rather than suppressing it (an empty string is truthy in Lua, so a blanked attribute read as a set one)
- Fix: boxes with an `href` no longer emit both `display:block` and `display:flex`. The duplicate was harmless only because the later declaration happened to win
- Increase minimum Quarto requirement to 1.4.0. This is only currently due to Typst usage in test suite but as in the long run it would be nice to support typst, doing this preemptively.

# v1.2.1

- Version numbering fix

# v1.2.0

- Add color parameters
    - icon-color
    - font-color
    - value-color

- Add font size parameters
    - font-size
    - value-font-size

- Add better support for additional style parameters beyond those defined in helper functions
    - outer-extra-style
    - icon-extra-style
    - details-extra-style
    - value-extra-style

# v1.1.1

- Set valign default to middle
- Remove outdated reference to scss files in config

# v1.1.0

- Add valign support
- Fix halign behaviour for png icons

# v1.0.0

Initial release
