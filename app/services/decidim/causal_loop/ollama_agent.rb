# frozen_string_literal: true

require "net/http"
require "json"

module Decidim
  module CausalLoop
    # Runs the agentic tool loop against a local Ollama server — the free,
    # no-API-key provider. Ollama serves the OpenAI-compatible chat completions
    # endpoint, so the tool loop is inherited; this class only adds Ollama's
    # model discovery and its own error messages.
    #
    #   brew install ollama && ollama pull qwen3
    #
    # Configure with CAUSAL_LOOP_OLLAMA_URL and CAUSAL_LOOP_OLLAMA_MODEL.
    # With no model configured the first model the server reports is used, so
    # a fresh clone works with whatever the user already has pulled.
    class OllamaAgent < OpenaiCompatibleAgent
      DEFAULT_URL = "http://localhost:11434"

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

      def initialize(url: nil, model: nil)
        url = url.presence || self.class.base_url
        model = model.presence || ENV["CAUSAL_LOOP_OLLAMA_MODEL"].presence || self.class.models(url).first
        raise Error, "No Ollama model available. Run: ollama pull qwen3" if model.blank?

        @ollama_url = url
        super(base_url: URI.join(url, "/v1").to_s, model: model, extra_params: {}, extra_headers: {})
      end

      def name
        "ollama:#{@model}"
      end

      private

      def provider_label
        "Ollama"
      end

      def unreachable_message
        "Cannot reach Ollama at #{@ollama_url}. Start it with: ollama serve"
      end
    end
  end
end
