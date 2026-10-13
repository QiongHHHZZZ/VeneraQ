# AVIF fixtures

These unmodified samples come from [AOMediaCodec/libavif](https://github.com/AOMediaCodec/libavif/tree/b70519419573c958adc1bf94176ca0bf496e88e2/tests/data), pinned at commit `b70519419573c958adc1bf94176ca0bf496e88e2`. Each sample is explicitly listed as licensed under the same license as libavif in the [upstream fixture README](https://github.com/AOMediaCodec/libavif/blob/b70519419573c958adc1bf94176ca0bf496e88e2/tests/data/README.md). The BSD 2-Clause copyright and license notice is preserved in [LICENSE](LICENSE).

The samples cover a static pixel, an animated sequence, animation with alpha/Exif/XMP, and alpha with rotation. They are used for format recognition and optional codec probes; recognition does not imply that every platform can decode them.

| File | Bytes | SHA-256 |
|---|---:|---|
| `white_1x1.avif` | 305 | `ea4e43d1f07e4c00de16c13afa32376111bb306e51f08212cf4c1b6064df3667` |
| `colors-animated-8bpc.avif` | 1235 | `2f8683d21725261f37f86e115f0c212cc52d0fefd3a2ddfcc4fa648c1859906d` |
| `colors-animated-8bpc-alpha-exif-xmp.avif` | 7506 | `c2e38681057c15009c4b76ea08cea68cdde80806abd41d42a646f697bf5aabb2` |
| `abc_color_irot_alpha_irot.avif` | 10597 | `b371cc88244a873131e4d10ff9363d71ce4f41cf333bd4a491b38d970d9abd3b` |
