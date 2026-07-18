# rubocop-rspec-unused-let

A [RuboCop](https://github.com/rubocop/rubocop) extension that detects
unreferenced RSpec `let` definitions.

It adds a single cop, `RSpec/UnusedLet`, which flags `let` (and optionally
`let!`) definitions whose name is never referenced within their scope. The cop
is deliberately conservative around `shared_examples` so that it avoids false
positives that a naive implementation would produce.

## Installation

Add the gem to your `Gemfile`:

```ruby
gem "rubocop-rspec-unused-let", require: false
```

This gem builds on [rubocop-rspec](https://github.com/rubocop/rubocop-rspec),
so make sure that is available too.

## Usage

Enable both plugins in your `.rubocop.yml`:

```yaml
plugins:
  - rubocop-rspec
  - rubocop-rspec-unused-let
```

## What it detects

```ruby
# bad
RSpec.describe Foo do
  let(:used)   { 1 }
  let(:unused) { 2 } # never referenced

  it { expect(used).to eq(1) }
end

# good
RSpec.describe Foo do
  let(:used) { 1 }

  it { expect(used).to eq(1) }
end
```

A `let` is considered *used* when its name appears as a bare method call
anywhere in its scope — inside examples, hooks (`before`/`after`/`around`),
`subject`, other `let` blocks, and nested example groups. Dynamic references
such as `send(:name)` / `public_send("name")` are also treated as usages.

## How it handles `shared_examples`

Because RuboCop analyzes one file at a time, a `let` can be consumed by a shared
example block defined in another file. To avoid false positives, the cop stays
silent whenever it cannot see every possible reference:

- `let` definitions **inside** a `shared_examples` / `shared_context` block are
  ignored (their consumers are the including groups, which may be external).
- When an example group's subtree contains a shared example inclusion
  (`it_behaves_like`, `include_examples`, `include_context`, ...), the `let`
  definitions **visible at that inclusion point** are ignored. Sibling subtrees
  that do not include shared examples are still checked.

```ruby
RSpec.describe Foo do
  let(:a) { 1 }              # skipped: visible at the inclusion below

  context "with shared" do
    let(:b) { 2 }            # skipped: same
    it_behaves_like "something"
  end

  context "other" do
    let(:c) { 3 }            # checked: the shared block cannot see `c`
    it { expect(c).to eq(3) }
  end
end
```

## Autocorrect

The cop can remove flagged `let` definitions automatically, but the
correction is marked **unsafe** because a `let!` block may exist for its
side effects. Run `rubocop --autocorrect-all` (or `-A`) to apply the
corrections, and review the diff before committing.

```ruby
# before -A
RSpec.describe Foo do
  let(:used)   { 1 }
  let(:unused) { 2 }

  it { expect(used).to eq(1) }
end

# after -A
RSpec.describe Foo do
  let(:used)   { 1 }

  it { expect(used).to eq(1) }
end
```

## Configuration

```yaml
RSpec/UnusedLet:
  # Whether to also check `let!`. On by default. Since `let!` is sometimes used
  # purely for its side effects (e.g. `let!(:user) { create(:user) }`), set this
  # to `false` to opt out.
  CheckLetBang: true
```

## Known-gem support

Some gems ship a shared context that dereferences `let` names dynamically
(e.g. via `eval`), so a single-file static analysis cannot see the
references. When the cop recognizes such a gem by the `type:` metadata on
an example group (or one of its ancestors), it treats the affected `let`
names as used automatically.

Currently supported:

- [rspec-validator_spec_helper](https://github.com/izumin5210/rspec-validator_spec_helper)
  — groups tagged with `type: :validator` may define `let(:value)`,
  `let(:attribute_names)`, `let(:options)` (and the helper's other
  overridable lets) without being flagged.

```ruby
RSpec.describe JsonFormatValidator, type: :validator do
  let(:value) { "String" }   # not flagged
  it { is_expected.to be_invalid }
end
```

## Known limitations

- Analysis is limited to a single file; references reachable only across files
  (e.g. through external shared examples) are intentionally not flagged.
- `let` definitions in an override chain (redefined in a nested group, or
  overriding an outer definition) are skipped, since the outer one may be
  reached through `super`.
- Helper specs under `spec/helpers/` are excluded by default. Override
  `Exclude` in your `.rubocop.yml` if you want them checked.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then run
`rake spec` to run the tests and `rake rubocop` to lint the gem. `rake` runs
both.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/tk0miya/rubocop-rspec-unused-let.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
