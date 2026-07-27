## [Unreleased]

- `RSpec/UnusedLet` now also flags helper methods (`def`) written at an
  example group's level whose name is never referenced. Such a method
  becomes an instance method on the group's example class, so it is checked
  with the same rules as a `let`, and autocorrect removes it.
- `RSpec/UnusedLet` now resolves `shared_examples`/`shared_context`
  inclusions precisely instead of silencing every `let` in scope: it works
  out which `let`s the shared block actually references and treats only
  those as used, staying conservative for an inclusion it cannot resolve.
  Blocks in the file under inspection are handled automatically; set
  `SharedExamplePaths` (a list of paths or globs, e.g.
  `spec/support/**/*.rb`; default `[]`) to also resolve the top-level
  blocks of other files. Missing or unparseable listed files are skipped.
- `RSpec/UnusedLet` no longer flags a `let` that overrides one a shared
  block defines and uses, when that block is included inline with
  `include_examples` / `include_context`. Included with `it_behaves_like`,
  the block keeps its own definition, so the outer `let` stays checked.
- `RSpec/UnusedLet` now skips helper specs (rspec-rails `type: :helper`, or
  files under `spec/helpers`) by default, since the auto-included module may
  reference any `let` unseen. Set `CheckHelperSpecs: true` to check them.
- `RSpec/UnusedLet` now recognizes `let` definitions consumed by
  well-known gems' shared contexts and treats them as used. Currently
  supports [rspec-validator_spec_helper](https://github.com/izumin5210/rspec-validator_spec_helper):
  groups tagged with `type: :validator` may override `value`,
  `attribute_names`, `options` (and the helper's other overridable
  lets) without being flagged.
- Fix a false positive in `RSpec/UnusedLet` when a `let` defined in a
  nested group was only referenced from an ancestor group's `let`,
  `subject`, or hook block. Those ancestor blocks run in the example's
  scope, so their references resolve to the nested definition.
- Fix a false positive in `RSpec/UnusedLet` when a `let` was only
  referenced from a plain `def` helper method defined in an ancestor
  example group. Such helpers become instance methods on the example
  class and can reference `let` names visible at the example.

## [1.1.0] - 2026-07-15

- `RSpec/UnusedLet` now supports autocorrect. The correction is marked
  unsafe because a `let!` block may exist for side effects — flagged
  definitions are removed under `rubocop --autocorrect-all`.

## [1.0.0] - 2026-07-15

- Initial release
