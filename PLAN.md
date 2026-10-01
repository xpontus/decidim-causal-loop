# Decidim Causal Loop — Development Plan

A Decidim component for collaboratively building **causal loop diagrams**:
nodes are variables, links are signed causal arrows (+ / −), and loops are
reinforcing or balancing depending on how many negative links they contain.

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Decidim running locally | ✅ Done |
| 2 | Scaffold component gem | ✅ Done |
| 3 | Node / Link data models | ✅ Done |
| 4 | JSON API | ✅ Done |
| 5 | Interactive Cytoscape.js frontend editor | ✅ Done |
| 6 | AI agent integration | ✅ Done |

---

## Architecture

```
Browser
  Stimulus controller "causal-loop-editor"  (app/packs/src/.../causal_loop_editor_controller.js)
    Cytoscape.js canvas + toolbar + AI chat panel
      │  JSON over fetch
      ▼
Rails engine  Decidim::CausalLoop::Engine
    NodesController    POST/PATCH/DELETE  nodes
    LinksController    POST/PATCH/DELETE  links
    DiagramsController GET  the editor page
    ConversationsController POST /agent
      │
      ├── AnthropicAgent   (paid, Anthropic API)
      └── OllamaAgent      (free, local Ollama)
           both run the same tool loop over the same tool set
      ▼
PostgreSQL
    decidim_causal_loop_nodes    (title, description, position, size, font)
    decidim_causal_loop_links    (source, target, polarity, label, control points)
    decidim_causal_loop_editors  (component ↔ user grants)
```

### Permissions

Editing a diagram is allowed for:

1. organization admins,
2. admins of the participatory space holding the component,
3. users with an explicit row in `decidim_causal_loop_editors`.

Everyone else gets a read-only view: zoom, fit and export still work, and an
on-page notice explains why editing is unavailable. Grant explicit editors in
the admin panel under the component's **Editors** screen.

### AI assistant

Optional. Two interchangeable providers behind one interface
(`run(system:, messages:, tools:) { |name, input| ... }`):

- **Ollama** — free, local, no key. Uses the OpenAI-compatible
  `/v1/chat/completions` endpoint, translating this module's
  Anthropic-shaped tool definitions into function tools and OpenAI
  `tool_calls` back again. Tool-call arguments arrive as a JSON *string*
  and are parsed.
- **Anthropic** — paid. Native tool-use blocks.

Selection: an Anthropic key if configured, else a reachable Ollama, else a
503 explaining how to set either up. `CAUSAL_LOOP_AI_PROVIDER` forces one.
See the README for configuration, including the git-ignored
`config/anthropic_api_key` file.

### Example diagram

Seeding creates a published component holding a small worked example, so a
fresh installation shows what the component is for rather than an empty
canvas. It is the smallest diagram that demonstrates why polarity matters —
one reinforcing and one balancing loop:

```
                    Participation
                   /      ▲      \
               (+)/       |(+)    \(+)
                 ▼        |        ▼
    Trust in the process  |   Moderation workload
                 ▲        |        |
              (+)|        |        |(−)
                 |        |        ▼
                 \--------+---- Response speed
```

- **R** — Participation →(+) Trust →(+) Participation.
  No negative links, so the loop amplifies itself.
- **B** — Participation →(+) Moderation workload →(−) Response speed →(+)
  Trust →(+) Participation. One negative link, so the loop is self-limiting.

The seeds also grant the seeded participant (`user@example.org`) an editor
row, so the Editors mechanism is visible without having to be discovered.
See `lib/decidim/causal_loop/seeds.rb`.

The agent calls the same database operations the frontend uses
(`create_node`, `create_link`, `update_node`, `update_link`, `delete_node`,
`delete_link`, `list_graph`) and returns a list of actions the Stimulus
controller applies to the live Cytoscape graph.

---

## Development setup

Requires PostgreSQL, ImageMagick and libvips, plus Ruby and Node at the
versions in `.ruby-version` / `.node-version` (3.3.11 and 22.14.0). On macOS:

```bash
brew install mise postgresql@16 imagemagick vips
brew services start postgresql@16
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc && source ~/.zshrc
mise install
```

The module is consumed by a host Decidim application. In the host app's
`Gemfile`:

```ruby
gem "decidim-causal_loop", path: "../decidim-module-causal_loop"
```

Then, in the host app:

```bash
bundle install
npm install
bin/rails decidim:choose_target_plugins railties:install:migrations
bin/rails decidim_causal_loop:install:migrations
bin/rails db:create db:migrate db:seed
./bin/shakapacker          # build assets
bin/rails server
```

Seeds create `admin@example.org` / `decidim123456789`.

Add the component to a participatory space through
**Admin → (space) → Components → Add component → Causal Loop**, then publish
it.

---

## Gotchas

Things that cost real time, recorded so they do not have to be rediscovered.

| Problem | Cause and fix |
|---|---|
| `db:migrate` dies around migration 195 with `PG::DuplicateTable: relation "active_storage_variant_records" already exists` | Plain `railties:install:migrations` also copies migrations from ActiveStorage, whose migrations Decidim already vendors as `*.decidim.rb`, so two migrations create the same table. Use `decidim:choose_target_plugins railties:install:migrations`. Plain `decidim:install:migrations` is also wrong alone — it installs only decidim-core's 247, omitting the component engines. A correct install is 640 files, all suffixed `.decidim*`. |
| Every CSS/JS request returns 500, page renders unstyled | Shakapacker's railtie inserts `DevServerProxy` whenever a `dev_server` config exists — and one always does, since Shakapacker supplies defaults when the key is absent. The proxy engages when `DevServer#running?` is true, which probes the port with Ruby's `Socket.tcp`. That can wrongly report success for a refused localhost port, making every asset proxy to a dead `:3035`. Either run `./bin/shakapacker-dev-server`, or delete the middleware in an initializer. |
| Editor renders but nothing is clickable and no requests are made | Not a JavaScript failure: the edit toolbar is server-rendered inside `if @editable`. The account lacks edit permission. See Permissions above. |
| `You can only call prepend_javascript_pack_tag before javascript_pack_tag` | Use `prepend_javascript_pack_tag`, not `javascript_pack_tag`, in component views. |
| Component tab missing from the space's public page | The component is not published — publish it in the admin panel. |
| Asset manifest missing | Run `./bin/shakapacker`, then restart Rails. |

---

## Possible next steps

- **More AI providers.** The agent interface is deliberately small —
  `run(system:, messages:, tools:)` yielding tool calls — so a provider is one
  class and a translation of the tool schema. Worth adding:
  - any **OpenAI-compatible** endpoint (OpenAI, Groq, Mistral, Together,
    OpenRouter, vLLM, LM Studio). `OllamaAgent` already speaks this dialect,
    so this is mostly a configurable base URL, model and API key rather than
    new code.
  - **Google Gemini**, which uses a different shape (`functionDeclarations`,
    `functionCall` / `functionResponse` parts) and so needs its own adapter.
  - **Azure OpenAI**, same dialect as OpenAI but different auth and URL layout.
  A provider registry keyed by `CAUSAL_LOOP_AI_PROVIDER` would replace the
  current if/else selection, and providers should declare whether they support
  tool calling — some small local models do not, and should degrade to
  answering questions rather than failing silently.
- Automatic loop detection: find cycles, label them reinforcing or balancing,
  surface them in the UI.
- Real-time collaboration, so several participants can edit one diagram at once.
- Streaming AI replies instead of request/response.
- Decidim resource registration, so diagrams can be linked from proposals and
  appear in search and the activity feed.
- Specs for the editor and the two AI providers; CI currently runs rspec only.
