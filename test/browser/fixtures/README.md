# Public startup fixture

`public-bundle.json` is a reviewed copy of the Counter example's public export. It supplies inert route snapshots for the two-document browser model, not signed session state. Keeping it here makes the tests independent of a leftover `.fow` build folder.

When intentionally changing the example's public route contract, export its configured pages through `mix fow.export` into a fresh directory, inspect the public bundle, and replace this fixture. Do not auto-populate missing routes in the test to make navigation pass. The model uses only each page's snapshot and the example's local stylesheet; exported asset filenames and the original development origin are not used as a native-loading proof.
