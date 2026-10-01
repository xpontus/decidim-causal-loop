import { Controller } from "@hotwired/stimulus";
import cytoscape from "cytoscape";

export default class extends Controller {
  static values = {
    nodes: Array,
    links: Array,
    nodesUrl: String,
    linksUrl: String,
    conversationsUrl: String,
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
          "label": "data(label)",
          "color": "#fff",
          "text-valign": "center",
          "text-halign": "center",
          "width": "data(width)",
          "height": "data(height)",
          "font-size": "data(fontSize)",
          "shape": "round-rectangle",
          "text-wrap": "wrap",
          "text-max-width": "data(textMaxWidth)"
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
      { selector: "edge:selected", style: { "width": 4 } }
    ];
  }

  buildElements() {
    const nodes = this.nodesValue.map(n => ({
      data: {
        id:          `n${n.id}`,
        label:       n.title,
        dbId:        n.id,
        width:       n.width      ?? 130,
        height:      n.height     ?? 44,
        fontSize:    n.font_size  ?? 13,
        textMaxWidth: (n.width ?? 130) - 10
      },
      position: { x: n.position_x || 150, y: n.position_y || 150 }
    }));
    const edges = this.linksValue.map(l => ({
      data: {
        id:          `l${l.id}`,
        source:      `n${l.source_node_id}`,
        target:      `n${l.target_node_id}`,
        polarity:    l.polarity,
        dbId:        l.id,
        cp1Distance: l.cp1_distance ?? 0,
        cp2Distance: l.cp2_distance ?? 0
      }
    }));
    return [...nodes, ...edges];
  }

  // Apply unbundled-bezier style with two control points to an edge
  applyBendStyle(edge, cp1, cp2) {
    edge.style("curve-style", "unbundled-bezier");
    edge.style("control-point-distances", `${cp1} ${cp2}`);
    edge.style("control-point-weights", "0.25 0.75");
  }

  setupEditing() {
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
        edge.data("polarity", newPolarity);
        this.updateLink(edge.data("dbId"), { polarity: newPolarity });
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

    // Save position after drag
    this.cy.on("dragfree", "node", (evt) => {
      const node = evt.target;
      const pos  = node.position();
      this.updateNode(node.data("dbId"), { position_x: pos.x, position_y: pos.y });
      this.removeBendHandles();
    });

    // Keyboard
    this.onKeyDown = (e) => {
      if (e.target.tagName === "INPUT") return;
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
          edge.data("cp1Distance", cp1);
          edge.data("cp2Distance", cp2);
          this.updateLink(edge.data("dbId"), { cp1_distance: cp1, cp2_distance: cp2 });
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
      const cyNode = this.cy.add({
        data: {
          id:          `n${n.id}`,
          label:       n.title,
          dbId:        n.id,
          width:       n.width     ?? 130,
          height:      n.height    ?? 44,
          fontSize:    n.font_size ?? 13,
          textMaxWidth: (n.width ?? 130) - 10
        },
        position: { x: n.position_x, y: n.position_y }
      });
      this.startInlineEdit(cyNode);
    } else {
      const body = await resp.json().catch(() => ({}));
      this.updateStatus(`Error: ${(body.errors || []).join(", ") || resp.status}`);
    }
  }

  startInlineEdit(cyNode) {
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
      cyNode.data("label", t);
      this.updateNode(cyNode.data("dbId"), { title: t });
      input.remove();
    };
    input.addEventListener("blur", save);
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter")  { e.preventDefault(); save(); }
      if (e.key === "Escape") { saved = true; input.remove(); }
    });
  }

  resizeSelected(dw, dh) {
    this.cy.$("node:selected").forEach(n => {
      const w = Math.max(60,  (n.data("width")  ?? 130) + dw);
      const h = Math.max(24,  (n.data("height") ?? 44)  + dh);
      n.data("width",  w);
      n.data("height", h);
      n.data("textMaxWidth", w - 10);
      this.updateNode(n.data("dbId"), { width: w, height: h });
    });
  }

  fontSizeSelected(delta) {
    this.cy.$("node:selected").forEach(n => {
      const fs = Math.max(8, (n.data("fontSize") ?? 13) + delta);
      n.data("fontSize", fs);
      this.updateNode(n.data("dbId"), { font_size: fs });
    });
  }

  async updateNode(dbId, attrs) {
    await this.apiRequest(`${this.nodesUrlValue}/${dbId}`, "PATCH", { node: attrs });
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
    this.cy.add({
      data: {
        id:          `l${l.id}`,
        source:      `n${l.source_node_id}`,
        target:      `n${l.target_node_id}`,
        polarity:    l.polarity,
        dbId:        l.id,
        cp1Distance: 0,
        cp2Distance: 0
      }
    });
  }

  async updateLink(dbId, attrs) {
    const resp = await this.apiRequest(`${this.linksUrlValue}/${dbId}`, "PATCH", { link: attrs });
    if (!resp.ok) console.warn("updateLink failed:", resp.status);
  }

  // ---- Delete ----

  deleteSelected() {
    this.cy.$("node:selected").forEach(n => this.deleteNode(n.data("dbId"), n));
    this.cy.$("edge:selected").forEach(e => this.deleteLink(e.data("dbId"), e));
  }

  async deleteNode(dbId, cyNode) {
    const resp = await this.apiRequest(`${this.nodesUrlValue}/${dbId}`, "DELETE");
    if (resp.ok) { this.removeBendHandles(); cyNode.remove(); }
    else console.warn("deleteNode failed:", resp.status);
  }

  async deleteLink(dbId, cyEdge) {
    const resp = await this.apiRequest(`${this.linksUrlValue}/${dbId}`, "DELETE");
    if (resp.ok) { this.removeBendHandles(); cyEdge.remove(); }
    else console.warn("deleteLink failed:", resp.status);
  }

  // ---- View controls ----

  setupViewControls() {
    this.element.querySelector("#btn-zoom-in") ?.addEventListener("click", () => {
      this.cy.zoom({ level: this.cy.zoom() * 1.25, renderedPosition: { x: this.cy.width() / 2, y: this.cy.height() / 2 } });
    });
    this.element.querySelector("#btn-zoom-out")?.addEventListener("click", () => {
      this.cy.zoom({ level: this.cy.zoom() / 1.25, renderedPosition: { x: this.cy.width() / 2, y: this.cy.height() / 2 } });
    });
    this.element.querySelector("#btn-fit")?.addEventListener("click", () => {
      this.cy.fit(this.cy.elements(), 40);
    });
    this.element.querySelector("#btn-export-json")   ?.addEventListener("click", () => this.exportJson());
    this.element.querySelector("#btn-export-graphml") ?.addEventListener("click", () => this.exportGraphml());
    this.element.querySelector("#btn-save-png")      ?.addEventListener("click", () => this.savePng());
    this.element.querySelector("#btn-print-pdf")     ?.addEventListener("click", () => this.printPdf());
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
    const btn   = this.element.querySelector("#btn-ai-chat");
    const panel = this.element.querySelector("#cl-chat");
    const input = this.element.querySelector("#cl-chat-input");
    const send  = this.element.querySelector("#cl-chat-send");
    if (!btn || !panel) return;

    btn.addEventListener("click", () => {
      const open = panel.style.display === "flex";
      panel.style.display = open ? "none" : "flex";
      btn.textContent = open ? "🤖 AI Assistant" : "✕ Close AI";
      if (!open) input?.focus();
    });

    send?.addEventListener("click", () => this.sendChatMessage());
    input?.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); this.sendChatMessage(); }
    });
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
        this.appendChatMessage("assistant", data.reply || "(no reply)");
        if (data.actions?.length) this.applyActions(data.actions);
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

  applyActions(actions) {
    for (const action of actions) {
      switch (action.type) {
        case "add_node":
          if (!this.cy.$(`#n${action.id}`).length) {
            this.cy.add({
              data: {
                id: `n${action.id}`, label: action.title, dbId: action.id,
                width: action.width ?? 130, height: action.height ?? 44,
                fontSize: action.font_size ?? 13, textMaxWidth: (action.width ?? 130) - 10
              },
              position: { x: action.position_x, y: action.position_y }
            });
          }
          break;

        case "update_node": {
          const n = this.cy.$(`#n${action.id}`);
          if (n.length && action.title) n.data("label", action.title);
          break;
        }

        case "remove_node":
          this.cy.$(`#n${action.id}`).remove();
          break;

        case "add_link":
          if (!this.cy.$(`#l${action.id}`).length) {
            this.cy.add({
              data: {
                id: `l${action.id}`, source: `n${action.source_node_id}`,
                target: `n${action.target_node_id}`, polarity: action.polarity,
                dbId: action.id, cp1Distance: 0, cp2Distance: 0
              }
            });
          }
          break;

        case "update_link": {
          const e = this.cy.$(`#l${action.id}`);
          if (e.length && action.polarity) e.data("polarity", action.polarity);
          break;
        }

        case "remove_link":
          this.cy.$(`#l${action.id}`).remove();
          break;
      }
    }
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
    this.cy?.destroy();
  }
}
