# frozen_string_literal: true

require "net/http"
require "json"

module Decidim
  module CausalLoop
    # Runs the agentic tool loop against a local Ollama server — the free,
    # no-API-key provider. Uses Ollama's OpenAI-compatible chat completions
    # endpoint, translating Anthropic-shaped tool definitions on the way in
    # and OpenAI-shaped tool calls on the way out.
    #
    #   brew install ollama && ollama pull qwen3
    #
    # Configure with CAUSAL_LOOP_OLLAMA_URL and CAUSAL_LOOP_OLLAMA_MODEL.
    # With no model configured the first model the server reports is used, so
    # a fresh clone works with whatever the user already has pulled.
    class OllamaAgent
      DEFAULT_URL = "http://localhost:11434"
      MAX_ROUNDS = 10
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 180

      class Error < StandardError; end

      def self.base_url
        ENV["CAUSAL_LOOP_OLLAMA_URL"].presence || DEFAULT_URL
      end

      # Reachable and has at least one model pulled.
      def self.available?
        models(base_url).any?
      rescue StandardError
        false
      end

      def self.models(url = base_url)
        uri = URI.join(url, "/api/tags")
        res = http_for(uri).get(uri.request_uri)
        return [] unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(res.body).fetch("models", []).filter_map { |m| m["name"] }
      rescue StandardError
        []
      end

      def self.http_for(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http
      end

      def initialize(url: nil, model: nil)
        @url = url.presence || self.class.base_url
        @model = model.presence || ENV["CAUSAL_LOOP_OLLAMA_MODEL"].presence || self.class.models(@url).first
        raise Error, "No Ollama model available. Run: ollama pull qwen3" if @model.blank?
      end

      def name
        "ollama:#{@model}"
      end

      def run(system:, messages:, tools:, &execute_tool)
        loop_messages = [{ "role" => "system", "content" => system }] +
                        messages.map { |m| { "role" => m[:role].to_s, "content" => m[:content].to_s } }
        openai_tools = tools.map { |t| to_openai_tool(t) }

        MAX_ROUNDS.times do
          message = chat(loop_messages, openai_tools)
          calls = message["tool_calls"].to_a

          return message["content"].to_s if calls.empty?

          # Echo the assistant turn back verbatim so the model sees its own calls.
          loop_messages << message

          calls.each do |call|
            fn = call["function"] || {}
            # OpenAI-compatible APIs send arguments as a JSON *string*.
            args = parse_arguments(fn["arguments"])
            result = execute_tool.call(fn["name"].to_s, args)
            loop_messages << {
              "role" => "tool",
              "tool_call_id" => call["id"].to_s,
              "content" => result.to_s
            }
          end
        end

        "Done."
      end

      private

      # Anthropic { name:, description:, input_schema: } -> OpenAI function tool.
      def to_openai_tool(tool)
        t = tool.transform_keys(&:to_sym)
        {
          "type" => "function",
          "function" => {
            "name" => t[:name],
            "description" => t[:description],
            "parameters" => t[:input_schema]
          }
        }
      end

      def parse_arguments(raw)
        return raw if raw.is_a?(Hash)

        parsed = JSON.parse(raw.to_s)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def chat(messages, tools)
        uri = URI.join(@url, "/v1/chat/completions")
        req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
        req.body = JSON.generate(model: @model, messages: messages, tools: tools, stream: false)

        res = self.class.http_for(uri).request(req)
        raise Error, "Ollama returned #{res.code}: #{res.body.to_s[0, 300]}" unless res.is_a?(Net::HTTPSuccess)

        body = JSON.parse(res.body)
        message = body.dig("choices", 0, "message")
        raise Error, "Unexpected Ollama response: #{res.body[0, 300]}" if message.nil?

        message
      rescue Errno::ECONNREFUSED
        raise Error, "Cannot reach Ollama at #{@url}. Start it with: ollama serve"
      rescue JSON::ParserError => e
        raise Error, "Invalid JSON from Ollama: #{e.message}"
      end
    end
  end
end
