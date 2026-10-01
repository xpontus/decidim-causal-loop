# frozen_string_literal: true

module Decidim
  module CausalLoop
    # Runs the agentic tool loop against the Anthropic API.
    #
    # Tool definitions are supplied in Anthropic's native shape
    # ({ name:, description:, input_schema: }) and used as-is.
    class AnthropicAgent
      DEFAULT_MODEL = "claude-opus-5"
      MAX_ROUNDS = 10

      def self.available?(api_key:)
        api_key.present?
      end

      def initialize(api_key:, model: nil)
        @client = ::Anthropic::Client.new(api_key: api_key)
        @model = model.presence || ENV["CAUSAL_LOOP_ANTHROPIC_MODEL"].presence || DEFAULT_MODEL
      end

      def name
        "anthropic:#{@model}"
      end

      # Yields [tool_name, input_hash] for each tool call; the block returns the
      # tool result as a String. Returns the assistant's final text.
      def run(system:, messages:, tools:, &execute_tool)
        loop_messages = messages.dup

        MAX_ROUNDS.times do
          response = @client.messages.create(
            model: @model,
            max_tokens: 4096,
            system: system,
            tools: tools,
            messages: loop_messages
          )

          # The SDK returns Symbols here; compare via to_s so either works.
          return response.content.find { |b| b.type.to_s == "text" }&.text.to_s unless response.stop_reason.to_s == "tool_use"

          loop_messages << { role: "assistant", content: response.content.map(&:to_h) }

          results = response.content.select { |b| b.type.to_s == "tool_use" }.map do |block|
            { type: "tool_result",
              tool_use_id: block.id,
              content: execute_tool.call(block.name, block.input) }
          end
          loop_messages << { role: "user", content: results }
        end

        "Done."
      end
    end
  end
end
