#!/usr/bin/env bash
#
# Render every fixture in tests/fixtures to a matrix of output formats and
# assert invariants on the results.
#
#   tests/run-tests.sh              # everything
#   tests/run-tests.sh --no-pdf     # skip the PDF leg (much faster, needs no LaTeX)
#   tests/run-tests.sh --only html  # a single format
#
# Two classes of problem are covered:
#
#   1. Formats that fail to build at all. Note that the PDF leg must render to
#      "pdf", not "latex" — Quarto exits 0 after writing a .tex file that will
#      not compile, so only the real compile catches a corrupted preamble.
#   2. Output that builds but is silently wrong — duplicated stylesheet links,
#      raw HTML leaking into non-HTML formats, invalid CSS, missing content.
#
# Each format renders in its own directory under tests/_work, because several
# formats write the same output filename (html and revealjs both produce
# .html; pdf and typst both produce .pdf).
# ---8<--- end of help text

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$repo_root/tests/_work"

# latex renders alongside pdf: pdf proves it compiles, latex leaves a readable
# .tex behind to assert against.
all_formats=(html revealjs latex pdf typst docx)
formats=()
skip_pdf=0

while [ $# -gt 0 ]; do
  case "$1" in
    --no-pdf) skip_pdf=1 ;;
    --only)
      shift
      [ $# -gt 0 ] || { echo "--only needs a format" >&2; exit 2; }
      # Validate before this ever reaches the rm -rf in stage().
      case " ${all_formats[*]} " in
        *" $1 "*) formats+=("$1") ;;
        *) echo "unknown format: $1 (want one of: ${all_formats[*]})" >&2; exit 2 ;;
      esac
      ;;
    -h|--help) sed -n '2,/^# ---8<---/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ ${#formats[@]} -eq 0 ]; then
  formats=("${all_formats[@]}")
fi

if [ "$skip_pdf" -eq 1 ]; then
  remaining=()
  for f in "${formats[@]}"; do
    [ "$f" = "pdf" ] || remaining+=("$f")
  done
  formats=("${remaining[@]}")
fi

# e.g. `--only pdf --no-pdf`. The demo-deck check at the end would otherwise
# still register passes and make an empty matrix look like a successful run.
if [ ${#formats[@]} -eq 0 ]; then
  echo "no formats selected — nothing to test" >&2
  exit 2
fi

if [ -t 1 ]; then
  green=$'\033[32m'; red=$'\033[31m'; dim=$'\033[2m'; reset=$'\033[0m'
else
  green=""; red=""; dim=""; reset=""
fi

passed=0
failed=0
failures=()

ok() {
  passed=$((passed + 1))
  printf '  %sPASS%s %s\n' "$green" "$reset" "$1"
}

fail() {
  failed=$((failed + 1))
  failures+=("$1")
  printf '  %sFAIL%s %s\n' "$red" "$reset" "$1"
  if [ -n "${2:-}" ]; then
    printf '       %s%s%s\n' "$dim" "$2" "$reset"
  fi
}

# All three helpers match fixed strings, not regexes (grep -F). Icon CDN URLs
# are full of characters a regex would reinterpret, and a pattern that silently
# stops matching is a test that silently stops testing.

# assert_count <expected> <pattern> <file> <description>
assert_count() {
  local expected=$1 pattern=$2 file=$3 desc=$4 actual
  # -s not -f: an empty output file must never satisfy an assertion. The latex
  # leg in particular contains only absence checks, which a truncated .tex
  # would otherwise pass cleanly.
  if [ ! -s "$file" ]; then
    fail "$desc" "missing or empty file: ${file#"$repo_root"/}"
    return
  fi
  # -o counts occurrences rather than matching lines: Quarto emits several head
  # elements on one line, so a line-based count would miss real duplicates.
  actual=$(grep -o -F -- "$pattern" "$file" | wc -l | tr -d '[:space:]')
  if [ "$actual" -eq "$expected" ]; then
    ok "$desc"
  else
    fail "$desc" "expected $expected occurrence(s) of '$pattern', found $actual"
  fi
}

# assert_absent <pattern> <file> <description>
assert_absent() {
  local pattern=$1 file=$2 desc=$3 actual
  # -s not -f: an empty output file must never satisfy an assertion. The latex
  # leg in particular contains only absence checks, which a truncated .tex
  # would otherwise pass cleanly.
  if [ ! -s "$file" ]; then
    fail "$desc" "missing or empty file: ${file#"$repo_root"/}"
    return
  fi
  actual=$(grep -o -F -- "$pattern" "$file" | wc -l | tr -d '[:space:]')
  if [ "$actual" -eq 0 ]; then
    ok "$desc"
  else
    fail "$desc" "expected no '$pattern', found $actual"
  fi
}

# assert_present <pattern> <file> <description>
assert_present() {
  local pattern=$1 file=$2 desc=$3
  # -s not -f: an empty output file must never satisfy an assertion. The latex
  # leg in particular contains only absence checks, which a truncated .tex
  # would otherwise pass cleanly.
  if [ ! -s "$file" ]; then
    fail "$desc" "missing or empty file: ${file#"$repo_root"/}"
    return
  fi
  if grep -q -F -- "$pattern" "$file"; then
    ok "$desc"
  else
    fail "$desc" "expected to find '$pattern'"
  fi
}

# assert_no_empty_css <file> <description>
#
# Scoped to style attributes rather than the whole document. A document-wide
# scan couples this check to Quarto's boilerplate (a future `href="javascript:;"`
# would trip it) and to the fixtures' own prose — the fixture that documents
# this very defect writes "font-size:;" in its body text.
assert_no_empty_css() {
  local file=$1 desc=$2 actual
  if [ ! -s "$file" ]; then
    fail "$desc" "missing or empty file: ${file#"$repo_root"/}"
    return
  fi
  actual=$(grep -o 'style="[^"]*"' "$file" | grep -c -E ':[[:space:]]*;')
  if [ "$actual" -eq 0 ]; then
    ok "$desc"
  else
    fail "$desc" "found $actual empty CSS declaration(s) in style attributes"
  fi
}

# Stage a directory with its own copy of the extension, the fixtures and the
# image assets the fixtures reference. The extension is copied rather than
# resolved in place because this repo has no _quarto.yml, so Quarto looks for
# _extensions only in the input file's own directory — and copying exercises
# the same layout a user gets from `quarto add`. Local icon paths likewise
# resolve relative to the fixture, so the images must sit beside it.
stage() {
  local dir=$1
  case "$dir" in
    "$work"/*) ;;
    *) echo "refusing to remove a path outside $work: $dir" >&2; return 1 ;;
  esac
  rm -rf "$dir"
  mkdir -p "$dir"
  cp -r "$repo_root/_extensions" "$dir/"
  cp "$repo_root/example-icon.svg" "$repo_root/example-icon.png" "$dir/"
}

# render <dir> <format> <basename> -> 0 on success
render() {
  local dir=$1 fmt=$2 fixture=$3
  local log="$dir/$fixture.$fmt.log"
  (cd "$dir" && quarto render "$fixture.qmd" --to "$fmt") > "$log" 2>&1
  return $?
}

# Derived from the directory rather than hardcoded: a fixture that was staged
# but never listed would otherwise be silently skipped.
fixtures=()
for f in "$repo_root"/tests/fixtures/*.qmd; do
  fixtures+=("$(basename "$f" .qmd)")
done

echo "value-box test matrix"
echo "  quarto $(quarto --version)"
echo "  formats: ${formats[*]}"
echo

# Clear the whole work tree once, so stale output from an earlier run with a
# different format list cannot be mistaken for this run's.
rm -rf "$work"

for fmt in "${formats[@]}"; do
  echo "[$fmt]"
  stage "$work/$fmt" || { fail "stage $fmt" "could not stage $work/$fmt"; continue; }
  cp "$repo_root/tests/fixtures/"*.qmd "$work/$fmt/"

  for fixture in "${fixtures[@]}"; do
    if render "$work/$fmt" "$fmt" "$fixture"; then
      ok "$fixture renders to $fmt"
    else
      fail "$fixture renders to $fmt" "see tests/_work/$fmt/$fixture.$fmt.log"
      # Assertions below would only produce noise once the render itself failed.
      continue
    fi

    log="$work/$fmt/$fixture.$fmt.log"
    if [ "$fixture" = "passthrough" ]; then
      # Deliberately triggers three collision warnings — a literal style, a
      # literal data-fragment-index that collides with a generated one, and a
      # mixed-case Style that must still be recognised as the same collision
      # — in every format, since the Lua that emits them isn't gated on
      # output format.
      assert_count 3 "value-box warning" "$log" "$fixture/$fmt warns about every dropped colliding attribute"
    elif [ "$fixture" = "layout" ]; then
      # Deliberately triggers one warning: an unrecognised delta-direction.
      assert_count 1 "value-box warning" "$log" "$fixture/$fmt warns about the one unrecognised delta-direction"
    elif [ "$fixture" = "row" ]; then
      # Deliberately triggers three warnings: a literal style collision, an
      # unrecognised (non-numeric) columns value, and an unrecognised
      # responsive value.
      assert_count 3 "value-box warning" "$log" "$fixture/$fmt warns about the dropped style, the unrecognised columns value and the unrecognised responsive value"
    else
      assert_absent "value-box warning" "$log" "$fixture/$fmt emits no filter warnings"
    fi

    case "$fmt" in
      html|revealjs)
        out="$work/$fmt/$fixture.html"

        # An unset attribute must not produce "height:;" — an invalid
        # declaration browsers discard silently. Both spellings appeared in
        # real output before css_decl was introduced.
        assert_no_empty_css "$out" "$fixture/$fmt emits no empty CSS declarations"

        # The extension's own stylesheet ships as an HTML dependency. Quarto
        # dedupes it by name, so this is a presence check, not a dedupe one.
        assert_present "value-box.css" "$out" "$fixture/$fmt links value-box.css"

        if [ "$fixture" = "icons" ]; then
          # Regression guard: these were once emitted once per box, not once
          # per document.
          assert_count 1 "bootstrap-icons.min.css"  "$out" "$fixture/$fmt links Bootstrap Icons once"
          assert_count 1 "font-awesome/6.5.1"       "$out" "$fixture/$fmt links Font Awesome once"
          assert_count 1 "tabler-icons.min.css"     "$out" "$fixture/$fmt links Tabler once"
          # Assert per-URL rather than per-family. A total of two Material or
          # Phosphor links cannot distinguish "two variants, deduped" from
          # "one variant, duplicated" — checking each variant appears exactly
          # once pins down both halves.
          assert_count 1 "Material+Symbols+Outlined" "$out" "$fixture/$fmt links Material Outlined once"
          assert_count 1 "Material+Symbols+Rounded"  "$out" "$fixture/$fmt links Material Rounded once"
          assert_count 1 "phosphor-icons/web@2.1.2/src/regular" "$out" "$fixture/$fmt links Phosphor regular once"
          assert_count 1 "phosphor-icons/web@2.1.2/src/bold"    "$out" "$fixture/$fmt links Phosphor bold once"
          assert_present "<svg"                     "$out" "$fixture/$fmt inlines the local SVG"
          assert_present 'src="example-icon.png"'   "$out" "$fixture/$fmt references the local PNG"

          # Regression guard: align must reach the icon via a real cross-axis
          # alignment property, not text-align — see the icon_align_value
          # comment in value-box.lua. Anchored to the mechanism (the custom
          # property, and the CSS rule that consumes it) rather than a
          # rendered pixel position, consistent with how --vb-justify-content
          # and --vb-align-items are pinned elsewhere in this suite.
          assert_present "--vb-icon-align:center;" "$out" "$fixture/$fmt align=center reaches the icon via --vb-icon-align"
          assert_present "align-self: var(--vb-icon-align" "$work/$fmt/_extensions/value-box/value-box.css" \
            "$fixture/$fmt value-box.css keeps the align-self rule that consumes --vb-icon-align"

          # Regression guard: icon-size must constrain only the icon's
          # larger natural dimension, not force a square box that a non-
          # square source image (this PNG is ~3:1) gets letterboxed inside
          # of — see the icon_size_style comment in value-box.lua. The PNG
          # is wider than tall, so width is the explicit declaration and
          # height is left auto to preserve its aspect ratio; object-fit is
          # a no-op once the box already matches the image's proportions,
          # so it's dropped along with the square fallback that needed it.
          assert_present '<img class="icon" src="example-icon.png" style="width:64px; height:auto; display:block;" alt="">' \
            "$out" "$fixture/$fmt PNG icon-size constrains width only, height stays auto to match its aspect ratio"
        fi

        if [ "$fixture" = "minimal" ]; then
          assert_present "Bibbles bobbled"          "$out" "$fixture/$fmt keeps the details text"
          assert_present ">60<"                     "$out" "$fixture/$fmt keeps the value"
        fi

        # The layout fixture drives almost the whole styling surface. These are
        # the checks that make a refactor of the style-building code reviewable
        # rather than a leap of faith.
        if [ "$fixture" = "layout" ]; then
          # Layout is expressed as a class switch plus a --vb-* custom
          # property, not a hand-built inline declaration — see the
          # "Move layout from inline styles to CSS custom properties" refactor.
          # The class/property names are only ever emitted by this filter, so
          # they anchor just as tightly as the inline declarations they replace.
          assert_count 1 'class="value-box vb-icon-right bg-blue"' "$out" "$fixture/$fmt icon-position=right gets the vb-icon-right layout class"
          assert_count 1 "--vb-justify-content:flex-start;" "$out" "$fixture/$fmt valign=top"
          assert_count 1 "--vb-justify-content:flex-end;"   "$out" "$fixture/$fmt valign=bottom"
          assert_count 1 'class="icon vb-bearing-right bi bi-star"' "$out" "$fixture/$fmt align=right gets the right optical bearing class"
          assert_present 'class="value-box bg-teal"'   "$out" "$fixture/$fmt colour class reaches the wrapper"
          # Themeable defaults live in value-box.css now, but a box that sets
          # the attribute still gets an inline --vb-* declaration, which beats
          # any project-level :root value.
          assert_present 'class="value-box bg-teal" style="--vb-width:40%; --vb-height:200px; --vb-min-height:40px; --vb-padding:0.5rem; ">' \
            "$out" "$fixture/$fmt width/height/min-height/padding attributes still land inline and override the stylesheet default"
          # A color value (as opposed to a bg-* class) must become a
          # background-color custom property, not get concatenated into
          # class="..." where it would match no stylesheet rule and silently
          # do nothing.
          assert_absent '#c8102e"'                     "$out" "$fixture/$fmt hex colour value is not appended to the class attribute"
          assert_present "--vb-bg:#c8102e;"             "$out" "$fixture/$fmt hex colour value becomes a --vb-bg custom property"
          assert_absent 'var(--brand-color)"'           "$out" "$fixture/$fmt var() colour value is not appended to the class attribute"
          assert_present "--vb-bg:var(--brand-color);"  "$out" "$fixture/$fmt var() colour value becomes a --vb-bg custom property"
          assert_present 'data-fragment-index="2"'     "$out" "$fixture/$fmt fragment index passes through"
          assert_present "fragment fade-in-then-semi-out" "$out" "$fixture/$fmt fragment=true expands to the default effect"
          assert_present "fragment fade-in-then-out"   "$out" "$fixture/$fmt explicit fragment effect passes through"
          assert_present '<a href="https://example.com"' "$out" "$fixture/$fmt href wraps the box in an anchor"
          # target="_blank" must also get rel="noopener noreferrer" — an
          # opener-less new tab is the whole point of _blank, and leaving
          # window.opener reachable is a known phishing vector (reverse
          # tabnabbing) other target values don't share. It must also get
          # data-preview-link="false", or reveal.js's previewLinks option
          # hijacks the click and opens the href in an in-slide iframe
          # instead of a real new tab, regardless of target.
          assert_present '<a href="https://example.com" target="_blank" data-preview-link="false" rel="noopener noreferrer" class="value-box bg-blue"' \
            "$out" "$fixture/$fmt target=_blank adds rel=noopener noreferrer and opts out of reveal.js preview-link hijacking"
          # These five must be anchored to filter-generated markup. Pandoc
          # echoes unrecognised div attributes back out as data-* attributes,
          # so asserting on the bare user string (e.g. "opacity:0.5") passes
          # even with the filter removed entirely — it tests Pandoc, not us.
          # Each pattern below spans the boundary between something the filter
          # generated and the user's string.
          # A box that sets no geometry/align/valign attribute carries an empty
          # base style now that every --vb-* default lives in value-box.css, so
          # an *-extra-style hook is all that's left in the element's style.
          assert_present '<div class="value-box bg-blue" style="border:2px solid red;">' "$out" "$fixture/$fmt outer-extra-style merges into the wrapper style"
          assert_present 'class="icon vb-bearing-left bi bi-star" style="opacity:0.5;"' "$out" "$fixture/$fmt icon-extra-style merges into the icon style"
          assert_present '<div class="vb-content" style="letter-spacing:1px;"' "$out" "$fixture/$fmt content-extra-style merges into the content style"
          assert_present '<div class="details" style="font-style:italic;"' "$out" "$fixture/$fmt details-extra-style merges into the details style"
          assert_present '<div class="value" style="text-decoration:underline;"' "$out" "$fixture/$fmt value-extra-style merges into the value style"

          # Blanked attributes must not suppress a default into "font-size:;" —
          # icon-size="" and icon-color="" both leave the icon with an empty
          # style, with the stylesheet supplying both. Anchored through to the
          # value (14) since a bare empty-style icon is no longer distinctive.
          assert_present 'class="icon vb-bearing-left bi bi-star" style=""></i><div class="vb-content" style=""><div class="value" style="">14</div>' "$out" "$fixture/$fmt blank icon-size and icon-color leave an empty icon style"

          # title. No font-size or colour is emitted by default, on purpose:
          # the stylesheet's .value-box .title rule (and its var() fallbacks)
          # supplies them unless an attribute overrides them.
          assert_present '<div class="title" style="">Bibbles</div>' "$out" "$fixture/$fmt renders the title and leaves its size to the stylesheet"
          assert_present '<div class="title" style="font-size:1.4rem; color:yellow; text-transform:uppercase;">Styled</div>' "$out" "$fixture/$fmt title colour, size and style hook all apply"

          # A title above a left/right value row needs an extra wrapper, so the
          # title spans the width instead of becoming a third item in the row.
          assert_present '<div class="title" style="">Rowed</div><div class="vb-row vb-value-left">' "$out" "$fixture/$fmt title sits above the value row, not inside it"
          # ...and must not appear otherwise: without a title the row class
          # stays on .vb-content exactly as it did before the feature existed.
          assert_present '<div class="vb-content vb-value-left" style=""><div class="value"' "$out" "$fixture/$fmt value-position row is unwrapped when there is no title"
          assert_count 1 'class="vb-row vb-value-left"' "$out" "$fixture/$fmt emits the row wrapper only where it is needed"

          # Title placement is fixed at the top of the content, so a bottom
          # value gives title, details, value. A deliberate choice, pinned here.
          assert_present '<div class="title" style="">Bottomed</div><div class="details"' "$out" "$fixture/$fmt title stays above the details when the value is below"

          # Guards the wrapper's *closing* tag, which nothing else can. Dropping
          # it does not fail the render or unbalance the tag counts: Quarto
          # re-parses and repairs the HTML, silently reparenting everything that
          # follows into the broken box. The only visible trace is the depth of
          # this close-tag run, which only the wrapped box produces.
          assert_count 1 '</div></div></div></div>' "$out" "$fixture/$fmt closes the row wrapper"

          # Delta: arrow inference from a leading +/-, an explicit delta-color
          # override, no arrow when there is neither a sign nor an explicit
          # delta-direction, an explicit delta-direction overriding inference,
          # the size/style hooks, and escaping. Each is anchored to the
          # "vb-value-row" wrapper the filter builds around value+delta (not
          # just the delta div), so a change that drops that wrapper — the
          # thing that keeps the two side by side — fails these too. Without
          # the filter, Pandoc echoes delta as a bare data-delta="..."
          # attribute with no escaping of its own, so these do not pass by
          # coincidence the way an escaped-quote check can (see tests/README.md).
          assert_present '<div class="vb-value-row" style=""><div class="value" style="">17</div><div class="delta" style=""><span class="delta-arrow" aria-hidden="true">▲</span> +12%</div></div>' "$out" "$fixture/$fmt delta infers an up arrow from a leading + and sits beside the value"
          assert_present '<div class="delta" style="color:#ff5252; "><span class="delta-arrow" aria-hidden="true">▼</span> -8%</div>' "$out" "$fixture/$fmt delta infers a down arrow and applies delta-color"
          assert_present '<div class="delta" style="">steady</div>' "$out" "$fixture/$fmt delta with no sign and no delta-direction gets no arrow"
          assert_present '<span class="delta-arrow" aria-hidden="true">→</span> 0%' "$out" "$fixture/$fmt delta-direction=flat overrides sign inference"
          assert_present '<div class="delta" style="font-size:1.3rem; font-style:italic;">' "$out" "$fixture/$fmt delta-font-size and delta-extra-style apply"
          assert_present '<div class="delta" style="">&lt;img src=x onerror=alert(1)&gt;</div>' "$out" "$fixture/$fmt delta is escaped, not raw HTML like value/title"
          assert_absent '<img src=x onerror=alert(1)>' "$out" "$fixture/$fmt escaped delta cannot inject a live tag"

          # delta-direction is matched case-insensitively and, when set,
          # overrides sign inference — "Down" must win over the "+" in "+3%".
          assert_present '<span class="delta-arrow" aria-hidden="true">▼</span> +3%' "$out" "$fixture/$fmt mixed-case delta-direction overrides an inferred arrow"

          # An unrecognised delta-direction shows no arrow rather than
          # crashing or falling back to a guess (the accompanying warning is
          # checked by the value-box-warning count above).
          assert_present '<div class="delta" style="">5%</div>' "$out" "$fixture/$fmt unrecognised delta-direction shows no arrow"

          # value-position=left makes .vb-value-row the flex item next to
          # .details, so the CSS scoped under .vb-value-left/.vb-value-right
          # gives it flex-shrink:0 to hold its size under pressure (see
          # value-box.css) — pinned here via the wrapper that carries that
          # class actually containing the value+delta row.
          assert_present '<div class="vb-content vb-value-left" style=""><div class="vb-value-row" style="">' "$out" "$fixture/$fmt delta with value-position=left protects the wrapper from shrinking"
        fi

        if [ "$fixture" = "passthrough" ]; then
          # Regression guard: a box using none of these attributes must render
          # identically to how every other box in this suite already does.
          assert_present '<div class="value-box bg-blue" style=""><div class="vb-content" style=""><div class="value" style="">1<' \
            "$out" "$fixture/$fmt a box with no extra attributes is unchanged"

          # id, an extra class alongside value-box, role/aria-label and an
          # already-namespaced data-id all pass through — but an arbitrary
          # attribute (top) that isn't data-*/aria-*/role/tabindex/lang is
          # left off entirely, not renamed into a data-* attribute that looks
          # like it survived but is actually inert.
          assert_present '<div id="kpi-1" class="value-box bg-blue custom-hook" style="" role="group" aria-label="Sales this quarter" data-id="box1">' \
            "$out" "$fixture/$fmt passes through id, extra class, role/aria-label, data-id and drops an unrecognised attribute"
          assert_absent 'data-top' "$out" "$fixture/$fmt does not rename an unrecognised attribute into a data- attribute"

          # A literal style attribute is dropped, not emitted as a second
          # style attribute alongside the box's own — the warning assertion
          # for this lives outside this format-scoped block, see above.
          assert_absent 'style="color:red"' "$out" "$fixture/$fmt drops a literal style attribute"

          # The href branch (an anchor, not a div) gets passthrough too. The
          # anchor's text-decoration/cursor styling now lives in value-box.css
          # (see the a.value-box rule) rather than being rebuilt inline here.
          assert_present '<a href="https://example.com" class="value-box bg-blue" style="" data-tracking="promo">' \
            "$out" "$fixture/$fmt passes through a data attribute on the href branch"

          # A double-quote in a passthrough value must not be able to close
          # the attribute early and inject a new one (e.g. onmouseover=...).
          # Note: deleting the filters: key does NOT falsify this pair, unlike
          # every other check in this fixture — Pandoc's own native div writer
          # independently escapes quotes too, so a filter-less render produces
          # the same escaped string by coincidence. Verified instead by
          # mutating escape_attr() directly to a no-op: the injected
          # onmouseover became a live attribute, confirming this protection is
          # this filter's own and not something Quarto's HTML postprocessing
          # would supply for free. See tests/README.md.
          assert_present 'data-note="payload&quot; onmouseover=&quot;alert(1)"' "$out" "$fixture/$fmt escapes a quote in a passthrough value"
          assert_absent 'onmouseover="alert' "$out" "$fixture/$fmt passthrough value cannot break out of its attribute"

          # A literal data-fragment-index would silently collide with the one
          # generated from index — dropped instead (warning asserted above,
          # outside this format-scoped block).
          assert_present 'data-fragment-index="1"' "$out" "$fixture/$fmt keeps the generated data-fragment-index"
          assert_absent 'data-fragment-index="9"' "$out" "$fixture/$fmt drops a literal data-fragment-index"

          # Regression guard for a real bug: the drop above must only fire
          # when index is actually set. Earlier this attribute was reserved
          # unconditionally, so it was dropped (and warned about) even with
          # nothing to collide with.
          assert_present '<div class="value-box bg-blue fragment fade-in-then-semi-out" style="" data-fragment-index="3">' \
            "$out" "$fixture/$fmt keeps a literal data-fragment-index when there is no index to collide with"

          # HTML attribute names are case-insensitive, and Quarto's own
          # postprocessing lowercases them regardless, so matching case-
          # sensitively would turn a mixed-case Role into data-role instead
          # of role. Asserted on the exact tag rather than a bare 'role='
          # search: this fixture's own explanatory prose contains the literal
          # string "data-role", which a document-wide search would also match
          # — the tautology trap tests/README.md warns about, hit here while
          # writing this very assertion.
          assert_present '<div class="value-box bg-blue" style="" role="group">' \
            "$out" "$fixture/$fmt matches a mixed-case attribute name case-insensitively, without double-prefixing it"

          # Regression guard for a real bug: collision detection (not just the
          # data- prefix decision) must also be case-insensitive. A mixed-case
          # Style previously slipped past the exact-case "style" check and
          # leaked through as an inert data-style attribute instead of being
          # recognised as the same collision a lowercase style triggers.
          # Anchored through to the value text (">9<"), not just the tag: the
          # tag alone is byte-identical to earlier boxes in this same fixture
          # (the "no extras" and "style dropped" cases), so a bare tag match
          # would be tautological — always present regardless of whether this
          # specific box's handling is correct. Also not a bare 'data-style'
          # search — this fixture's own prose explaining the fix contains
          # that literal string, the same trap that caught the Role assertion
          # above.
          assert_present '<div class="value-box bg-blue" style=""><div class="vb-content" style=""><div class="value" style="">9<' \
            "$out" "$fixture/$fmt does not leak a mixed-case Style as data-style"
        fi

        if [ "$fixture" = "row" ]; then
          # display:flex is the .value-box-row default (see value-box.css);
          # display:grid only turns on via the vb-row-grid class, which only
          # this filter ever emits — a plain Pandoc div never turns a
          # columns/gap attribute into a class or custom property — so these
          # anchor to filter-generated markup, not an echoed attribute. A row
          # with no relevant attributes carries an empty style now that gap
          # (like every other --vb-* default) lives in value-box.css.
          assert_present 'class="value-box-row" style="">' \
            "$out" "$fixture/$fmt no columns attribute lays out a wrapping flex row (no extra class or custom property)"
          assert_present 'class="value-box-row vb-row-grid" style="--vb-row-columns:3; ">' \
            "$out" "$fixture/$fmt columns=3 switches to a grid with equal-height wrapped rows"
          assert_present 'class="value-box-row" style="--vb-row-gap:3rem; border:1px dashed red;">' \
            "$out" "$fixture/$fmt gap and extra-style apply to the row wrapper"

          # Small-screen reflow. min-column-width travels as the --vb-row-min-col
          # custom property, emitted only when set (after gap, before columns);
          # responsive="false" adds the vb-row-fixed class. All filter-generated.
          assert_present 'class="value-box-row" style="--vb-row-min-col:16rem; ">' \
            "$out" "$fixture/$fmt min-column-width travels as --vb-row-min-col"
          assert_present 'class="value-box-row vb-row-grid" style="--vb-row-columns:4; --vb-row-min-col:10rem; ">' \
            "$out" "$fixture/$fmt min-column-width and columns coexist on the row"
          # A blank min-column-width is "unset": the row it produces is
          # byte-identical to a plain row (asserted above), and no partial
          # --vb-row-min-col declaration is left behind.
          assert_absent '--vb-row-min-col:;' "$out" "$fixture/$fmt a blank min-column-width emits no empty --vb-row-min-col declaration"
          assert_absent '--vb-row-min-col: ' "$out" "$fixture/$fmt a blank min-column-width emits no whitespace-only --vb-row-min-col declaration"
          assert_present 'class="value-box-row vb-row-fixed" style="">' \
            "$out" "$fixture/$fmt responsive=false adds vb-row-fixed to opt out of reflow"
          assert_present 'class="value-box-row vb-row-grid vb-row-fixed" style="--vb-row-columns:3; ">' \
            "$out" "$fixture/$fmt responsive=false alongside columns pins the grid to exactly N"

          # The reflow behaviour lives entirely in value-box.css — anchor to
          # the mechanism (the custom property the filter feeds and the rules
          # that consume it), as the icons/align check at ~L286 does, rather
          # than to a rendered pixel width.
          css="$work/$fmt/_extensions/value-box/value-box.css"
          assert_present 'flex: 1 1 var(--vb-row-min-col, 14rem);' "$css" \
            "$fixture/$fmt value-box.css sizes flex-row children from --vb-row-min-col"
          assert_present 'repeat(' "$css" "$fixture/$fmt value-box.css keeps a repeat() grid template"
          assert_present 'auto-fill,' "$css" \
            "$fixture/$fmt value-box.css grid uses auto-fill so columns drop as the row narrows"
          assert_present 'grid-auto-rows: 1fr;' "$css" \
            "$fixture/$fmt value-box.css keeps grid-auto-rows:1fr for equal-height wrapped rows"
          assert_present '.value-box-row.vb-row-fixed.vb-row-grid {' "$css" \
            "$fixture/$fmt value-box.css keeps the responsive=false opt-out for the grid"
          assert_present 'grid-template-columns: repeat(var(--vb-row-columns), 1fr);' "$css" \
            "$fixture/$fmt value-box.css opt-out restores the exact-N-column grid"

          # Themeable defaults: value-box.css must carry each default as a
          # var(--vb-*, <default>) fallback, so that a box the filter left
          # bare (asserted above and in passthrough) still renders and a
          # project :root override can reach it. A representative sample.
          assert_present 'width: var(--vb-width, 80%);' "$css" \
            "$fixture/$fmt value-box.css carries the --vb-width default"
          assert_present 'padding: var(--vb-padding, 1.5rem);' "$css" \
            "$fixture/$fmt value-box.css carries the --vb-padding default"
          assert_present 'font-size: var(--vb-value-font-size, 2.2rem);' "$css" \
            "$fixture/$fmt value-box.css carries the --vb-value-font-size default"
          assert_present 'color: var(--vb-font-color, white);' "$css" \
            "$fixture/$fmt value-box.css carries the --vb-font-color default"
          assert_present 'gap: var(--vb-row-gap, 1.5rem);' "$css" \
            "$fixture/$fmt value-box.css carries the --vb-row-gap default"

          # id, an extra class, and role/aria-label/data-id all pass through,
          # but top is outside the recognised set and must be left off
          # entirely rather than renamed into a data- attribute.
          assert_present '<div id="kpi-row" class="value-box-row custom-hook" style="" role="group" aria-label="Key metrics" data-id="row1">' \
            "$out" "$fixture/$fmt passes through id, extra class, role/aria-label and data-id"
          assert_absent 'data-top' "$out" "$fixture/$fmt does not rename an unrecognised attribute into a data- attribute"

          # A literal style attribute must not survive as a second style
          # attribute alongside the row's own generated one.
          assert_absent 'style="color:red"' "$out" "$fixture/$fmt drops a literal style attribute on the row wrapper"

          # Row-level attribute inheritance. Each pattern below is entirely
          # filter-generated (class list + custom-property style), so it
          # cannot pass by coincidence the way an echoed attribute could. Only
          # the attributes the row actually sets (icon-position → class,
          # align → --vb-text-align/--vb-icon-align) reach the child; width /
          # min-height / padding / valign are unset, so they stay in the
          # stylesheet and no longer appear inline.
          assert_count 2 '<div class="value-box vb-icon-left bg-teal" style="--vb-text-align:right; --vb-icon-align:flex-end; ">' \
            "$out" "$fixture/$fmt both children with no attributes of their own inherit icon-position, color, icon-size and align from the row"
          assert_present 'style="font-size:4em; "></i>' "$out" "$fixture/$fmt icon-size inherited from the row reaches the icon"

          # A child that sets its own color overrides the row's, but keeps
          # every other inherited attribute (icon-position, icon-size, align).
          assert_present '<div class="value-box vb-icon-right bg-red" style="--vb-text-align:center; --vb-icon-align:center; ">' \
            "$out" "$fixture/$fmt a child's own color overrides the row's, other inherited attributes are unaffected"
          assert_present '<div class="value-box vb-icon-right bg-teal" style="--vb-text-align:center; --vb-icon-align:center; ">' \
            "$out" "$fixture/$fmt a sibling with no color of its own still inherits the row's"

          # An explicit blank icon-color on a child is a deliberate override,
          # not "unset" — it must not be replaced by the row's icon-color, and
          # must not emit an empty "color:;" declaration either. With icon-size
          # also unset the icon carries an empty style.
          assert_present 'class="icon vb-bearing-left bi bi-star" style=""></i>' \
            "$out" "$fixture/$fmt a child that blanks icon-color keeps no colour declaration, not the row's"
          assert_present 'class="icon vb-bearing-left bi bi-star" style="color:red; "></i>' \
            "$out" "$fixture/$fmt a sibling with no icon-color of its own inherits the row's"

          # href is not in the inheritable list, so a row that carries one has
          # no effect on a child that sets no href of its own.
          assert_absent '<a href="https://example.com/row"' "$out" "$fixture/$fmt href on the row does not make a child render as a link"

          # icon-extra-style inherits from the row, and a child's own value
          # overrides it rather than being appended alongside it.
          assert_present 'class="icon vb-bearing-left bi bi-star" style="opacity:0.5;"></i>' \
            "$out" "$fixture/$fmt icon-extra-style inherited from the row reaches a child with none of its own"
          assert_present 'class="icon vb-bearing-left bi bi-star" style="opacity:0.9;"></i>' \
            "$out" "$fixture/$fmt a child's own icon-extra-style overrides the row's"

          # An inherited font-color flows through the value/title colour
          # fallback chain exactly as a locally-set one would.
          assert_present '<div class="value" style="color:black; ">7</div>' \
            "$out" "$fixture/$fmt inherited font-color reaches the value via the existing fallback chain"
          assert_present '<div class="title" style="color:black; ">Composed</div>' \
            "$out" "$fixture/$fmt inherited font-color reaches the title via the existing fallback chain"
        fi
        ;;

      latex)
        out="$work/$fmt/$fixture.tex"

        # Raw HTML must never reach a non-HTML writer. A <link> tag in the
        # preamble is what broke PDF renders before the stylesheets moved to
        # HTML dependencies.
        assert_absent "<link"             "$out" "$fixture/$fmt has no HTML link tags"
        # Currently inert: Pandoc's LaTeX writer drops html RawBlocks outright.
        # It becomes a live check once a native LaTeX representation exists.
        assert_absent 'class="value-box'  "$out" "$fixture/$fmt has no HTML div markup"

        if [ "$fixture" = "minimal" ]; then
          # Body content survives today. The value does not — value boxes have
          # no non-HTML representation yet, so this records current behaviour
          # and should gain a matching value assertion when that lands.
          assert_present "Bibbles bobbled" "$out" "$fixture/$fmt keeps the details text"
        fi
        ;;

      docx)
        if [ "$fixture" = "minimal" ]; then
          # A .docx is a zip; read the document part out of it to assert on.
          xml="$work/$fmt/$fixture.docx.xml"
          unzip -p "$work/$fmt/$fixture.docx" word/document.xml > "$xml" 2>/dev/null
          assert_present "Bibbles bobbled" "$xml" "$fixture/$fmt keeps the details text"
        fi
        ;;
    esac
  done
  echo
done

# The project's long-standing test bar: the demo deck must still build. Staged
# and rendered in the work tree so a test run never touches the tracked
# index.html at the repo root.
echo "[demo deck]"
if stage "$work/demo"; then
  cp "$repo_root/example.qmd" "$work/demo/"
  if render "$work/demo" revealjs example; then
    ok "example.qmd renders to revealjs"
    assert_absent "value-box warning" "$work/demo/example.revealjs.log" "example.qmd emits no filter warnings"
    # Regression guard for a real bug: Quarto's Reveal.js theme ships
    # `.reveal a { background-color: rgba(0,0,0,0); ... }`, a class+tag
    # selector more specific than a plain `.value-box`/`.bg-*` class rule and
    # loaded after value-box.css, so a linked (href) box on a revealjs slide
    # silently lost its background/text colour back to the theme's plain-link
    # defaults. The fix restates those properties at doubled-class
    # specificity (a.value-box.value-box, a.value-box.bg-*) so they win
    # regardless of load order — assert both are still present in the CSS
    # this stylesheet.
    assert_present "a.value-box.value-box" "$work/demo/_extensions/value-box/value-box.css" \
      "value-box.css keeps the doubled-specificity override for a linked box's base colour/background"
    assert_present "a.value-box.bg-slate" "$work/demo/_extensions/value-box/value-box.css" \
      "value-box.css keeps the doubled-specificity override for a linked box's named background colour"
  else
    fail "example.qmd renders to revealjs" "see tests/_work/demo/example.revealjs.log"
  fi
else
  fail "example.qmd renders to revealjs" "could not stage $work/demo"
fi
echo

echo "─────────────────────────────"
printf '%d passed, %d failed\n' "$passed" "$failed"

# A run that checked nothing must not look like a run that passed.
if [ "$passed" -eq 0 ] && [ "$failed" -eq 0 ]; then
  echo "no checks ran — refusing to report success" >&2
  exit 2
fi

if [ "$failed" -gt 0 ]; then
  echo
  echo "failed checks:"
  for f in "${failures[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
