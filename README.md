# Decidim::CausalLoop

.

## Usage

CausalLoop will be available as a Component for a Participatory
Space.

## What it can and cannot do

### What it can do

- **One diagram per component.** Each Causal Loop component in a
  participatory space holds one diagram. For several diagrams, add several
  components.
- **Variables and causal links.** Add, rename, move and delete variables
  (nodes). Draw directed links between them and mark each as positive (+) or
  negative (−). Resize nodes, change their font size, and bend links so they
  don't overlap.
- **Automatic layout.** The Auto-layout button rearranges the diagram with a
  force-directed (spring) layout and saves the result. Press it again for a
  different arrangement.
- **Full view.** The editor fills the browser window by default, hiding
  Decidim's header and footer. The AI assistant panel sits beside the canvas
  (or below it), and can be resized.
- **Saved as you go.** Every change is saved to the server as you
  make it. There is no separate save step.
- **Edit and view permissions.** Organization admins, admins of the
  participatory space, and users granted access under the component's
  **Editors** screen can edit. Everyone else who can see the component can
  view, zoom and export it.
- **Export.** Download the diagram as JSON or GraphML, save it as a PNG, or
  print it / save it as a PDF.
- **Optional AI assistant.** Editors can ask an AI to add, rename and delete
  variables and links, change polarity, or explain how the diagram works (see
  [AI assistant](#ai-assistant)).

### What it cannot do

**Analysis**

- It does not find loops or label them as reinforcing (R) or balancing (B).
  Spotting the loops and counting the negative links is left to the people
  using the diagram.
- Links can only be positive or negative. There is no way to mark delays,
  link strength, or uncertain polarity.
- It does not simulate the system or compute any values. It is a drawing
  tool, not a system-dynamics model.

**Collaboration**

- No real-time collaboration. When several editors work at once, nobody sees
  anyone else's changes until they reload the page. If two people change the
  same thing, the last save wins.
- No undo, no version history, and no record of who changed what. Deleting
  a variable deletes all of its links immediately, without asking for
  confirmation.
- Editing rights cover the whole diagram. An editor can change or delete
  anything, including other people's work. Participants without edit rights
  cannot suggest changes or comment on the diagram.

**Content**

- Each variable has only a title. There is nowhere to add a description or
  notes, and links cannot carry text labels.
- Every node looks the same. You can't colour, group or categorise
  variables. Long titles wrap onto several lines, breaking at spaces or
  inside CamelCase names, and the box grows to fit.
- New links always start as positive. Clicking a link switches its polarity,
  so a stray click can flip a sign; the link flashes and a message offers to
  undo it for a few seconds.
- Diagrams cannot be imported. The JSON and GraphML exports leave out
  layout details: GraphML has no positions, and neither format includes node
  sizes, fonts or link curves. Use them for analysis in other tools, not as
  backups.

**Decidim integration**

- Diagrams are not connected to the rest of Decidim. They don't appear in
  search, the activity feed, notifications or statistics, and they can't be
  linked from proposals or other content.
- Not multilingual. The editor's interface text is English only, and
  variable titles are stored in a single language rather than as Decidim
  translatable fields.

**Devices and accessibility**

- Built for mouse and keyboard. Drawing links with the <kbd>C</kbd> key,
  renaming existing variables (double-click) and bending links all need a
  mouse. On touch devices, expect to be able to view and pan, but not to
  edit fully.
- The diagram is drawn on a canvas, so screen readers cannot read it, and
  there is no text-only view of the variables and links.

**AI assistant**

- The site administrator must set it up: an Anthropic API key, an
  OpenAI-compatible endpoint, or an Ollama server (see
  [AI assistant](#ai-assistant)). It is available only to editors.
- It can add, rename and delete variables and links and change polarity. It
  cannot move or resize nodes or bend links.
- Its changes take effect immediately, without asking for confirmation, and
  can include deletions. The exception is replacing the whole diagram: the
  editor asks before the previous diagram is deleted.
- The conversation is kept only in your browser (per diagram), so it
  survives a reload but not a switch to another computer, and other editors
  cannot see it. **Clear chat** starts over.
- Each request is limited to 25 rounds of tool calls. The assistant can
  create many variables or links in one round, so a whole starter diagram
  usually takes a handful. If it runs out, it says so; reply "continue".
- It places new variables automatically and cannot choose where they go.
- The diagram's contents and the conversation are sent to the configured
  provider: Anthropic's API, the OpenAI-compatible endpoint (which may be a
  third party such as OpenRouter), or the Ollama server. They stay on your own
  infrastructure only if that server is yours.
- Small local models are much less reliable than hosted ones. The Anthropic
  provider has not yet been tested against the live API.

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
