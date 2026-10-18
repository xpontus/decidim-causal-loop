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
| 7 | Editor features: loops, undo/redo, files, help | ✅ Done |
| 8 | Decidim integration specs (admin, permissions, access, seeds) | ✅ Done |

---

## Architecture

```
Browser
  Stimulus controller "causal-loop-editor"  (app/packs/src/decidim/causal_loop/)
    causal_loop_editor_controller.js  Cytoscape.js canvas, toolbars, panels, AI chat
    command_manager.js                undo/redo stacks and request queue
      │  JSON over fetch
      ▼
Rails engine  Decidim::CausalLoop::Engine  (public side)
    DiagramsController       GET  /             the editor page
                             GET  /loops        feedback loops (LoopFinder)
                             GET  /file         the diagram file (DiagramFile.dump)
    NodesController          POST/PATCH/DELETE  nodes
    LinksController          POST/PATCH/DELETE  links
    OperationsController     POST /operations   batches of update/delete/restore (undo/redo)
    ImportsController        POST /import       load a diagram file, replace or add
    ConversationsController  POST /agent        the AI assistant (JSON, or NDJSON stream of progress)
      │
      ├── AnthropicAgent         (paid, Anthropic API)
      └── OpenaiCompatibleAgent  (OpenAI, OpenRouter, TensorX, vLLM, ...)
            └── OllamaAgent      (free, local Ollama)
           both run the same tool loop over the same tool set
Rails engine  Decidim::CausalLoop::AdminEngine  (admin side)
    EditorsController        the component's Manage page: who may edit
Services
    LoopFinder      every elementary cycle, labelled R or B
    DiagramFile     the file format: dump, parse (incl. old Export JSON), import
    DeletedRecords  restore soft-deleted rows; purge old ones
      ▼
PostgreSQL
    decidim_causal_loop_nodes    (title, description, position, size, font, deleted_at)
    decidim_causal_loop_links    (source, target, polarity, label, control points, deleted_at)
    decidim_causal_loop_editors  (component ↔ user grants)
```

### Permissions

Editing a diagram is allowed for:

1. organization admins,
2. admins of the participatory space holding the component,
3. users with an explicit row in `decidim_causal_loop_editors`.

Everyone else gets a read-only view: zoom, loops, saving and export still
work, and an on-page notice explains why editing is unavailable. Grant
explicit editors under **Manage** on the component in the admin, which opens
**Diagram editors**.

Reading follows Decidim: `Decidim::Components::BaseController` refuses
unpublished components (except to admins) and private spaces (except to
members). Components in the admin's trash are still routed by Decidim, so
`CausalLoop::ApplicationController` answers 404 for them itself.
`spec/requests/decidim/causal_loop/access_spec.rb` covers all of this.

### AI assistant

Optional. Interchangeable providers behind one interface
(`run(system:, messages:, tools:) { |name, input| ... }`), chosen by
`AgentProviders`:

- **OpenAI-compatible** (`OpenaiCompatibleAgent`) — any endpoint speaking the
  OpenAI chat completions dialect (OpenAI, OpenRouter, TensorX, Groq, vLLM…).
  Translates this module's Anthropic-shaped tool definitions into function
  tools and OpenAI `tool_calls` back again. Tool-call arguments arrive as a
  JSON *string* and are parsed. Base URL, model, key, extra body params and
  extra headers are configurable.
- **Ollama** (`OllamaAgent`) — free, local, no key. A subclass of the
  OpenAI-compatible agent that adds model discovery.
- **Anthropic** (`AnthropicAgent`) — paid. Native tool-use blocks.

Selection: the first configured of Anthropic, OpenAI-compatible, Ollama; else a
503 explaining how to set one up. `CAUSAL_LOOP_AI_PROVIDER` forces one. See the
README for configuration, including the git-ignored key files.

The agent's tools work on the database directly (`list_graph`,
`find_loops`, `create_node(s)`, `update_node`, `delete_node`,
`create_link(s)`, `update_link`, `delete_link`, `clear_diagram`) and return a
list of actions the Stimulus controller applies to the canvas and records as
one undoable step. Titles are matched with `Node.title_key` (ignoring case
and punctuation), so asking for an existing variable reuses it.

The batch tools exist because small local models such as gpt-oss make
exactly one tool call per round. With single-item tools only, a 12-node,
23-link diagram needed ~40 rounds and hit the cap after 3 nodes; with batch
tools it takes 3–4. The model cannot choose node positions: it placed nodes
100 px apart, overlapping them, so placement is always automatic.
`clear_diagram` only marks the old diagram; the editor asks before deleting
it. `find_loops` uses `LoopFinder`, since models are unreliable at finding
cycles themselves.

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
**Admin → (space) → Components → Add component → RUSIF Causal Loop Diagram**, then publish
it.

### Running the specs

From the module, once, generate the dummy app the specs run against (the
`Rakefile` overrides Decidim's `test_app` to install `cytoscape` and the
module's migrations first), then run them:

```bash
bundle exec rake test_app
bundle exec rspec
```

Specs cover the request endpoints, the services, permissions and access
(unpublished, private, trashed), the seeds, the editor in headless Chrome
(`spec/system/diagram_editor_spec.rb`, with a fake AI agent) and the admin
screens (`spec/system/admin_manages_diagram_spec.rb`). CI runs them on every
push to `main`.

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
| JavaScript changes don't take effect after a rebuild and reload | Decidim's service worker caches `/decidim-packs/` by URL, and development bundles are unhashed. Set `useContentHash: true` under `development:` in the host's `config/shakapacker.yml`. |
| A new route 404s in development | Engine routes don't reload; restart the server. |
| A link with `target="_blank"` goes to a "you are leaving the site" page | Decidim rewrites every `target="_blank"` link to `/link?external_url=…`, even internal ones. Use plain links. |
| A `keydown` listener on `document` never sees Escape | The editor's key handler runs in the capture phase and stops Escape. Register other Escape listeners in the capture phase too. |
| A streamed response arrives all at once in specs | Loading Rails' test helpers makes `ActionController::Live` run actions inline (actionpack `test_case.rb`). The streaming system spec swaps real threads back in. In development and production it streams. |
| A trashed component is still reachable by URL | Decidim's router finds trashed components (`with_deleted`) and leaves hiding them to each component. See Permissions. |

---

## Next actions

In this order. Each step adds specs for what it changes.

1. **Quick wins** ✅
   - **Long titles.** Split long titles at word or CamelCase boundaries
     ("LongestNameEver" → "Longest\nNameEver"), and grow the node box to fit
     the text instead of overflowing it.
   - **Polarity flips.** A single click on a link toggles +/−, which is easy
     to do by accident (it happened while taking screenshots). Flash the link
     and show a toast ("Mining → IslandIncome is now −  [Undo]"). The Undo
     later moves into the general undo system (step 4).
   - **Clear chat** button in the AI panel header.
   - **Keep the AI conversation across reloads,** in browser storage (per
     browser, per diagram). Server-side storage is listed under "Later".
2. **Editor specs.** ✅ System specs (Capybara with headless Chrome, already
   provided by decidim-dev and set up in CI) for the editor's JavaScript:
   add, rename, move and delete nodes; links and polarity; auto-layout; the
   AI panel with a stubbed agent; the clear-diagram dialog. A safety net
   before the undo/redo refactor.
3. **Loops.** ✅
   - **`find_loops` tool for the AI assistant.** Asked to "list all the
     loops", gpt-oss:20b reasoned for 80 s with no tool, and models are
     unreliable at finding cycles anyway. Find every cycle on the server (a
     DFS is fine at this size; Johnson's algorithm if diagrams grow), label
     each R or B by counting negative links, and let the model only explain
     the result. Removes the README's "does not find loops" limitation.
   - **Loops in the editor.** A panel listing the loops with R/B labels;
     selecting one highlights its nodes and links on the canvas. Reuses the
     same cycle detection.
4. **Undo/redo.** ✅ See "Undo/redo" below.
5. **Save to file and load from file.** ✅ A full-fidelity file (titles,
   positions, sizes, fonts, polarity, bends) and a load that replaces the
   diagram or adds it beside, merging variables with the same name. Undoable.
   Replaced Export JSON, whose files still load.
Also done: **Diagram help** panel; **integration specs** for the CoP site
(admin screens, permissions, access, seeds), which found and fixed an
unreachable Editors screen, missing translations and readable trashed
components.

6. **Streaming AI replies.** ✅ As progress, not text: the agent endpoint
   streams NDJSON (ActionController::Live) with a "progress" event after each
   tool call, carrying that call's changes, then "done" or "error". The
   editor shows the steps and draws the changes as they come, and records
   the reply as one undo step. Streaming the reply's words was skipped: it
   needs streaming code per provider, and the replies are a few sentences.

**Marcello:** deploying to the Rurbanive CoP Decidim instance, and Decidim
integration (search, activity feed, linking from proposals). First: which
Decidim version the CoP site runs. The gemspec pins `decidim-core` to exactly
0.31.3, so any other version needs the pin loosened and CI run against it.

**Open questions:**
- The README's Security section still has a placeholder address.
- Interface text is English only; translations would need the strings moved
  into `config/locales`.

**Later:**
- **AI conversation on the server.** Store conversations per user and
  diagram, so they follow people across devices and could be shown to other
  editors. Step 1 keeps them in browser storage only.

**Parked:**
- More AI providers (Gemini, Azure OpenAI): until one is needed.
- Real-time collaboration: until we know what Decidim's conventions are.

---

## Undo/redo

Built as planned, with the command pattern, but simpler in two ways.

**Soft delete.** Nodes and links have `deleted_at`. Deleting only marks a
record, so it keeps its ID and every older step in the history still refers
to the right record. A default scope hides marked rows from every read,
including the AI assistant's. `DeletedRecords.purge!` (rake
`decidim_causal_loop:purge_deleted`) removes rows deleted over 30 days ago.

**Commands are operation lists.** Instead of one class per kind of edit,
every edit is a list of operations and its inverse:
`{op: "update", type, id, attrs}`, `{op: "delete", type, id}` and
`{op: "restore", type, id, snapshot}` (the snapshot redraws the element;
the server ignores it). The inverse of a delete is a restore, and redoing a
creation is a restore too, so nothing is ever re-created. A step made of
several changes (`combine`) concatenates the lists and reverses the
inverses; that is the Macro. Each list is sent to `POST operations` and
applied in one transaction, so an undo happens completely or not at all.

**CommandManager** (`command_manager.js`) keeps the undo and redo stacks
(100 entries) and runs everything through one promise queue. `execute`
runs a command; `record` remembers one that has already happened (a node
the server created, an AI reply). A command whose undo or redo fails is
dropped with a toast, and the rest of the history is kept.

| Edit | How it is recorded |
|---|---|
| Add node, then name it | `record`; naming it amends the same step |
| Rename, resize, font size | `execute` of attribute updates |
| Drag, one or several nodes | `execute`, one step per drag (grab/free) |
| Add link | `record` |
| Flip polarity | `execute`; the toast's Undo is the same undo |
| Bend a link | `execute` on release |
| Delete selection | `execute`; links are deleted explicitly before nodes |
| Auto-layout | `execute` with a first `run` that only saves, since the nodes are already animating |
| AI reply | `record`; inverses are taken from the canvas before each action, so the server sends no previous values |
| Confirmed clear | `execute` of a delete, a step of its own |

**Not done, possibly later:** the clear-diagram dialog stays (it now says
the deletion can be undone). Undo history does not survive a reload, and
there is no optimistic locking: an undo over someone else's later change to
the same record silently overwrites it, while an undo of a record that is
gone fails with a message.

---

## Parked: details

- **More AI providers.** The agent interface is deliberately small —
  `run(system:, messages:, tools:)` yielding tool calls — so a provider is one
  class plus an entry in `AgentProviders::PROVIDERS`. Any OpenAI-compatible
  endpoint is already covered by `OpenaiCompatibleAgent`. Still worth adding:
  - **Google Gemini**, which uses a different shape (`functionDeclarations`,
    `functionCall` / `functionResponse` parts) and so needs its own adapter.
  - **Azure OpenAI**, same dialect as OpenAI but different auth and URL layout.
  Providers should also declare whether they support tool calling — some small local models do not, and should degrade to
  answering questions rather than failing silently.
