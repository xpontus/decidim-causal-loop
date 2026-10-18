# frozen_string_literal: true

require "spec_helper"

module Decidim::CausalLoop
  describe OpenaiCompatibleAgent do
    subject(:agent) do
      described_class.new(api_key: "sk-test", base_url: "https://openrouter.ai/api/v1/", model: "openai/gpt-4.1-mini",
                          extra_params:, extra_headers:)
    end

    let(:extra_params) { {} }
    let(:tool_call_turn) do
      { role: "assistant", content: nil,
        tool_calls: [{ id: "call_1", type: "function",
                       function: { name: "create_node", arguments: '{"title":"Stress"}' } }] }
    end
    let(:final_turn) { { role: "assistant", content: "Added Stress." } }
    let(:extra_headers) { {} }
    let(:endpoint) { "https://openrouter.ai/api/v1/chat/completions" }
    let(:tools) do
      [{ name: "create_node", description: "Creates a node",
         input_schema: { type: "object", properties: { title: { type: "string" } }, required: ["title"] } }]
    end

    def completion(message)
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { choices: [{ message: }] }.to_json }
    end

    describe "#run" do
      it "runs the tool loop against the configured endpoint" do
        stub = stub_request(:post, endpoint)
               .to_return(completion(tool_call_turn), completion(final_turn))
        calls = []

        reply = agent.run(system: "You are helpful", messages: [{ role: "user", content: "Add Stress" }], tools:) do |name, input|
          calls << [name, input]
          '{"id":1}'
        end

        expect(reply).to eq("Added Stress.")
        expect(calls).to eq([["create_node", { "title" => "Stress" }]])
        expect(stub).to have_been_requested.twice
      end

      it "sends the key, the model and the tools in OpenAI format" do
        stub_request(:post, endpoint).to_return(completion(final_turn))

        agent.run(system: "sys", messages: [{ role: "user", content: "hi" }], tools:) { "" }

        expect(a_request(:post, endpoint).with do |req|
          body = JSON.parse(req.body)
          req.headers["Authorization"] == "Bearer sk-test" &&
            body["model"] == "openai/gpt-4.1-mini" &&
            body["messages"].first == { "role" => "system", "content" => "sys" } &&
            body["tools"].first == { "type" => "function",
                                     "function" => { "name" => "create_node", "description" => "Creates a node",
                                                     "parameters" => JSON.parse(tools.first[:input_schema].to_json) } }
        end).to have_been_made
      end

      it "feeds tool results back with the call id" do
        stub_request(:post, endpoint).to_return(completion(tool_call_turn), completion(final_turn))

        agent.run(system: "sys", messages: [{ role: "user", content: "hi" }], tools:) { "tool output" }

        expect(a_request(:post, endpoint).with do |req|
          JSON.parse(req.body)["messages"].last == { "role" => "tool", "tool_call_id" => "call_1", "content" => "tool output" }
        end).to have_been_made
      end

      context "with extra params and headers" do
        let(:extra_params) { { "max_tokens" => 2048, "model" => "must-not-win", "provider" => { "sort" => "price" } } }
        let(:extra_headers) { { "X-Title" => "Causal loop" } }

        it "merges them into the request without overriding the model" do
          stub_request(:post, endpoint).to_return(completion(final_turn))

          agent.run(system: "sys", messages: [], tools:) { "" }

          expect(a_request(:post, endpoint).with do |req|
            body = JSON.parse(req.body)
            req.headers["X-Title"] == "Causal loop" &&
              body["max_tokens"] == 2048 &&
              body["provider"] == { "sort" => "price" } &&
              body["model"] == "openai/gpt-4.1-mini"
          end).to have_been_made
        end
      end

      context "without an API key" do
        subject(:agent) { described_class.new(base_url: "http://localhost:1234/v1", model: "local", extra_params: {}, extra_headers: {}) }

        it "sends no Authorization header" do
          stub_request(:post, "http://localhost:1234/v1/chat/completions").to_return(completion(final_turn))

          agent.run(system: "sys", messages: [], tools:) { "" }

          expect(a_request(:post, "http://localhost:1234/v1/chat/completions").with do |req|
            !req.headers.has_key?("Authorization")
          end).to have_been_made
        end
      end

      it "raises an Error carrying the provider's message on HTTP errors" do
        stub_request(:post, endpoint).to_return(status: 401, body: '{"error":"invalid key"}')

        expect { agent.run(system: "sys", messages: [], tools:) { "" } }
          .to raise_error(OpenaiCompatibleAgent::Error, /openrouter.ai returned 401.*invalid key/)
      end
    end

    describe ".available?" do
      around do |example|
        keys = %w(CAUSAL_LOOP_OPENAI_MODEL CAUSAL_LOOP_OPENAI_BASE_URL)
        saved = keys.index_with { |k| ENV.fetch(k, nil) }
        keys.each { |k| ENV.delete(k) }
        example.run
      ensure
        saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end

      it "needs a model" do
        expect(described_class.available?(api_key: "sk-test")).to be(false)
      end

      it "needs a key when using the default OpenAI endpoint" do
        ENV["CAUSAL_LOOP_OPENAI_MODEL"] = "gpt-4.1-mini"

        expect(described_class.available?(api_key: nil)).to be(false)
        expect(described_class.available?(api_key: "sk-test")).to be(true)
      end

      it "accepts no key for an explicitly configured endpoint" do
        ENV["CAUSAL_LOOP_OPENAI_MODEL"] = "local"
        ENV["CAUSAL_LOOP_OPENAI_BASE_URL"] = "http://localhost:1234/v1"

        expect(described_class.available?(api_key: nil)).to be(true)
      end
    end

    describe ".extra_params" do
      around do |example|
        saved = ENV.fetch("CAUSAL_LOOP_OPENAI_EXTRA_PARAMS", nil)
        example.run
      ensure
        saved.nil? ? ENV.delete("CAUSAL_LOOP_OPENAI_EXTRA_PARAMS") : ENV["CAUSAL_LOOP_OPENAI_EXTRA_PARAMS"] = saved
      end

      it "parses a JSON object" do
        ENV["CAUSAL_LOOP_OPENAI_EXTRA_PARAMS"] = '{"temperature":0.2}'

        expect(described_class.extra_params).to eq("temperature" => 0.2)
      end

      it "reports malformed JSON as a configuration error" do
        ENV["CAUSAL_LOOP_OPENAI_EXTRA_PARAMS"] = "{temperature:0.2"

        expect { described_class.extra_params }
          .to raise_error(AgentProviders::ConfigurationError, /CAUSAL_LOOP_OPENAI_EXTRA_PARAMS is not valid JSON/)
      end

      it "rejects JSON that is not an object" do
        ENV["CAUSAL_LOOP_OPENAI_EXTRA_PARAMS"] = "[1,2]"

        expect { described_class.extra_params }
          .to raise_error(AgentProviders::ConfigurationError, /must be a JSON object/)
      end
    end
  end
end
