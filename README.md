# Decidim::CausalLoop

.

## Usage

CausalLoop will be available as a Component for a Participatory
Space.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "decidim-causal_loop"
```

And then execute:

```bash
bundle
```

## AI assistant

The diagram editor includes an optional AI panel that can add, rename and delete
nodes and links by instruction ("link Stress to Burnout with a positive link").
It is entirely optional — the editor works fully without it.

Three providers are supported, chosen automatically:

| Provider | Cost | Setup |
|---|---|---|
| **Ollama** (local) | Free, no account | `brew install ollama && ollama pull qwen3` |
| **OpenAI-compatible** | Depends on the endpoint | see below |
| **Anthropic** | Paid API key | see below |

The first configured provider is used, in this order: Anthropic, then
OpenAI-compatible, then a reachable local Ollama server. With none of them the
panel reports that AI is not configured and the rest of the editor carries on
working.

Force a provider with `CAUSAL_LOOP_AI_PROVIDER=anthropic`, `=openai` or
`=ollama`.

### Ollama (free)

```bash
brew install ollama      # or https://ollama.com/download
ollama pull qwen3        # any tool-calling model: qwen3, llama3.1, gpt-oss
```

Ollama serves on `http://localhost:11434` by default. Override with
`CAUSAL_LOOP_OLLAMA_URL` and `CAUSAL_LOOP_OLLAMA_MODEL`; with no model set, the
first model the server reports is used. Note that small local models are
markedly less reliable at multi-step tool use than a frontier model.

### OpenAI-compatible endpoints

Any endpoint that speaks the OpenAI chat completions format with tool calling:
OpenAI, OpenRouter, TensorX, Groq, Mistral, Together, vLLM, LM Studio and others.

| Variable | Required | Example |
|---|---|---|
| `CAUSAL_LOOP_OPENAI_MODEL` | yes | `openai/gpt-4.1-mini` |
| `CAUSAL_LOOP_OPENAI_BASE_URL` | no, defaults to `https://api.openai.com/v1` | `https://openrouter.ai/api/v1` |
| `CAUSAL_LOOP_OPENAI_API_KEY` | unless the endpoint needs none | `sk-or-...` |
| `CAUSAL_LOOP_OPENAI_EXTRA_PARAMS` | no | `{"temperature":0.2,"max_tokens":2048}` |
| `CAUSAL_LOOP_OPENAI_EXTRA_HEADERS` | no | `{"HTTP-Referer":"https://example.org","X-Title":"Causal loop"}` |

The base URL includes the version segment; `/chat/completions` is appended to
it. The model must support tool calling.

`CAUSAL_LOOP_OPENAI_EXTRA_PARAMS` is a JSON object merged into every request
body, for provider-specific options such as OpenRouter's `provider` routing. It
cannot override `model`, `messages`, `tools` or `stream`.
`CAUSAL_LOOP_OPENAI_EXTRA_HEADERS` adds HTTP headers. Malformed JSON in either
is reported in the AI panel rather than ignored.

The key is read from, in order: Rails credentials `causal_loop.openai_api_key`,
`CAUSAL_LOOP_OPENAI_API_KEY`, then the git-ignored file `config/openai_api_key`
in the host app. A generic `OPENAI_API_KEY` is deliberately not used: the
endpoint may be a third party, and an OpenAI key must not be sent there by
accident.

A local server that needs no key (vLLM, LM Studio) only needs the base URL and
the model.

### Anthropic (paid)

The key is read from, in order:

1. Rails credentials — `anthropic.api_key`
2. `ANTHROPIC_API_KEY` in the environment
3. `config/anthropic_api_key` in the host app — a plain file holding just the key

The third option keeps a paid key on one machine without putting it in the
environment or in the repository. It is git-ignored:

```bash
echo "sk-ant-..." > config/anthropic_api_key
```

Override the model with `CAUSAL_LOOP_ANTHROPIC_MODEL` (default `claude-opus-5`).

## Contributing

Contributions are welcome !

We expect the contributions to follow the [Decidim's contribution guide](https://github.com/decidim/decidim/blob/develop/CONTRIBUTING.adoc).

## Security

Security is very important to us. If you have any issue regarding security, please disclose the information responsibly by sending an email to ____ and not by creating a GitHub issue.

## License

This engine is distributed under the GNU AFFERO GENERAL PUBLIC LICENSE.
