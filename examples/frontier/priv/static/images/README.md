# Image variants

Keep source PNGs in `<asset>/originals/`, such as `monster/originals/`.
Run from this folder:

```sh
./resize.sh
```

The script discovers original PNGs and updates missing or older copies in sibling
`512/` and `256/` folders. It also regenerates outputs when the script changes.
Use `./resize.sh --force` to rebuild every variant.

Requires ImageMagick (`brew install imagemagick` on macOS). Resizing uses Lanczos,
preserves proportions and transparency, and centers the full source canvas within
an exact 512 × 512 or 256 × 256 canvas. Avoid cropping individual animation frames
before resizing, so their relative positioning is retained. Removed originals do
not automatically delete generated files.
