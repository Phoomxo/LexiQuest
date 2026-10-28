const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

async function main() {
  const source = fs.readFileSync(path.join(__dirname, '../../../lib/add_default_categories.js'), 'utf8');
  const module = { exports: {} };
  let imports = 0;
  const context = {
    module, process: { env: {} }, console,
    require: () => { imports++; throw new Error('Firebase must not load before authorization'); },
  };
  vm.runInNewContext(source, context);
  assert.equal(imports, 0, 'import must not load or initialize Firebase');
  assert.equal(typeof module.exports.addDefaultCategories, 'function');
  assert.throws(() => module.exports.checkEnvironmentGuard(), /Environment Guard/);
  await assert.rejects(module.exports.addDefaultCategories(), /Environment Guard/);
  assert.equal(imports, 0, 'blocked seed must not load or initialize Firebase');
  for (const env of [{ FIRESTORE_EMULATOR_HOST: 'localhost:8080' }, { NODE_ENV: 'development' }, { ALLOW_SEED: 'true' }]) {
    context.process.env = env;
    assert.doesNotThrow(() => module.exports.checkEnvironmentGuard());
  }
  // Inspect the literal catalog without executing a seed or loading its SDK.
  const catalog = vm.runInNewContext(source + '\ndefaultCategories', { ...context, module: { exports: {} } });
  assert.equal(catalog.length, 10);
  assert.equal(new Set(catalog.map(c => c.category_name)).size, 10);
  assert.equal(catalog.reduce((sum, c) => sum + c.words.length, 0), 197);
  console.log('PASS: parse/import/blocked seed, three existing guards, unique catalog; no Firebase initialization or writes');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
