const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const pluginDir = path.join(__dirname, '../src/main/ets/components/plugin');
function load(name, requireMock) {
  const compiled = ts.transpileModule(fs.readFileSync(path.join(pluginDir, name), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
  }).outputText;
  const module = { exports: {} };
  new Function('require', 'exports', 'module', compiled)(requireMock, module.exports, module);
  return module.exports;
}
const queue = load('PdfiumRenderQueue.ets', require);
const flush = () => new Promise(resolve => setImmediate(resolve));
function deferred() {
  let resolve;
  const promise = new Promise(yes => { resolve = yes; });
  return { promise, resolve };
}
function fixture() {
  const order = [];
  const gate = deferred();
  const renderer = {
    renderPage: async (document, page, width) => {
      order.push(`${document}:${page}:${width}`);
      return width === 10 ? gate.promise : new Uint8Array([width]);
    },
    renderTile: async () => { order.push('tile'); return new Uint8Array([9]); },
    closeDocument: () => {},
  };
  const mocks = {
    '@ohos/flutter_ohos': { StandardMethodCodec: class {}, StandardMessageCodec: {} },
    '@kit.PDFKit': {}, '@kit.CoreFileKit': {}, '@kit.ImageKit': {},
    '@kit.ArkTS': { HashMap: class extends Map { hasKey(key) { return this.has(key); }
      remove(key) { this.delete(key); } } },
    './utils/LogUtil': { LogUtil: { info() {}, error() {} } },
    'libpdf_renderer.so': { default: renderer }, './PdfiumRenderQueue': queue,
  };
  const Plugin = load('SyncfusionFlutterPdfViewerPlugin.ets', name => {
    assert.ok(name in mocks, `unexpected import ${name}`);
    return mocks[name];
  }).default;
  const plugin = new Plugin();
  for (const [id, nativeId] of [['reader', 1], ['other', 2]]) {
    plugin.documentRepo.set(id, {
      filePath: 'fixture.pdf', ownsFile: false, pageCount: 9,
      pdfDocument: { releaseDocument() {} }, pdfiumDocumentId: nativeId,
      pageRequestGeneration: [], tileRequestGeneration: [],
      pageRenderActive: [], pageRenderPriority: [],
    });
  }
  function call(method, args) {
    const result = deferred();
    plugin.onMethodCall({ method, args, argument: key => args[key] }, {
      success: value => result.resolve(value),
      error: (...error) => { throw new Error(error.join(' ')); },
    });
    return result.promise;
  }
  function page(index, width, renderPriority, documentID = 'reader') {
    return call('getPage', { index, width, height: 1, renderPriority, documentID });
  }
  function state(index, active, visible, invalidate = false) {
    return call('updateRenderState', { documentID: 'reader', index, active, visible, invalidate });
  }
  return { order, gate, page, state, call };
}

test('RGBA visible pages overtake queued RGBA previews and legacy thumbnails', async () => {
  const f = fixture();
  const active = f.page(1, 10, undefined, 'other');
  const thumbnail = f.page(2, 20, undefined, 'other');
  const preview = f.page(2, 30, 1);
  const visible = f.page(3, 40, 0);
  f.gate.resolve(null);
  await Promise.all([active, thumbnail, preview, visible]);
  assert.deepEqual(f.order, ['2:0:10', '1:2:40', '1:1:30', '2:1:20']);
});

test('viewport departure cancels pending base and tile calls without native work', async () => {
  const f = fixture();
  const active = f.page(1, 10, undefined, 'other');
  const page = f.page(2, 30, 0);
  const tile = f.call('getTileImage', { documentID: 'reader', pageNumber: 2,
    scale: 2, x: 0, y: 0, width: 1, height: 1 });
  await f.state(2, false, false);
  assert.deepEqual(await Promise.all([page, tile]), [null, null]);
  // Reentry submits a fresh generation; it must not resurrect the old tasks.
  await f.state(2, true, true);
  const fresh = f.page(2, 40, 0);
  await flush();
  assert.deepEqual(f.order, ['2:0:10']);
  f.gate.resolve(null);
  await Promise.all([active, fresh]);
  assert.deepEqual(f.order, ['2:0:10', '1:1:40']);
});

test('queued preview promotion uses viewport updates without resubmitting pixels', async () => {
  const f = fixture();
  const active = f.page(1, 10, undefined, 'other');
  const preview = f.page(2, 30, 1);
  const olderVisible = f.page(3, 40, 0);
  await f.state(2, true, true);
  await f.state(3, true, false);
  f.gate.resolve(null);
  await Promise.all([active, preview, olderVisible]);
  assert.deepEqual(f.order, ['2:0:10', '1:1:30', '1:2:40']);
});

test('zoom invalidation prunes queued pixels even while the page stays visible', async () => {
  const f = fixture();
  const active = f.page(1, 10, undefined, 'other');
  const old = f.page(2, 30, 0);
  await f.state(2, true, true, true);
  assert.equal(await old, null);
  const fresh = f.page(2, 40, 0);
  f.gate.resolve(null);
  await Promise.all([active, fresh]);
  assert.deepEqual(f.order, ['2:0:10', '1:1:40']);
});

test('closing the document settles its pending channel results safely', async () => {
  const f = fixture();
  const active = f.page(1, 10, undefined, 'other');
  const page = f.page(2, 30, 0);
  await f.call('closeDocument', 'reader');
  assert.equal(await page, null);
  f.gate.resolve(null);
  await active;
  assert.deepEqual(f.order, ['2:0:10']);
});
