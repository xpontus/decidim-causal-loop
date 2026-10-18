# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe AgentProviders do
    env_keys = %w(CAUSAL_LOOP_AI_PROVIDER ANTHROPIC_API_KEY OPENAI_API_KEY CAUSAL_LOOP_OPENAI_API_KEY
                  CAUSAL_LOOP_OPENAI_MODEL CAUSAL_LOOP_OPENAI_BASE_URL CAUSAL_LOOP_OLLAMA_URL)

    around do |example|
      saved = env_keys.index_with { |k| ENV.fetch(k, nil) }
      env_keys.each { |k| ENV.delete(k) }
      example.run
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    before do
      # No credentials and no key files, so only ENV decides.
      allow(Rails.application.credentials).to receive(:dig).and_return(nil)
      allow(described_class).to receive(:api_key_from_file).and_return(nil)
      allow(OllamaAgent).to receive(:available?).and_return(false)
    end

    it "returns nil when nothing is configured" do
      expect(described_class.build).to be_nil
    end

    it "builds the OpenAI-compatible agent from module settings" do
      ENV["CAUSAL_LOOP_OPENAI_API_KEY"] = "sk-or-test"
      ENV["CAUSAL_LOOP_OPENAI_BASE_URL"] = "https://openrouter.ai/api/v1"
      ENV["CAUSAL_LOOP_OPENAI_MODEL"] = "openai/gpt-4.1-mini"

      expect(described_class.build.name).to eq("openai:openrouter.ai:openai/gpt-4.1-mini")
    end

    it "never uses a generic OPENAI_API_KEY" do
      ENV["OPENAI_API_KEY"] = "sk-generic"
      ENV["CAUSAL_LOOP_OPENAI_MODEL"] = "gpt-4.1-mini"

      expect(described_class.build).to be_nil
    end

    it "prefers Anthropic when several providers are configured" do
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
      ENV["CAUSAL_LOOP_OPENAI_API_KEY"] = "sk-test"
      ENV["CAUSAL_LOOP_OPENAI_MODEL"] = "gpt-4.1-mini"

      expect(described_class.build).to be_a(AnthropicAgent)
    end

    it "honours a forced provider" do
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
      ENV["CAUSAL_LOOP_OPENAI_API_KEY"] = "sk-test"
      ENV["CAUSAL_LOOP_OPENAI_MODEL"] = "gpt-4.1-mini"

      expect(described_class.build("openai")).to be_a(OpenaiCompatibleAgent)
    end

    it "rejects an unknown provider name" do
      expect { described_class.build("gemini") }
        .to raise_error(AgentProviders::ConfigurationError, /Unknown CAUSAL_LOOP_AI_PROVIDER 'gemini'/)
    end
  end
end
