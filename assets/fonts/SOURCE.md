# Fonts

The app's typefaces ship inside it and are never downloaded at run time
(invariant 1). Each folder holds one family and its SIL Open Font License
1.1 text (`OFL.txt`); they are not covered by this repository's MIT
licence, and the app registers each OFL with Flutter's licence page.

| Family (in the app) | Folder | Files | Source |
|---|---|---|---|
| `Outfit` — text | `outfit/` | 300, 400, 500, 600, 700 | Outfitio/Outfit-Fonts @ `902773808eb372f70fb34e8946dd1ffe604efc79` (committed 2023-03-26), `fonts/ttf/` |
| `PlexMono` — IBM Plex Mono, text | `plexmono/` | 400, 500, 600 | google/fonts @ `23e54b51ddffbc7713c583748e3bd86f62b1fa4a` (committed 2026-09-24), `ofl/ibmplexmono/` |
| `HonestPieces` — the pieces | `pieces/` | Noto Sans Symbols 2 Regular, subset to U+2654–265F | google/fonts @ `23e54b51ddffbc7713c583748e3bd86f62b1fa4a` (committed 2026-09-24), `ofl/notosanssymbols2/`, cut by `tools/subset_piece_font.sh` |

Commit dates are from the GitHub API, read 2026-09-29; the google/fonts
commit was main's head when #71 was filed (2026-09-28). google/fonts carries
Outfit only as a variable font, so the static weights come from the Outfit
project's own repository, at the same commit Honest Solitaire and Honest
Sudoku pin (the files below match Honest Solitaire's `assets/fonts/SHA256SUMS`
byte for byte, checked 2026-09-29). `HonestPieces.ttf` was written on
2026-09-29 by `tools/subset_piece_font.sh` with fontTools 4.63.0.

SHA-256, from `shasum -a 256 assets/fonts/*/*` on 2026-09-29 (upstream's `plexmono/OFL.txt` has CRLF line ends; it is committed with LF line ends, and its hash is of that):

| File | SHA-256 |
|---|---|
| `outfit/OFL.txt` | `c676351bf8576b9aba743cd5eaa8c0e7ee0d51f805d720447b4df4ddb6a2e416` |
| `outfit/Outfit-Bold.ttf` | `f620b69582e06d7e1b3bbde74ed8c5876eadabb038390780db2a3414a1490197` |
| `outfit/Outfit-Light.ttf` | `181c6867345960e0fbd807131624d092accb5f87185910f9496ba8b188aa2730` |
| `outfit/Outfit-Medium.ttf` | `dc8d9212fc57556a55d01e863071f727cd6264b748e28885d853807aeb186142` |
| `outfit/Outfit-Regular.ttf` | `3b64ac4f6ab6a8eebddd4b0bc03c811c43602e11e176382ab0ee6be615ab861b` |
| `outfit/Outfit-SemiBold.ttf` | `bf2e1d2a6ec2a67952e8b36edd2b2bb9f340c0cdd10b0ad5145b4dbbc1339608` |
| `pieces/HonestPieces.ttf` | `1e938940957f3ea526d7cb75200b4c7a20a66ed5ab9a41750e9548c70ceb5bdc` |
| `pieces/OFL.txt` | `b118dd41337806a5d4797052c77caf3bd096aed783e5eb21b4d11154351e1ac0` |
| `plexmono/IBMPlexMono-Medium.ttf` | `a9b4c49bb299e05b5f6c481e7fb5e78943d2793249a0c8874ab574a2d1ea6755` |
| `plexmono/IBMPlexMono-Regular.ttf` | `6a3412f058c7d8dfd9170c41e85ade48e5156ecb89356110ca57a0a27734af46` |
| `plexmono/IBMPlexMono-SemiBold.ttf` | `d3c38e55c78f5b0f28009fddba4834ec503278936a5986032424c9bd2d23aa46` |
| `plexmono/OFL.txt` | `37784b44044a4ffd9256702b7c0982c37e5c8887ba90c6dca0479aea93dc898d` |
