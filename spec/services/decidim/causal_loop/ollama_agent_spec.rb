# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe OllamaAgent do
    let(:url) { "http://ollama.test:11434" }

    before do
      stub_request(:get, "#{url}/api/tags")
        .to_return(status: 200, body: { models: [{ name: "qwen3:latest" }] }.to_json)
    end

    it "uses the first model the server reports" do
      expect(described_class.new(url:).name).to eq("ollama:qwen3:latest")
    end

    it "talks to Ollama's OpenAI-compatible endpoint without a key" do
      stub_request(:post, "#{url}/v1/chat/completions")
        .to_return(status: 200, body: { choices: [{ message: { role: "assistant", content: "Hi" } }] }.to_json)

      reply = described_class.new(url:).run(system: "sys", messages: [{ role: "user", content: "hi" }], tools: []) { "" }

      expect(reply).to eq("Hi")
      expect(a_request(:post, "#{url}/v1/chat/completions").with do |req|
        !req.headers.has_key?("Authorization")
      end).to have_been_made
    end

    it "explains how to start Ollama when it cannot be reached" do
      stub_request(:post, "#{url}/v1/chat/completions").to_raise(Errno::ECONNREFUSED)

      expect { described_class.new(url:).run(system: "sys", messages: [], tools: []) { "" } }
        .to raise_error(OpenaiCompatibleAgent::Error, /Cannot reach Ollama.*ollama serve/)
    end
  end
end
