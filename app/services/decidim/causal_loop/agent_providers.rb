# frozen_string_literal: true

module Decidim
  module CausalLoop
    # Chooses and builds the AI agent. Every agent exposes the same interface,
    # `run(system:, messages:, tools:) { |name, input| ... }`, so adding a
    # provider means one agent class and one entry in PROVIDERS.
    #
    # CAUSAL_LOOP_AI_PROVIDER forces a provider; otherwise the first available
    # one in PROVIDERS order is used, so the module still works with no paid
    # key at all through a local Ollama server.
    module AgentProviders
      class ConfigurationError < StandardError; end

      PROVIDERS = {
        "anthropic" => :anthropic_agent,
        "openai" => :openai_agent,
        "ollama" => :ollama_agent
      }.freeze

      module_function

      # Returns an agent, or nil when no provider is configured.
      def build(provider = ENV.fetch("CAUSAL_LOOP_AI_PROVIDER", nil))
        name = provider.to_s.strip.downcase
        return PROVIDERS.each_value.lazy.filter_map { |builder| send(builder) }.first if name.empty?

        builder = PROVIDERS[name]
        raise ConfigurationError, "Unknown CAUSAL_LOOP_AI_PROVIDER '#{provider}'. Use one of: #{PROVIDERS.keys.join(", ")}" unless builder

        send(builder)
      end

      def anthropic_agent
        key = api_key_for(credential: [:anthropic, :api_key], env: "ANTHROPIC_API_KEY", file: "anthropic_api_key")
        return nil unless AnthropicAgent.available?(api_key: key)

        AnthropicAgent.new(api_key: key)
      end

      # The key is read only from settings specific to this module, never from a
      # generic OPENAI_API_KEY: the endpoint may be OpenRouter or another
      # third party, and an OpenAI key must not be sent there by accident.
      def openai_agent
        key = api_key_for(credential: [:causal_loop, :openai_api_key], env: "CAUSAL_LOOP_OPENAI_API_KEY", file: "openai_api_key")
        return nil unless OpenaiCompatibleAgent.available?(api_key: key)

        OpenaiCompatibleAgent.new(api_key: key)
      end

      def ollama_agent
        return nil unless OllamaAgent.available?

        OllamaAgent.new
      end

      # Resolution order: Rails credentials, then ENV, then a local git-ignored
      # file in the host app's config/ folder. The file exists so a paid key can
      # live on one machine only:
      #   echo "sk-..." > config/openai_api_key
      def api_key_for(credential:, env:, file:)
        Rails.application.credentials.dig(*credential).presence ||
          ENV[env].presence ||
          api_key_from_file(file)
      end

      def api_key_from_file(name)
        path = Rails.root.join("config", name)
        return nil unless File.exist?(path)

        File.read(path).strip.presence
      end

      def unconfigured_message
        "AI assistant is not configured. Set ANTHROPIC_API_KEY for Anthropic; or " \
          "CAUSAL_LOOP_OPENAI_MODEL plus CAUSAL_LOOP_OPENAI_API_KEY (and " \
          "CAUSAL_LOOP_OPENAI_BASE_URL for providers other than OpenAI) for any " \
          "OpenAI-compatible endpoint; or run a local Ollama server for free: " \
          "brew install ollama && ollama pull qwen3"
      end
    end
  end
end
