# Publishing to the private registry

This package publishes as `@nohles/react-native-readium` to the team Verdaccio instance at `http://192.168.1.202:4873/`.

## Prerequisites

- Your machine can reach `192.168.1.202:4873` (LAN or VPN).
- Registry authentication configured (see below).
- Version bumped in `package.json` if this version was already published.

## Registry configuration

The repo [`.npmrc`](../.npmrc) sets `@nohles:registry` for installs and publishes. Copy [`.npmrc.example`](../.npmrc.example) if you need the full template.

Authenticate once:

```bash
npm login --registry http://192.168.1.202:4873
```

Or add a token to your user `~/.npmrc` (never commit tokens):

```ini
//192.168.1.202:4873/:_authToken=YOUR_TOKEN
```

If npm errors on HTTP, for your user config only:

```bash
npm config set strict-ssl false --location=user
```

## Publish

From the repository root:

```bash
yarn install
yarn publish:registry
```

This runs a TypeScript check (`prepublishOnly`), compiles to `lib/` (`prepare`), and publishes with `npm publish --access public --tag rc`. Prerelease versions must use an explicit dist-tag; the registry also exposes `latest` (update with `npm dist-tag` if you want `latest` to match a new RC).

The registry URL comes from `publishConfig` in `package.json`.

`publish:npm` is an alias for `publish:registry`.

## Version bumps

Prefer the existing release flow:

```bash
yarn release
yarn publish:registry
```

`release-it` does not publish to npm automatically (`npm.publish: false`). Avoid `npm version` unless you intend `postversion` to publish immediately.

## Verify

```bash
npm view @nohles/react-native-readium version --registry http://192.168.1.202:4873
npm pack --dry-run
```

Open the Verdaccio web UI to confirm the tarball.

Re-publishing the same version will fail; bump the version or unpublish on the registry per your policy.

## Consumer install

In the consuming app, add the same scope registry to `.npmrc`:

```ini
@nohles:registry=http://192.168.1.202:4873/
```

Install with the `npm:` alias so imports stay `react-native-readium`:

```bash
yarn add react-native-readium@npm:@nohles/react-native-readium@5.0.0-rc.18 react-native-nitro-modules
```

Or in `package.json`:

```json
"react-native-readium": "npm:@nohles/react-native-readium@5.0.0-rc.18"
```

Peer dependencies (`react`, `react-native`, `react-native-nitro-modules`) and runtime deps (`@readium/*`) still resolve from the public npm registry unless your Verdaccio instance proxies them.

Native setup (CocoaPods, Expo plugin, Android Gradle) is unchanged; those files are included in the published package.
