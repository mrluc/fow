# ADR-002 CSS findings: darkening transparent PNG sprites

## Recommendation

For uniform darkening, use CSS `filter: brightness(...)` directly on the sprite image. It is the smallest solution, works with the already-proven `fog-of-war-assets://` image display path, and preserves the sprite's alpha because brightness has an equivalent SVG filter that scales only R/G/B; the alpha transfer function remains the identity. This darkens opaque and antialiased sprite pixels while keeping transparent pixels transparent.

If a textured fog treatment is required, an inline SVG filter applied to the displayed image is the viable CSS-only direction: combine `feTurbulence` noise with the image's `SourceAlpha` using compositing, then apply a dark color/texture. `SourceAlpha` is expressly the input graphic's alpha channel, including antialiasing, so texture can be constrained to the sprite silhouette. This is more complex and should be treated as a prototype path; assess WebKit rendering and performance before choosing it.

## Options

| Option | Assessment |
| --- | --- |
| `filter: brightness(0.5)` | Best baseline. Minimal, tunable and preserves alpha while reducing RGB. It darkens original colors rather than tinting every pixel to a uniform fog color. |
| Inline SVG `filter` with `feComponentTransfer` | Appropriate if needing a precise channel remap/tint while preserving alpha. Leave `feFuncA` unspecified (identity) and adjust R/G/B. `SourceAlpha` can supply the silhouette for later compositing. More markup and filter-graph complexity than brightness. |
| CSS `mask-image: url(fog-of-war-assets://...)` | Do not rely on this for the custom asset scheme. The CSS Masking specification requires anonymous CORS-enabled fetches for mask-image resources; our custom-scheme anonymous image test already fails under HTTPS. A mask also controls visibility, rather than recoloring/darkening source pixels by itself. |

## Texture limits

A monochrome noise field composited inside `SourceAlpha` can produce mottling without canvas reads. It is a spatial texture, not a semantic per-pixel recoloring system: Game state can select filters using ordinary CSS classes. A procedural texture needs additional filter primitives; reproducing the current exact, screen-aligned 1px checkerboard is a separate rendering problem. The texture is generated at filter resolution and may look different when sprites are scaled. An overlay textured element clipped by `mask-image` is particularly unsuitable here because of the custom-scheme limitation.

## Compatibility context

The application experiment reports that WKWebView can display these assets through `<img>` and CSS backgrounds, while `crossorigin="anonymous"` and `fetch()` fail and ordinary image drawing taints canvas. The proposed CSS filters operate on the rendered element and require no script-readable pixel access; they do not remove canvas taint. The SVG filter option uses a same-document filter definition (`filter: url(#...)`) to avoid depending on loading a separate filter or mask resource. Confirm that target WKWebView version renders the selected filter consistently.

## Sources

1. W3C, [Filter Effects Module Level 1: brightness and equivalent SVG filter](https://www.w3.org/TR/filter-effects/#brightness-function). Defines brightness as a linear multiplier and gives the equivalent `feComponentTransfer` form with only R/G/B functions.
2. W3C, [Filter Effects Module Level 1: SourceAlpha and component transfer](https://www.w3.org/TR/filter-effects/) and [feComponentTransfer](https://www.w3.org/TR/filter-effects/). `SourceAlpha` carries the source alpha channel; omitted channel transfer functions are identity transforms.
3. W3C, [CSS Masking: security](https://www.w3.org/TR/css-masking-1/#security). Requires anonymous CORS-enabled resource fetching for masks. Inline or data-based masks differ from fetching the custom-scheme sprite.
