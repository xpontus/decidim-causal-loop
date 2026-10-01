# frozen_string_literal: true

module Decidim
  module CausalLoop
    class ConversationsController < CausalLoop::ApplicationController
      before_action :authenticate_user!

      def create
        message = params[:message].to_s.strip
        history = Array(params[:history]).map { |m| { role: m[:role].to_s, content: m[:content].to_s } }

        return render json: { error: "Message cannot be blank" }, status: :bad_request if message.blank?

        agent = build_agent
        unless agent
          return render json: { error: unconfigured_message }, status: :service_unavailable
        end

        @nodes   = Node.where(decidim_component_id: current_component.id).to_a
        @links   = Link.where(decidim_component_id: current_component.id).to_a
        @actions = []

        messages = history + [{ role: "user", content: message }]
        reply    = agent.run(system: system_prompt, messages: messages, tools: tool_definitions) do |name, input|
          execute_tool(name, input)
        end

        render json: {
          reply:    reply,
          actions:  @actions,
          provider: agent.name,
          history:  messages + [{ role: "assistant", content: reply }]
        }
      rescue OllamaAgent::Error => e
        render json: { error: e.message }, status: :bad_gateway
      rescue Anthropic::Errors::APIError => e
        render json: { error: "Anthropic API error: #{e.message}" }, status: :bad_gateway
      rescue => e
        Rails.logger.error "ConversationsController error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        render json: { error: "Unexpected error: #{e.message}" }, status: :internal_server_error
      end

      private

      # Resolution order: Rails credentials, then ENV, then a local git-ignored file.
      # The file exists so a paid key can live on one machine only:
      #   echo "sk-ant-..." > config/anthropic_api_key
      def anthropic_api_key
        return @anthropic_api_key if defined?(@anthropic_api_key)

        @anthropic_api_key =
          Rails.application.credentials.dig(:anthropic, :api_key).presence ||
          ENV["ANTHROPIC_API_KEY"].presence ||
          anthropic_api_key_from_file
      end

      def anthropic_api_key_from_file
        path = Rails.root.join("config", "anthropic_api_key")
        return nil unless File.exist?(path)

        File.read(path).strip.presence
      end

      # Provider selection. CAUSAL_LOOP_AI_PROVIDER forces one ("anthropic" or
      # "ollama"); otherwise prefer a configured Anthropic key and fall back to a
      # local Ollama server, so the module is usable with no paid key at all.
      def build_agent
        case ENV["CAUSAL_LOOP_AI_PROVIDER"].to_s.downcase
        when "anthropic" then anthropic_agent
        when "ollama"    then ollama_agent
        else                  anthropic_agent || ollama_agent
        end
      end

      def anthropic_agent
        return nil unless AnthropicAgent.available?(api_key: anthropic_api_key)

        AnthropicAgent.new(api_key: anthropic_api_key)
      end

      def ollama_agent
        return nil unless OllamaAgent.available?

        OllamaAgent.new
      end

      def unconfigured_message
        "AI assistant is not configured. Either set ANTHROPIC_API_KEY (or write the key to " \
          "config/anthropic_api_key), or run a local Ollama server for free: " \
          "brew install ollama && ollama pull qwen3"
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

        when "create_node"
          title = input["title"].to_s.strip
          return "Error: title is required" if title.blank?

          pos  = auto_position
          node = Node.create!(
            title:                title,
            position_x:           input["position_x"]&.to_f || pos[:x],
            position_y:           input["position_y"]&.to_f || pos[:y],
            decidim_component_id: current_component.id
          )
          @nodes << node
          @actions << { type: "add_node", id: node.id, title: node.title,
                        position_x: node.position_x, position_y: node.position_y }
          { id: node.id, title: node.title }.to_json

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

          Link.where(decidim_component_id: current_component.id)
              .where("source_node_id = ? OR target_node_id = ?", node.id, node.id)
              .each do |l|
                @actions << { type: "remove_link", id: l.id }
                @links.delete_if { |x| x.id == l.id }
                l.destroy!
              end
          node.destroy!
          @nodes.delete_if { |n| n.id == node.id }
          @actions << { type: "remove_node", id: node.id }
          "Deleted node #{node.id} (\"#{node.title}\")"

        when "create_link"
          source_id = input["source_node_id"].to_i
          target_id = input["target_node_id"].to_i
          polarity  = input["polarity"].to_s.in?(%w[positive negative]) ? input["polarity"] : "positive"

          return "Error: source node not found" unless @nodes.any? { |n| n.id == source_id }
          return "Error: target node not found" unless @nodes.any? { |n| n.id == target_id }

          link = Link.create!(
            source_node_id:       source_id,
            target_node_id:       target_id,
            polarity:             polarity,
            decidim_component_id: current_component.id
          )
          @links << link
          @actions << { type: "add_link", id: link.id, source_node_id: source_id,
                        target_node_id: target_id, polarity: polarity }
          { id: link.id }.to_json

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

          link.destroy!
          @links.delete_if { |l| l.id == link.id }
          @actions << { type: "remove_link", id: link.id }
          "Deleted link #{link.id}"

        else
          "Error: unknown tool '#{name}'"
        end
      rescue ActiveRecord::RecordInvalid => e
        "Error: #{e.message}"
      end

      def find_node(id)
        @nodes.find { |n| n.id == id.to_i } ||
          Node.find_by(id: id.to_i, decidim_component_id: current_component.id)
      end

      def find_link(id)
        @links.find { |l| l.id == id.to_i } ||
          Link.find_by(id: id.to_i, decidim_component_id: current_component.id)
      end

      # Place new node in a spiral outward from the centroid, avoiding existing nodes
      def auto_position
        return { x: 300, y: 300 } if @nodes.empty?

        cx = @nodes.sum { |n| n.position_x.to_f } / @nodes.size
        cy = @nodes.sum { |n| n.position_y.to_f } / @nodes.size

        72.times do |i|
          angle  = i * 5 * Math::PI / 180.0
          radius = 180 + (i / 12) * 60
          x      = cx + Math.cos(angle) * radius
          y      = cy + Math.sin(angle) * radius
          next if @nodes.any? { |n| Math.hypot(n.position_x.to_f - x, n.position_y.to_f - y) < 120 }

          return { x: x.round, y: y.round }
        end

        { x: (cx + rand(-250..250)).round, y: (cy + rand(-250..250)).round }
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
          - You may call multiple tools in sequence to complete one request.
          - Always call list_graph first if you need to look up IDs.
          - Keep node titles short (1–4 words), starting with a capital letter.
          - After changes, briefly explain what you did and the systems logic behind it.
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
            name: "create_node",
            description: "Creates a new node (variable) in the diagram.",
            input_schema: {
              type: "object",
              properties: {
                title:      { type: "string", description: "Short variable name, 1–4 words" },
                position_x: { type: "number", description: "X canvas position (optional)" },
                position_y: { type: "number", description: "Y canvas position (optional)" }
              },
              required: ["title"]
            }
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
