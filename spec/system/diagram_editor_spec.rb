# frozen_string_literal: true

require "spec_helper"

describe "Diagram editor" do # rubocop:disable RSpec/DescribeClass -- a system spec of the whole editor page
  let(:organization) { create(:organization) }
  let(:participatory_space) { create(:participatory_process, :with_steps, organization:) }
  let(:component) { create(:causal_loop_component, :published, participatory_space:) }
  let(:user) { create(:user, :confirmed, organization:) }
  let(:diagram_path) { Decidim::EngineRouter.main_proxy(component).root_path }
  let(:nodes) { Decidim::CausalLoop::Node.where(decidim_component_id: component.id) }
  let(:links) { Decidim::CausalLoop::Link.where(decidim_component_id: component.id) }

  # An agent that makes the given tool calls, as a model would, then replies.
  let(:fake_agent_class) do
    Class.new do
      def initialize(calls, reply)
        @calls = calls
        @reply = reply
      end

      def name = "fake"

      def run(**)
        @calls.each { |name, input| yield name, input }
        @reply
      end
    end
  end

  def node(title, pos_x, pos_y)
    Decidim::CausalLoop::Node.create!(title:, position_x: pos_x, position_y: pos_y, decidim_component_id: component.id)
  end

  def link(source, target, polarity = "positive")
    Decidim::CausalLoop::Link.create!(source_node_id: source.id, target_node_id: target.id, polarity:,
                                      decidim_component_id: component.id)
  end

  def open_editor
    visit diagram_path
    expect(page).to have_css("#cy canvas")
  end

  # Runs JavaScript with the editor's Stimulus controller as `c`.
  def editor_script(code)
    page.evaluate_script(<<~JS)
      (function(c) { #{code} })(window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("[data-controller=causal-loop-editor]"), "causal-loop-editor"))
    JS
  end

  # Canvas coordinates, relative to the top-left corner of #cy.
  def rendered_position(selector)
    editor_script("const p = c.cy.$('#{selector}').renderedPosition(); return [p.x, p.y];")
  end

  def edge_midpoint(link)
    editor_script("const p = c.cy.$('#l#{link.id}').renderedMidpoint(); return [p.x, p.y];")
  end

  def canvas_offset(pos_x, pos_y)
    return { x: pos_x, y: pos_y } unless Capybara.w3c_click_offset

    width, height = page.evaluate_script("(() => { const r = document.querySelector('#cy').getBoundingClientRect(); return [r.width, r.height]; })()")
    { x: pos_x - (width / 2), y: pos_y - (height / 2) }
  end

  def click_canvas(pos_x, pos_y) = find_by_id("cy").click(**canvas_offset(pos_x, pos_y))

  def double_click_canvas(pos_x, pos_y) = find_by_id("cy").double_click(**canvas_offset(pos_x, pos_y))

  # The editor saves in the background; wait until the database agrees.
  def eventually(timeout: Capybara.default_max_wait_time)
    deadline = Time.current + timeout
    loop do
      return if yield
      raise "condition not met within #{timeout}s" if Time.current > deadline

      sleep 0.1
    end
  end

  before { switch_to_host(organization.host) }

  context "without edit access" do
    before do
      node("Tourists", 100, 100)
      login_as user, scope: :user
      open_editor
    end

    it "shows the diagram read-only" do
      expect(page).to have_content("You do not have edit access to this diagram")
      expect(page).to have_no_button("+ Add node")
      expect(page).to have_no_button("AI Assistant")
      expect(page).to have_button("Export JSON")
    end
  end

  context "with edit access" do
    before do
      Decidim::CausalLoop::Editor.create!(decidim_component_id: component.id, decidim_user_id: user.id)
      login_as user, scope: :user
    end

    it "adds a node from the toolbar and names it" do
      open_editor
      click_on "+ Add node"
      find("#cy input[type=text]").set("Tourists").send_keys(:enter)

      eventually { nodes.pluck(:title) == ["Tourists"] }
      expect(editor_script("return c.cy.nodes().map(n => n.data('label'));")).to eq(["Tourists"])
    end

    it "renames a node by double-clicking it" do
      tourists = node("Tourists", 300, 200)
      open_editor
      double_click_canvas(*rendered_position("#n#{tourists.id}"))
      find("#cy input[type=text]").set("Visitors").send_keys(:enter)

      eventually { tourists.reload.title == "Visitors" }
      expect(page).to have_no_css("#cy input")
    end

    it "deletes the selected node and its links" do
      tourists = node("Tourists", 100, 100)
      income = node("Island Income", 400, 100)
      link(tourists, income)
      open_editor
      editor_script("c.cy.$('#n#{tourists.id}').select();")
      click_on "Delete selected"

      eventually { nodes.pluck(:title) == ["Island Income"] && links.none? }
      expect(editor_script("return c.cy.nodes().map(n => n.data('label'));")).to eq(["Island Income"])
    end

    it "flips a link's sign on click, and offers to undo it" do
      crowding = node("Crowding", 100, 200)
      attractiveness = node("Attractiveness", 500, 200)
      crowding_link = link(crowding, attractiveness)
      open_editor
      click_canvas(*edge_midpoint(crowding_link))

      expect(page).to have_css(".cl-toast", text: "Crowding → Attractiveness is now −")
      eventually { crowding_link.reload.polarity == "negative" }

      within(".cl-toast") { click_on "Undo" }
      expect(page).to have_no_css(".cl-toast")
      eventually { crowding_link.reload.polarity == "positive" }
    end

    it "arranges the diagram without overlaps and saves it" do
      titles = %w(Tourists Income Infrastructure Crowding Attractiveness Pollution)
      created = titles.map { |t| node(t, 200, 200) }
      created.each_cons(2) { |a, b| link(a, b) }
      open_editor
      click_on "Auto-layout"

      expect(page).to have_content("Layout saved")
      boxes = nodes.map { |n| [n.position_x, n.position_y] }
      boxes.combination(2).each do |(ax, ay), (bx, by)|
        expect((ax - bx).abs >= 130 || (ay - by).abs >= 44).to be(true)
      end
    end

    it "lists the loops and highlights the one selected" do
      tourists = node("Tourists", 100, 100)
      income = node("Island Income", 300, 100)
      crowding = node("Crowding", 100, 300)
      link(tourists, income)
      link(income, tourists)
      link(tourists, crowding)
      link(crowding, tourists, "negative")
      open_editor
      click_on "Loops"

      within(".cl-loops") do
        expect(page).to have_content("Loops: 1 reinforcing, 1 balancing")
        expect(page).to have_content("Tourists → Island Income → Tourists")
        click_on "B1"
      end

      expect(editor_script("return c.cy.$('.cl-in-loop').map(e => e.id()).sort();"))
        .to match_array(["n#{tourists.id}", "n#{crowding.id}"] + links.where(source_node_id: [tourists.id, crowding.id],
                                                                             target_node_id: [tourists.id, crowding.id]).map { |l| "l#{l.id}" })
      expect(editor_script("return c.cy.$('#n#{income.id}').hasClass('cl-dim');")).to be(true)
    end

    it "wraps long titles onto several lines" do
      node("GovernmentRegulation", 200, 200)
      open_editor

      expect(editor_script("return c.cy.nodes()[0].data('displayLabel');")).to eq("Government\nRegulation")
    end

    it "keeps a node stored at x = 0 there" do
      node("Tourists", 0, 0)
      open_editor

      expect(editor_script("const p = c.cy.nodes()[0].position(); return [p.x, p.y];")).to eq([0, 0])
    end

    it "hides the empty-diagram hint once there are nodes" do
      open_editor
      expect(page).to have_content("No nodes yet")

      click_on "+ Add node"
      expect(page).to have_no_content("No nodes yet")
    end

    it "opens in full view, which can be left" do
      open_editor
      expect(page).to have_css("html.cl-full-view")

      click_on "Exit full view"
      expect(page).to have_no_css("html.cl-full-view")
      visit diagram_path
      expect(page).to have_button("Full view")
    end

    describe "undo and redo" do
      let(:all_nodes) { Decidim::CausalLoop::Node.with_deleted.where(decidim_component_id: component.id) }

      def canvas_labels = editor_script("return c.cy.nodes().map(n => n.data('label')).sort();")

      it "undoes and redoes adding and naming a node as one step" do
        open_editor
        click_on "+ Add node"
        find("#cy input[type=text]").set("Tourists").send_keys(:enter)
        eventually { nodes.pluck(:title) == ["Tourists"] }
        id = nodes.first.id

        click_on "Undo"
        eventually { nodes.none? }
        expect(canvas_labels).to eq([])

        click_on "Redo"
        eventually { nodes.pluck(:id, :title) == [[id, "Tourists"]] }
        expect(canvas_labels).to eq(["Tourists"])
      end

      it "brings back a deleted node with its links, and the same IDs" do
        tourists = node("Tourists", 100, 100)
        income = node("Island Income", 400, 100)
        tourists_income = link(tourists, income)
        open_editor
        editor_script("c.cy.$('#n#{tourists.id}').select();")
        click_on "Delete selected"
        eventually { nodes.pluck(:title) == ["Island Income"] && links.none? }

        click_on "Undo"
        eventually { nodes.count == 2 && links.pluck(:id) == [tourists_income.id] }
        expect(editor_script("return c.cy.$('#l#{tourists_income.id}').length;")).to eq(1)
        expect(page).to have_button("Redo", disabled: false)
      end

      it "undoes a drag of several nodes with the keyboard" do
        tourists = node("Tourists", 100, 100)
        income = node("Island Income", 400, 100)
        open_editor
        editor_script(<<~JS)
          const nodes = c.cy.nodes();
          nodes.forEach(n => n.emit("grab"));
          nodes.forEach(n => n.position({ x: n.position("x") + 50, y: 300 }));
          nodes.forEach(n => n.emit("free"));
        JS
        eventually { tourists.reload.position_y == 300 && income.reload.position_y == 300 }
        expect(page).to have_css("#btn-undo[title^='Undo move 2 nodes']")

        find("body").send_keys([:control, "z"])
        eventually { tourists.reload.position_x == 100 && income.reload.position_y == 100 }
        expect(editor_script("return c.cy.$('#n#{tourists.id}').position('y');")).to eq(100)
      end

      it "undoes an auto-layout in one step" do
        created = %w(Tourists Income Crowding).map.with_index { |t, i| node(t, 100 * i, 50) }
        created.each_cons(2) { |a, b| link(a, b) }
        open_editor
        click_on "Auto-layout"
        expect(page).to have_content("Layout saved")

        click_on "Undo"
        eventually { nodes.order(:id).pluck(:position_x, :position_y) == [[0, 50], [100, 50], [200, 50]] }
      end

      it "reports an undo that the server refuses, and drops it" do
        tourists = node("Tourists", 100, 100)
        open_editor
        editor_script("c.cy.$('#n#{tourists.id}').select();")
        click_on "Delete selected"
        eventually { nodes.none? }
        all_nodes.delete_all

        click_on "Undo"
        expect(page).to have_css(".cl-toast", text: "Could not undo delete “Tourists”")
        expect(page).to have_button("Undo", disabled: true)
      end
    end

    describe "the AI assistant" do
      let(:reply) { "Built a new diagram." }
      let(:tool_calls) { [] }
      let(:existing_nodes) { [] }

      before do
        existing_nodes
        allow_any_instance_of(Decidim::CausalLoop::ConversationsController) # rubocop:disable RSpec/AnyInstance
          .to receive(:build_agent).and_return(fake_agent_class.new(tool_calls, reply))
        open_editor
        click_on "AI Assistant"
      end

      def canvas_labels = editor_script("return c.cy.nodes().map(n => n.data('label')).sort();")

      def ask(message)
        find_by_id("cl-chat-input").set(message)
        click_on "Send"
        expect(page).to have_css(".cl-msg--assistant", text: reply)
      end

      it "opens beside the canvas, and can move below it" do
        expect(page).to have_css(".cl-workspace--right.is-chat-open")
        click_on "Move below"
        expect(page).to have_css(".cl-workspace--below")

        visit diagram_path
        click_on "AI Assistant"
        expect(page).to have_css(".cl-workspace--below.is-chat-open")
      end

      it "keeps the conversation across reloads until it is cleared" do
        ask("Hello")
        visit diagram_path
        click_on "AI Assistant"
        expect(page).to have_css(".cl-msg--user", text: "Hello")

        click_on "Clear chat"
        expect(page).to have_no_css(".cl-msg--user")
        visit diagram_path
        click_on "AI Assistant"
        expect(page).to have_no_css(".cl-msg--user")
      end

      context "when it replaces the diagram" do
        let(:existing_nodes) { [node("Old idea", 100, 100)] }
        let(:tool_calls) do
          [
            ["clear_diagram", {}],
            ["create_nodes", { "titles" => %w(Tourists Crowding) }],
            ["create_links", { "links" => [{ "source" => "Tourists", "target" => "Crowding", "polarity" => "positive" }] }]
          ]
        end

        it "deletes the old diagram once the user confirms" do
          ask("Start a new diagram")
          within("#cl-confirm") do
            expect(page).to have_content("Delete the 1 earlier variables")
            click_on "Delete them"
          end

          eventually { nodes.pluck(:title).sort == %w(Crowding Tourists) }
          expect(links.count).to eq(1)
          expect(editor_script("return c.cy.nodes().map(n => n.data('label')).sort();")).to eq(%w(Crowding Tourists))
        end

        it "undoes the reply and the deletion separately" do
          ask("Start a new diagram")
          within("#cl-confirm") { click_on "Delete them" }
          eventually { nodes.pluck(:title).sort == %w(Crowding Tourists) }

          click_on "Undo"
          eventually { nodes.pluck(:title).sort == ["Crowding", "Old idea", "Tourists"] }
          expect(page).to have_css("#btn-undo[title^='Undo AI: “Start a new diagram”']")
          click_on "Undo"
          eventually { nodes.pluck(:title) == ["Old idea"] && links.none? }
          expect(canvas_labels).to eq(["Old idea"])
        end

        it "keeps the old diagram if the user declines" do
          ask("Start a new diagram")
          within("#cl-confirm") { click_on "Keep them" }

          expect(page).to have_content("Kept the previous diagram")
          expect(nodes.pluck(:title)).to contain_exactly("Old idea", "Tourists", "Crowding")
        end
      end
    end
  end
end
