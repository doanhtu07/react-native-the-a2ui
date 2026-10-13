# Contributing

## Branching

Most up-to-date branches:

- `main`, ...

Release tags (code freeze, lockstep across all `@the-a2ui/*` packages):

- `v0.1.0`, `v1.2.0-alpha.0`, `v1.2.0-beta.0`, ...

Pushing a `v*` tag runs the release workflow (npm publish + tarballs + GitHub
Release). See [Publish NPM Package](./docs/packages/publish.md).

## Versioning

We use @changesets/cli for managing versioning and releases

- We will use lockstep versioning for simplicity (see the `fixed` group in
  `.changeset/config.json` once there is more than one shippable package)
- See [Versioning Guidelines](./docs/rules/versioning-guidelines.md) for
  SemVer rules and the `alpha` (QA) / `beta` (UAT) / stable channel flow.

## Testing

### Manual testing

- When you change something, make sure to manually test it in the example Expo app
