# rubocop-rspec-unused-let

A [RuboCop](https://github.com/rubocop/rubocop) extension that detects
unreferenced RSpec `let` definitions and helper methods.

It adds a single cop, `RSpec/UnusedLet`, which flags `let` (and optionally
`let!`) definitions and helper methods (`def`) whose name is never referenced
within their scope. The cop resolves `shared_examples` references precisely when
it can see the shared block — in the same file, or in a file listed in
`SharedExamplePaths`, which covers `spec/support/**/*.rb` by default — and stays
conservative otherwise, so that it avoids false positives that a naive
implementation would produce.

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

A `let` is considered *used* when its name appears as a bare method call in any
of these places:

- in an example of the group that defines it, or of any group nested inside that
  one — but not in an **ancestor's** example
- in a helper body — a hook (`before`/`after`/`around`), `subject`/`subject!`,
  another `let`, or a plain `def` method written at a group's level — of any of
  those groups **or of an ancestor**

Any of these may instead be a dynamic dispatch with a literal name: `send`,
`public_send`, `__send__`, `method` or `respond_to?`.

### Helper methods

A `def` written at an example group's level becomes an instance method on the
group's example class, so it is checked with the same rules — flagged when
nothing references its name, used when a `let`, hook, example, or another method
calls it:

```ruby
# bad
RSpec.describe Foo do
  def unused # never referenced
    1
  end

  it { expect(true).to be(true) }
end

# good
RSpec.describe Foo do
  def used
    1
  end

  it { expect(used).to eq(1) }
end
```

## How it handles `shared_examples`

Because RuboCop analyzes one file at a time, a `let` can be consumed by a shared
example block defined in another file. An inclusion is **in reach** when the cop
can resolve it: the name is a literal, RSpec's scoping makes a definition of it
visible at that point, and the same holds for whatever that block includes in
turn. The cop is precise for those and conservative for the rest:

- `let` definitions **inside** a `shared_examples` / `shared_context` block —
  including any nested `context`/`describe` within it — are never flagged, since
  the groups that include the block (possibly in other files) may reference them.
- When the included block is in reach, only the `let`s it actually references
  are treated as used; every other `let` stays checked.
- When it is not in reach, the cop cannot tell what it references, so it leaves
  every `let` **visible at that inclusion point** alone. Sibling subtrees
  without such an inclusion are still checked. A top-level block defined in
  another file is in reach when that file is listed in `SharedExamplePaths`.
- Whether a `let` in the **including** group with the *same name* as one in the
  shared block is checked depends on the inclusion: an inline one
  (`include_examples` / `include_context`) makes it the override, so it counts
  as used when the block references the name; a nested one (`it_behaves_like` /
  `it_should_behave_like`) does not. The match is approximate; see Known
  limitations.

```ruby
RSpec.shared_examples "uses a" do
  it { expect(a).to eq(1) }  # references `a`, and only `a`
end

RSpec.describe Foo do
  let(:a) { 1 }              # skipped: referenced by the shared block above
  let(:b) { 2 }              # flagged: the shared block never references it

  it_behaves_like "uses a"
end
```

For an inclusion the cop cannot resolve, it falls back to silencing every
visible `let`:

```ruby
RSpec.describe Foo do
  let(:a) { 1 }              # skipped: visible at the inclusion below

  context "with shared" do
    let(:b) { 2 }            # skipped: same
    it_behaves_like "an external thing"   # in a file outside SharedExamplePaths
  end

  context "other" do
    let(:c) { 3 }            # checked: the shared block cannot see `c`
    it { expect(c).to eq(3) }
  end
end
```

An inline inclusion lets the including group override a name the shared block
uses, where a nested one does not:

```ruby
RSpec.shared_examples "uses size" do
  let(:size) { 1 }
  it { expect(size).to be_positive }
end

RSpec.describe Foo do
  include_examples "uses size"
  let(:size) { 2 }   # skipped: overrides the `size` the shared block uses
end

RSpec.describe Bar do
  it_behaves_like "uses size"
  let(:size) { 2 }   # flagged: the nested group uses its own `size`
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

  # Whether to check helper specs. Off by default. A helper spec (rspec-rails
  # `type: :helper`, or a spec file under `spec/helpers`) auto-includes the
  # described module into the example group, so its externally defined methods
  # may reference any `let` in scope — invisibly to single-file analysis. Set
  # this to `true` to check them anyway, accepting the risk of false positives.
  CheckHelperSpecs: false

  # Files defining shared examples/contexts, as paths or globs. Pre-loading them
  # lets the cop resolve inclusions of blocks defined there precisely instead of
  # silencing every visible `let`. Relative patterns resolve against the
  # `.rubocop.yml` in effect, as `Include` and `Exclude` do. Setting this key
  # replaces the default rather than adding to it, so keep the default glob
  # below if you still want those files.
  SharedExamplePaths:
    - "spec/support/**/*.rb"
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

## Helper specs

Helper specs (rspec-rails `type: :helper` groups, or spec files under
`spec/helpers`) auto-include the described module into the example group.
Its methods live in another file and may reference any `let` in scope, so a
single-file static analysis cannot see those references. To avoid false
positives, such groups are skipped by default. Set `CheckHelperSpecs: true`
to check them anyway.

```ruby
RSpec.describe MyHelper, type: :helper do
  let(:current_user) { User.new }   # not flagged (may be used by MyHelper's methods)
  it { expect(helper.greeting).to eq("Hi") }
end
```

## Known limitations

- Analysis is limited to the file under inspection plus the top-level
  `shared_examples`/`shared_context` blocks of the files listed in
  `SharedExamplePaths`. A `let` reached only from outside that range (a module
  mixed into the example group) or through a name that is not statically known
  (`send(attribute)`) can be a false positive. The cases the sections above
  cover are deliberately left unflagged instead.
- The override an inline inclusion allows is matched approximately: it can flag
  a `let` the shared block does use through a further inclusion of its own, and
  leave one alone that RSpec would in fact render dead — a `let` written before
  the inclusion, say.

## Comparison with rspectre

[rspectre](https://github.com/dgollahon/rspectre) also detects unused RSpec code,
but it is a dynamic tool: it runs your test suite and observes usage at runtime.
This gem instead performs **static analysis on a single file at a time (a RuboCop
cop)**, so it is **lightweight and fast** — it never runs your tests — and drops
straight into your existing RuboCop workflow.

For unused `let` detection specifically, the two reach roughly the same
precision. Being static, however, it is weaker than rspectre in a few cases:

- `let`s **inside** a `shared_examples` / `shared_context` block are left
  unchecked — an including group may reference them, so they are conservatively
  skipped.
- Unused shared example/context definitions themselves are not detected at all.
- A `let` reached only through a dynamic reference such as `send(name)`, or
  through a module mixed into the group, is invisible statically, so it can be
  reported as a false positive.

Those are exactly the cases runtime observation handles well, so rspectre is
stronger there. Conversely, rspectre has to run the whole suite or it may report
a shared example as unused when it is not, whereas this gem's results never
depend on which tests you run.

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
