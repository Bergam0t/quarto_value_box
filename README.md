This is a small filter to allow you to set up value boxes in any Quarto document.

![](assets/2026-05-27-13-00-27.png)

![](assets/2026-05-27-13-22-09.png)

![](assets/2026-05-27-13-00-53.png)

There are a wide range of customisation options available for size, icon type, and more (see the full list in the [customisation](https://github.com/Bergam0t/quarto_value_box#customisation) section below.)

## Installation

You can add this extension to your project by running

```
quarto add bergam0t/quarto-value-box
```

## Usage

First, you must make sure the filter is added to the list of extensions in your document header.

```yml
---
format:
  revealjs: default  # this will also work with other web-based formats, such as html
filters:
  - value-box
---
```

> [!WARNING]
> Note that it is called 'value-box' when added to your document - not 'quarto-value-box'


> [!TIP]
> You could also do
>
> ```yml
> ---
> filters:
>   - bergam0t/value-box
> ---
> ```
>
> if you have another filter extension with the same name!


Now you can create value boxes like so:

```md
::: {.value-box value=60}
Number of bibbles bobbled this week
:::
```

![](assets/2026-05-27-13-01-53.png)

```md
::: {.value-box icon="bi-arrow-down-up" color="bg-amber" width="60%" align="center"}
Here's a more advanced type of box with an icon and some formatting, but no value
:::
```

![](assets/2026-05-27-13-21-07.png)

## [Customisation](#customisation)

> [!NOTE]
> `title` and `value` are inserted into the page as raw HTML. Inline tags work — `value="<b>42</b>"` renders bold — but **markdown is not processed**, so `title="**Q4** revenue"` renders the asterisks literally. This differs from Quarto's own callout `title=`, which does parse markdown. The main content of the box (everything between the `:::` fences) is ordinary markdown as usual. `delta` is plain text, not raw HTML — any markup in it is escaped and shown literally.
>
> A screen reader has no way to know a `delta` is a change *relative to* the `value` next to it beyond the order the two are read in — there's no automatic "increase of" or "compared to last quarter" narration. Write `delta` so it stands on its own, e.g. `delta="+12% vs last quarter"` rather than just `delta="+12%"`, if that context matters for your audience.

Beyond the parameters below, an `#id` and any extra `.classes` on a value box pass through onto the rendered box, along with `data-*`/`aria-*` attributes and `role`/`tabindex`/`lang`.

```md
::: {#kpi-1 .value-box value="42" role="group" aria-label="Sales this quarter" data-id="kpi-1"}
Useful for revealjs auto-animate (`data-id`), crossref targets (`#id`), your own CSS hooks (extra classes), and ARIA attributes.
:::
```

Anything outside that list is left off rather than renamed to a `data-` attribute — an attribute that would have worked on a plain Pandoc div (`onclick`, say) is not silently turned into one that doesn't. A literal `style` attribute is dropped, with a warning, rather than colliding with the `style` the box itself generates — use `outer-extra-style` instead.

> [!WARNING]
> Class-driven Quarto/revealjs features that work by a *filter* rewriting attributes on the div — `.absolute` positioning is the main example — do **not** work on a value box. The div is already replaced with raw HTML by the time those filters would run, so the class survives but the behaviour it triggers does not.

### Row / grid layout

Wrap a set of value boxes in `::: {.value-box-row}` to lay them out with equal width and equal height — the usual "KPI strip" you'd otherwise get by hand-rolling `.columns`/`.column` scaffolding and hand-setting `height` on every box.

```md
::: {.value-box-row}

::: {.value-box value="128" color="bg-teal"}
Signups this week
:::

::: {.value-box value="42" color="bg-amber"}
Open tickets
:::

::: {.value-box value="99%" color="bg-green"}
Uptime
:::

:::
```

With no `columns` set, boxes lay out in a single row that reflows onto further lines as its container narrows — the common case. Set `columns` to switch to a grid that wraps extra boxes onto further rows once it's full, with every row (not just each individual row) kept the same height:

```md
::: {.value-box-row columns="3"}
<!-- six boxes here wrap into two rows of three, each row equal height -->
:::
```

**Small screens.** By default a row adapts to the width of its container: the plain flex row wraps its boxes onto more lines, and a `columns="N"` grid drops columns one at a time — down to a single column — rather than crushing `N` boxes together or overflowing sideways. `columns="N"` is therefore an *upper* bound on the column count, not a fixed count. `min-column-width` (default `14rem`) sets how narrow a column may get before the row drops one; as a rough guide a row reaches a single column at roughly `min-column-width × columns`. Set it per row, or globally for a project with `:root { --vb-row-min-col: 12rem; }` in your own stylesheet. Quarto's default HTML article column is fairly narrow (~700px), so at the `14rem` default a `columns="4"` or wider row will usually render with fewer than `N` columns at rest unless you place it in a wide (`.column-page`/`.column-screen`) layout or lower `min-column-width`. `responsive="false"` turns the adaptation off and restores a rigid single row / exactly-`N`-column grid. Equal height *across* wrapped lines only applies in `columns="N"` grid mode; a plain flex row equalises heights within each line.

The adaptation is intrinsic CSS sizing (`flex-wrap`, `auto-fill` grid), not `@media`/`@container` queries, so it tracks the row's own container width rather than the viewport — which is what makes it behave sensibly inside a `.column`, a margin block, or a `.column-page`/`.column-screen` layout.

> **This is a reflowing-layout feature — i.e. `format: html` and similar.** There, the page (and the row's container) resizes with the browser window, and the row reflows continuously as it does. **Reveal.js slides do not reflow**: a slide is a fixed pixel size and is scaled as a whole to fit the screen, so resizing a deck's window changes nothing about the layout. The only effect you see on a slide is static: a row placed in a narrow container (a `columns` layout, an explicit width) shows fewer columns than the same row at full slide width. If a full-width `columns="N"` row shows fewer than `N` columns on your slides, `N × min-column-width` exceeds the slide width — lower `min-column-width`, or set `responsive="false"` on that row.

Like `.value-box` itself, `.value-box-row` passes through its own `#id`, extra classes, and `data-*`/`aria-*`/`role`/`tabindex`/`lang` attributes; a literal `style` attribute is dropped (with a warning) — use `extra-style` instead.

Rather than repeating the same styling attributes on every box in a row, set them once on the row itself — any `.value-box` child that doesn't set that attribute itself picks up the row's value, and a child that does set its own always wins (including an explicit blank, e.g. `icon-color=""`, which counts as "set"):

```md
::: {.value-box-row icon-position="top" color="bg-red" icon-size="2rem" width="90%" align="center"}

::: {.value-box href="https://podcast.hsma.co.uk/episodes" icon="bi bi-headphones"}
Click here to listen to our past episodes
:::

::: {.value-box href="https://hsma.co.uk" icon="fa-solid fa-chalkboard-user"}
Click here to find out more about the HSMA programme
:::

:::
```

The inheritable attributes are: `icon-position`, `icon-size`, `icon-color`, `color`, `width`, `height`, `min-height`, `padding`, `align`, `valign`, `font-size`, `font-color`, `value-position`, `value-font-size`, `value-color`, `title-font-size`, `title-color`, `delta-color`, `delta-font-size`, `target`, and the `*-extra-style` hooks (`outer-extra-style`, `icon-extra-style`, `content-extra-style`, `details-extra-style`, `value-extra-style`, `title-extra-style`, `delta-extra-style`, `value-row-extra-style`).

The following never inherit, since they identify a specific box rather than style it: `icon`, `value`, `title`, `delta`, `delta-direction`, `href`, `index`, `fragment`. `icon-type` also never inherits — despite being a styling-like switch, it's the only way to opt into Material Symbols icons (never auto-detected), so inheriting it from the row would silently coerce every other child's icon onto the Material renderer too; set it on each box that needs it.

| Parameter    | Type    | Default    | Description                                                                                                                                    |
| ------------ | ------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `columns`    | number  | `""`       | Maximum number of columns in the grid. Extra boxes wrap onto further rows; on a narrow container the grid shows fewer than this. If omitted, boxes lay out in a single flex row that wraps onto more lines as space runs out — no count needed.             |
| `gap`        | string  | `1.5rem`   | Spacing between boxes, both between columns and (when `columns` wraps) between rows. Accepts any valid CSS size unit (a single length — it also feeds the responsive column maths).                            |
| `min-column-width` | string | `14rem` | How narrow a column may get before the row wraps (flex) or drops a column (grid). Raise it for boxes with long text or large icons, lower it to keep more columns on tablets / in narrow layouts. Accepts any valid CSS length. Also settable project-wide as `:root { --vb-row-min-col: … }`.  |
| `responsive` | `true` \| `false` | `true` | When `true` (the default) the row reflows to fewer columns as its container narrows. Set to `false` to restore a rigid single non-wrapping row / exactly-`columns`-wide grid at every width.  |
| `extra-style`| string  | `""`       | Additional CSS styles applied to the row wrapper itself. Useful for advanced customisation beyond the built-in options.                          |

| Parameter             | Type                                | Default         | Description                                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------- | ----------------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `value`               | string                              | `""`            | A prominent value or stat displayed above the main content.                                                                                                                                                                                                                                                                                                                                       |
| `title`               | string                              | `""`            | A small label displayed above the `value`, for naming what the value measures. Rendered at the top of the box's content regardless of `value-position`; when `value-position` is `left` or `right`, the title spans the full width above that row rather than joining it.                                                                                                                          |
| `icon`                | string                              | `""`            | Icon identifier or file path. For Bootstrap Icons use e.g. `bi-star`, for Font Awesome `fa-star`, for Tabler Icons `ti-star`, for Phosphor Icons `ph ph-star` (or `ph-bold ph-star`, `ph-thin ph-star`, etc. for other weights), for Material Symbols use the icon name directly e.g. `home` (requires `icon-type="material"`), for image types provide a file path e.g. `images/icon.svg`. Supported options are Font Awesome, Bootstrap Icons, Tabler Icons, Phosphor Icons, Material Symbols, SVG and PNG. If Font Awesome, Bootstrap Icons, Tabler Icons, Phosphor Icons, or Material Symbols are used, the required stylesheet will automatically be linked in the document header. |
| `icon-type`           | `bi` \| `fa` \| `svg` \| `png` \| `material` \| `material-outlined` \| `material-rounded` \| `material-sharp` \| `tabler` \| `phosphor` | auto | Icon library or format to use. If omitted the type is auto-detected from the `icon` value, falling back to Bootstrap Icons. Material Symbols is never auto-detected — it must always be set explicitly, since a bare icon name like `home` is indistinguishable from a Bootstrap Icons fallback string. Phosphor Icons, like Font Awesome, is auto-detected from the full weight+name class string passed via `icon` (e.g. `ph-bold ph-heart`) — `icon-type` rarely needs setting explicitly. |
| `icon-size`           | string                              | `3em` / `128px` | Size of the icon. Font-based icons (`bi`, `fa`, `material*`, `tabler`, `phosphor`) default to `3em`; image-based (`svg`, `png`) default to `128px`. Accepts any valid CSS size unit.                                                                                                                                                                                                              |
| `icon-position`       | `top` | `bottom` | `left` | `right` | `top`           | Where the icon is rendered relative to the box's content (the value and details together). Independent of `value-position`.                                                                                                                                                                                                                                                                      |
| `value-position`      | `top` | `bottom` | `left` | `right` | `top`           | Where the value is rendered relative to the details text. Independent of `icon-position`.                                                                                                                                                                                                                                                                                                        |
| `icon-color`          | string                              | `white`         | Colour of Font Awesome, Bootstrap Icons, Tabler Icons, Phosphor Icons, or Material Symbols. Ignored for image-based icons (`svg`, `png`). Accepts any valid CSS colour value.                                                                                                                                                                                                                     |
| `color`               | string                              | `bg-blue`       | CSS class or value controlling the box background colour. Prespecified options are `bg-blue`, `bg-navy`, `bg-teal`, `bg-green`, `bg-olive`, `bg-amber`, `bg-orange`, `bg-red`, `bg-pink`, `bg-purple`, `bg-slate`, `bg-grey`. A value starting with `#`, `rgb(`/`rgba(`, `hsl(`/`hsla(`, or `var(` is applied directly as the box's `background-color` instead, e.g. `color="#c8102e"` — anything else (including bare colour keywords like `red`) is treated as a class name. For details on changing or adding `bg-*` classes, see the [advanced customisation](https://github.com/Bergam0t/quarto_value_box?tab=readme-ov-file#colours) section below. |
| `width`               | string                              | `80%`           | Width of the box. Accepts any valid CSS size unit, e.g. `50%`, `300px`.                                                                                                                                                                                                                                                                                                                           |
| `height`              | string                              | `""`            | Height of the box. If omitted the box sizes to its content. Accepts any valid CSS size unit, e.g. `200px`.                                                                                                                                                                                                                                                                                        |
| `min-height`          | string                              | `100px`         | Minimum height of the box; the actual rendered height is `max(height, min-height)`, so a small `height` below this floor is otherwise clamped back up to it. Lower this (e.g. `40px`) alongside `padding` to let a box shrink to fit tighter content on busy slides. Accepts any valid CSS size unit.                                                                                          |
| `padding`             | string                              | `1.5rem`        | Inner padding of the box (all sides). Accepts any valid CSS size unit.                                                                                                                                                                                                                                                                                                                            |
| `font-size`           | string                              | `1.1rem`        | Font size used for the main content of the value box (excluding the `value` and `title`). The default comes from the extension's stylesheet rather than being set inline. Accepts any valid CSS size unit.                                                                                                                                                                                                                                                                                    |
| `value-font-size`     | string                              | `2.2rem`        | Font size used for the `value` displayed above the main content. Accepts any valid CSS size unit.                                                                                                                                                                                                                                                                                                 |
| `font-color`          | string                              | `white`         | Text colour used for the main content. Accepts any valid CSS colour value.                                                                                                                                                                                                                                                                                                                        |
| `value-color`         | string                              | `font-color`    | Text colour used for the `value`. Defaults to the same colour as `font-color`. Accepts any valid CSS colour value.                                                                                                                                                                                                                                                                                |
| `delta`               | string                              | `""`            | A small trend indicator rendered next to the `value`, e.g. `delta="+12%"`. Plain text, not raw HTML (see the note above) — any markup is shown literally rather than rendered.                                                                                                                                                                                                                   |
| `delta-direction`     | `up` \| `down` \| `flat`              | auto            | Which arrow glyph to show next to `delta`, matched case-insensitively. If omitted, it's inferred from a leading `+` (up) or `-` (down) in `delta`; anything else — including an ASCII `+`/`-` further into the string, a typographic minus, or a worded/parenthetical convention like `"12% decrease"` or `"(12%)"` — shows no arrow. An unrecognised `delta-direction` value also shows no arrow, with a warning. Colour is **not** inferred from direction — set `delta-color` yourself, since "up" isn't always good news (a falling cost, say).                                                                                                          |
| `delta-color`         | string                              | inherited       | Text colour used for `delta`. Unset by default, so it inherits the surrounding text colour — set this explicitly for a semantic red/green treatment. Accepts any valid CSS colour value.                                                                                                                                                                                                        |
| `delta-font-size`     | string                              | `1rem`          | Font size used for `delta`. The default comes from the extension's stylesheet rather than being set inline, so your own CSS can restyle it without needing `!important`. Accepts any valid CSS size unit.                                                                                                                                                                                        |
| `delta-extra-style`   | string                              | `""`            | Additional CSS styles applied to the `delta` element. Useful for advanced customisation beyond the built-in options.                                                                                                                                                                                                                                                                              |
| `value-row-extra-style` | string                            | `""`            | Additional CSS styles applied to the wrapper around `value` and `delta` — only present when `delta` is set. Useful for advanced customisation beyond the built-in options.                                                                                                                                                                                                                       |
| `title-font-size`     | string                              | `0.9rem`        | Font size used for the `title`. The default comes from the extension's stylesheet rather than being set inline, so your own CSS can restyle titles without needing `!important`. Accepts any valid CSS size unit.                                                                                                                                                                                        |
| `title-color`         | string                              | `font-color`    | Text colour used for the `title`. Defaults to the same colour as `font-color`. Accepts any valid CSS colour value.                                                                                                                                                                                                                                                                               |
| `align`               | `left` \| `center` \| `right`         | `left`          | Horizontal text alignment within the box.                                                                                                                                                                                                                                                                                                                                                         |
| `valign`              | `top` \| `middle` \| `bottom`         | `middle`        | Vertical alignment within the box. Accepts one of the example strings for convenience, but any valid CSS `justify-content` or `align-items` value is also accepted.                                                                                                                                                                                                                               |
| `outer-extra-style`   | string                              | `""`            | Additional CSS styles applied to the outer value box container. Useful for advanced customisation beyond the built-in options.                                                                                                                                                                                                                                                                    |
| `content-extra-style` | string                              | `""`            | Additional CSS styles applied to the wrapper around the title, value and details. Useful for advanced customisation beyond the built-in options. Note that when a `title` is combined with `value-position="left"` or `"right"`, the value and details move into an inner row element and this wrapper becomes the column stacking the title above it — so flex properties set here apply to that stacking, not to the row. |
| `details-extra-style` | string                              | `""`            | Additional CSS styles applied to the wrapper around the main content. Useful for advanced customisation beyond the built-in options.                                                                                                                                                                                                                                                              |
| `value-extra-style`   | string                              | `""`            | Additional CSS styles applied to the `value` element. Useful for advanced customisation beyond the built-in options.                                                                                                                                                                                                                                                                              |
| `title-extra-style`   | string                              | `""`            | Additional CSS styles applied to the `title` element. Useful for advanced customisation beyond the built-in options.                                                                                                                                                                                                                                                                              |
| `icon-extra-style`    | string                              | `""`            | Additional CSS styles applied to the icon element. Useful for advanced customisation beyond the built-in options.                                                                                                                                                                                                                                                                                 |
| `href`                | string                              | `""`            | If provided, wraps the entire box in a link, and gives it a subtle hover lift/shadow (static boxes with no `href` don't get it).                                                                                                                                                                                                                                                                 |
| `target`              | string                              | `""`            | Sets the link's `target`, e.g. `target="_blank"` to open in a new tab. Only meaningful alongside `href`. Automatically also sets `data-preview-link="false"` so Reveal.js's `preview-links` option (if enabled) doesn't hijack the click and open the href in an in-slide iframe instead; `target="_blank"` additionally gets `rel="noopener noreferrer"`.                                     |
| `fragment`            | string | `true`                     | Enables Reveal.js fragment animation. Set to `true` for the default `fade-in-then-semi-out` animation, or provide any valid Reveal.js fragment class (see [https://quarto.org/docs/presentations/revealjs/advanced.html#fragment-classes](https://quarto.org/docs/presentations/revealjs/advanced.html#fragment-classes)). If providing one of the Reveal.js fragment classes, format this argument like `fragment=".fade-in"`.                                                                        |
| `index`               | string                              | `""`              | Sets the `data-fragment-index` for controlling Reveal.js fragment ordering. Ensure to pass as a string (e.g. "1", "2").                                                                                                                                                                                                                                                                                                                       |


## Advanced Customisation

### Setting defaults for a whole project

Every styling default is a CSS custom property with the default baked into the extension's stylesheet as a `var(--vb-…, <default>)` fallback. The filter only writes a `--vb-*` value onto a box when you set the matching **attribute** on that box (or inherit it from its `.value-box-row`). So to change a default everywhere, set the variable once on `:root` (or any container) in a stylesheet you load after the extension:

```yml
format:
  html:
    css: value-box-theme.css   # loaded after the extension
```

```css
/* value-box-theme.css — applies to every value box in the project */
:root {
  --vb-width: 100%;          /* stop boxes sitting at 80% of their container */
  --vb-padding: 1.25rem;
  --vb-min-height: 120px;
  --vb-font-size: 1rem;         /* the details text                         */
  --vb-value-font-size: 2.6rem;
  --vb-font-color: #1b1b1b;     /* dark text — pair with light bg-* colours  */
  --vb-row-gap: 1rem;           /* spacing between boxes in a .value-box-row */
  --vb-row-min-col: 12rem;      /* how narrow a column gets before the row reflows */
}
```

A per-box or per-row attribute still wins, because it lands in that element's inline `style`. Scope a variable to part of a document by setting it on a wrapper instead of `:root` (e.g. `::: {style="--vb-value-font-size: 3.5rem"}` around a section).

| Variable | Default | Per-box attribute |
| --- | --- | --- |
| `--vb-width` | `80%` | `width` |
| `--vb-height` | `auto` | `height` |
| `--vb-min-height` | `100px` | `min-height` |
| `--vb-padding` | `1.5rem` | `padding` |
| `--vb-text-align` | `left` | `align` |
| `--vb-icon-align` | `flex-start` | `align` (takes a flex keyword: `flex-start`/`center`/`flex-end`) |
| `--vb-justify-content` | `center` | `valign` (box with a top/bottom icon) |
| `--vb-align-items` | `center` | `valign` (box with a left/right icon) |
| `--vb-font-size` | `1.1rem` | `font-size` |
| `--vb-value-font-size` | `2.2rem` | `value-font-size` |
| `--vb-title-font-size` | `0.9rem` | `title-font-size` |
| `--vb-delta-font-size` | `1rem` | `delta-font-size` |
| `--vb-icon-size` | `3em` | `icon-size` (font-glyph icons only — SVG/PNG icons are sized on the `icon-size` attribute) |
| `--vb-font-color` | `white` | `font-color` |
| `--vb-value-color` | inherits `--vb-font-color` | `value-color` |
| `--vb-title-color` | inherits `--vb-font-color` | `title-color` |
| `--vb-icon-color` | `white` | `icon-color` |
| `--vb-delta-color` | `inherit` | `delta-color` |
| `--vb-row-gap` | `1.5rem` | `gap` (on `.value-box-row`) |
| `--vb-row-min-col` | `14rem` | `min-column-width` (on `.value-box-row`) |

Box background is not in this list — set it with the `color` attribute, a `bg-*` class, or `_brand.yml` (see below).

### Colours

A range of colours are supported.

For a one-off colour that doesn't need a reusable class, pass a CSS value straight to `color` instead of defining a new `.bg-*` class:

```md
::: {.value-box value="42" color="#c8102e"}
Uses #c8102e as the background colour directly, no SCSS needed
:::
```

To override in your project, add your own SCSS file and include it after the extension in your _quarto.yml. Quarto loads styles in order, so yours will win:

```yml
format:
  revealjs:
    css: my-colours.scss
```

(swapping revealjs for whatever format you are using, like html)

Your overrides and new colours should be specified like this.

background-color specifies the colour of the box.
color is used for text and icons within the box.

Always pair the plain `.bg-*` selector with an `a.value-box.bg-*` selector, as shown below. A box rendered
with `href=` becomes an `<a>` element instead of a `<div>`, and the extension's own CSS includes a
higher-specificity rule on `<a>` boxes (needed so linked boxes keep their colour under themes like
Reveal.js, which style anchors directly). A plain single-class `.bg-brand` rule loses to that rule and gets
silently reverted to the default background — the doubled selector avoids this, exactly like the built-in
colours in value-box.css already do.

```scss
// Override extension defaults
.bg-blue, a.value-box.bg-blue { background-color: #1a3f6f; color: white; }

// Add entirely new colours not in the extension
.bg-brand, a.value-box.bg-brand { background-color: #c8102e; color: white; }
```

You can also use SCSS variables if you want to define your palette once and reuse it across your project:
```scss
// my-colours.scss
$brand-primary:   #c8102e;
$brand-secondary: #003087;
$brand-neutral:   #4a4f57;

.bg-brand-primary,   a.value-box.bg-brand-primary   { background-color: $brand-primary;   color: white; }
.bg-brand-secondary, a.value-box.bg-brand-secondary { background-color: $brand-secondary; color: white; }
.bg-brand-neutral,   a.value-box.bg-brand-neutral   { background-color: $brand-neutral;   color: white; }
```

### Brand colours (`_brand.yml`)

Quarto compiles a project's [`_brand.yml`](https://quarto.org/docs/authoring/brand.html) palette into CSS custom properties, so `color` (and `icon-color`/`font-color`/`value-color`/`title-color`/`delta-color`) can reference it with `var(...)` directly — no SCSS file or `.bg-*` class needed.

Every format exports every resolved theme/brand value as a `--quarto-scss-export-<name>` custom property, including one per palette entry under a `brand-` prefix — so a palette key maps onto a variable of the same name, in every format, without needing to know format-internal names like Bootstrap's `--bs-*` or reveal.js's own `--r-link-color`:

```yaml
# _brand.yml
color:
  palette:
    accent: "#3d6a9e"
  primary: accent
```

```md
::: {.value-box color="var(--quarto-scss-export-brand-accent)" value="42"}
Picks up the brand's "accent" palette colour by name, in every format
:::
```

The semantic roles (`primary`, `secondary`, `success`, ...) are exported the same way, as `--quarto-scss-export-primary` etc. Bootstrap-based formats (`html`, `dashboard`) additionally expose those same roles under Bootstrap's own names (`--bs-primary`, `--bs-secondary`, ...), if you'd rather use those instead.

To find the exact variable name for any brand or theme value without reading Quarto's SCSS source, render once and grep the compiled theme CSS for the `--quarto-scss-export-` prefix:

```sh
grep -o -- "--quarto-scss-export-[a-zA-Z0-9_-]*:[^;]*" path/to/theme.css
```

— for `revealjs` that file is under `<doc>_files/libs/revealjs/dist/theme/quarto-*.css`; for `html`/`dashboard` it's `<doc>_files/libs/bootstrap/bootstrap-*.min.css`.

`icon-color`, `font-color`, `value-color`, `title-color` and `delta-color` already accept `var(...)` (or any CSS colour) regardless of this filter's version — unlike `color`, they were never concatenated into a `class` attribute, so they've always rendered straight into an inline `style`.

## Acknowledgements

This work started with a solution provided by [Guillaume CHRETIEN](https://github.com/GuillaumeChretienCerema) in [this issue](https://github.com/quarto-dev/quarto-cli/issues/8475), which I used and tweaked across several projects before realising I needed a filter to keep it consistent as I added new features.

Thank you for creating such a brilliant starting point, Guillaume!

## Contributing

Please take a look at our [contributor guidance](CONTRIBUTING) and [code of conduct](CODE_OF_CONDUCT)

Changes are checked by a test suite that renders a set of fixtures to every supported output format — run it with `bash tests/run-tests.sh`. If you have not tested a Quarto extension before, [tests/README.md](tests/README.md) walks through what is being tested and why, and how to add a check for a new feature.


## Generative AI use disclosure and policy

This filter has been written with the help of Claude Sonnet 4.6, Claude Sonnet 5.0, Claude Opus 5.0, and Gemini 3.1 Pro.

All AI-generated code will always be thoroughly reviewed and tested before inclusion.

We are happy to accept AI-supported contributions to the extension, but reserve the right to reject wholly AI generated pull requests which are not felt to add value to the project.


A note about AI usage from Sammi:
> I've been coding for over ten years, love the act of coding, and have significant concerns about the ethics and environmental impact of AI. However, I can't deny its utility as a solo maintainer when it comes to making all the features I want to include in my projects a reality. I hope you find these projects useful enough to help offset some of the downsides of AI, and will use them to help do some good in the world, or at least use them to claw back some of your time so you can spend more of it enjoying being human. For my part, I will continue to use AI critically and carefully, and I will try to make environmentally-conscious choices in my personal life to help balance the scales.
