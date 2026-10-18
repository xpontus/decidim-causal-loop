# frozen_string_literal: true

require "net/http"
require "json"

module Decidim
  module CausalLoop
    # Runs the agentic tool loop against any endpoint that speaks the OpenAI
    # chat completions dialect: OpenAI itself, OpenRouter, TensorX, Groq,
    # Mistral, Together, vLLM, LM Studio and many others.
    #
    # Tool definitions arrive in this module's Anthropic shape
    # ({ name:, description:, input_schema: }) and are translated into OpenAI
    # function tools; OpenAI `tool_calls` are translated back into
    # [name, input_hash] pairs for the caller.
    #
    # Configure with:
    #   CAUSAL_LOOP_OPENAI_BASE_URL  e.g. https://openrouter.ai/api/v1
    #                                (default https://api.openai.com/v1)
    #   CAUSAL_LOOP_OPENAI_MODEL     required, e.g. openai/gpt-4.1-mini
    #   CAUSAL_LOOP_OPENAI_EXTRA_PARAMS   optional JSON object merged into the
    #                                request body, e.g. {"temperature":0.2}
    #   CAUSAL_LOOP_OPENAI_EXTRA_HEADERS  optional JSON object of HTTP headers,
    #                                e.g. {"X-Title":"Causal loop"}
    #   API key                      see AgentProviders
    #
    # The base URL includes the version segment; "/chat/completions" is
    # appended to it, as every OpenAI-compatible client does.
    class OpenaiCompatibleAgent
      DEFAULT_BASE_URL = "https://api.openai.com/v1"
      MAX_ROUNDS = 10
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 180

      class Error < StandardError; end

      def self.base_url
        ENV["CAUSAL_LOOP_OPENAI_BASE_URL"].presence || DEFAULT_BASE_URL
      end

      def self.model
        ENV["CAUSAL_LOOP_OPENAI_MODEL"].presence
      end

      def self.extra_params
        json_env("CAUSAL_LOOP_OPENAI_EXTRA_PARAMS")
      end

      def self.extra_headers
        json_env("CAUSAL_LOOP_OPENAI_EXTRA_HEADERS")
      end

      # A malformed value raises instead of being ignored, so a typo in the
      # configuration is reported rather than silently changing behaviour.
      def self.json_env(var)
        raw = ENV[var].presence
        return {} unless raw

        parsed = JSON.parse(raw)
        raise AgentProviders::ConfigurationError, "#{var} must be a JSON object" unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError => e
        raise AgentProviders::ConfigurationError, "#{var} is not valid JSON: #{e.message}"
      end

      # A model is required, since no default makes sense across providers.
      # A key is required unless a base URL is set explicitly, which allows
      # keyless local servers such as vLLM or LM Studio.
      def self.available?(api_key:)
        model.present? && (api_key.present? || ENV["CAUSAL_LOOP_OPENAI_BASE_URL"].present?)
      end

      def self.http_for(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = self::OPEN_TIMEOUT
        http.read_timeout = self::READ_TIMEOUT
        http
      end

      def initialize(api_key: nil, base_url: nil, model: nil, extra_params: nil, extra_headers: nil)
        @api_key = api_key.presence
        @base_url = (base_url.presence || self.class.base_url).chomp("/")
        @model = model.presence || self.class.model
        @extra_params = extra_params || self.class.extra_params
        @extra_headers = extra_headers || self.class.extra_headers
        raise Error, "No model configured. Set CAUSAL_LOOP_OPENAI_MODEL." if @model.blank?
      end

      def name
        "openai:#{URI(@base_url).host}:#{@model}"
      end

      # Yields [tool_name, input_hash] for each tool call; the block returns the
      # tool result as a String. Returns the assistant's final text.
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

      def chat_completions_url
        "#{@base_url}/chat/completions"
      end

      # Used in error messages, so each subclass can name itself.
      def provider_label
        URI(@base_url).host
      end

      def unreachable_message
        "Cannot reach #{provider_label} at #{@base_url}"
      end

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

      def request_headers
        headers = { "Content-Type" => "application/json" }
        headers["Authorization"] = "Bearer #{@api_key}" if @api_key
        headers.merge(@extra_headers.transform_keys(&:to_s).transform_values(&:to_s))
      end

      # Extra params go first so they cannot override the fields the tool loop
      # depends on.
      def request_body(messages, tools)
        @extra_params.transform_keys(&:to_s)
                     .merge("model" => @model, "messages" => messages, "tools" => tools, "stream" => false)
      end

      def chat(messages, tools)
        uri = URI(chat_completions_url)
        req = Net::HTTP::Post.new(uri.request_uri, request_headers)
        req.body = JSON.generate(request_body(messages, tools))

        res = self.class.http_for(uri).request(req)
        raise Error, "#{provider_label} returned #{res.code}: #{res.body.to_s[0, 300]}" unless res.is_a?(Net::HTTPSuccess)

        body = JSON.parse(res.body)
        message = body.dig("choices", 0, "message")
        raise Error, "Unexpected response from #{provider_label}: #{res.body[0, 300]}" if message.nil?

        message
      rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout
        raise Error, unreachable_message
      rescue JSON::ParserError => e
        raise Error, "Invalid JSON from #{provider_label}: #{e.message}"
      end
    end
  end
end
