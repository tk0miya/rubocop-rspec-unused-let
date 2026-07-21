## [Unreleased]

- `RSpec/UnusedLet` now resolves shared example inclusions
  (`it_behaves_like`, `include_examples`, `include_context`, ...) to their
  `shared_examples` / `shared_context` definitions in the same file and
  searches the shared block as if it were written at the inclusion point.
  A `let` that the resolved shared block never references is now flagged,
  where previously any inclusion in scope silenced every visible `let`.
  Unresolvable inclusions (dynamic names, definitions in other files, or
  names defined more than once) keep the previous conservative behavior.
- Fix a false positive in `RSpec/UnusedLet` where `let` definitions inside an
  example group nested within a `shared_examples` / `shared_context` block
  were checked even though external including groups may reference them.
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
