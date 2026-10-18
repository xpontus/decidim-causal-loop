// Undo and redo for the diagram editor.
//
// A command is { label, do(), undo() }, where do and undo are async and
// change both the server and the canvas. execute() runs a command and
// remembers it; record() remembers one whose effect has already happened
// (a node the server has created, an AI assistant's reply). A command may
// also have run(), used instead of do() the first time, when that differs
// (auto-layout animates the nodes into place itself).
//
// Every call goes through one promise queue, so a quick double Ctrl+Z cannot
// interleave two requests. A command that fails to undo or redo (another
// editor changed the diagram meanwhile) is dropped, and the rest of the
// history is kept.
export default class CommandManager {
  constructor({ limit = 100, onChange = () => {}, onError = () => {} } = {}) {
    this.limit     = limit;
    this.onChange  = onChange;
    this.onError   = onError;
    this.undoStack = [];
    this.redoStack = [];
    this.pending   = 0;
    this.queue     = Promise.resolve();
  }

  get canUndo() { return this.pending === 0 && this.undoStack.length > 0; }
  get canRedo() { return this.pending === 0 && this.redoStack.length > 0; }
  get undoLabel() { return this.undoStack.at(-1)?.label; }
  get redoLabel() { return this.redoStack.at(-1)?.label; }
  get lastCommand() { return this.undoStack.at(-1); }

  execute(command) {
    return this.enqueue(async () => {
      try {
        await (command.run ?? command.do).call(command);
      } catch (error) {
        this.onError(error, command, "do");
        return;
      }
      this.push(command);
    });
  }

  record(command) {
    return this.enqueue(async () => this.push(command));
  }

  undo() {
    return this.enqueue(async () => {
      const command = this.undoStack.pop();
      if (!command) return;
      try {
        await command.undo();
        this.redoStack.push(command);
      } catch (error) {
        this.onError(error, command, "undo");
      }
    });
  }

  redo() {
    return this.enqueue(async () => {
      const command = this.redoStack.pop();
      if (!command) return;
      try {
        await command.do();
        this.undoStack.push(command);
      } catch (error) {
        this.onError(error, command, "redo");
      }
    });
  }

  push(command) {
    this.undoStack.push(command);
    if (this.undoStack.length > this.limit) this.undoStack.shift();
    this.redoStack = [];
  }

  enqueue(task) {
    this.pending += 1;
    this.onChange();
    const run = this.queue.then(task).finally(() => {
      this.pending -= 1;
      this.onChange();
    });
    this.queue = run.catch(() => {});
    return run;
  }
}
