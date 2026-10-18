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
      ├── AnthropicAgent         (paid, Anthropic API)
      └── OpenaiCompatibleAgent  (OpenAI, OpenRouter, TensorX, vLLM, ...)
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

It also has batch tools — `create_nodes`, `create_links` (nodes referenced by
title or ID) and `clear_diagram` — because small local models such as
gpt-oss make exactly one tool call per round. With single-item tools only, a
12-node, 23-link diagram needed ~40 rounds and hit the cap after 3 nodes; with
batch tools it takes 3–4. The model cannot choose node positions: it placed
nodes 100 px apart, overlapping them, so placement is always automatic.

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

## Next actions

In this order. Each step adds specs for what it changes.

1. **Quick wins**
   - **Long titles.** Split long titles at word or CamelCase boundaries
     ("LongestNameEver" → "Longest\nNameEver"), and grow the node box to fit
     the text instead of overflowing it.
   - **Polarity flips.** A single click on a link toggles +/−, which is easy
     to do by accident (it happened while taking screenshots). Flash the link
     and show a toast ("Mining → IslandIncome is now −  [Undo]"). The Undo
     later moves into the general undo system (step 4).
   - **Clear chat** button in the AI panel header.
   - **Keep the AI conversation across reloads.** Start with browser storage
     (per browser, per diagram). Server-side storage per user and diagram is
     the later option, if it should follow people across devices.
2. **Editor specs.** System specs (Capybara with headless Chrome, already
   provided by decidim-dev and set up in CI) for the editor's JavaScript:
   add, rename, move and delete nodes; links and polarity; auto-layout; the
   AI panel with a stubbed agent; the clear-diagram dialog. A safety net
   before the undo/redo refactor.
3. **Loops.**
   - **`find_loops` tool for the AI assistant.** Asked to "list all the
     loops", gpt-oss:20b reasoned for 80 s with no tool, and models are
     unreliable at finding cycles anyway. Find every cycle on the server (a
     DFS is fine at this size; Johnson's algorithm if diagrams grow), label
     each R or B by counting negative links, and let the model only explain
     the result. Removes the README's "does not find loops" limitation.
   - **Loops in the editor.** A panel listing the loops with R/B labels;
     selecting one highlights its nodes and links on the canvas. Reuses the
     same cycle detection.
4. **Undo/redo.** See the plan below.
5. **Save to file and load from file.** A full-fidelity file (titles,
   positions, sizes, fonts, polarity, bends), unlike today's exports, and an
   import that replaces the diagram or adds to it. After undo/redo so that a
   load can be undone. Today's backups use `../backups/restore.rb`, outside
   the repo.
6. **Streaming AI replies.** Show the reply as it is written instead of
   "Thinking…" for up to a minute. Needs a streaming response (SSE or
   ActionController::Live) that also reports tool calls as they happen, and
   streaming support in each provider. Check the complexity before going
   deep.

**Marcello:** deploying to the Rurbanive CoP Decidim instance, and Decidim
integration (search, activity feed, linking from proposals).

**Parked:**
- More AI providers (Gemini, Azure OpenAI): until one is needed.
- Real-time collaboration: until we know what Decidim's conventions are.

---

## Plan: undo/redo with the command pattern

### Goal

Undo and redo every change an editor makes to the diagram, including a
whole AI assistant reply as a single step. Toolbar buttons plus
<kbd>Ctrl/Cmd+Z</kbd> and <kbd>Ctrl/Cmd+Shift+Z</kbd> (and <kbd>Ctrl+Y</kbd>).
The history covers the current page session in this browser; it is not
shared between editors and is lost on reload.

### Where changes happen today

Every mutation is an ad-hoc `apiRequest` inside an event handler, and the
canvas is updated separately. These are the call sites the refactor must
cover:

| User action | Code today | Command |
|---|---|---|
| Add node (button, double-click) | `addNodeAt` | `AddNode` |
| Rename (inline edit) | `startInlineEdit` → `save` | `RenameNode` |
| Drag one or several nodes | `dragfree` handler | `MoveNodes` |
| Width/height, font size | `resizeSelected`, `fontSizeSelected` | `ResizeNodes`, `SetFontSize` |
| Add link (C key, button) | `createLink` | `AddLink` |
| Toggle polarity | edge `tap` handler | `SetPolarity` |
| Bend a link | bend handle `onUp` | `BendLink` |
| Delete selected | `deleteSelected` | `DeleteElements` |
| Auto-layout | `autoLayout` | `MoveNodes` + `BendLink`s, as one `Macro` |
| AI assistant reply | `applyActions` | `Macro` of the reply's actions |
| Confirmed clear | `confirmClear` | `DeleteElements` |

### Design

**Command interface.** Each command is an object with `label` (shown in
the button tooltip: "Undo move 3 nodes"), and async `do()` and `undo()`. Both
call the server *and* update Cytoscape, so a command is the only place that
knows how to apply and reverse its change. Commands carry plain data (titles,
positions, polarity), never Cytoscape element references, which do not
survive a delete and re-create.

**CommandManager.** Owns an undo stack and a redo stack (capped at about
100 entries).
- `execute(cmd)` runs `do()`, pushes the command onto the undo stack and
  clears the redo stack.
- `record(cmd)` pushes a command whose effect has already happened. Drags
  and AI replies are applied before we know to record them, so they use this
  instead of `execute`.
- `undo()` / `redo()` move commands between the stacks.

All calls go through one promise queue, so a fast double <kbd>Ctrl+Z</kbd>
cannot interleave two requests. The buttons are disabled while the queue is
busy, and while the stacks are empty.

**Macro.** A composite holding a list of commands. `do()` runs them in
order and `undo()` runs their undos in reverse. Used for auto-layout, an AI
reply, and a multi-selection delete.

### The hard part: IDs after undoing a delete

Undoing a delete must bring the node back. If that means creating a new
record, it gets a new ID, and every older command in the history that names
the old ID (a rename, a link to it) breaks.

**Recommended: soft delete on the server.**
- Add `deleted_at` to nodes and links.
- `destroy` sets it instead of deleting the row; deleting a node also
  soft-deletes its links in the same transaction.
- A `restore` endpoint clears it.
- All reads (`index`, `list_graph`, the agent's queries) scope to
  `deleted_at: nil`.

IDs never change, so every command can keep using database IDs and undo of a
delete is simply restore. A periodic purge (rake task) removes rows deleted
more than, say, 30 days ago. This also lays the groundwork for a future
history view.

*Alternative, rejected:* keep client-side keys and an ID map that is
rewritten whenever a record is re-created. It works without a migration,
but every command has to go through the map, and the map also has to be
rewritten for links that were re-created because a node was. That's easy
to get subtly wrong.

### Batch endpoint

An AI reply or an auto-layout can touch 30+ records. Add
`POST /operations`, which takes an ordered list of
`{op: create|update|delete|restore, type: node|link, id, attrs}`, runs it
in one transaction and returns the new IDs. Macros send one request, so an
undo applies completely or not at all. Single commands may keep using the
existing REST endpoints.

### AI replies

The agent already returns `actions`. For undo the browser needs the
previous state:
- `update_node` and `update_link` actions gain the old values (`previous`).
- With soft delete, `remove_*` needs only the ID.

`applyActions` then records one `Macro` labelled "AI: <first words of the
request>". Undoing it reverses the whole reply.

Once this exists, `clear_diagram` can delete immediately (soft) and the
confirmation dialog can go: undo becomes the safety net, which interrupts
less. Decide when we get there.

### Concurrency

The editor has no real-time sync, so another editor may have changed or
deleted something since. An undo whose request fails (404, or a node that
was hard-purged) shows "Could not undo: the diagram has changed", drops that
entry, and leaves the rest of the history alone. Optimistic locking
(`lock_version`) is a possible later addition. Not needed for the first
version.

### UI

- **Buttons:** Undo and Redo in the edit toolbar, with the command label as
  tooltip.
- **Shortcuts:** added to the existing `keydown` handler. Ignored while
  typing in an input or textarea, so the browser's own text undo still works
  there.

### Phases

1. **Soft delete.** Migration, model scopes, `restore` endpoints, specs.
   Read paths must exclude deleted rows. Request specs.
2. **CommandManager and commands for direct edits.** Route every call site
   in the table except AI and auto-layout through commands. Add the buttons
   and shortcuts.
3. **Batch endpoint and Macro.** Auto-layout and multi-delete as macros.
4. **AI replies as undoable macros.** Add `previous` to the agent's update
   actions. Revisit the clear-diagram dialog.

**Tests.** There is no JavaScript test runner yet. Either add system specs
(Capybara with headless Chrome, which decidim-dev already sets up) covering
undo and redo of add, move, delete and an AI reply with a stubbed agent; or
add a small JS unit-test runner for CommandManager. System specs are
recommended, since they also cover the server side.

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
