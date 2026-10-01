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

Two providers are supported, chosen automatically:

| Provider | Cost | Setup |
|---|---|---|
| **Ollama** (local) | Free, no account | `brew install ollama && ollama pull qwen3` |
| **Anthropic** | Paid API key | see below |

If an Anthropic key is configured it is used; otherwise a local Ollama server is
used if one is reachable; otherwise the panel reports that AI is not configured
and the rest of the editor carries on working.

Force a provider with `CAUSAL_LOOP_AI_PROVIDER=anthropic` or `=ollama`.

### Ollama (free)

```bash
brew install ollama      # or https://ollama.com/download
ollama pull qwen3        # any tool-calling model: qwen3, llama3.1, gpt-oss
```

Ollama serves on `http://localhost:11434` by default. Override with
`CAUSAL_LOOP_OLLAMA_URL` and `CAUSAL_LOOP_OLLAMA_MODEL`; with no model set, the
first model the server reports is used. Note that small local models are
markedly less reliable at multi-step tool use than a frontier model.

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
