# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe Archetypes do
    it "ships the eight MS08 archetypes and the leverage points L1-L10" do
      expect(described_class.all.map { |a| a[:code] }).to eq(%w(FL1 FL2 FL3 FL4 FL5 FL6 FL7 FL8))
      expect(described_class.leverage_points.map { |p| p[:code] }).to eq((1..10).map { |i| "L#{i}" })
    end

    it "links only the archetype's own variables, and refers only to known leverage points" do
      codes = described_class.leverage_points.pluck(:code)
      described_class.all.each do |archetype|
        expect(archetype[:links]).to all(satisfy { |l| archetype[:nodes].include?(l[:from]) && archetype[:nodes].include?(l[:to]) })
        expect(archetype[:ms08_leverage_points] - codes).to be_empty
        expect(archetype[:recognise]).to be_present
        expect(archetype[:leverage]).to be_present
      end
    end

    it "finds each archetype's own loops, with delays on the links that have them" do
      fixes = described_class.find(:fl3)

      expect(fixes[:loops].map { |l| [l[:name], l[:nodes]] }).to contain_exactly(
        ["B1", ["Problem symptom", "Fix"]],
        ["R1", ["Problem symptom", "Fix", "Unintended consequence"]]
      )
      expect(fixes[:links].select { |l| l[:delay] }.map { |l| [l[:from], l[:to]] }).to eq([["Fix", "Unintended consequence"]])
    end

    it "gives every archetype at least one feedback loop" do
      expect(described_class.all).to all(satisfy { |a| a[:loops].any? })
    end
  end
end
