# Deploying Frontier Habitat 5.0 (GitHub Pages + Cloudflare R2)

## Why two hosts
GitHub refuses any file over 100 MB. The 5.0 game data file `index.pck` is about 186 MB. All other files
(`index.html`, `index.js`, `index.wasm` 43.7 MB, icons) are under the limit and stay on GitHub Pages
(https://paulbarby.github.io/frontier-habitat/). Only `index.pck` goes to a public Cloudflare R2 bucket.
The loading page reads the pack from that URL (`FH_PACK_URL`, set at build time by `tools/make_shell.mjs`).

## One-time set-up (Paul, in the Cloudflare dashboard)
1. R2 > Create bucket, for example `fh-assets`.
2. Bucket > Settings > Public access: enable the r2.dev URL (or connect a custom domain). Note the public
   host, for example `https://pub-xxxx.r2.dev`.
3. Bucket > Settings > CORS policy:
   ```json
   [{"AllowedOrigins":["https://paulbarby.github.io","http://localhost:5791"],"AllowedMethods":["GET","HEAD"],"AllowedHeaders":["*"],"MaxAgeSeconds":86400}]
   ```
4. On this PC, once: `npx wrangler login` (opens the Cloudflare sign-in; you sign in yourself).

## Each release (orchestrator, after Paul says "deploy")
1. `FH_PACK_URL=https://<public-host>/frontier-habitat/5.0.0/index.pck node tools/release_v5.mjs build`
2. `node tools/release_v5.mjs upload fh-assets`
3. `FH_PACK_URL=... node tools/release_v5.mjs verify` (must print status 200, the right size and a CORS header)
4. Commit, `git push origin main --tags`, then publish build/web to the gh-pages branch
   (`git subtree split --prefix build/web -b gh-pages`, `git push -f origin gh-pages`), tag `v5.0.0`, `gh release create`.
5. Open the live page in headless Chrome (`tools/shoot.mjs`) and confirm it starts.

## Notes
- `build/web/index.pck` and `build/release_pack/` are git-ignored, so the pack never enters git.
- A new release uses a new key (`frontier-habitat/<version>/index.pck`), so browsers never mix versions.
- The local repository is large (over 2.3 GB of history with model files). GitHub accepts it; a clone is slow.
