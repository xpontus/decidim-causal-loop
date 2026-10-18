import { Controller } from "@hotwired/stimulus";
import cytoscape from "cytoscape";
import CommandManager from "./command_manager";

export default class extends Controller {
  static values = {
    nodes: Array,
    links: Array,
    nodesUrl: String,
    linksUrl: String,
    conversationsUrl: String,
    loopsUrl: String,
    operationsUrl: String,
    editable: Boolean,
    csrfToken: String
  }

  connect() {
    this.hoveredNode      = null;
    this.cLinkMode        = false;
    this.cLinkSource      = null;
    this.buttonLinkMode   = false;
    this.buttonLinkSource = null;
    this.bendHandle       = null;   // { els: [el, el], edge }
    this.edgeTapTimer     = null;
    this.chatHistory      = [];
    this.cyContainer      = this.element.querySelector("#cy");

    this.cy = cytoscape({
      container: this.cyContainer,
      style: this.graphStyles(),
      elements: this.buildElements(),
      layout: { name: "preset" }
    });

    // Apply stored two-point bezier styles to edges that have bend data
    this.cy.edges().forEach(edge => {
      const cp1 = edge.data("cp1Distance");
      const cp2 = edge.data("cp2Distance");
      if (cp1 !== 0 || cp2 !== 0) {
        this.applyBendStyle(edge, cp1, cp2);
      }
    });

    // Recompute the wrapped label and box size whenever a node is added or
    // its title, size or font changes, wherever the change came from.
    this.cy.on("add data", "node", (evt) => this.refreshLabel(evt.target));

    // The "No nodes yet" hint is rendered by the server; keep it in step.
    this.cy.on("add remove", "node", () => {
      const hint = this.element.querySelector("#cl-empty-hint");
      if (hint) hint.hidden = this.cy.nodes().length > 0;
    });

    if (this.editableValue) this.setupEditing();
    this.setupViewControls();
    if (this.editableValue) this.setupChat();
  }

  graphStyles() {
    return [
      {
        selector: "node",
        style: {
          "background-color": "#4a90d9",
          "label": "data(displayLabel)",
          "color": "#fff",
          "text-valign": "center",
          "text-halign": "center",
          "width": "data(displayWidth)",
          "height": "data(displayHeight)",
          "font-size": "data(fontSize)",
          "shape": "round-rectangle",
          "text-wrap": "wrap",
          "text-max-width": "data(displayWidth)"
        }
      },
      { selector: "node:selected",   style: { "border-width": 3, "border-color": "#f0a500" } },
      { selector: "node.link-source", style: { "border-width": 3, "border-color": "#9b59b6", "background-color": "#6c3483" } },
      {
        selector: "edge[polarity='positive']",
        style: {
          "width": 2,
          "curve-style": "bezier",
          "line-color": "#27ae60",
          "target-arrow-color": "#27ae60",
          "target-arrow-shape": "triangle",
          "label": "+",
          "font-size": "16px",
          "color": "#27ae60",
          "text-background-color": "#fff",
          "text-background-opacity": 1,
          "text-background-padding": "2px"
        }
      },
      {
        selector: "edge[polarity='negative']",
        style: {
          "width": 2,
          "curve-style": "bezier",
          "line-color": "#e74c3c",
          "target-arrow-color": "#e74c3c",
          "target-arrow-shape": "triangle",
          "line-style": "dashed",
          "label": "−",
          "font-size": "16px",
          "color": "#e74c3c",
          "text-background-color": "#fff",
          "text-background-opacity": 1,
          "text-background-padding": "2px"
        }
      },
      { selector: "edge:selected", style: { "width": 4 } },
      { selector: ".cl-dim", style: { "opacity": 0.2 } },
      { selector: "node.cl-in-loop", style: { "border-width": 3, "border-color": "#f0a500" } },
      { selector: "edge.cl-in-loop", style: { "width": 4 } },
      {
        selector: "edge.cl-flash",
        style: { "width": 5, "underlay-color": "#f0a500", "underlay-opacity": 0.6, "underlay-padding": 6 }
      }
    ];
  }

  buildElements() {
    return [...this.nodesValue.map(n => this.nodeElement(n)), ...this.linksValue.map(l => this.linkElement(l))];
  }

  // Canvas elements from records in the server's format, which is also the
  // format of the snapshots that undo uses to bring deleted elements back.
  nodeElement(n) {
    return {
      data: {
        id:       `n${n.id}`,
        label:    n.title,
        dbId:     n.id,
        width:    n.width     ?? 130,
        height:   n.height    ?? 44,
        fontSize: n.font_size ?? 13,
        ...this.labelLayout(n.title, n.width ?? 130, n.height ?? 44, n.font_size ?? 13)
      },
      position: { x: n.position_x ?? 150, y: n.position_y ?? 150 }
    };
  }

  linkElement(l) {
    return {
      data: {
        id:          `l${l.id}`,
        source:      `n${l.source_node_id}`,
        target:      `n${l.target_node_id}`,
        polarity:    l.polarity,
        dbId:        l.id,
        cp1Distance: l.cp1_distance ?? 0,
        cp2Distance: l.cp2_distance ?? 0
      }
    };
  }

  nodeSnapshot(node) {
    const pos = node.position();
    return {
      id: node.data("dbId"), title: node.data("label"), position_x: pos.x, position_y: pos.y,
      width: node.data("width"), height: node.data("height"), font_size: node.data("fontSize")
    };
  }

  linkSnapshot(edge) {
    return {
      id: edge.data("dbId"), source_node_id: edge.source().data("dbId"), target_node_id: edge.target().data("dbId"),
      polarity: edge.data("polarity"), cp1_distance: edge.data("cp1Distance"), cp2_distance: edge.data("cp2Distance")
    };
  }

  // ---- Node labels ----

  // Lays a title out on as many lines as needed to fit the node's width,
  // breaking at spaces first and, inside a long word, at CamelCase, "_" and
  // "-" boundaries ("GovernmentRegulation" → "Government\nRegulation"). The box
  // grows when a piece still does not fit, or when the lines need more height.
  // The stored width and height are minimums; they are not changed.
  labelLayout(title, width, height, fontSize) {
    const padding = 16;
    const maxText = width - padding;
    this.measureCtx ||= document.createElement("canvas").getContext("2d");
    this.measureCtx.font = `${fontSize}px "Helvetica Neue", Helvetica, sans-serif`;
    const measure = (text) => this.measureCtx.measureText(text).width;

    const lines = [];
    let line = "";
    for (const word of String(title ?? "").split(/\s+/).filter(Boolean)) {
      const joined = line ? `${line} ${word}` : word;
      if (measure(joined) <= maxText) { line = joined; continue; }
      if (line) { lines.push(line); line = ""; }
      if (measure(word) <= maxText) { line = word; continue; }

      for (const piece of word.split(/(?<=[a-z0-9])(?=[A-Z])|(?<=[_-])/)) {
        if (!line || measure(line + piece) <= maxText) { line += piece; continue; }
        lines.push(line);
        line = piece;
      }
    }
    if (line) lines.push(line);
    if (lines.length === 0) lines.push("");

    const textWidth = Math.max(...lines.map(measure));
    return {
      displayLabel:  lines.join("\n"),
      displayWidth:  Math.max(width, Math.ceil(textWidth) + padding),
      displayHeight: Math.max(height, Math.ceil(lines.length * fontSize * 1.25) + 14)
    };
  }

  refreshLabel(node) {
    const layout = this.labelLayout(node.data("label"), node.data("width") ?? 130,
                                    node.data("height") ?? 44, node.data("fontSize") ?? 13);
    // Only write when something changed: writing fires another "data" event.
    if (Object.keys(layout).some(key => node.data(key) !== layout[key])) node.data(layout);
  }

  // Apply unbundled-bezier style with two control points to an edge
  applyBendStyle(edge, cp1, cp2) {
    edge.style("curve-style", "unbundled-bezier");
    edge.style("control-point-distances", `${cp1} ${cp2}`);
    edge.style("control-point-weights", "0.25 0.75");
  }

  setupEditing() {
    this.setupUndo();
    this.cy.on("mouseover", "node", (evt) => { this.hoveredNode = evt.target; });
    this.cy.on("mouseout",  "node", () =>     { this.hoveredNode = null; });

    // Double-click empty canvas → add node
    this.cy.on("dblclick", (evt) => {
      if (evt.target === this.cy) this.addNodeAt(evt.position.x, evt.position.y);
    });

    // Double-click node → rename
    this.cy.on("dblclick", "node", (evt) => {
      this.startInlineEdit(evt.target);
    });

    // Single tap edge → toggle polarity (debounced so dblclick can cancel it)
    this.cy.on("tap", "edge", (evt) => {
      if (this.bendHandle) return;
      const edge = evt.target;
      clearTimeout(this.edgeTapTimer);
      this.edgeTapTimer = setTimeout(() => {
        const newPolarity = edge.data("polarity") === "positive" ? "negative" : "positive";
        this.setPolarity(edge, newPolarity, { notify: true });
      }, 300);
    });

    // Double-click edge → bend handles
    this.cy.on("dblclick", "edge", (evt) => {
      clearTimeout(this.edgeTapTimer);
      this.showBendHandles(evt.target);
    });

    // Tap or mouseup on node → complete C-key or button link
    this.cy.on("tap", "node", (evt) => {
      const node = evt.target;

      if (this.cLinkMode && this.cLinkSource) {
        if (node.id() !== this.cLinkSource.id()) {
          this.createLink(this.cLinkSource.data("dbId"), node.data("dbId"), "positive");
          this.cancelCLink();
        }
        return;
      }

      if (this.buttonLinkMode) {
        if (!this.buttonLinkSource) {
          this.buttonLinkSource = node;
          node.addClass("link-source");
          this.updateStatus("Click the target node");
        } else if (node.id() !== this.buttonLinkSource.id()) {
          this.createLink(this.buttonLinkSource.data("dbId"), node.data("dbId"), "positive");
          this.buttonLinkSource.removeClass("link-source");
          this.buttonLinkSource = null;
          this.exitButtonLinkMode();
        }
        return;
      }
    });

    // Tap empty canvas → cancel any active mode
    this.cy.on("tap", (evt) => {
      if (evt.target !== this.cy) return;
      if (this.cLinkMode) { this.cancelCLink(); return; }
      if (this.buttonLinkMode) { this.exitButtonLinkMode(); return; }
      this.removeBendHandles();
    });

    // Save positions after a drag, as one step however many nodes moved.
    // Cytoscape fires grab and free once per dragged node, so the positions
    // are noted at the first grab and compared once all are released.
    this.cy.on("grab", "node", () => {
      this.dragStart ||= new Map(this.cy.nodes().map(n => [n.id(), { ...n.position() }]));
    });
    this.cy.on("free", "node", () => {
      clearTimeout(this.dragTimer);
      this.dragTimer = setTimeout(() => this.finishDrag(), 0);
    });

    // Keyboard
    this.onKeyDown = (e) => {
      if (["INPUT", "TEXTAREA"].includes(e.target.tagName) || e.target.isContentEditable) return;
      if ((e.ctrlKey || e.metaKey) && !e.altKey) {
        const key = e.key.toLowerCase();
        if (key === "z" || key === "y") {
          e.preventDefault();
          if (key === "z" && !e.shiftKey) this.undo();
          else this.redo();
        }
        return;
      }
      if ((e.key === "c" || e.key === "C") && !this.cLinkMode && this.hoveredNode) {
        this.startCLink(this.hoveredNode);
      }
      if (e.key === "Escape") {
        e.stopPropagation();
        this.cancelCLink();
        this.exitButtonLinkMode();
        this.removeBendHandles();
      }
      if (e.key === "Delete" || e.key === "Backspace") this.deleteSelected();
    };
    document.addEventListener("keydown", this.onKeyDown, true);

    // Toolbar buttons — graph operations
    this.element.querySelector("#btn-add-node")?.addEventListener("click", () => this.addNode());
    this.element.querySelector("#btn-add-link")?.addEventListener("click", () => this.toggleButtonLinkMode());
    this.element.querySelector("#btn-delete")  ?.addEventListener("click", () => this.deleteSelected());

    // Toolbar buttons — node size / font
    this.element.querySelector("#btn-node-wider")   ?.addEventListener("click", () => this.resizeSelected( 20,  0));
    this.element.querySelector("#btn-node-narrower") ?.addEventListener("click", () => this.resizeSelected(-20,  0));
    this.element.querySelector("#btn-node-taller")  ?.addEventListener("click", () => this.resizeSelected(  0, 10));
    this.element.querySelector("#btn-node-shorter") ?.addEventListener("click", () => this.resizeSelected(  0,-10));
    this.element.querySelector("#btn-font-larger")  ?.addEventListener("click", () => this.fontSizeSelected( 2));
    this.element.querySelector("#btn-font-smaller") ?.addEventListener("click", () => this.fontSizeSelected(-2));

    this.element.querySelector("#btn-layout")?.addEventListener("click", () => this.autoLayout());
  }

  // ---- Undo and redo ----

  // Every edit is a list of operations on the server and the canvas, with
  // its inverse: { op: "update", type, id, attrs }, { op: "delete", type,
  // id } and { op: "restore", type, id, snapshot }. Deleting only marks a
  // record on the server, so records keep their IDs and the inverse of a
  // delete is a restore. Each list is sent as one request and applied in one
  // transaction.
  setupUndo() {
    this.undoButton = this.element.querySelector("#btn-undo");
    this.redoButton = this.element.querySelector("#btn-redo");
    this.commands = new CommandManager({
      onChange: () => this.updateUndoButtons(),
      onError: (error, command, action) => {
        const verb = { do: "Could not", undo: "Could not undo", redo: "Could not redo" }[action];
        this.showToast(`${verb} ${command.label}: ${error.message}. Reload the page to see the current diagram.`,
                       { duration: 10000 });
      }
    });
    this.undoButton?.addEventListener("click", () => this.undo());
    this.redoButton?.addEventListener("click", () => this.redo());
    this.updateUndoButtons();
  }

  undo() {
    this.removeBendHandles();
    this.hideToast();
    return this.commands.undo();
  }

  redo() {
    this.removeBendHandles();
    this.hideToast();
    return this.commands.redo();
  }

  updateUndoButtons() {
    const shortcut = /Mac|iPhone|iPad/.test(navigator.platform) ? "⌘" : "Ctrl+";
    if (this.undoButton) {
      this.undoButton.disabled = !this.commands.canUndo;
      this.undoButton.title = this.commands.undoLabel ? `Undo ${this.commands.undoLabel} (${shortcut}Z)` : "Nothing to undo";
    }
    if (this.redoButton) {
      this.redoButton.disabled = !this.commands.canRedo;
      this.redoButton.title = this.commands.redoLabel ? `Redo ${this.commands.redoLabel} (${shortcut}Shift+Z)` : "Nothing to redo";
    }
  }

  updateOp(type, id, attrs) { return { op: "update", type, id, attrs }; }

  deleteOp(type, id) { return { op: "delete", type, id }; }

  restoreOp(type, snapshot) { return { op: "restore", type, id: snapshot.id, snapshot }; }

  // A command from operations and their inverse, in the order each is to be
  // applied.
  change(label, forward, backward) {
    return {
      label, forward, backward,
      do:   () => this.applyOperations(forward),
      undo: () => this.applyOperations(backward)
    };
  }

  // One step made of several changes; undone in reverse order.
  combine(label, changes) {
    return this.change(label, changes.flatMap(c => c.forward), changes.slice().reverse().flatMap(c => c.backward));
  }

  updateChange(label, type, id, before, after) {
    return this.change(label, [this.updateOp(type, id, after)], [this.updateOp(type, id, before)]);
  }

  // Deleting nodes deletes their links too; these are deleted explicitly
  // first, so undo knows exactly what to bring back.
  deleteChange(label, nodes, edges = this.cy.collection()) {
    const links = edges.union(nodes.connectedEdges());
    return this.change(label,
      [...links.map(e => this.deleteOp("link", e.data("dbId"))), ...nodes.map(n => this.deleteOp("node", n.data("dbId")))],
      [...nodes.map(n => this.restoreOp("node", this.nodeSnapshot(n))), ...links.map(e => this.restoreOp("link", this.linkSnapshot(e)))]);
  }

  async applyOperations(operations, { canvas = true } = {}) {
    const resp = await this.apiRequest(this.operationsUrlValue, "POST", {
      operations: operations.map(({ snapshot, ...operation }) => operation)
    });
    if (!resp.ok) {
      const body = await resp.json().catch(() => ({}));
      throw new Error((body.errors || []).join(", ") || `error ${resp.status}`);
    }
    if (canvas) operations.forEach(operation => this.applyToCanvas(operation));
  }

  applyToCanvas({ op, type, id, attrs, snapshot }) {
    const element = this.cy.getElementById(`${type === "node" ? "n" : "l"}${id}`);
    if (op === "update" && element.length) {
      if (type === "node") this.setNodeAttributes(element, attrs);
      else this.setLinkAttributes(element, attrs);
    } else if (op === "delete") {
      if (this.bendHandle && element.union(element.connectedEdges()).contains(this.bendHandle.edge)) this.removeBendHandles();
      element.remove();
    } else if (op === "restore" && !element.length) {
      if (type === "node") this.cy.add(this.nodeElement(snapshot));
      else this.setLinkAttributes(this.cy.add(this.linkElement(snapshot)), snapshot);
    }
  }

  setNodeAttributes(node, attrs) {
    const data = {};
    if ("title" in attrs) data.label = attrs.title;
    if ("width" in attrs) data.width = attrs.width;
    if ("height" in attrs) data.height = attrs.height;
    if ("font_size" in attrs) data.fontSize = attrs.font_size;
    if (Object.keys(data).length) node.data(data);
    if ("position_x" in attrs || "position_y" in attrs) {
      node.position({ x: attrs.position_x ?? node.position("x"), y: attrs.position_y ?? node.position("y") });
    }
  }

  setLinkAttributes(edge, attrs) {
    if ("polarity" in attrs) edge.data("polarity", attrs.polarity);
    if ("cp1_distance" in attrs || "cp2_distance" in attrs) {
      const cp1 = attrs.cp1_distance ?? edge.data("cp1Distance") ?? 0;
      const cp2 = attrs.cp2_distance ?? edge.data("cp2Distance") ?? 0;
      edge.data({ cp1Distance: cp1, cp2Distance: cp2 });
      if (cp1 || cp2) this.applyBendStyle(edge, cp1, cp2);
      else edge.removeStyle("curve-style control-point-distances control-point-weights");
    }
  }

  finishDrag() {
    const start = this.dragStart;
    this.dragStart = null;
    if (!start) return;
    const moved = this.cy.nodes().filter(n => {
      const from = start.get(n.id());
      return from && (from.x !== n.position("x") || from.y !== n.position("y"));
    });
    if (moved.length === 0) return;

    this.removeBendHandles();
    const changes = moved.map(n => {
      const from = start.get(n.id());
      return this.updateChange("", "node", n.data("dbId"), { position_x: from.x, position_y: from.y },
                               { position_x: n.position("x"), position_y: n.position("y") });
    });
    const label = moved.length === 1 ? `move “${moved[0].data("label")}”` : `move ${moved.length} nodes`;
    this.commands.execute(this.combine(label, changes));
  }

  // ---- Automatic layout ----

  // Rearranges the diagram with Cytoscape's built-in force-directed "cose"
  // layout: links act as springs, nodes repel each other. Only cose's
  // arrangement is kept; it is rescaled to the canvas's shape (cose tends to
  // produce tall, sparse layouts) and then overlapping boxes are pushed
  // apart, since cose treats nodes almost as points and ours are wide
  // rectangles. The layout starts from random positions, so pressing the
  // button again gives a different arrangement. Bends are reset, since they
  // were drawn for the old positions. The result is saved, as one step that
  // can be undone.
  autoLayout() {
    if (this.cy.nodes().length === 0) return;
    this.removeBendHandles();

    const layout = this.cy.layout({
      name: "cose",
      animate: false,
      fit: false,
      randomize: true,
      idealEdgeLength: () => 120,
      nodeRepulsion: () => 20000,
      nodeOverlap: 40,
      componentSpacing: 80,
      gravity: 0.8
    });

    // The layout is computed without animation and only then animated into
    // place, so saving never waits on animation frames (which a background
    // tab does not get).
    const start = new Map(this.cy.nodes().map(n => [n.id(), { ...n.position() }]));
    layout.one("layoutstop", () => {
      const boxes = this.cy.nodes().map(n => ({
        node: n, x: n.position("x"), y: n.position("y"),
        w: n.data("displayWidth") ?? 130, h: n.data("displayHeight") ?? 44
      }));
      this.scaleToCanvas(boxes);
      this.removeOverlaps(boxes);
      boxes.forEach(b => { b.x = Math.round(b.x); b.y = Math.round(b.y); });

      boxes.forEach(b => b.node.position(start.get(b.node.id())));
      this.cy.layout({
        name: "preset",
        positions: (n) => { const b = boxes.find(x => x.node === n); return { x: b.x, y: b.y }; },
        animate: true,
        animationDuration: 500,
        fit: true,
        padding: 40,
        stop: () => { if (this.cy.zoom() > 1) this.cy.zoom(1).center(); }
      }).run();

      this.saveLayout(boxes, start);
    });
    layout.run();
  }

  // Rescales positions so the layout has the canvas's aspect ratio and gives
  // each node a cell of roughly cellWidth x cellHeight.
  scaleToCanvas(boxes, cellWidth = 230, cellHeight = 110) {
    const xs = boxes.map(b => b.x);
    const ys = boxes.map(b => b.y);
    const minX = Math.min(...xs);
    const minY = Math.min(...ys);
    const aspect = this.cy.width() / this.cy.height();
    const width  = Math.sqrt(boxes.length * cellWidth * cellHeight * aspect);
    const height = width / aspect;
    const scaleX = width  / ((Math.max(...xs) - minX) || 1);
    const scaleY = height / ((Math.max(...ys) - minY) || 1);
    boxes.forEach(b => {
      b.x = (b.x - minX) * scaleX;
      b.y = (b.y - minY) * scaleY;
    });
  }

  // Moves overlapping boxes apart along the axis where they overlap least,
  // until there is at least a gap between every pair (or it gives up).
  removeOverlaps(boxes, gapX = 30, gapY = 20) {
    for (let iteration = 0; iteration < 300; iteration++) {
      let moved = false;
      for (let i = 0; i < boxes.length; i++) {
        for (let j = i + 1; j < boxes.length; j++) {
          const a = boxes[i];
          const b = boxes[j];
          const dx = b.x - a.x;
          const dy = b.y - a.y;
          const overlapX = (a.w + b.w) / 2 + gapX - Math.abs(dx);
          const overlapY = (a.h + b.h) / 2 + gapY - Math.abs(dy);
          if (overlapX <= 0 || overlapY <= 0) continue;

          moved = true;
          if (overlapX / (a.w + b.w) < overlapY / (a.h + b.h)) {
            const shift = (dx >= 0 ? 1 : -1) * overlapX / 2;
            a.x -= shift; b.x += shift;
          } else {
            const shift = (dy >= 0 ? 1 : -1) * overlapY / 2;
            a.y -= shift; b.y += shift;
          }
        }
      }
      if (!moved) return;
    }
  }

  // The nodes are already animating into place, so the first run only
  // resets the bends on the canvas and saves; undo and redo move the nodes.
  async saveLayout(boxes, start) {
    const moves = boxes.map(b => {
      const from = start.get(b.node.id());
      return this.updateChange("", "node", b.node.data("dbId"), { position_x: from.x, position_y: from.y },
                               { position_x: b.x, position_y: b.y });
    });
    const bends = this.cy.edges().filter(e => e.data("cp1Distance") || e.data("cp2Distance")).map(e =>
      this.updateChange("", "link", e.data("dbId"),
                        { cp1_distance: e.data("cp1Distance"), cp2_distance: e.data("cp2Distance") },
                        { cp1_distance: 0, cp2_distance: 0 }));
    const command = this.combine("auto-layout", [...moves, ...bends]);
    command.run = async () => {
      bends.forEach(b => b.forward.forEach(operation => this.applyToCanvas(operation)));
      await this.applyOperations(command.forward, { canvas: false });
      this.updateStatus("Layout saved");
      setTimeout(() => this.updateStatus(""), 3000);
    };

    this.updateStatus("Saving layout…");
    await this.commands.execute(command);
  }

  // ---- Confirmation dialog ----

  // Resolves to true if the user confirms. Uses a native <dialog>, so it is
  // modal, closes on Escape (as a cancel) and keeps focus inside.
  confirmDialog({ title, message, confirmLabel, cancelLabel }) {
    const dialog = this.element.querySelector("#cl-confirm");
    if (!dialog?.showModal) return Promise.resolve(false);

    dialog.querySelector("#cl-confirm-title").textContent   = title;
    dialog.querySelector("#cl-confirm-message").textContent = message;
    const ok     = dialog.querySelector("#cl-confirm-ok");
    const cancel = dialog.querySelector("#cl-confirm-cancel");
    ok.textContent     = confirmLabel;
    cancel.textContent = cancelLabel;

    return new Promise(resolve => {
      const finish = (result) => {
        ok.removeEventListener("click", onOk);
        cancel.removeEventListener("click", onCancel);
        dialog.removeEventListener("close", onClose);
        if (dialog.open) dialog.close();
        resolve(result);
      };
      const onOk     = () => finish(true);
      const onCancel = () => finish(false);
      const onClose  = () => finish(false);
      ok.addEventListener("click", onOk);
      cancel.addEventListener("click", onCancel);
      dialog.addEventListener("close", onClose);
      dialog.showModal();
      cancel.focus();
    });
  }

  // The AI assistant marks the old diagram for deletion instead of deleting
  // it; the user decides here.
  async confirmClear(nodeIds) {
    const nodes = nodeIds.map(id => this.cy.$(`#n${id}`)).filter(n => n.length);
    if (nodes.length === 0) return;
    const linkCount = this.cy.collection(nodes).connectedEdges().length;

    const confirmed = await this.confirmDialog({
      title: "Delete the previous diagram?",
      message: `The AI assistant wants to replace the diagram. Delete the ${nodes.length} earlier ` +
               `variables and their ${linkCount} links? You can undo this.`,
      confirmLabel: "Delete them",
      cancelLabel: "Keep them"
    });
    if (!confirmed) {
      this.appendChatMessage("assistant", "Kept the previous diagram. You can delete parts of it yourself.");
      return;
    }

    await this.commands.execute(this.deleteChange("delete the previous diagram", this.cy.collection(nodes)));
  }

  // ---- C-key link creation ----

  startCLink(sourceNode) {
    this.cLinkMode   = true;
    this.cLinkSource = sourceNode;
    sourceNode.addClass("link-source");

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.style.cssText = "position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:10;";

    const defs   = document.createElementNS("http://www.w3.org/2000/svg", "defs");
    const marker = document.createElementNS("http://www.w3.org/2000/svg", "marker");
    marker.setAttribute("id", "cl-preview-arrow");
    marker.setAttribute("markerWidth", "8"); marker.setAttribute("markerHeight", "6");
    marker.setAttribute("refX", "8");        marker.setAttribute("refY", "3");
    marker.setAttribute("orient", "auto");
    const poly = document.createElementNS("http://www.w3.org/2000/svg", "polygon");
    poly.setAttribute("points", "0 0, 8 3, 0 6"); poly.setAttribute("fill", "#9b59b6");
    marker.appendChild(poly); defs.appendChild(marker); svg.appendChild(defs);

    const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.setAttribute("stroke", "#9b59b6");
    line.setAttribute("stroke-width", "2");
    line.setAttribute("stroke-dasharray", "6,4");
    line.setAttribute("marker-end", "url(#cl-preview-arrow)");
    svg.appendChild(line);

    this.previewSvg  = svg;
    this.previewLine = line;
    this.cyContainer.appendChild(svg);

    const pos = sourceNode.renderedPosition();
    line.setAttribute("x1", pos.x); line.setAttribute("y1", pos.y);
    line.setAttribute("x2", pos.x); line.setAttribute("y2", pos.y);

    this.onPreviewMove = (e) => {
      if (!this.previewLine) return;
      const rect = this.cyContainer.getBoundingClientRect();
      const src  = this.cLinkSource.renderedPosition();
      this.previewLine.setAttribute("x1", src.x); this.previewLine.setAttribute("y1", src.y);
      this.previewLine.setAttribute("x2", e.clientX - rect.left);
      this.previewLine.setAttribute("y2", e.clientY - rect.top);
    };
    document.addEventListener("mousemove", this.onPreviewMove);

    this.updateStatus("Click target node to connect — Esc to cancel");
  }

  cancelCLink() {
    if (!this.cLinkMode) return;
    this.cLinkMode = false;
    this.cLinkSource?.removeClass("link-source");
    this.cLinkSource = null;
    this.previewSvg?.remove();
    this.previewSvg  = null;
    this.previewLine = null;
    document.removeEventListener("mousemove", this.onPreviewMove);
    this.onPreviewMove = null;
    this.updateStatus("");
  }

  // A click on a link flips its sign, which is easy to do by accident, so the
  // link flashes and a toast offers to undo the change.
  async setPolarity(edge, polarity, { notify = false } = {}) {
    const name = `${edge.source().data("label")} → ${edge.target().data("label")}`;
    const command = this.updateChange(`sign of ${name}`, "link", edge.data("dbId"),
                                      { polarity: edge.data("polarity") }, { polarity });
    await this.commands.execute(command);
    if (!notify || this.commands.lastCommand !== command) return;

    edge.flashClass("cl-flash", 1500);
    this.showToast(`${name} is now ${polarity === "positive" ? "+" : "−"}`, {
      actionLabel: "Undo",
      action: () => { if (this.commands.lastCommand === command) this.undo(); }
    });
  }

  // A short message at the bottom of the canvas, with an optional button.
  showToast(message, { actionLabel = null, action = null, duration = 6000 } = {}) {
    this.toast?.remove();
    clearTimeout(this.toastTimer);

    const toast = document.createElement("div");
    toast.className = "cl-toast";
    toast.setAttribute("role", "status");
    const text = document.createElement("span");
    text.textContent = message;
    toast.appendChild(text);
    if (actionLabel && action) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = actionLabel;
      button.addEventListener("click", () => { action(); this.hideToast(); });
      toast.appendChild(button);
    }
    this.cyContainer.appendChild(toast);
    this.toast = toast;
    this.toastTimer = setTimeout(() => this.hideToast(), duration);
  }

  hideToast() {
    clearTimeout(this.toastTimer);
    this.toast?.remove();
    this.toast = null;
  }

  // ---- Two bend handles ----

  showBendHandles(edge) {
    this.removeBendHandles();

    const src = edge.source().position();
    const tgt = edge.target().position();
    const len = Math.hypot(tgt.x - src.x, tgt.y - src.y) || 1;
    // Perpendicular unit vector (left of the src→tgt direction)
    const px = -(tgt.y - src.y) / len;
    const py =  (tgt.x - src.x) / len;

    let cp1 = edge.data("cp1Distance") ?? 0;
    let cp2 = edge.data("cp2Distance") ?? 0;

    const makeHandle = (weight, getCP, setCP, color) => {
      const el = document.createElement("div");
      Object.assign(el.style, {
        position: "absolute",
        width: "14px", height: "14px",
        borderRadius: "50%",
        background: color,
        border: "2px solid white",
        cursor: "grab",
        zIndex: 20,
        boxShadow: "0 1px 4px rgba(0,0,0,0.4)"
      });
      this.cyContainer.appendChild(el);

      const positionHandle = () => {
        const zoom = this.cy.zoom();
        const pan  = this.cy.pan();
        const cpd  = getCP();
        const gx   = src.x + weight * (tgt.x - src.x) + cpd * px;
        const gy   = src.y + weight * (tgt.y - src.y) + cpd * py;
        const rx   = gx * zoom + pan.x;
        const ry   = gy * zoom + pan.y;
        el.style.left = `${rx - 7}px`;
        el.style.top  = `${ry - 7}px`;
      };
      positionHandle();

      el.addEventListener("mousedown", (e) => {
        e.stopPropagation(); e.preventDefault();
        const before = { cp1_distance: cp1, cp2_distance: cp2 };
        el.style.cursor = "grabbing";
        this.cy.userPanningEnabled(false);
        this.cy.userZoomingEnabled(false);

        const onMove = (me) => {
          const rect    = this.cyContainer.getBoundingClientRect();
          const zoom    = this.cy.zoom();
          const pan     = this.cy.pan();
          const gx      = (me.clientX - rect.left - pan.x) / zoom;
          const gy      = (me.clientY - rect.top  - pan.y) / zoom;
          const basex   = src.x + weight * (tgt.x - src.x);
          const basey   = src.y + weight * (tgt.y - src.y);
          const cpd     = (gx - basex) * px + (gy - basey) * py;
          setCP(cpd);
          this.applyBendStyle(edge, cp1, cp2);
          el.style.left = `${me.clientX - rect.left - 7}px`;
          el.style.top  = `${me.clientY - rect.top  - 7}px`;
        };

        const onUp = () => {
          el.style.cursor = "grab";
          this.cy.userPanningEnabled(true);
          this.cy.userZoomingEnabled(true);
          document.removeEventListener("mousemove", onMove);
          document.removeEventListener("mouseup",   onUp);
          if (before.cp1_distance === cp1 && before.cp2_distance === cp2) return;
          this.commands.execute(this.updateChange("bend link", "link", edge.data("dbId"), before,
                                                  { cp1_distance: cp1, cp2_distance: cp2 }));
        };

        document.addEventListener("mousemove", onMove);
        document.addEventListener("mouseup",   onUp);
      });

      return el;
    };

    const el1 = makeHandle(0.25, () => cp1, (v) => { cp1 = v; }, "#9b59b6");
    const el2 = makeHandle(0.75, () => cp2, (v) => { cp2 = v; }, "#8e44ad");

    this.bendHandle = { els: [el1, el2], edge };
  }

  removeBendHandles() {
    if (!this.bendHandle) return;
    this.bendHandle.els.forEach(el => el.remove());
    this.bendHandle = null;
  }

  // ---- Button link mode ----

  toggleButtonLinkMode() {
    if (this.buttonLinkMode) { this.exitButtonLinkMode(); return; }
    this.buttonLinkMode   = true;
    this.buttonLinkSource = null;
    this.element.querySelector("#btn-add-link").textContent = "✕ Cancel";
    this.updateStatus("Click the source node");
  }

  exitButtonLinkMode() {
    this.buttonLinkMode = false;
    this.buttonLinkSource?.removeClass("link-source");
    this.buttonLinkSource = null;
    const btn = this.element.querySelector("#btn-add-link");
    if (btn) btn.textContent = "→ Add link";
    this.updateStatus("");
  }

  // ---- Node operations ----

  async addNode() {
    const ext = this.cy.extent();
    await this.addNodeAt(
      (ext.x1 + ext.x2) / 2 + (Math.random() - 0.5) * 80,
      (ext.y1 + ext.y2) / 2 + (Math.random() - 0.5) * 80
    );
  }

  async addNodeAt(x, y) {
    const resp = await this.apiRequest(this.nodesUrlValue, "POST", {
      node: { title: "New node", position_x: x, position_y: y }
    });
    if (resp.ok) {
      const n = await resp.json();
      const cyNode = this.cy.add(this.nodeElement(n));
      const command = this.change("add node", [this.restoreOp("node", n)], [this.deleteOp("node", n.id)]);
      this.commands.record(command);
      this.startInlineEdit(cyNode, { created: command });
    } else {
      const body = await resp.json().catch(() => ({}));
      this.updateStatus(`Error: ${(body.errors || []).join(", ") || resp.status}`);
    }
  }

  // Naming a node just added is part of adding it: one undo removes it.
  startInlineEdit(cyNode, { created = null } = {}) {
    const pos = cyNode.renderedPosition();
    const w   = cyNode.renderedWidth();
    const h   = cyNode.renderedHeight();
    const input = document.createElement("input");
    input.type  = "text";
    input.value = cyNode.data("label");
    const fs = cyNode.data("fontSize") ?? 13;
    Object.assign(input.style, {
      position: "absolute",
      left: `${pos.x - w / 2}px`, top: `${pos.y - h / 2}px`,
      width: `${w}px`, height: `${h}px`,
      textAlign: "center", fontSize: `${fs}px`,
      border: "2px solid #f0a500", borderRadius: "4px",
      padding: "0 4px", boxSizing: "border-box",
      background: "#fff", color: "#333", zIndex: 1000
    });
    this.cyContainer.appendChild(input);
    input.focus();
    input.select();

    let saved = false;
    const save = () => {
      if (saved) return;
      saved = true;
      const t = input.value.trim() || "New node";
      const previous = cyNode.data("label");
      input.remove();
      if (created) {
        created.forward[0].snapshot.title = t;
        created.label = `add “${t}”`;
        this.updateUndoButtons();
      }
      if (t === previous) return;
      if (created) {
        cyNode.data("label", t);
        this.apiRequest(`${this.nodesUrlValue}/${cyNode.data("dbId")}`, "PATCH", { node: { title: t } });
      } else {
        this.commands.execute(this.updateChange(`rename “${previous}”`, "node", cyNode.data("dbId"),
                                                { title: previous }, { title: t }));
      }
    };
    input.addEventListener("blur", save);
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter")  { e.preventDefault(); save(); }
      if (e.key === "Escape") { saved = true; input.remove(); }
    });
  }

  resizeSelected(dw, dh) {
    this.changeSelectedNodes("resize", n => ({
      width:  Math.max(60, (n.data("width")  ?? 130) + dw),
      height: Math.max(24, (n.data("height") ?? 44)  + dh)
    }));
  }

  fontSizeSelected(delta) {
    this.changeSelectedNodes("change font size of", n => ({ font_size: Math.max(8, (n.data("fontSize") ?? 13) + delta) }));
  }

  changeSelectedNodes(verb, attributesFor) {
    const nodes = this.cy.$("node:selected");
    if (nodes.length === 0) return;
    const current = n => ({ width: n.data("width"), height: n.data("height"), font_size: n.data("fontSize") });
    const changes = nodes.map(n => {
      const after = attributesFor(n);
      const before = Object.fromEntries(Object.keys(after).map(key => [key, current(n)[key]]));
      return this.updateChange("", "node", n.data("dbId"), before, after);
    });
    const label = nodes.length === 1 ? `${verb} “${nodes[0].data("label")}”` : `${verb} ${nodes.length} nodes`;
    this.commands.execute(this.combine(label, changes));
  }

  // ---- Link operations ----

  async createLink(sourceId, targetId, polarity) {
    let resp;
    try {
      resp = await this.apiRequest(this.linksUrlValue, "POST", {
        link: { source_node_id: sourceId, target_node_id: targetId, polarity }
      });
    } catch (err) {
      this.updateStatus(`Network error: ${err.message}`);
      return;
    }
    if (!resp.ok) {
      const body = await resp.json().catch(() => ({}));
      this.updateStatus(`Error: ${(body.errors || []).join(", ") || resp.status}`);
      return;
    }
    const l = await resp.json();
    const edge = this.cy.add(this.linkElement(l));
    this.commands.record(this.change(`link ${edge.source().data("label")} → ${edge.target().data("label")}`,
                                     [this.restoreOp("link", l)], [this.deleteOp("link", l.id)]));
  }

  // ---- Delete ----

  deleteSelected() {
    const nodes = this.cy.$("node:selected");
    const edges = this.cy.$("edge:selected");
    if (nodes.length + edges.length === 0) return;
    const label = nodes.length === 1 && edges.length === 0 ? `delete “${nodes[0].data("label")}”`
      : nodes.length === 0 && edges.length === 1 ? "delete link" : "delete selection";
    this.commands.execute(this.deleteChange(label, nodes, edges));
  }

  // ---- View controls ----

  setupViewControls() {
    this.element.querySelector("#btn-zoom-in") ?.addEventListener("click", () => {
      this.cy.zoom({ level: this.cy.zoom() * 1.25, renderedPosition: { x: this.cy.width() / 2, y: this.cy.height() / 2 } });
    });
    this.element.querySelector("#btn-zoom-out")?.addEventListener("click", () => {
      this.cy.zoom({ level: this.cy.zoom() / 1.25, renderedPosition: { x: this.cy.width() / 2, y: this.cy.height() / 2 } });
    });
    // Full view is the default; the choice is remembered per browser.
    this.setFullView(this.readPreference("fullView") !== "false");
    this.element.querySelector("#btn-full-view")?.addEventListener("click", () => {
      const full = !this.element.classList.contains("is-full-view");
      this.setFullView(full);
      this.writePreference("fullView", full);
    });

    this.element.querySelector("#btn-fit")?.addEventListener("click", () => {
      this.cy.fit(this.cy.elements(), 40);
    });
    this.setupLoops();
    this.element.querySelector("#btn-export-json")   ?.addEventListener("click", () => this.exportJson());
    this.element.querySelector("#btn-export-graphml") ?.addEventListener("click", () => this.exportGraphml());
    this.element.querySelector("#btn-save-png")      ?.addEventListener("click", () => this.savePng());
    this.element.querySelector("#btn-print-pdf")     ?.addEventListener("click", () => this.printPdf());
  }

  // ---- Loops ----

  // The loops panel lists the diagram's feedback loops, found by the server
  // (the same code the AI assistant's find_loops tool uses). Selecting one
  // highlights it and dims everything else. While the panel is open it
  // refreshes shortly after the diagram changes.
  setupLoops() {
    this.element.querySelector("#btn-loops")?.addEventListener("click", () => {
      if (this.loopsPanel) this.closeLoops();
      else this.openLoops();
    });
    this.cy.on("add remove data", () => {
      if (!this.loopsPanel) return;
      clearTimeout(this.loopsRefreshTimer);
      this.loopsRefreshTimer = setTimeout(() => this.refreshLoops(), 800);
    });
    this.onLoopsKeyDown = (e) => { if (e.key === "Escape") this.highlightLoop(null); };
    document.addEventListener("keydown", this.onLoopsKeyDown);
  }

  openLoops() {
    const panel = document.createElement("div");
    panel.className = "cl-loops";
    panel.innerHTML = `<div class="cl-loops-header"><span>Loops</span>
      <button type="button" aria-label="Close loops">&#x2715;</button></div>
      <div class="cl-loops-note">Finding loops…</div>`;
    panel.querySelector("button").addEventListener("click", () => this.closeLoops());
    this.cyContainer.appendChild(panel);
    this.loopsPanel = panel;
    this.refreshLoops();
  }

  closeLoops() {
    clearTimeout(this.loopsRefreshTimer);
    this.highlightLoop(null);
    this.loopsPanel?.remove();
    this.loopsPanel = null;
  }

  async refreshLoops() {
    let data;
    try {
      const resp = await fetch(this.loopsUrlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" });
      if (!resp.ok) throw new Error(`error ${resp.status}`);
      data = await resp.json();
    } catch (err) {
      this.renderLoops(null, `Could not find the loops (${err.message}).`);
      return;
    }
    this.renderLoops(data);
  }

  renderLoops(data, error = null) {
    if (!this.loopsPanel) return;
    this.highlightLoop(null);
    this.loopsPanel.querySelectorAll("ul, .cl-loops-note").forEach(el => el.remove());
    const title = this.loopsPanel.querySelector(".cl-loops-header span");

    const note = (text) => {
      const p = document.createElement("div");
      p.className = "cl-loops-note";
      p.textContent = text;
      this.loopsPanel.appendChild(p);
    };
    if (error) { note(error); return; }

    title.textContent = `Loops: ${data.reinforcing} reinforcing, ${data.balancing} balancing`;
    if (data.loops.length === 0) { note("This diagram has no feedback loops yet."); return; }

    const list = document.createElement("ul");
    data.loops.forEach(loop => {
      const item = document.createElement("li");
      const button = document.createElement("button");
      button.type = "button";
      button.setAttribute("aria-pressed", "false");
      button.title = loop.type === "R" ? "Reinforcing: an even number of negative links"
                                       : "Balancing: an odd number of negative links";
      const badge = document.createElement("span");
      badge.className = `cl-loop-badge cl-loop-badge--${loop.type}`;
      badge.textContent = loop.name;
      const text = document.createElement("span");
      text.textContent = [...loop.nodes, loop.nodes[0]].join(" → ");
      button.append(badge, text);
      button.addEventListener("click", () => {
        this.highlightLoop(this.highlightedLoop === loop ? null : loop);
        list.querySelectorAll("button").forEach(b => b.setAttribute("aria-pressed", String(b === button && this.highlightedLoop === loop)));
      });
      item.appendChild(button);
      list.appendChild(item);
    });
    this.loopsPanel.appendChild(list);
    if (data.truncated) note(`Showing the first ${data.loops.length} loops; the diagram has more.`);
  }

  highlightLoop(loop) {
    this.highlightedLoop = loop;
    this.cy.elements().removeClass("cl-dim cl-in-loop");
    this.loopsPanel?.querySelectorAll("button[aria-pressed]").forEach(b => b.setAttribute("aria-pressed", "false"));
    if (!loop) return;

    const members = this.cy.collection();
    loop.node_ids.forEach(id => { members.merge(this.cy.$(`#n${id}`)); });
    loop.link_ids.forEach(id => { members.merge(this.cy.$(`#l${id}`)); });
    this.cy.elements().not(members).addClass("cl-dim");
    members.addClass("cl-in-loop");
  }

  // The editor covers the window, hiding Decidim's header and footer.
  setFullView(full) {
    this.element.classList.toggle("is-full-view", full);
    document.documentElement.classList.toggle("cl-full-view", full);
    const btn = this.element.querySelector("#btn-full-view");
    if (btn) btn.textContent = full ? "✕ Exit full view" : "⛶ Full view";
    this.fitView();
  }

  // After the canvas changes size: fit the diagram, but never enlarge it
  // beyond 100%.
  fitView() {
    this.cy.resize();
    if (this.cy.elements().length === 0) return;
    this.cy.fit(this.cy.elements(), 40);
    if (this.cy.zoom() > 1) this.cy.zoom(1).center();
  }

  // ---- Export ----

  exportJson() {
    const data = {
      nodes: this.cy.nodes().map(n => ({ id: n.data("dbId"), title: n.data("label"), x: Math.round(n.position("x")), y: Math.round(n.position("y")) })),
      links: this.cy.edges().map(e => ({ id: e.data("dbId"), source: e.data("source").slice(1), target: e.data("target").slice(1), polarity: e.data("polarity") }))
    };
    this.downloadBlob(new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }), "causal-loop-diagram.json");
  }

  exportGraphml() {
    const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    const nodeLines = this.cy.nodes().map(n => `    <node id="${n.data("dbId")}"><data key="label">${esc(n.data("label"))}</data></node>`).join("\n");
    const edgeLines = this.cy.edges().map(e => `    <edge source="${e.data("source").slice(1)}" target="${e.data("target").slice(1)}"><data key="polarity">${esc(e.data("polarity"))}</data></edge>`).join("\n");
    const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<graphml xmlns="http://graphml.graphdrawing.org/graphml">\n  <key id="label" for="node" attr.name="label" attr.type="string"/>\n  <key id="polarity" for="edge" attr.name="polarity" attr.type="string"/>\n  <graph id="G" edgedefault="directed">\n${nodeLines}\n${edgeLines}\n  </graph>\n</graphml>`;
    this.downloadBlob(new Blob([xml], { type: "application/xml" }), "causal-loop-diagram.graphml");
  }

  savePng() {
    const dataUrl = this.cy.png({ bg: "#ffffff", scale: 2, full: true });
    const a = document.createElement("a");
    a.href = dataUrl; a.download = "causal-loop-diagram.png"; a.click();
  }

  printPdf() {
    const dataUrl = this.cy.png({ bg: "#ffffff", scale: 2, full: true });
    const win = window.open("");
    win.document.write(`<!DOCTYPE html><html><head><title>Causal Loop Diagram</title><style>body{margin:0;}img{max-width:100%;display:block;}</style></head><body><img src="${dataUrl}" onload="window.print();window.close();"/></body></html>`);
    win.document.close();
  }

  downloadBlob(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = filename; a.click();
    URL.revokeObjectURL(url);
  }

  // ---- AI Chat ----

  setupChat() {
    const btn       = this.element.querySelector("#btn-ai-chat");
    const workspace = this.element.querySelector("#cl-workspace");
    const input     = this.element.querySelector("#cl-chat-input");
    const send      = this.element.querySelector("#cl-chat-send");
    if (!btn || !workspace) return;

    this.workspace = workspace;
    this.applyChatPosition(this.readPreference("chatPosition") || "right");
    const width  = this.readPreference("chatWidth");
    const height = this.readPreference("chatHeight");
    if (width)  workspace.style.setProperty("--cl-chat-width",  `${width}px`);
    if (height) workspace.style.setProperty("--cl-chat-height", `${height}px`);

    btn.addEventListener("click", () => {
      const open = workspace.classList.toggle("is-chat-open");
      btn.textContent = open ? "✕ Close AI" : "🤖 AI Assistant";
      this.fitView();
      if (open) input?.focus();
    });

    this.element.querySelector("#cl-chat-position")?.addEventListener("click", () => {
      const next = this.chatPosition === "right" ? "below" : "right";
      this.applyChatPosition(next);
      this.writePreference("chatPosition", next);
    });

    this.setupChatResize();

    const messages = this.element.querySelector("#cl-chat-messages");
    this.chatGreeting = messages?.innerHTML ?? "";
    this.restoreChat();
    this.element.querySelector("#cl-chat-clear")?.addEventListener("click", () => this.clearChat());

    send?.addEventListener("click", () => this.sendChatMessage());
    input?.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); this.sendChatMessage(); }
    });
  }

  // "right" puts the panel beside the canvas, "below" under it. Narrow
  // screens always get "below".
  applyChatPosition(position) {
    const narrow = window.matchMedia("(max-width: 767px)").matches;
    this.chatPosition = narrow ? "below" : position;
    this.workspace.classList.toggle("cl-workspace--right", this.chatPosition === "right");
    this.workspace.classList.toggle("cl-workspace--below", this.chatPosition === "below");
    // The native grip leaves an inline height, which must not stretch the
    // panel once it is back beside the canvas.
    const chat = this.element.querySelector("#cl-chat");
    if (chat) chat.style.height = "";
    const toggle = this.element.querySelector("#cl-chat-position");
    if (toggle) {
      toggle.textContent = this.chatPosition === "right" ? "Move below" : "Move right";
      toggle.hidden = narrow;
    }
    this.fitView();
  }

  // Beside the canvas, dragging the splitter sets the panel's width. Below
  // it, the panel has a native resize grip; its height is remembered.
  setupChatResize() {
    const splitter = this.element.querySelector("#cl-splitter");
    const chat     = this.element.querySelector("#cl-chat");
    if (!splitter || !chat) return;

    splitter.addEventListener("mousedown", (e) => {
      e.preventDefault();
      splitter.classList.add("is-dragging");
      const rect = this.workspace.getBoundingClientRect();
      let width = null;

      const onMove = (me) => {
        width = Math.min(Math.max(rect.right - me.clientX, 260), rect.width - 300);
        this.workspace.style.setProperty("--cl-chat-width", `${width}px`);
        this.cy.resize();
      };
      const onUp = () => {
        splitter.classList.remove("is-dragging");
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", onUp);
        if (width !== null) this.writePreference("chatWidth", Math.round(width));
      };
      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", onUp);
    });

    let saveTimer = null;
    this.chatResizeObserver = new ResizeObserver(() => {
      if (this.chatPosition !== "below" || !chat.style.height) return;
      this.workspace.style.setProperty("--cl-chat-height", chat.style.height);
      clearTimeout(saveTimer);
      saveTimer = setTimeout(() => this.writePreference("chatHeight", parseInt(chat.style.height, 10)), 300);
    });
    this.chatResizeObserver.observe(chat);
  }

  // Panel position and size are a per-browser convenience; storage may be
  // unavailable (private mode), which just means the defaults.
  readPreference(key) {
    try { return window.localStorage.getItem(`causalLoop.${key}`); } catch { return null; }
  }

  writePreference(key, value) {
    try { window.localStorage.setItem(`causalLoop.${key}`, String(value)); } catch { /* ignore */ }
  }

  removePreference(key) {
    try { window.localStorage.removeItem(`causalLoop.${key}`); } catch { /* ignore */ }
  }

  async sendChatMessage() {
    const input = this.element.querySelector("#cl-chat-input");
    const send  = this.element.querySelector("#cl-chat-send");
    const text  = input?.value.trim();
    if (!text) return;

    input.value    = "";
    input.disabled = true;
    if (send) send.disabled = true;

    this.appendChatMessage("user", text);
    const pending = this.appendChatMessage("pending", "Thinking…");

    try {
      const resp = await this.apiRequest(this.conversationsUrlValue, "POST", {
        message: text,
        history: this.chatHistory
      });
      pending.remove();

      if (resp.ok) {
        const data = await resp.json();
        this.chatHistory = data.history || [];
        this.saveChat();
        this.appendChatMessage("assistant", data.reply || "(no reply)");
        if (data.actions?.length) this.applyActions(data.actions, text);
      } else {
        const body = await resp.json().catch(() => ({}));
        this.appendChatMessage("error", body.error || `Server error ${resp.status}`);
      }
    } catch (err) {
      pending.remove();
      this.appendChatMessage("error", `Network error: ${err.message}`);
    } finally {
      input.disabled = false;
      if (send) send.disabled = false;
      input.focus();
    }
  }

  // The conversation is kept in browser storage, per diagram, so it
  // survives a reload. Only the last turns are kept: the whole history is
  // sent with every request, and a long one slows the model down.
  get chatStorageKey() {
    return `chat:${this.conversationsUrlValue}`;
  }

  saveChat() {
    this.chatHistory = this.chatHistory.slice(-40);
    this.writePreference(this.chatStorageKey, JSON.stringify(this.chatHistory));
  }

  restoreChat() {
    let history = [];
    try { history = JSON.parse(this.readPreference(this.chatStorageKey) || "[]"); } catch { history = []; }
    if (!Array.isArray(history)) return;

    this.chatHistory = history.filter(m => ["user", "assistant"].includes(m?.role) && typeof m.content === "string");
    this.chatHistory.forEach(m => this.appendChatMessage(m.role, m.content));
  }

  clearChat() {
    this.chatHistory = [];
    this.removePreference(this.chatStorageKey);
    const messages = this.element.querySelector("#cl-chat-messages");
    if (messages) messages.innerHTML = this.chatGreeting;
    this.element.querySelector("#cl-chat-input")?.focus();
  }

  appendChatMessage(role, text) {
    const messages = this.element.querySelector("#cl-chat-messages");
    if (!messages) return null;
    const div = document.createElement("div");
    div.className = `cl-msg cl-msg--${role}`;
    div.textContent = text;
    messages.appendChild(div);
    messages.scrollTop = messages.scrollHeight;
    return div;
  }

  // The server has already made these changes; this shows them, and records
  // the whole reply as one step that can be undone. The inverse of each
  // action is taken from the canvas before the action is applied. Deleting
  // the old diagram is asked about, and done, as a step of its own.
  applyActions(actions, request = "") {
    let clearIds = null;
    const forward = [];
    const backward = [];
    const step = (operation, inverse) => { forward.push(operation); backward.unshift(inverse); this.applyToCanvas(operation); };

    for (const action of actions) {
      const node = this.cy.getElementById(`n${action.id}`);
      const edge = this.cy.getElementById(`l${action.id}`);
      switch (action.type) {
        case "confirm_clear":
          clearIds = action.node_ids;
          break;
        case "add_node":
          if (!node.length) step(this.restoreOp("node", action), this.deleteOp("node", action.id));
          break;
        case "update_node":
          if (node.length && action.title) {
            step(this.updateOp("node", action.id, { title: action.title }),
                 this.updateOp("node", action.id, { title: node.data("label") }));
          }
          break;
        case "remove_node":
          if (node.length) step(this.deleteOp("node", action.id), this.restoreOp("node", this.nodeSnapshot(node)));
          break;
        case "add_link":
          if (!edge.length) step(this.restoreOp("link", action), this.deleteOp("link", action.id));
          break;
        case "update_link":
          if (edge.length && action.polarity) {
            step(this.updateOp("link", action.id, { polarity: action.polarity }),
                 this.updateOp("link", action.id, { polarity: edge.data("polarity") }));
          }
          break;
        case "remove_link":
          if (edge.length) step(this.deleteOp("link", action.id), this.restoreOp("link", this.linkSnapshot(edge)));
          break;
      }
    }

    if (forward.length) {
      const words = request.split(/\s+/).filter(Boolean);
      const summary = words.slice(0, 6).join(" ") + (words.length > 6 ? "…" : "");
      this.commands.record(this.change(`AI: “${summary}”`, forward, backward));
    }
    if (clearIds) this.confirmClear(clearIds);
  }

  // ---- Helpers ----

  updateStatus(msg) {
    const el = this.element.querySelector("#toolbar-status");
    if (el) el.textContent = msg;
  }

  apiRequest(url, method, body = null) {
    const opts = {
      method,
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfTokenValue },
      credentials: "same-origin"
    };
    if (body) opts.body = JSON.stringify(body);
    return fetch(url, opts);
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeyDown, true);
    if (this.onPreviewMove) document.removeEventListener("mousemove", this.onPreviewMove);
    this.removeBendHandles();
    this.chatResizeObserver?.disconnect();
    this.hideToast();
    clearTimeout(this.loopsRefreshTimer);
    document.removeEventListener("keydown", this.onLoopsKeyDown);
    document.documentElement.classList.remove("cl-full-view");
    this.cy?.destroy();
  }
}
