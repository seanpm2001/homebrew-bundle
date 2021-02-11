# frozen_string_literal: true

require "spec_helper"
require "tsort"
require "formula"
require "tab"

describe Bundle::BrewDumper do
  subject(:dumper) { described_class }

  let(:foo) do
    instance_double("Formula",
                    name:                 "foo",
                    desc:                 "foobar",
                    oldname:              "oldfoo",
                    full_name:            "qux/quuz/foo",
                    aliases:              ["foobar"],
                    runtime_dependencies: [],
                    deps:                 [],
                    conflicts:            [],
                    any_installed_prefix: nil,
                    linked?:              false,
                    keg_only?:            true,
                    pinned?:              false,
                    outdated?:            false,
                    bottle_defined?:      false)
  end
  let(:foo_hash) do
    {
      aliases:                  ["foobar"],
      args:                     [],
      bottle:                   false,
      build_dependencies:       [],
      conflicts_with:           [],
      dependencies:             [],
      desc:                     "foobar",
      full_name:                "qux/quuz/foo",
      installed_as_dependency?: false,
      installed_on_request?:    false,
      link?:                    nil,
      name:                     "foo",
      oldname:                  "oldfoo",
      outdated?:                false,
      pinned?:                  false,
      poured_from_bottle?:      false,
      version:                  nil,
    }
  end
  let(:bar) do
    linked_keg = Pathname("/usr/local").join("var").join("homebrew").join("linked").join("bar")
    instance_double("Formula",
                    name:                 "bar",
                    desc:                 "barfoo",
                    oldname:              nil,
                    full_name:            "bar",
                    aliases:              [],
                    runtime_dependencies: [],
                    deps:                 [],
                    conflicts:            [],
                    any_installed_prefix: nil,
                    linked?:              true,
                    keg_only?:            false,
                    pinned?:              true,
                    outdated?:            true,
                    bottle_defined?:      true,
                    linked_keg:           linked_keg,
                    bottle_hash:          {
                      cellar: ":any",
                      files:  {
                        big_sur: {
                          sha256: "abcdef",
                          url:    "https://brew.sh//foo-1.0.big_sur.bottle.tar.gz",
                        },
                      },
                    })
  end
  let(:bar_hash) do
    {
      aliases:                  [],
      args:                     [],
      bottle:                   {
        cellar: ":any",
        files:  {
          big_sur: {
            sha256: "abcdef",
            url:    "https://brew.sh//foo-1.0.big_sur.bottle.tar.gz",
          },
        },
      },
      build_dependencies:       [],
      conflicts_with:           [],
      dependencies:             [],
      desc:                     "barfoo",
      full_name:                "bar",
      installed_as_dependency?: false,
      installed_on_request?:    false,
      link?:                    nil,
      name:                     "bar",
      oldname:                  nil,
      outdated?:                true,
      pinned?:                  true,
      poured_from_bottle?:      true,
      version:                  "1.0",
    }
  end
  let(:baz) do
    instance_double("Formula",
                    name:                 "baz",
                    desc:                 "",
                    oldname:              nil,
                    full_name:            "bazzles/bizzles/baz",
                    aliases:              [],
                    runtime_dependencies: [OpenStruct.new(name: "bar")],
                    deps:                 [OpenStruct.new(name: "bar", build?: true)],
                    conflicts:            [],
                    any_installed_prefix: nil,
                    linked?:              false,
                    keg_only?:            false,
                    pinned?:              false,
                    outdated?:            false,
                    bottle_defined?:      false)
  end
  let(:baz_hash) do
    {
      aliases:                  [],
      args:                     [],
      bottle:                   false,
      build_dependencies:       ["bar"],
      conflicts_with:           [],
      dependencies:             ["bar"],
      desc:                     "",
      full_name:                "bazzles/bizzles/baz",
      installed_as_dependency?: false,
      installed_on_request?:    false,
      link?:                    false,
      name:                     "baz",
      oldname:                  nil,
      outdated?:                false,
      pinned?:                  false,
      poured_from_bottle?:      false,
      version:                  nil,
    }
  end

  before do
    described_class.reset!
  end

  describe "#formulae" do
    it "returns an empty array when no formulae are installed" do
      expect(dumper.formulae).to be_empty
    end
  end

  describe "#formulae_by_full_name" do
    it "returns an empty hash when no formulae are installed" do
      expect(dumper.formulae_by_full_name).to eql({})
    end

    it "returns an empty hash for an unavailable formula" do
      expect(Formula).to receive(:[]).with("bar").and_raise(FormulaUnavailableError)
      expect(dumper.formulae_by_full_name("bar")).to eql({})
    end

    it "exits on cyclic exceptions" do
      expect(Formula).to receive(:installed).and_return([foo, bar, baz])
      expect_any_instance_of(Bundle::BrewDumper::Topo).to receive(:tsort).and_raise(
        TSort::Cyclic,
        'topological sort failed: ["foo", "bar"]',
      )
      expect { dumper.formulae_by_full_name }.to raise_error(SystemExit)
    end

    it "returns a hash for a formula" do
      expect(Formula).to receive(:[]).with("qux/quuz/foo").and_return(foo)
      expect(dumper.formulae_by_full_name("qux/quuz/foo")).to eql(foo_hash)
    end

    it "returns an array for all formulae" do
      expect(Formula).to receive(:installed).and_return([foo, bar, baz])
      expect(bar.linked_keg).to receive(:realpath).and_return(OpenStruct.new(basename: "1.0"))
      expect(Tab).to receive(:for_keg).with(bar.linked_keg).and_return \
        instance_double("Tab",
                        installed_as_dependency: false,
                        installed_on_request:    false,
                        poured_from_bottle:      true,
                        runtime_dependencies:    [],
                        used_options:            [])
      expect(dumper.formulae_by_full_name).to eql({
                                                    "bar"                 => bar_hash,
                                                    "qux/quuz/foo"        => foo_hash,
                                                    "bazzles/bizzles/baz" => baz_hash,
                                                  })
    end
  end

  describe "#formulae_by_name" do
    it "returns a hash for a formula" do
      expect(Formula).to receive(:[]).with("foo").and_return(foo)
      expect(dumper.formulae_by_name("foo")).to eql(foo_hash)
    end
  end

  describe "#dump" do
    it "returns a dump string with installed formulae" do
      expect(Formula).to receive(:installed).and_return([foo, bar, baz])
      expected = <<~EOS
        # barfoo
        brew "bar"
        brew "bazzles/bizzles/baz", link: false
        # foobar
        brew "qux/quuz/foo"
      EOS
      expect(dumper.dump(describe: true)).to eql(expected.chomp)
    end
  end

  describe "#formula_aliases" do
    it "returns an empty string when no formulae are installed" do
      expect(dumper.formula_aliases).to eql({})
    end

    it "returns a hash with installed formulae aliases" do
      expect(Formula).to receive(:installed).and_return([foo, bar, baz])
      expect(dumper.formula_aliases).to eql({
                                              "qux/quuz/foobar" => "qux/quuz/foo",
                                              "foobar"          => "qux/quuz/foo",
                                            })
    end
  end

  describe "#formula_oldnames" do
    it "returns an empty string when no formulae are installed" do
      expect(dumper.formula_oldnames).to eql({})
    end

    it "returns a hash with installed formulae old names" do
      expect(Formula).to receive(:installed).and_return([foo, bar, baz])
      expect(dumper.formula_oldnames).to eql({
                                               "qux/quuz/oldfoo" => "qux/quuz/foo",
                                               "oldfoo"          => "qux/quuz/foo",
                                             })
    end
  end
end
