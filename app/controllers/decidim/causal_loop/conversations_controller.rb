# frozen_string_literal: true

module Decidim
  module CausalLoop
    class ConversationsController < CausalLoop::ApplicationController
      include ActionController::Live

      before_action :authenticate_user!
      before_action :require_edit_permission!

      # The history comes from the browser, so only conversation turns are
      # accepted. A forged "system" or "tool" turn could otherwise override the
      # system prompt or fake a tool result.
      HISTORY_ROLES = %w(user assistant).freeze
      STREAM_TYPE = "application/x-ndjson"
      # How progress reports name each kind of change, as [verb, noun].
      PROGRESS_WORDS = {
        "add_node" => %w(Added variable), "update_node" => %w(Renamed variable),
        "remove_node" => %w(Deleted variable), "add_link" => %w(Added link),
        "update_link" => %w(Changed link), "remove_link" => %w(Deleted link)
      }.freeze

      def create
        message = params[:message].to_s.strip
        history = Array(params[:history]).filter_map do |m|
          role = m[:role].to_s
          { role:, content: m[:content].to_s } if HISTORY_ROLES.include?(role)
        end

        return render json: { error: "Message cannot be blank" }, status: :bad_request if message.blank?

        agent = build_agent
        unless agent
          return render json: { error: AgentProviders.unconfigured_message }, status: :service_unavailable
        end

        messages = history + [{ role: "user", content: message }]
        return stream_conversation(agent, messages) if stream_requested?

        render json: converse(agent, messages)
      rescue StandardError => e
        error, status = error_response(e)
        render json: { error: }, status:
      end

      private

      # The editor asks for a stream (Accept: application/x-ndjson), so it can
      # show what the assistant is doing and draw its changes as they happen,
      # instead of waiting up to a minute for the whole reply. Each line is
      # one JSON event: "progress" after each tool call, with the changes it
      # made, then "done" with the reply, or "error". If a proxy holds the
      # stream back, the editor gets all the lines at once and still works.
      def stream_requested?
        request.headers["Accept"].to_s.include?(STREAM_TYPE)
      end

      def stream_conversation(agent, messages)
        response.headers["Content-Type"] = STREAM_TYPE
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no" # tells nginx not to buffer
        response.headers["Last-Modified"] = Time.now.httpdate # keeps Rack::ETag from buffering
        result = converse(agent, messages) { |event| write_event(event) }
        write_event(result.merge(type: "done"))
      rescue StandardError => e
        write_event(type: "error", error: error_response(e).first)
      ensure
        response.stream.close
      end

      def write_event(event)
        response.stream.write("#{event.to_json}\n")
      end

      # Runs the agent over the diagram. With a block, reports progress after
      # every tool call.
      def converse(agent, messages)
        @nodes = Node.where(decidim_component_id: current_component.id).to_a
        @links = Link.where(decidim_component_id: current_component.id).to_a
        @actions = []
        @pending_clear_ids = []

        reply = agent.run(system: system_prompt, messages: messages, tools: tool_definitions) do |name, input|
          before = @actions.size
          result = execute_tool(name, input)
          if block_given?
            changes = @actions[before..]
            yield({ type: "progress", text: progress_text(name, changes), actions: changes })
          end
          result
        end

        { reply:, actions: @actions, provider: agent.name, history: messages + [{ role: "assistant", content: reply }] }
      end

      # What a tool call did, for the chat panel: "Added 12 variables".
      def progress_text(name, changes)
        counts = changes.map { |a| a[:type] }.tally
        done = PROGRESS_WORDS.filter_map do |type, (verb, noun)|
          "#{verb} #{counts[type]} #{noun}#{"s" unless counts[type] == 1}" if counts[type]
        end
        return done.join(", ") if done.any?

        { "list_graph" => "Read the diagram", "find_loops" => "Found the loops",
          "clear_diagram" => "Set the old diagram aside" }.fetch(name, "Worked on the diagram")
      end

      def error_response(error)
        case error
        when AgentProviders::ConfigurationError then [error.message, :service_unavailable]
        when OpenaiCompatibleAgent::Error then [error.message, :bad_gateway]
        when Anthropic::Errors::APIError then ["Anthropic API error: #{error.message}", :bad_gateway]
        else
          Rails.logger.error "ConversationsController error: #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}"
          ["Unexpected error: #{error.message}", :internal_server_error]
        end
      end

      # The agent's tools create, update and delete nodes and links, so it needs
      # the same permission as the nodes and links endpoints. The JSON key is
      # `error` (not `errors`) because that is what the chat panel displays.
      def require_edit_permission!
        return if allowed_to?(:edit, :diagram, component: current_component)

        render json: { error: "Not authorized" }, status: :forbidden
      end

      def build_agent
        AgentProviders.build
      end

      def execute_tool(name, input)
        case name
        when "list_graph"
          {
            nodes: @nodes.map { |n| { id: n.id, title: n.title, x: n.position_x.to_f.round, y: n.position_y.to_f.round } },
            links: @links.map { |l|
              src = @nodes.find { |n| n.id == l.source_node_id }&.title || l.source_node_id
              tgt = @nodes.find { |n| n.id == l.target_node_id }&.title || l.target_node_id
              { id: l.id, from: src, to: tgt, polarity: l.polarity,
                source_node_id: l.source_node_id, target_node_id: l.target_node_id }
            }
          }.to_json

        when "find_loops"
          LoopFinder.report(@nodes, @links).to_json

        when "create_node"
          title = input["title"].to_s.strip
          return "Error: title is required" if title.blank?

          find_or_add_node(title).to_json

        when "create_nodes"
          titles = Array(input["titles"]).map { |t| t.to_s.strip }.compact_blank
          return "Error: titles must be a non-empty list" if titles.empty?

          titles.map { |title| find_or_add_node(title) }.to_json

        # Deleting a whole diagram is not something to do on a model's say-so,
        # so the current nodes are only marked here. The editor asks the user
        # to confirm and then deletes them; until then they are invisible to
        # the other tools, so the model builds the new diagram from scratch.
        when "clear_diagram"
          ids = @nodes.map(&:id) - @pending_clear_ids
          return "The diagram is already empty" if ids.empty?

          @pending_clear_ids.concat(ids)
          @nodes.reject! { |n| ids.include?(n.id) }
          @links.reject! { |l| ids.include?(l.source_node_id) || ids.include?(l.target_node_id) }
          @actions << { type: "confirm_clear", node_ids: @pending_clear_ids.dup }
          "The #{ids.size} existing nodes and their links will be deleted once the user confirms. " \
            "Treat the diagram as empty and build the new one now."

        when "update_node"
          node  = find_node(input["id"])
          return "Error: node not found" unless node

          title = input["title"].to_s.strip
          return "Error: title is required" if title.blank?

          node.update!(title: title)
          @actions << { type: "update_node", id: node.id, title: node.title }
          { id: node.id, title: node.title }.to_json

        when "delete_node"
          node = find_node(input["id"])
          return "Error: node not found" unless node

          remove_node(node)
          "Deleted node #{node.id} (\"#{node.title}\")"

        when "create_link"
          source_id = input["source_node_id"].to_i
          target_id = input["target_node_id"].to_i
          polarity  = input["polarity"].to_s.in?(%w[positive negative]) ? input["polarity"] : "positive"

          return "Error: source node not found" unless @nodes.any? { |n| n.id == source_id }
          return "Error: target node not found" unless @nodes.any? { |n| n.id == target_id }

          { id: add_link(source_id, target_id, polarity).id }.to_json

        when "create_links"
          links = Array(input["links"]).select { |l| l.respond_to?(:to_h) }.map { |l| l.to_h.stringify_keys }
          return "Error: links must be a non-empty list" if links.empty?

          links.map { |l| create_link_by_reference(l) }.to_json

        when "update_link"
          link     = find_link(input["id"])
          return "Error: link not found" unless link

          polarity = input["polarity"].to_s
          return "Error: polarity must be 'positive' or 'negative'" unless polarity.in?(%w[positive negative])

          link.update!(polarity: polarity)
          @actions << { type: "update_link", id: link.id, polarity: link.polarity }
          { id: link.id, polarity: link.polarity }.to_json

        when "delete_link"
          link = find_link(input["id"])
          return "Error: link not found" unless link

          link.soft_delete!
          @links.delete_if { |l| l.id == link.id }
          @actions << { type: "remove_link", id: link.id }
          "Deleted link #{link.id}"

        else
          "Error: unknown tool '#{name}'"
        end
      rescue ActiveRecord::RecordInvalid => e
        "Error: #{e.message}"
      end

      # A causal loop diagram has one node per variable, so a title that is
      # already in use (ignoring case and spacing) returns the existing node.
      def find_or_add_node(title)
        existing = @nodes.find { |n| title_key(n.title) == title_key(title) }
        return { id: existing.id, title: existing.title, note: "already existed" } if existing

        node = add_node(title)
        { id: node.id, title: node.title }
      end

      def add_node(title)
        pos  = auto_position
        node = Node.create!(title:, position_x: pos[:x], position_y: pos[:y], decidim_component_id: current_component.id)
        @nodes << node
        @actions << { type: "add_node", id: node.id, title: node.title,
                      position_x: node.position_x, position_y: node.position_y }
        node
      end

      def remove_node(node)
        node.soft_delete!.each do |l|
          @actions << { type: "remove_link", id: l.id }
          @links.delete_if { |x| x.id == l.id }
        end
        @nodes.delete_if { |n| n.id == node.id }
        @actions << { type: "remove_node", id: node.id }
      end

      def add_link(source_id, target_id, polarity)
        link = Link.create!(source_node_id: source_id, target_node_id: target_id, polarity:,
                            decidim_component_id: current_component.id)
        @links << link
        @actions << { type: "add_link", id: link.id, source_node_id: source_id,
                      target_node_id: target_id, polarity: }
        link
      end

      # One entry of create_links. Errors are reported per link, so one bad
      # reference does not stop the rest of the batch.
      def create_link_by_reference(spec)
        source_ref = link_end(spec, "source", "from")
        target_ref = link_end(spec, "target", "to")
        source = resolve_node(source_ref)
        target = resolve_node(target_ref)
        polarity = spec["polarity"].to_s.in?(%w(positive negative)) ? spec["polarity"] : "positive"
        return { source: source_ref, error: "source node not found; give a node title or ID as \"source\"" } unless source
        return { target: target_ref, error: "target node not found; give a node title or ID as \"target\"" } unless target

        link = add_link(source.id, target.id, polarity)
        { id: link.id, from: source.title, to: target.title, polarity: }
      end

      # Models invent their own key names ("source_node_id", "source_node_title",
      # "from"), so take the documented key, its short alias, or any key that
      # starts with the documented one.
      def link_end(spec, key, short)
        spec[key] || spec[short] || spec.find { |k, _| k.start_with?(key) }&.last
      end

      # Small models lose track of IDs, so links may name nodes by title
      # instead. Titles match ignoring case, spaces and punctuation, so
      # "Island Income" finds "IslandIncome".
      def resolve_node(ref)
        return find_node(ref) if ref.is_a?(Integer) || ref.to_s.strip.match?(/\A\d+\z/)

        key = title_key(ref)
        key.present? && @nodes.find { |n| title_key(n.title) == key }
      end

      def title_key(title) = Node.title_key(title)

      def find_node(id)
        return nil if @pending_clear_ids.include?(id.to_i)

        @nodes.find { |n| n.id == id.to_i } ||
          Node.find_by(id: id.to_i, decidim_component_id: current_component.id)
      end

      def find_link(id)
        @links.find { |l| l.id == id.to_i } ||
          Link.find_by(id: id.to_i, decidim_component_id: current_component.id)
      end

      # Nodes default to 130x44 on the canvas; keep at least this far apart.
      NODE_SPACING_X = 180
      NODE_SPACING_Y = 80

      # Place a new node on rings around the diagram's centre, taking the first
      # free slot. Rings are wider than tall to match the node shape.
      def auto_position
        return { x: 300, y: 300 } if @nodes.empty?

        cx = @nodes.sum { |n| n.position_x.to_f } / @nodes.size
        cy = @nodes.sum { |n| n.position_y.to_f } / @nodes.size

        (1..10).each do |ring|
          radius = ring * NODE_SPACING_Y * 1.5
          slots  = [(2 * Math::PI * radius / NODE_SPACING_Y).floor, 8].max
          slots.times do |i|
            angle = 2 * Math::PI * i / slots
            x = cx + (Math.cos(angle) * radius * 2)
            y = cy + (Math.sin(angle) * radius)
            return { x: x.round, y: y.round } unless position_taken?(x, y)
          end
        end

        { x: (cx + rand(-250..250)).round, y: (cy + rand(-250..250)).round }
      end

      def position_taken?(pos_x, pos_y)
        @nodes.any? do |n|
          (n.position_x.to_f - pos_x).abs < NODE_SPACING_X && (n.position_y.to_f - pos_y).abs < NODE_SPACING_Y
        end
      end

      def system_prompt
        node_list = @nodes.map { |n| "  [#{n.id}] #{n.title}" }.join("\n")
        link_list = @links.map { |l|
          src = @nodes.find { |n| n.id == l.source_node_id }&.title || "node #{l.source_node_id}"
          tgt = @nodes.find { |n| n.id == l.target_node_id }&.title || "node #{l.target_node_id}"
          "  [#{l.id}] #{src} →(#{l.polarity[0]})→ #{tgt}"
        }.join("\n")

        <<~PROMPT
          You are an AI assistant helping users build causal loop diagrams — a systems thinking tool
          that maps how variables in a system influence each other.

          CURRENT DIAGRAM
          Nodes (variables):
          #{node_list.presence || "  (none yet)"}

          Links (causal arrows):
          #{link_list.presence || "  (none yet)"}

          CAUSAL LOOP CONCEPTS
          - A POSITIVE link (+): when A increases, B increases (same direction).
          - A NEGATIVE link (−): when A increases, B decreases (opposite direction).
          - A REINFORCING loop (R): even number of negative links → amplifies change (vicious/virtuous cycle).
          - A BALANCING loop (B): odd number of negative links → seeks equilibrium.
          - Good diagrams combine both R and B loops and reveal leverage points.

          YOUR ROLE
          - Use tools when asked to add, rename, or delete nodes and links.
          - Work in as few tool calls as possible: use create_nodes and create_links to add
            many at once, and clear_diagram (only when the user asks to start over or clear
            the diagram) instead of deleting nodes one by one.
          - create_links accepts node titles, so you can link nodes you just created without
            looking up their IDs. The current diagram above already lists every ID.
          - When the user approves a diagram you proposed, build all of it: every node and
            every link, not a part of it.
          - For any question about loops (which loops exist, reinforcing or balancing, how
            many), call find_loops and explain its result. Never work out loops yourself:
            find_loops is exact, and it returns each loop's name (R1, B1, ...), its nodes in
            order and its number of negative links.
          - When the user asks for a new or fresh diagram and the current diagram is not
            empty, call clear_diagram first. The user is asked to confirm the deletion.
          - Keep node titles short (1–4 words), starting with a capital letter.
          - After changes, briefly explain what you did and the systems logic behind it.
          - The chat shows plain text and does not render Markdown: no tables, headings or
            bold. Use short paragraphs, and lists with "-" at the start of a line.
          - Answer questions without tools — only call tools when actually modifying the diagram.
          - If a user describes a system (e.g. "staff burnout"), suggest a starter diagram and build it.
        PROMPT
      end

      def tool_definitions
        [
          {
            name: "list_graph",
            description: "Returns all current nodes and links with their IDs. Call this before referencing IDs in other tools.",
            input_schema: { type: "object", properties: {}, required: [] }
          },
          {
            name: "find_loops",
            description: "Finds every feedback loop in the diagram and labels it reinforcing (R, even " \
                         "number of negative links) or balancing (B, odd number). Use this for any question " \
                         "about loops instead of working them out yourself.",
            input_schema: { type: "object", properties: {}, required: [] }
          },
          {
            name: "create_node",
            description: "Creates a new node (variable) in the diagram.",
            input_schema: {
              type: "object",
              properties: {
                title: { type: "string", description: "Short variable name, 1–4 words" }
              },
              required: ["title"]
            }
          },
          {
            name: "create_nodes",
            description: "Creates several nodes at once. Prefer this to repeated create_node calls. " \
                         "Nodes are placed automatically.",
            input_schema: {
              type: "object",
              properties: {
                titles: { type: "array", items: { type: "string" }, description: "Short variable names, 1–4 words each" }
              },
              required: ["titles"]
            }
          },
          {
            name: "clear_diagram",
            description: "Deletes every node and link. Use only when the user asks to start over or clear the diagram.",
            input_schema: { type: "object", properties: {}, required: [] }
          },
          {
            name: "update_node",
            description: "Renames an existing node.",
            input_schema: {
              type: "object",
              properties: {
                id:    { type: "integer", description: "Node ID (from list_graph)" },
                title: { type: "string",  description: "New title" }
              },
              required: ["id", "title"]
            }
          },
          {
            name: "delete_node",
            description: "Deletes a node and all its connected links.",
            input_schema: {
              type: "object",
              properties: { id: { type: "integer", description: "Node ID" } },
              required: ["id"]
            }
          },
          {
            name: "create_link",
            description: "Creates a directed causal link from one node to another.",
            input_schema: {
              type: "object",
              properties: {
                source_node_id: { type: "integer", description: "ID of the cause node" },
                target_node_id: { type: "integer", description: "ID of the effect node" },
                polarity:       { type: "string", enum: ["positive", "negative"],
                                  description: "positive = same direction; negative = opposite direction" }
              },
              required: ["source_node_id", "target_node_id", "polarity"]
            }
          },
          {
            name: "create_links",
            description: "Creates several causal links at once. Prefer this to repeated create_link calls. " \
                         "Refer to nodes by title or by ID. Returns the result of each link; failed links " \
                         "carry an error and the others are still created.",
            input_schema: {
              type: "object",
              properties: {
                links: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      source:   { type: "string", description: "Title or ID of the cause node" },
                      target:   { type: "string", description: "Title or ID of the effect node" },
                      polarity: { type: "string", enum: %w(positive negative) }
                    },
                    required: %w(source target polarity)
                  }
                }
              },
              required: ["links"]
            }
          },
          {
            name: "update_link",
            description: "Changes the polarity of an existing link.",
            input_schema: {
              type: "object",
              properties: {
                id:       { type: "integer", description: "Link ID" },
                polarity: { type: "string",  enum: ["positive", "negative"] }
              },
              required: ["id", "polarity"]
            }
          },
          {
            name: "delete_link",
            description: "Deletes a causal link.",
            input_schema: {
              type: "object",
              properties: { id: { type: "integer", description: "Link ID" } },
              required: ["id"]
            }
          }
        ]
      end
    end
  end
end
