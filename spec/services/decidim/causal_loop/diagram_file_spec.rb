# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe DiagramFile do
    let(:component) { create(:causal_loop_component) }
    let(:other_component) { create(:causal_loop_component, participatory_space: component.participatory_space) }
    let(:nodes) { Node.where(decidim_component_id: other_component.id).order(:id) }
    let(:links) { Link.where(decidim_component_id: other_component.id).order(:id) }

    def node(title, pos_x, pos_y, **attrs)
      Node.create!(title:, position_x: pos_x, position_y: pos_y, decidim_component_id: component.id, **attrs)
    end

    # What a file looks like after a download and an upload.
    def as_file(data) = JSON.parse(data.to_json)

    it "loads back exactly what it saved" do
      fishing = node("Fishing", 10.5, 20, description: "Boats", width: 160, height: 60, font_size: 17)
      income = node("Island Income", 300, -40)
      Link.create!(source_node_id: fishing.id, target_node_id: income.id, polarity: "negative", label: "less",
                   cp1_distance: 12.5, cp2_distance: -8, decidim_component_id: component.id)
      file = as_file(described_class.dump(Node.where(decidim_component_id: component.id), Link.where(decidim_component_id: component.id)))

      described_class.new(file).import!(other_component.id, replace: true)

      expect(nodes.map { |n| n.editor_json.except(:id) }).to eq([
                                                                  { title: "Fishing", description: "Boats", position_x: 10.5, position_y: 20.0, width: 160, height: 60, font_size: 17 },
                                                                  { title: "Island Income", description: nil, position_x: 300.0, position_y: -40.0, width: 130, height: 44, font_size: 13 }
                                                                ])
      expect(links.map { |l| l.editor_json.except(:id) }).to eq([
                                                                  { source_node_id: nodes.first.id, target_node_id: nodes.last.id, polarity: "negative",
                                                                    label: "less", cp1_distance: 12.5, cp2_distance: -8.0 }
                                                                ])
    end

    it "reads the older Export JSON files" do
      file = { "nodes" => [{ "id" => 7, "title" => "Tourists", "x" => 100, "y" => 50 }, { "id" => 9, "title" => "Crowding", "x" => 300, "y" => 50 }],
               "links" => [{ "id" => 3, "source" => "7", "target" => "9", "polarity" => "positive" }] }

      described_class.new(file).import!(other_component.id, replace: true)

      expect(nodes.pluck(:title, :position_x)).to eq([["Tourists", 100.0], ["Crowding", 300.0]])
      expect(links.pluck(:source_node_id, :target_node_id)).to eq([nodes.pluck(:id)])
    end

    it "replaces the diagram, keeping the old one restorable" do
      old = Node.create!(title: "Old", decidim_component_id: other_component.id)
      result = described_class.new({ "nodes" => [{ "id" => 1, "title" => "New" }] }).import!(other_component.id, replace: true)

      expect(nodes.pluck(:title)).to eq(["New"])
      expect(result[:deleted_nodes]).to eq([old])
      expect(Node.only_deleted.pluck(:id)).to eq([old.id])
    end

    it "adds to the diagram to the right of it" do
      Node.create!(title: "Old", position_x: 500, position_y: 80, decidim_component_id: other_component.id)
      file = { "nodes" => [{ "id" => 1, "title" => "A", "position_x" => 0, "position_y" => 0 },
                           { "id" => 2, "title" => "B", "position_x" => 100, "position_y" => 40 }] }
      described_class.new(file).import!(other_component.id, replace: false)

      expect(nodes.pluck(:title, :position_x, :position_y)).to eq([["Old", 500.0, 80.0], ["A", 750.0, 80.0], ["B", 850.0, 120.0]])
    end

    describe "adding a file whose variables are already in the diagram" do
      let!(:tourists) { Node.create!(title: "Tourists", position_x: 500, position_y: 80, decidim_component_id: other_component.id) }
      let!(:crowding) { Node.create!(title: "Crowding", position_x: 700, position_y: 80, decidim_component_id: other_component.id) }
      let(:file) do
        { "nodes" => [{ "id" => 1, "title" => "tourists!", "position_x" => 0, "position_y" => 0 },
                      { "id" => 2, "title" => "Crowding", "position_x" => 0, "position_y" => 50 },
                      { "id" => 3, "title" => "Income", "position_x" => 100, "position_y" => 40 }],
          "links" => [{ "source" => 1, "target" => 2, "polarity" => "positive" },
                      { "source" => 1, "target" => 3, "polarity" => "positive" },
                      { "source" => 3, "target" => 2, "polarity" => "negative" }] }
      end

      before do
        Link.create!(source_node_id: tourists.id, target_node_id: crowding.id, polarity: "negative", decidim_component_id: other_component.id)
      end

      it "uses those variables and their links instead of making copies" do
        result = described_class.new(file).import!(other_component.id, replace: false)
        income = nodes.find_by(title: "Income")

        expect(nodes.pluck(:title, :position_x, :position_y))
          .to eq([["Tourists", 500.0, 80.0], ["Crowding", 700.0, 80.0], ["Income", 950.0, 80.0]])
        expect(links.pluck(:source_node_id, :target_node_id, :polarity))
          .to eq([[tourists.id, crowding.id, "negative"], [tourists.id, income.id, "positive"], [income.id, crowding.id, "negative"]])
        expect(result).to include(nodes: [income], merged: [tourists, crowding],
                                  conflicts: ["Tourists → Crowding: kept −, the file has +"])
      end
    end

    it "skips links to variables that are not in the file" do
      file = { "nodes" => [{ "id" => 1, "title" => "A" }], "links" => [{ "source" => 1, "target" => 2 }] }
      result = described_class.new(file).import!(other_component.id, replace: true)

      expect(result[:skipped].size).to eq(1)
      expect(links).to be_empty
    end

    it "rejects files it cannot load, and changes nothing" do
      Node.create!(title: "Old", decidim_component_id: other_component.id)

      expect { described_class.new({ "title" => "x" }) }.to raise_error(DiagramFile::Error, /not a diagram/)
      expect { described_class.new({ "format" => DiagramFile::FORMAT, "version" => 2, "nodes" => [] }) }.to raise_error(DiagramFile::Error, /newer/)
      bad = { "nodes" => [{ "id" => 1, "title" => "A" }, { "id" => 2, "title" => "" }] }
      expect { described_class.new(bad).import!(other_component.id, replace: true) }.to raise_error(DiagramFile::Error, /Title/)
      expect(nodes.pluck(:title)).to eq(["Old"])
    end
  end
end
