require 'helper'

RSpec.describe Delayed::Priority do
  let(:custom_names) { nil }

  around do |example|
    described_class.names = custom_names
    example.run
  ensure
    described_class.names = nil
  end

  describe '.names, .ranges, method_missing' do
    it 'defaults to interactive, user_visible, eventual, reporting' do
      expect(described_class.names).to eq(
        interactive: 0,
        user_visible: 10,
        eventual: 20,
        reporting: 30,
      )
      expect(described_class.ranges).to eq(
        interactive: (0...10),
        user_visible: (10...20),
        eventual: (20...30),
        reporting: (30...Float::INFINITY),
      )
      expect(described_class).to respond_to(:interactive)
      expect(described_class).to respond_to(:user_visible)
      expect(described_class).to respond_to(:eventual)
      expect(described_class).to respond_to(:reporting)
      expect(described_class.interactive).to eq 0
      expect(described_class.user_visible).to eq 10
      expect(described_class.eventual).to eq 20
      expect(described_class.reporting).to eq 30
    end

    context 'when customized to high, medium, low' do
      let(:custom_names) { { high: 0, medium: 100, low: 500 } }

      it 'returns the customized value' do
        expect(described_class.names).to eq(
          high: 0,
          medium: 100,
          low: 500,
        )
        expect(described_class.ranges).to eq(
          high: (0...100),
          medium: (100...500),
          low: (500...Float::INFINITY),
        )
        expect(described_class).not_to respond_to(:interactive)
        expect(described_class).not_to respond_to(:user_visible)
        expect(described_class).not_to respond_to(:eventual)
        expect(described_class).not_to respond_to(:reporting)
        expect(described_class).to respond_to(:high)
        expect(described_class).to respond_to(:medium)
        expect(described_class).to respond_to(:low)
        expect(described_class.high).to eq 0
        expect(described_class.medium).to eq 100
        expect(described_class.low).to eq 500
      end
    end
  end

  it 'provides the name of the priority range' do
    expect(described_class.new(0).name).to eq :interactive
    expect(described_class.new(3).name).to eq :interactive
    expect(described_class.new(10).name).to eq :user_visible
    expect(described_class.new(29).name).to eq :eventual
    expect(described_class.new(999).name).to eq :reporting
    expect(described_class.new(-123).name).to eq nil
  end

  it 'supports initialization by symbol value' do
    expect(described_class.new(:interactive)).to eq(0)
    expect(described_class.new(:user_visible)).to eq(10)
    expect(described_class.new(:eventual)).to eq(20)
    expect(described_class.new(:reporting)).to eq(30)
  end

  it "supports predicate ('?') methods" do
    expect(described_class.new(0).interactive?).to eq true
    expect(described_class.new(3)).to be_interactive
    expect(described_class.new(3).user_visible?).to eq false
    expect(described_class.new(10)).to be_user_visible
    expect(described_class.new(29)).to be_eventual
    expect(described_class.new(999)).to be_reporting
    expect(described_class.new(-123).interactive?).to eq false
  end

  it 'supports comparisons' do
    expect(described_class.new(3)).to be < described_class.new(5)
    expect(described_class.new(10)).to be >= described_class.new(10)
    expect(described_class.new(101)).to eq described_class.new(101)
  end

  it 'suports coercion' do
    expect(described_class.new(0)).to eq 0
    expect(described_class.new(8)).to be > 5
    expect(described_class.new(5)).to be < 8
    expect(0 == described_class.new(0)).to eq true
    expect(8 > described_class.new(5)).to eq true
    expect(5 < described_class.new(8)).to eq true
  end

  it 'supports sorting' do
    expect(
      [
        described_class.new(5),
        described_class.new(40),
        described_class.new(3),
        described_class.new(-13),
      ].sort,
    ).to eq [-13, 3, 5, 40]
  end
end
