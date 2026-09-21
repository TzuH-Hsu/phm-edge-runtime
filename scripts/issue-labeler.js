'use strict';
// issue-labeler.js — the logic behind .github/workflows/issue-labeler.yml.
//
// The workflow is a thin caller: after checking out the default branch it
// runs `require('<workspace>/scripts/issue-labeler.js').run({github, context,
// core})` inside actions/github-script. Everything that decides anything is
// here, so it can be read in one place and exercised by
// scripts/issue-labeler.test.js under plain node — no GitHub involved
// (ADR-0008).
//
// What it does: parse the GitHub issue-form markdown body (### <Label>
// headings) and sync the form-managed labels to match. Only ever touches
// priority:*, area:* and the four type:* subtypes in FORM_MANAGED_TYPES —
// every other label on the issue is left alone, including any type:* label
// OUTSIDE that list (a coarse type:bug/type:feature, or an adopter's own).
// The four form-owned subtypes are still removed when the form no longer
// selects them; that is the point of the sync.
//
// The issue body is untrusted input. It is only ever read as data here —
// never interpolated into a shell — and every label this script adds is
// validated against a list the body cannot influence.

const fs = require('fs');
const path = require('path');

// Allowlists. Priorities and subtypes are fixed constants; area:* is read
// from .github/labels.yml (below), which only a merged PR can change.
const ALLOWED_PRIORITIES = ['p0', 'p1', 'p2', 'p3'];
// Deliberately NOT read from labels.yml: a repo running the coarse-Type
// label fallback (ADR-0006) declares type:bug and type:feature there, and a
// crafted "### Subtype" line must not be able to mint a coarse Type on a
// Task. scripts/check-label-forms.sh keeps this list and task.yml's dropdown
// equal.
const ALLOWED_SUBTYPES = ['chore', 'ops', 'docs', 'security'];
// The exact type:* labels this script owns. Deliberately NOT
// `label.startsWith('type:')`: only task.yml has a Subtype dropdown, so on a
// bug report or feature request `desired` never holds a type:* label — and a
// prefix match would put every hand-applied type:* label into `toRemove` and
// strip it on the next body edit.
const FORM_MANAGED_TYPES = ALLOWED_SUBTYPES.map((s) => `type:${s}`);

const LABELS_YML = path.join('.github', 'labels.yml');

// area:* allowlist = every `- name: area:...` entry in labels.yml. The parse
// mirrors parse_labels_yml in scripts/bootstrap.sh: an entry is a `- name:`
// line, the name is the rest of the line trimmed — no quote or comment
// stripping, so area:c# and area:team's survive intact and a quoted or
// inline-commented entry is wrong here exactly as it is wrong for bootstrap
// (labels.yml's header rules both out). A commented-out entry starts with #
// and never matches.
function parseAllowedAreas(ymlText) {
  const areas = [];
  for (const line of String(ymlText).split(/\r?\n/)) {
    const m = line.match(/^\s*-\s*name:\s*(area:\S.*?)\s*$/);
    if (m) areas.push(m[1]);
  }
  return areas;
}

// Reads labels.yml from the checked-out default branch. A read failure
// THROWS — an empty allowlist is not a safe default, because `desired` would
// then hold no area:* and every area label already on the issue would land in
// toRemove.
function readAllowedAreas(repoRoot) {
  const file = path.join(repoRoot, LABELS_YML);
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (err) {
    throw new Error(`cannot read ${file}: ${err.message} — refusing to run with an empty area:* allowlist`);
  }
  return parseAllowedAreas(text);
}

// Split the body into sections keyed by "### <Heading>".
function parseSections(text) {
  const lines = String(text || '').split(/\r?\n/);
  const sections = {};
  let current = null;
  for (const line of lines) {
    // Linear, not `(.+?)\s*$`: the lazy form backtracks quadratically on a
    // heading line padded with tens of thousands of spaces (~2 s at the
    // 65,536-char body cap). The `s` flag keeps a stray CR or U+2028 inside
    // the heading matching as it did before; the heading is trimmed either way.
    const heading = line.match(/^###\s(.+)$/s);
    if (heading) {
      current = heading[1].trim();
      sections[current] = [];
      continue;
    }
    if (current) sections[current].push(line);
  }
  return sections;
}

// Option text is "<value> — <description>". Rather than guessing where the
// value ends, match the text against the allowed values: the longest allowed
// value the text starts with, followed by the end of the text or a dash
// (—, – or -) with whitespace on both sides. A value may therefore contain
// spaces or a spaced dash, as GitHub label names can; the allowlist alone
// decides, and there is no second regex spelling out the same values
// (scripts/check-label-forms.sh keeps the forms and labels.yml on this
// convention).
function matchAllowed(text, allowed) {
  const candidates = [...allowed].sort((a, b) => b.length - a.length);
  for (const name of candidates) {
    if (text === name) return name;
    if (text.startsWith(name) && /^\s+[—–-]\s+/.test(text.slice(name.length))) return name;
  }
  return null;
}

// Pure: given the body, the issue's current labels and the area allowlist,
// return what the labels should be and the delta to get there.
function computeChanges({ body, currentLabels, allowedAreas }) {
  const sections = parseSections(body);

  function sectionText(name) {
    const raw = sections[name];
    return raw ? raw.join('\n').trim() : '';
  }
  // Dropdown answers render as a plain text line under the heading.
  // Missing/optional answers render as "_No response_".
  function dropdownPrefix(name) {
    const text = sectionText(name);
    if (!text || text === '_No response_') return null;
    return text.split(/\r?\n/)[0].trim().toLowerCase();
  }

  const desired = new Set();

  // ### Priority -> priority:pX (dropdown, e.g. "p0 — Critical, drop everything")
  const priorityLine = dropdownPrefix('Priority');
  if (priorityLine) {
    const value = matchAllowed(priorityLine, ALLOWED_PRIORITIES);
    if (value) desired.add(`priority:${value}`);
  }

  // ### Subtype -> type:X (task form only; dropdown, e.g. "chore — Maintenance")
  const subtypeLine = dropdownPrefix('Subtype');
  if (subtypeLine) {
    const value = matchAllowed(subtypeLine, ALLOWED_SUBTYPES);
    if (value) desired.add(`type:${value}`);
  }

  // ### Area -> area:* (checkboxes, e.g. "- [x] area:docs — Documentation and guides")
  const areaText = sectionText('Area');
  if (areaText) {
    const checkedLines = areaText.split(/\r?\n/).filter((line) => /^-\s*\[[xX]\]/.test(line));
    for (const line of checkedLines) {
      const value = matchAllowed(line.replace(/^-\s*\[[xX]\]\s*/, '').trim(), allowedAreas);
      if (value) desired.add(value);
    }
  }

  // Only these labels are form-managed; every other label is left untouched.
  // area: stays a prefix match on purpose — that is what cleans up a stale
  // area:old label after an adopter renames their area taxonomy in labels.yml.
  function isFormManaged(label) {
    return (
      label.startsWith('priority:') ||
      FORM_MANAGED_TYPES.includes(label) ||
      label.startsWith('area:')
    );
  }

  const current = currentLabels || [];
  const currentManaged = current.filter(isFormManaged);
  const toAdd = [...desired].filter((label) => !current.includes(label));
  // On 'edited', drop previously form-managed labels the user un-selected.
  // On 'opened' this is a no-op (nothing managed exists yet).
  const toRemove = currentManaged.filter((label) => !desired.has(label));
  return { desired: [...desired], toAdd, toRemove };
}

// Entry point for actions/github-script.
async function run({ github, context, core, repoRoot }) {
  const root = repoRoot || process.env.GITHUB_WORKSPACE || process.cwd();
  const allowedAreas = readAllowedAreas(root);
  if (allowedAreas.length === 0) {
    core.warning(`no area:* entries in ${LABELS_YML} — Area checkboxes will apply nothing`);
  }

  const issue = context.payload.issue;
  const { desired, toAdd, toRemove } = computeChanges({
    body: issue.body || '',
    currentLabels: (issue.labels || []).map((l) => l.name),
    allowedAreas,
  });

  const { owner, repo } = context.repo;
  const issue_number = issue.number;
  if (toAdd.length > 0) {
    await github.rest.issues.addLabels({ owner, repo, issue_number, labels: toAdd });
  }
  for (const label of toRemove) {
    await github.rest.issues.removeLabel({ owner, repo, issue_number, name: label });
  }

  core.info(`Desired: ${desired.join(', ') || '(none)'}`);
  core.info(`Added: ${toAdd.join(', ') || '(none)'}`);
  core.info(`Removed: ${toRemove.join(', ') || '(none)'}`);
  return { desired, toAdd, toRemove };
}

module.exports = {
  run,
  computeChanges,
  parseSections,
  parseAllowedAreas,
  readAllowedAreas,
  matchAllowed,
  ALLOWED_PRIORITIES,
  ALLOWED_SUBTYPES,
  FORM_MANAGED_TYPES,
};
