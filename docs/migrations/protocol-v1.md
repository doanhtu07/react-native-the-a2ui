# Supporting A2UI Protocol v1.0 alongside v0.9

Status: **blocked on `@a2ui/web_core@0.16.0`**. The renderer is currently on
`@a2ui/web_core@0.15.0` and renders v0.9 surfaces only. The plan below adds a
v1.0 catalog without dropping v0.9.

Last verified: 2026-11-22 against the repo and npm.

## TL;DR

- The renderer engine (`SurfaceModel`, `NodeResolver`, `MessageProcessor`,
  `GenericBinder`, `A2uiSurface`, `adapter.tsx`) is **version-agnostic**. The
  protocol version boundary is the **catalog**, not the renderer.
- Supporting v1.0 means adding a second catalog (`basicCatalogV1`) and binding
  the same React components to the v1.0 component APIs. It is **not** a rewrite.
- Only `Text` and `TextField` differ between the v0.9 and v1.0 basic catalogs.
- One `MessageProcessor` can hold both catalogs and render v0.9 and v1.0
  surfaces side by side. All catalogs used **within one surface** must share the
  same protocol version.
- We are waiting on `@a2ui/web_core@0.16.0` because 0.15.0 implements an **early
  v1.0 draft**: it uses bare envelope keys (`accessibility`, `checks`,
  `metadata`, `catalogId`) and rejects the final spec's `@`-prefixed keys.
- No separate branch is needed if 0.16.0 lands and keeps pre-1.0 behavior
  (it does). Use a short-lived `feat/protocol-v1` branch or an `alpha`/`beta`
  release channel only if 0.16.0 is delayed or destabilizes v0.9.

## 1. What we learned

### 1.1 The renderer core is already version-agnostic

The renderer builds almost entirely on version-neutral `@a2ui/web_core` APIs:

| Concern         | API                             | Version-specific?                                   |
| --------------- | ------------------------------- | --------------------------------------------------- |
| Message routing | `MessageProcessor`              | No; routes by envelope `version`                    |
| Component tree  | `NodeResolver`                  | No; resolves each component against `model.catalog` |
| Binding         | `GenericBinder`                 | No; schema comes from the component API             |
| Surface state   | `SurfaceModel`                  | No                                                  |
| Rendering       | `A2uiSurface`, `NodeView`       | No                                                  |
| React adapter   | `createComponentImplementation` | No; takes a `ComponentApi`                          |

`A2uiSurface` takes a `SurfaceModel` and uses `surface.defaultCatalog`. For a
v1.0 surface created without a default `catalogId`, that value is `undefined`,
which is allowed; each component resolves through its own
`ComponentModel.catalog`. No change is needed in `a2ui-surface.tsx` or
`adapter.tsx`.

Verified with 0.15.0:

```js
// one processor, both catalogs, both surface versions
const processor = new MessageProcessor([basicCatalogV09, basicCatalogV1])

processor.processMessages([
  {
    version: 'v0.9',
    createSurface: { surfaceId: 'old', catalogId: basicCatalogV09.id },
  },
  {
    version: 'v0.9',
    updateComponents: { surfaceId: 'old', components: [/* … */] },
  },
  {
    version: '1.0',
    createSurface: {
      surfaceId: 'new',
      catalogId: basicCatalogV1.id,
      components: [/* … */],
    },
  },
])
// both surfaces resolve and render
```

### 1.2 The catalog is the version boundary

A v0.9 catalog cannot render a v1.0 surface. `DEFAULT_CATALOG_COMPATIBILITY`
maps `'1.0'` to `new Set(['1.0'])` only, so a v0.9 catalog is incompatible with
a v1.0 message. Verified failure modes on 0.15.0:

- The surface's `catalogId` names an unregistered catalog →
  `A2uiCatalogError` `CATALOG_ERROR`, `Catalog not found: <id>`.
- The surface's `catalogId` names a registered v0.9 catalog →
  `A2uiCatalogError` `CATALOG_ERROR`:
  `specification version (0.9) does not match message protocol version (1.0)`.
  Pre-1.0 mismatches throw `VALIDATION_ERROR` instead.

This is why "support v1.0" means "add a v1.0 catalog", not "change the
renderer".

### 1.3 v0.9 vs v1.0 basic catalog differences

Compared programmatically from the installed `web_core` packages.

**Components** (only these differ among the 13 the renderer supports):

| Component       | v0.9                          | v1.0                                                                   |
| --------------- | ----------------------------- | ---------------------------------------------------------------------- |
| `Text.variant`  | `h1`–`h5`, `caption`, `body`  | `caption`, `body`; headings are Markdown `#`–`#####` in `text`         |
| `TextField`     | `validationRegexp`            | no `validationRegexp`; adds `placeholder`; spec makes `value` required |
| `accessibility` | bare `accessibility` property | `@accessibility` envelope key                                          |

All other supported components (`Button`, `Card`, `CheckBox`, `ChoicePicker`,
`Column`, `Divider`, `Image`, `List`, `Modal`, `Row`, `Tabs`) have the same
supported schema.

**Functions**:

- v1.0 **drops** `add`, `subtract`, `multiply`, `divide`, `equals`,
  `not_equals`, `greater_than`, `less_than`, `contains`, `starts_with`,
  `ends_with`.
- v1.0 **adds** `@index` (template iteration index, optional `offset`).
- Validation functions (`required`, `regex`, `length`, `numeric`, `email`)
  return `ValidationResult` objects instead of booleans.
- `and` / `or` / `not` coerce a `ValidationResult` to its `valid` boolean.

### 1.4 Packaging: the Lit problem is unchanged

`@a2ui/web_core/catalogs/basic/v1` is a real export, but its index transitively
imports `@lit/context` through `universal/basic_catalog/context/markdown.js`.
Metro does not tree-shake, so importing it would pull Lit into the React Native
bundle.

The v1.0 component APIs and functions themselves are Lit-free. Import the deep
files instead, using the same virtual-subpath mechanism the renderer already
uses for v0.9:

| Need                                      | Lit-free file                                       |
| ----------------------------------------- | --------------------------------------------------- |
| `TextApi`, `TextFieldApi`, `ButtonApi`, … | `catalogs/basic/v1/components/basic_components.js`  |
| `BASIC_FUNCTIONS`                         | `catalogs/basic/v1/functions/basic_functions.js`    |
| `BASIC_CATALOG_DOCUMENT_OPTIONS`          | `catalogs/basic/v1/components/basic_components.js`  |
| `BasicCatalogThemeSchema`                 | `universal/basic_catalog/theme.js` (already mapped) |

Do not import the `A2ui*` names (`A2uiText`, `A2uiTextField`, …) from
`catalogs/basic/v1/components/index.js`: those are the Lit web-component
implementations and pull in `universal/basic_catalog/components/index.js`. The
renderer only needs the `*Api` schema objects from `basic_components.js`.

`basic_components.js` also exports `BASIC_CATALOG_DOCUMENT_OPTIONS`
(`schemaId`, `title`, `description`, `instructions`), which should be passed to
the catalog so `toJson()` and renderer capabilities match the published
document.

### 1.5 web_core 0.15.0 is an early v1.0 draft

This is the blocker. Verified against the installed 0.15.0 and the published
spec / repo `main` (0.16.0):

| Area                         | 0.15.0 (npm latest)                                                                                                         | Published v1.0                                         |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| Envelope keys                | bare `catalogId`, `accessibility`, `metadata`, `checks`; **rejects** `@catalogId`, `@accessibility`, `@metadata`, `@checks` | `@catalogId`, `@accessibility`, `@metadata`, `@checks` |
| `updateDataModel.value`      | optional                                                                                                                    | **required**; `null` deletes the key                   |
| Wire version                 | `"1.0"` only; rejects `"v1.0"`                                                                                              | `"1.0"`                                                |
| `@path` / `@call` / `@index` | supported                                                                                                                   | supported                                              |
| `createSurface.theme`        | rejected                                                                                                                    | removed                                                |

The v1.0 Evolution Guide §2.9 describes exactly this transition: early drafts
used bare `catalogId`/`metadata`, and final v1.0 moved the envelope mixins into
the reserved `@` namespace. Core SDKs must dual-read the legacy bare keys and
emit only the `@` keys. That behavior lands in **0.16.0**.

## 2. What we are waiting on

### 2.1 `@a2ui/web_core@0.16.0`

- Release bump commit `979eaee` on **2026-11-18**: `0.15.0 -> 0.16.0`, described
  as _"in preparation for this week's npm release."_
- As of **2026-11-22**, npm still reports `latest: 0.15.0`; `0.16.0` is not in
  the registry.
- Publishing is manual (`typescript/scripts/publish_npm.mjs`). Recent releases
  went live ~50–75 minutes after their bump commit, so 0.16.0 is expected
  imminently.

Check when it lands:

```bash
npm view @a2ui/web_core dist-tags
npm view @a2ui/web_core@0.16.0 version
```

If the wait becomes a problem, pin the repo commit instead of the npm version:

```jsonc
// apps/example-expo/package.json (dependencies or overrides)
"@a2ui/web_core": "github:a2ui-project/a2ui#979eaee"
```

That gives final-spec v1.0 behavior today at the cost of a less stable lock;
use it only for a spike, not for a release.

### 2.2 What 0.16.0 fixes for us

- Emits `@catalogId`, `@metadata`, `@accessibility`, `@checks` on v1.0
  surfaces.
- Dual-reads legacy bare `catalogId`, `metadata`, `accessibility`, `checks`
  when the component schema does not declare them.
- Rejects components that specify both the `@` and bare form of the same mixin.
- Validates `@metadata.extensions` keys as UAX #31 identifiers.
- Keeps pre-1.0 behavior unchanged, so v0.9 rendering is unaffected.

### 2.3 Breaking changes to budget for

0.16.0 is not a drop-in type bump:

- `ResolveA2uiProp` now resolves optional or nullable properties declared
  directly as `DataBinding` or `FunctionCall` to `unknown` instead of
  `undefined` or `null`.
- `GenerateSetters` no longer declares a setter for `unknown` or string-indexed
  properties.
- Pre-1.0 nested function calls are validated against `returnType` and the
  enclosing `Dynamic*` slot; undeclared arguments and unbounded `length` /
  `numeric` arguments now fail.
- `SurfaceModel.protocolVersion` prefers the `createSurface` version over the
  default catalog version.

Plan a full `pnpm typecheck` and test pass, and expect to narrow a few optional
props in the component render functions.

## 3. How to stay compatible with both v0.9 and v1.0

### 3.1 Recommended: one package, two catalogs

Keep `basicCatalog` (v0.9) and add `basicCatalogV1` (v1.0) in the same package.
Consumers register the one(s) they need:

```ts
import { basicCatalog, basicCatalogV1 } from '@the-a2ui/renderer'

const processor = new MessageProcessor([basicCatalog, basicCatalogV1])
```

Why this works:

- `MessageProcessor` routes messages by envelope `version`.
- `NodeResolver` resolves each component against `model.catalog`, so mixed
  catalogs coexist as long as they are not mixed **inside one surface**.
- `A2uiSurface` and `adapter.tsx` need no changes.
- The React components are the same; only the API schema they are bound to
  changes.

Constraints and rules:

- **One protocol version per surface.** A v0.9 surface uses only v0.9
  catalogs; a v1.0 surface uses only v1.0 catalogs. An app can host both
  surfaces at the same time.
- **v1.0 surfaces may omit `catalogId`** and set `@catalogId` per component.
  `surface.defaultCatalog` is then `undefined`, which `A2uiSurface` already
  handles.
- **Do not mix `@` and bare envelope keys** in one component; 0.16.0 rejects it.
- Keep the v0.9 catalog exported and unchanged so existing consumers do not
  break.

### 3.2 Component reuse strategy

Define each component once, then bind it to both API versions. Two viable
shapes:

**Option A — two exports per file (simple, explicit):**

```tsx
// text.tsx
import { TextApi as TextApiV09 } from '@a2ui/web_core/v0_9/basic_catalog/api'
import { TextApi as TextApiV1 } from '@a2ui/web_core/catalogs/basic/v1/components'

const renderText: React.FC<ReactA2uiComponentProps<TextProps>> = ({
  props,
}) => {
  /* version-neutral render */
}

export const Text = createComponentImplementation(TextApiV09, renderText)
export const TextV1 = createComponentImplementation(TextApiV1, renderText)
```

**Option B — a catalog factory (less duplication at the catalog level):**

```ts
export function createBasicCatalog(version: '0.9' | '1.0') {
  return version === '1.0' ? basicCatalogV1 : basicCatalog
}
```

Either way, the render function should accept a version-neutral prop subset:
`text`, `variant` (as `string`), `weight`; and for `TextField`: `label`,
`value`, `variant`, `placeholder?`, `validationErrors?`, `setValue`.

The two components that need real version logic:

- `text.tsx`
  - v1.0 `variant` is only `caption | body`.
  - Parse leading Markdown headings (`#`–`#####`) from `text` and map them to
    the existing `h1`–`h5` styles and `accessibilityRole="header"`.
  - Keep the existing `h1`–`h5` variant handling for the v0.9 catalog.
- `text-field.tsx`
  - Add `placeholder` → `TextInput.placeholder`.
  - Keep `validationErrors`; v1.0 `@checks` feeds the same prop.
  - `value` is required by the spec but optional in 0.15.0; the existing
    `props.value || ''` already tolerates both.

Accessibility: `GenericBinder` already exposes `props.accessibility`
(`label`, `description`, `live`, `hidden`). Mapping it to React Native props is
an enhancement, not a blocker. Do it once in a wrapper so both catalogs get it.

### 3.3 Fallback: separate branch

A long-lived branch is **not** the default plan. Use one only if:

1. 0.16.0 is delayed and v1.0 support must ship first, or
2. 0.16.0's breaking changes destabilize v0.9 rendering.

In that case:

- `main` stays on `@a2ui/web_core@0.15.0` and v0.9.
- `feat/protocol-v1` pins 0.16.0 and carries `basicCatalogV1` plus the
  component/subpath changes.
- Merge when 0.16.0 is stable and v0.9 tests pass on it.
- Expect double maintenance for the duration: two dependency versions, two CI
  matrices, and duplicate changesets.

Prefer the release-channel mechanism in
[`docs/rules/versioning-guidelines.md`](../rules/versioning-guidelines.md) over a
branch: publish the v1.0 work as `alpha`/`beta` of the renderer while `latest`
stays on the v0.9-compatible build. That keeps one codebase and lets consumers
opt in.

## 4. Implementation plan

### Phase 0 — unblock

- [ ] Wait for `@a2ui/web_core@0.16.0` to appear on npm.
- [ ] Bump `packages/renderer` (`peerDependencies` / dev dependency) and
      `apps/example-expo` (`@a2ui/web_core`) to `0.16.0`.
- [ ] Run `pnpm typecheck` and the test suite; fix `ResolveA2uiProp` fallout.

### Phase 1 — v1.0 catalog

Add `packages/renderer/src/catalog/basic/basic-catalog-v1.ts` (or extend
`basic-catalog.ts`):

```ts
import { Catalog } from '@a2ui/web_core'
import {
  TextApi,
  TextFieldApi,
  // …the other v1 component APIs (ButtonApi, CardApi, …)
  BASIC_CATALOG_DOCUMENT_OPTIONS,
} from '@a2ui/web_core/catalogs/basic/v1/components'
import { BASIC_FUNCTIONS } from '@a2ui/web_core/catalogs/basic/v1/functions'
import { BasicCatalogThemeSchema } from '@a2ui/web_core/universal/basic_catalog/theme'

export const basicCatalogV1 = new Catalog(
  'https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json',
  '1.0',
  basicComponentsV1,
  BASIC_FUNCTIONS,
  {
    themeSchema: BasicCatalogThemeSchema,
    ...BASIC_CATALOG_DOCUMENT_OPTIONS,
  },
)
```

- Keep the existing `basicCatalog` (v0.9) unchanged.
- Export both from `catalog/basic/index.ts` and `catalog/index.ts`.
- Reuse the same 13 React implementations; bind each to the v1.0 API object.

### Phase 2 — components

- [ ] `text.tsx`: v1 API binding + Markdown heading parsing.
- [ ] `text-field.tsx`: v1 API binding + `placeholder`.
- [ ] Every other component: add a v1 binding (no render changes).
- [ ] Optional: apply `props.accessibility` in a shared wrapper.

### Phase 3 — packaging

Add the Lit-free v1 subpaths.

`packages/renderer/metro.js`:

```js
const VIRTUAL_SUBPATHS = {
  // existing v0.9 entries…
  '@a2ui/web_core/catalogs/basic/v1/components':
    'catalogs/basic/v1/components/basic_components.js',
  '@a2ui/web_core/catalogs/basic/v1/functions':
    'catalogs/basic/v1/functions/basic_functions.js',
}
```

`packages/renderer/tsconfig.json`:

```json
"@a2ui/web_core/catalogs/basic/v1/components": [
  "../../node_modules/@a2ui/web_core/src/catalogs/basic/v1/components/basic_components"
],
"@a2ui/web_core/catalogs/basic/v1/functions": [
  "../../node_modules/@a2ui/web_core/src/catalogs/basic/v1/functions/basic_functions"
]
```

Do **not** import `@a2ui/web_core/catalogs/basic/v1` directly; it pulls
`@lit/context`.

### Phase 4 — tests and example

- [ ] Add `packages/renderer/src/__tests__/catalog-v1.test.ts`:
      `version: '1.0'`, inline `createSurface`, `@path`, `@checks`, `@index`,
      `@accessibility`, `@catalogId`.
- [ ] Keep the existing v0.9 tests.
- [ ] Add a test that one `MessageProcessor` with both catalogs renders a
      v0.9 and a v1.0 surface.
- [ ] `apps/example-expo`: add a v1.0 example (or a protocol toggle on
      `Example`) using `version: '1.0'` and `basicCatalogV1`.

### Phase 5 — release

- [ ] Changeset: **`minor`** (new feature + pre-1.0 breaking surface), per
      `docs/rules/versioning-guidelines.md`.
- [ ] Optionally ship as `alpha`/`beta` first if the v1.0 path needs UAT.

## 5. What host apps and agents must change for v1.0

The renderer change is small; most migration work is on the producer side.

- Envelope `version: "1.0"` (not `"v1.0"`; 0.15.0 rejects `v1.0`).
- Register `basicCatalogV1`; advertise `supportedCatalogIds` /
  `inlineCatalogs`; use `@catalogId` per component and `catalogId` per function
  call for mixed catalogs.
- Dynamic values use `@path` / `@call`; literal `@` keys escape as `@@`; plain
  `path` / `call` keys are literal data.
- `createSurface`: `catalogId` is an optional default; inline `components` /
  `dataModel`; optional `metadata.extensions`; **no `theme`**.
- `updateDataModel`: `value` is required; `null` deletes a key.
- Text headings via Markdown; `TextField.placeholder`; `TextField.value`
  required; `@checks` with the `regex` function replaces `validationRegexp`.
- Functions: `@index`; `and` / `or` / `not` accept `ValidationResult`; check
  functions return `ValidationResult`; arithmetic/comparison helpers removed.
- RPC: handle `callRendererFunction` / `rendererFunctionResponse`; send
  `callAgentFunction` / handle `agentFunctionResponse`. web_core's
  `MessageProcessor` / `RpcHandler` does the protocol work; the app wires a
  transport and handlers. No renderer UI change.
- MIME `application/a2ui+json`; capabilities namespace `1.0`.

## 6. Open questions and risks

- **0.16.0 publish date.** No fixed date; the release commit says "this week."
  If it slips, use the branch or prerelease fallback.
- **0.16.0 type breakage.** `ResolveA2uiProp` and setter changes may require
  narrowing optional props. Budget a typecheck pass.
- **Markdown headings.** v1.0 moves headings into `Text.text`. The renderer
  currently shows text verbatim. A minimal heading parser is recommended;
  full Markdown stays a host override.
- **Accessibility.** `@accessibility` is available as `props.accessibility`.
  Decide whether to map `label` / `description` / `live` / `hidden` in this
  package or leave it to hosts.
- **Unsupported components.** `Icon`, `Video`, `AudioPlayer`, `Slider`,
  `DateTimeInput` remain out of the React Native catalog. v1.0's `posterUrl`
  and `steps` do not matter until those are added.
- **Multiple catalogs in one surface.** Allowed by v1.0 and by web_core, but
  not needed for the basic catalog. Keep the rule "one protocol version per
  surface" until a real mixed-catalog use case appears.

## 7. Checklist for when 0.16.0 lands

- [ ] `npm view @a2ui/web_core dist-tags` shows `0.16.0`.
- [ ] Bump renderer and example app to `0.16.0`.
- [ ] `pnpm typecheck` and tests pass on v0.9.
- [ ] Add `basicCatalogV1` and export it.
- [ ] Add Metro + tsconfig virtual subpaths.
- [ ] Add `Text` heading handling and `TextField.placeholder`.
- [ ] Add v1.0 tests, including both versions in one processor.
- [ ] Update the example app with a v1.0 example.
- [ ] Add a `minor` changeset.
- [ ] Verify a spec-compliant payload with `@accessibility`, `@checks`,
      `@catalogId`, and required `updateDataModel.value`.

## 8. References

- [A2UI v1.0 Evolution Guide](https://a2ui.org/specification/v1.0-evolution-guide/)
  — the source for §1.3, §1.5 and §5.
- [A2UI v1.0 Protocol Specification](https://a2ui.org/specification/v1.0-a2ui/)
- [A2UI v1.0 JSON Schemas](https://a2ui.org/specification/v1.0/schemas/)
- [`@a2ui/web_core` CHANGELOG](https://github.com/a2ui-project/a2ui/blob/main/typescript/core/web_core/CHANGELOG.md)
  — 0.16.0 release notes.
- Local plan documents: `docs/plan/1-initial-study.md` (Lit packaging study),
  `docs/plan/2-renderer-plan.md`, `docs/plan/3-concepts.md` (RPC notes).
- Versioning: `docs/rules/versioning-guidelines.md`.
