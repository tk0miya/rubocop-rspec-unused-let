## [Unreleased]

- `RSpec/UnusedLet` now skips helper specs (rspec-rails `type: :helper`, or
  files under `spec/helpers`) by default, since the auto-included module may
  reference any `let` unseen. Set `CheckHelperSpecs: true` to check them.
- `RSpec/UnusedLet` now supports shared examples defined in the same spec
  file: it resolves which `let`s the shared block references and only
  treats those as used, instead of silencing every `let` in scope.
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
