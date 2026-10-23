// Run with Node; TYPESCRIPT_PATH may point to DevEco's bundled TypeScript.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const source = path.join(__dirname,
  '../src/main/ets/components/plugin/PdfiumRenderQueue.ets');
const compiled = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
}).outputText;
const queueModule = { exports: {} };
new Function('exports', 'module', compiled)(queueModule.exports, queueModule);
const { PdfiumRenderQueue } = queueModule.exports;
const flush = () => new Promise(resolve => setImmediate(resolve));
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function request(label, priority, execute, isCurrent = () => true) {
  return { label, priority: () => priority, execute, isCurrent };
}

test('visible pixels precede queued previews and thumbnails; equal priority is FIFO', async () => {
  const order = [];
  const queue = new PdfiumRenderQueue(label => order.push(label));
  const gate = deferred();
  const running = queue.render(request('active', 2, () => gate.promise));
  const thumbnail = queue.render(request('thumbnail', 2, async () => null));
  const preview = queue.render(request('preview', 1, async () => null));
  const visible = queue.render(request('visible', 0, async () => null));
  const visible2 = queue.render(request('visible2', 0, async () => null));
  gate.resolve(null);
  await Promise.all([running, thumbnail, preview, visible, visible2]);
  assert.deepEqual(order, ['active', 'visible', 'visible2', 'preview', 'thumbnail']);
});

test('queued neighbor is promoted or demoted from its current viewport state', async () => {
  const order = [];
  const queue = new PdfiumRenderQueue(label => order.push(label));
  const gate = deferred();
  const running = queue.render(request('active', 0, () => gate.promise));
  let firstPriority = 0, secondPriority = 1;
  const first = queue.render({ ...request('oldVisible', 0, async () => null),
    priority: () => firstPriority });
  const second = queue.render({ ...request('newVisible', 1, async () => null),
    priority: () => secondPriority });
  firstPriority = 1;
  secondPriority = 0;
  queue.refresh();
  gate.resolve(null);
  await Promise.all([running, first, second]);
  assert.deepEqual(order, ['active', 'newVisible', 'oldVisible']);
});

test('offscreen work settles immediately without executing or releasing the active slot', async () => {
  const order = [];
  const queue = new PdfiumRenderQueue(label => order.push(label));
  const gate = deferred();
  const running = queue.render(request('active', 0, () => gate.promise));
  let active = true;
  const stale = queue.render(request('offscreen', 0, async () => {
    assert.fail('stale pixels must not be allocated');
  }, () => active));
  active = false;
  queue.refresh();
  assert.equal(await stale, null);
  const next = queue.render(request('next', 0, async () => null));
  await flush();
  assert.deepEqual(order, ['active']);
  gate.resolve(null);
  await Promise.all([running, next]);
  assert.deepEqual(order, ['active', 'next']);
});

test('cancelled running work retains the native slot and drops its eventual pixels', async () => {
  const order = [];
  const queue = new PdfiumRenderQueue(label => order.push(label));
  const gate = deferred();
  let current = true;
  const running = queue.render(request('active', 0, () => gate.promise, () => current));
  current = false;
  queue.refresh();
  const next = queue.render(request('next', 0, async () => null));
  await flush();
  assert.deepEqual(order, ['active']);
  gate.resolve(new Uint8Array([1]));
  assert.equal(await running, null);
  await next;
  assert.deepEqual(order, ['active', 'next']);
});

test('a newer generation supersedes pending base or tile work before native dispatch', async () => {
  const order = [];
  const queue = new PdfiumRenderQueue(label => order.push(label));
  const gate = deferred();
  const running = queue.render(request('active', 0, () => gate.promise));
  let generation = 1;
  const old = queue.render(request('old', 0, async () => {
    assert.fail('superseded request must not execute');
  }, () => generation === 1));
  generation++;
  const newest = queue.render(request('new', 0, async () => new Uint8Array([2]),
    () => generation === 2));
  assert.equal(await old, null);
  gate.resolve(null);
  assert.deepEqual(await newest, new Uint8Array([2]));
  await running;
  assert.deepEqual(order, ['active', 'new']);
});

test('closing a document cancels its pending tasks while other documents progress', async () => {
  const order = [];
  const queue = new PdfiumRenderQueue(label => order.push(label));
  const gate = deferred();
  const running = queue.render(request('otherActive', 0, () => gate.promise));
  let open = true;
  const page = queue.render(request('closedPage', 0, async () => null, () => open));
  const tile = queue.render(request('closedTile', 0, async () => null, () => open));
  const thumbnail = queue.render(request('otherThumbnail', 2, async () => null));
  open = false;
  queue.refresh();
  assert.deepEqual(await Promise.all([page, tile]), [null, null]);
  gate.resolve(null);
  await Promise.all([running, thumbnail]);
  assert.deepEqual(order, ['otherActive', 'otherThumbnail']);
});

test('rejection releases the real execution slot and preserves later requests', async () => {
  const queue = new PdfiumRenderQueue(() => {});
  const gate = deferred();
  const running = queue.render(request('failure', 0, () => gate.promise));
  const rejected = assert.rejects(running, /native failure/);
  const next = queue.render(request('next', 0, async () => new Uint8Array([3])));
  gate.reject(new Error('native failure'));
  await rejected;
  assert.deepEqual(await next, new Uint8Array([3]));
});
