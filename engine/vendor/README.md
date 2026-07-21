# Vendored dependency policy

MdCore pins GitHub's `cmark-gfm` at tag `0.29.0.gfm.13`.

The source checkout and generated build/install directories are intentionally not
committed in this source package. Run:

```sh
./scripts/bootstrap-cmark.sh
```

The script performs a shallow checkout of the exact tag and builds static
libraries. MdCore links those libraries privately; no cmark types cross the
public C ABI.

`cmark-gfm` is distributed under its upstream BSD-style license. The bootstrap
step leaves the upstream license files in `vendor/cmark-gfm/src` so binary
distributors can include the required notices.
