// Images
require.context("../images", true)

import CausalLoopEditorController from "../src/decidim/causal_loop/causal_loop_editor_controller";

const registerController = () => {
  if (window.Stimulus) {
    window.Stimulus.register("causal-loop-editor", CausalLoopEditorController);
    return;
  }
  setTimeout(registerController, 50);
};

// Run immediately — if DOMContentLoaded already fired, this still works
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", registerController);
} else {
  registerController();
}
