'use strict';
// issue-labeler.test.js — exercises scripts/issue-labeler.js under plain node.
// Run by scripts/check-node-tests.sh from `make check`. No dependencies:
// node:test + node:assert only. Fixtures are inline; the last group also runs
// the real .github/labels.yml of the repository this file lives in.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const labeler = require('./issue-labeler.js');

const YML = `
labels:
  - name: type:chore
  - name: area:a-architecture
    color: 111111
  - name: area:wp_1
  # - name: area:commented
  - name: "area:quoted"
  - name: area:c#
  - name: area:team's
  - name: area:pm
  - name: area:customer success
  - name: area:customer - success
  - name: area:ci
  - name: area:ci-tools
  - name: priority:p0
`;
const AREAS = labeler.parseAllowedAreas(YML);

function changes(body, currentLabels = [], allowedAreas = AREAS) {
  return labeler.computeChanges({ body, currentLabels, allowedAreas });
}

test('parseAllowedAreas: only `- name: area:` lines, commented and quoted excluded, punctuation kept', () => {
  assert.deepEqual(AREAS, [
    'area:a-architecture', 'area:wp_1', 'area:c#', "area:team's", 'area:pm',
    'area:customer success', 'area:customer - success', 'area:ci', 'area:ci-tools',
  ]);
});

test('parseSections: headings become keys, text is kept per section', () => {
  const s = labeler.parseSections('### A\n\nx\n\n### B\n\n- [x] y');
  assert.deepEqual(Object.keys(s), ['A', 'B']);
  assert.equal(s.B.join('\n').trim(), '- [x] y');
});

test('parseSections: stray line terminators inside a heading line still parse (parity with the inline original)', () => {
  assert.deepEqual(Object.keys(labeler.parseSections('### Area\r\n- [x] x')), ['Area']);
  assert.deepEqual(Object.keys(labeler.parseSections('### Area \r')), ['Area']);
  assert.deepEqual(Object.keys(labeler.parseSections('### Area\u2028')), ['Area']);
  assert.deepEqual(Object.keys(labeler.parseSections('###\tPriority')), ['Priority']);
  assert.deepEqual(Object.keys(labeler.parseSections('###Priority')), []);
});

test('parseSections: a heading line padded to the body cap parses in linear time', () => {
  const t0 = process.hrtime.bigint();
  const s = labeler.parseSections('### a' + ' '.repeat(65530) + 'b');
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  assert.deepEqual(Object.keys(s), ['a' + ' '.repeat(65530) + 'b']);
  assert.ok(ms < 200, `took ${ms} ms`);
});

test('matchAllowed: longest allowed value first, then end-of-text or a spaced dash', () => {
  assert.equal(labeler.matchAllowed('area:ci — CI', ['area:ci', 'area:ci-tools']), 'area:ci');
  assert.equal(labeler.matchAllowed('area:ci-tools — t', ['area:ci', 'area:ci-tools']), 'area:ci-tools');
  assert.equal(labeler.matchAllowed('area:customer - success — CS', AREAS), 'area:customer - success');
  assert.equal(labeler.matchAllowed('area:pm tools — undeclared', AREAS), null);
  assert.equal(labeler.matchAllowed('area:pm - hyphen', AREAS), 'area:pm');
  assert.equal(labeler.matchAllowed('area:pm', AREAS), 'area:pm');
});

test('opened: ticked boxes with digits/underscore/punctuation apply; unticked, commented and undeclared do not', () => {
  const r = changes([
    '### Area', '',
    '- [x] area:wp_1 — x', '- [x] area:commented — y', '- [ ] area:pm — z',
    '- [x] area:quoted — q', '- [x] area:c# — sharp', "- [x] area:team's — t", '- [x] area:evil — nope', '',
    '### Priority', '', 'p0 — Critical',
  ].join('\n'));
  assert.deepEqual(r.toAdd, ['priority:p0', 'area:wp_1', 'area:c#', "area:team's"]);
  assert.deepEqual(r.toRemove, []);
});

test('edited: the old area is removed, the new one added, hand-applied type:bug untouched', () => {
  const r = changes('### Area\n\n- [x] area:pm — z\n\n### Priority\n\np0 — Critical',
    ['area:wp_1', 'type:bug', 'priority:p0']);
  assert.deepEqual(r.toAdd, ['area:pm']);
  assert.deepEqual(r.toRemove, ['area:wp_1']);
});

test('dropdowns: case folded, allowlist decides, no second regex', () => {
  const ok = changes('### Priority\n\nP1 — Blocking\n\n### Subtype\n\nDocs — Documentation');
  assert.deepEqual(ok.toAdd, ['priority:p1', 'type:docs']);
  const bad = changes('### Priority\n\np9 — nope\n\n### Subtype\n\nbug — spoof');
  assert.deepEqual(bad.toAdd, []);
  const none = changes('### Priority\n\n_No response_');
  assert.deepEqual(none.toAdd, []);
});

test('a body without the sections strips form-managed labels but never type:bug/type:feature or unknown families', () => {
  const r = changes('just prose', ['priority:p2', 'area:pm', 'type:docs', 'type:bug', 'type:feature', 'wontfix']);
  assert.deepEqual(r.toRemove, ['priority:p2', 'area:pm', 'type:docs']);
});

test('stale area label outside the allowlist is still cleaned up (area: is a prefix match for removal)', () => {
  const r = changes('### Area\n\n- [x] area:pm — z', ['area:old']);
  assert.deepEqual(r.toAdd, ['area:pm']);
  assert.deepEqual(r.toRemove, ['area:old']);
});

test('run: adds then removes via the API stub, logs the three lines', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'labeler-'));
  fs.mkdirSync(path.join(dir, '.github'));
  fs.writeFileSync(path.join(dir, '.github', 'labels.yml'), YML);
  const calls = [];
  const github = { rest: { issues: {
    addLabels: async (a) => calls.push(['add', a.labels]),
    removeLabel: async (a) => calls.push(['remove', a.name]),
  } } };
  const context = { repo: { owner: 'o', repo: 'r' }, payload: { issue: {
    number: 7, body: '### Area\n\n- [x] area:pm — z', labels: [{ name: 'area:wp_1' }, { name: 'type:bug' }],
  } } };
  const logs = [];
  const core = { info: (m) => logs.push(m), warning: (m) => logs.push('WARN ' + m) };
  const r = await labeler.run({ github, context, core, repoRoot: dir });
  assert.deepEqual(r, { desired: ['area:pm'], toAdd: ['area:pm'], toRemove: ['area:wp_1'] });
  assert.deepEqual(calls, [['add', ['area:pm']], ['remove', 'area:wp_1']]);
  assert.deepEqual(logs, ['Desired: area:pm', 'Added: area:pm', 'Removed: area:wp_1']);
});

test('run: an unreadable labels.yml throws before any API call', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'labeler-'));
  const calls = [];
  const github = { rest: { issues: {
    addLabels: async () => calls.push('add'), removeLabel: async () => calls.push('remove'),
  } } };
  const context = { repo: { owner: 'o', repo: 'r' }, payload: { issue: { number: 1, body: '### Area\n\n- [x] area:pm — z', labels: [{ name: 'area:pm' }] } } };
  await assert.rejects(() => labeler.run({ github, context, core: { info() {}, warning() {} }, repoRoot: dir }), /cannot read .*labels\.yml/);
  assert.deepEqual(calls, []);
});

test('run: an empty area set warns and applies nothing for Area', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'labeler-'));
  fs.mkdirSync(path.join(dir, '.github'));
  fs.writeFileSync(path.join(dir, '.github', 'labels.yml'), 'labels:\n  - name: priority:p0\n');
  const warnings = [];
  const github = { rest: { issues: { addLabels: async () => {}, removeLabel: async () => {} } } };
  const context = { repo: { owner: 'o', repo: 'r' }, payload: { issue: { number: 1, body: '### Area\n\n- [x] area:pm — z', labels: [] } } };
  const r = await labeler.run({ github, context, core: { info() {}, warning: (m) => warnings.push(m) }, repoRoot: dir });
  assert.deepEqual(r.toAdd, []);
  assert.equal(warnings.length, 1);
});

test("this repository's labels.yml: a declared area is applied, an undeclared one is not", () => {
  // Must hold in any adopted repo, whatever the area names are — the
  // template tells adopters to rename the starter set, so no name is assumed.
  const areas = labeler.readAllowedAreas(path.join(__dirname, '..'));
  if (areas.length === 0) return; // an adopter may have dropped the family entirely
  const first = areas[0];
  let undeclared = 'area:undeclared';
  while (areas.includes(undeclared)) undeclared += '-x';
  const r = changes(`### Area\n\n- [x] ${first} — declared\n- [x] ${undeclared} — n`, [], areas);
  assert.deepEqual(r.toAdd, [first]);
});
