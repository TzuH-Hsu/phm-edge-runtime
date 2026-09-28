// SPDX-License-Identifier: MIT
'use strict';
// pr-lint.js — the pull-request checks behind the `Lint the pull request`
// step in .github/workflows/ci.yml. Same shape as scripts/issue-labeler.js
// (ADR-0008): a pure lint() the tests exercise, and one run() the workflow
// calls through actions/github-script. It reads the pull_request payload and
// makes one read call — does the linked issue exist, and is it an issue — then
// fails the job with a message that names the fix.
//
// What it enforces — the two conventions AGENTS.md states and the PR template
// carries, which were being broken silently:
//   1. the head branch is `<type>/<issue#>-<slug>`;
//   2. the body links an issue with a GitHub closing keyword (`Closes #N`);
//   3. exactly one issue in this repository is closed, and it is the branch's;
//   4. that issue exists, is open, and is an issue, not a pull request (a
//      made-up or already-closed number would otherwise satisfy 1-3).
// Bot PRs (release-please, Dependabot) have no issue and are exempt — by WHO
// opened them, never by branch name: on a public repository a fork author
// picks the head branch name, so `release-please--…` proves nothing.
//
// The PR body is untrusted input. It is only ever matched as text here; the
// numbers it yields go into a message, never into a command.

// The Conventional Commit types AGENTS.md lists (its "Branch" step is the one
// home for this list; pr-lint.test.js asserts the two are equal). The branch
// type mirrors them.
const TYPES = ['feat', 'fix', 'docs', 'chore', 'refactor', 'ci', 'test', 'perf'];
const BRANCH_RE = new RegExp(`^(${TYPES.join('|')})/(\\d+)-[a-z0-9][a-z0-9._-]*$`);
// GitHub's closing keywords: optional colon, then `#N`, `owner/repo#N`, or a
// full issue URL — the three forms GitHub itself links and auto-closes.
const CLOSES_RE = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\s+(?:https?:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/issues\/(\d+)|([\w.-]+\/[\w.-]+)?#(\d+))\b/gi;
// Exempt when the PR was opened by one of these accounts (Dependabot;
// release-please run with the default GITHUB_TOKEN), or carries the label
// release-please always applies (covers release-please run with a PAT, where
// the author is a human account). A fork author can choose neither.
const EXEMPT_AUTHORS = ['dependabot[bot]', 'github-actions[bot]'];
const EXEMPT_LABELS = ['autorelease: pending'];

// GitHub links closing keywords in prose only: not inside HTML comments,
// fenced code blocks or inline code spans. Strip those before matching so the
// check agrees with what GitHub will actually close. Linear scanners, not
// lazy regexes — the body is attacker-controlled and up to 65,536 chars.
//
// Order matters (CommonMark): block constructs first, line by line, whichever
// opens first wins — a `<!--` inside a fence is code, a ``` inside an HTML
// comment block is comment; then inline code spans; then inline comments,
// because a backtick to the left of `<!--` makes the comment marker code.

// Block pass. A fence line (3+ backticks or tildes, ≤3 spaces indent) opens a
// fence closed by a line of the same character at least that long; unclosed,
// it runs to EOF. A line-start `<!--` opens an HTML block (type 2) that ends
// on the line containing `-->` (that whole line included); unclosed, EOF.
// Blockquotes: `>` markers are stripped before a line is tested, and a fence
// or comment opened inside a quote ends when that quote does (a line with
// fewer `>` markers). Indentation is measured in columns with 4-column tab
// stops. An indented code block — lines indented 4+ columns past the current
// container, after a blank line or more indented code — is code; inside a
// list item the container is the item's content column (marker width plus
// the spaces after it), so shallower indentation continues the item's prose.
// Only an open paragraph stops an indented code block — a line right after a
// fence, a comment block, a heading or a blank line can start one. List items
// nest: each open item's content column is kept, and a line outside a
// paragraph that sits left of an item's column closes that item (and a fence
// opened inside it).
//
// This is an approximation of CommonMark's container rules, checked against
// markdown-it on 6,000 generated bodies: no disagreement unless blockquote,
// list and fence all nest (27 such bodies, lists inside quotes holding
// fences). That is out of scope for
// a PR-body convention check — the consequence is a closing keyword counted,
// or not, when GitHub would do the opposite, and the issue is then closed by
// hand.
const MARKER_RE = /^([-*+]|\d{1,9}[.)])([ \t]+|$)/;
// Leading indentation of `s` in columns, counting tab stops from the
// absolute column `start` where `s` begins.
function lead(s, start = 0) {
  let col = start;
  let i = 0;
  for (; i < s.length; i++) {
    if (s[i] === ' ') col += 1;
    else if (s[i] === '\t') col += 4 - (col % 4);
    else break;
  }
  return { col: col - start, rest: s.slice(i) };
}
// Up to `max` blockquote markers removed: { depth, body, start }. A marker's
// optional padding is one column — a space, or one column of a tab, whose
// remaining columns stay in the body as spaces (CommonMark).
function unquote(line, max = Infinity) {
  let i = 0;
  let col = 0;
  let depth = 0;
  let carry = 0;
  const marks = []; // per level: column of its `>`, relative to the enclosing level's content
  let prevContent = 0;
  while (depth < max) {
    let j = i;
    let c = col;
    for (let k = 0; k < 3 && line[j] === ' '; k++) { j++; c++; }
    if (line[j] !== '>') break;
    marks.push(c - prevContent);
    j++; c++; depth++;
    carry = 0;
    if (line[j] === ' ') { j++; c++; }
    else if (line[j] === '\t') { const w = 4 - (c % 4); j++; carry = w - 1; c += 1; }
    i = j;
    col = c;
    prevContent = c;
  }
  return { depth, body: ' '.repeat(carry) + line.slice(i), start: col, marks };
}
const HEADING_RE = /^#{1,6}(?:[ \t]|$)/;
const BREAK_RE = /^(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$/;
// Would this line start a block that can interrupt a paragraph (and so is
// never a lazy continuation)? Blank lines count: they end the paragraph.
function startsBlock(rest) {
  if (rest === '' || rest.startsWith('<!--') || HEADING_RE.test(rest) || BREAK_RE.test(rest)) return true;
  const f = rest.match(/^(`{3,}|~{3,})(.*)$/);
  if (f && !(f[1][0] === '`' && f[2].includes('`'))) return true;
  const m = rest.match(MARKER_RE);
  return !!m && rest.slice(m[0].length).trim() !== '' && (!/^\d/.test(m[1]) || parseInt(m[1], 10) === 1);
}
function stripBlocks(text) {
  const kept = [];
  let fence = null; // { ch, len, depth, base }
  let comment = null; // quote depth of an open HTML comment block
  let para = false; // an open paragraph: only it stops an indented code block
  let indented = false; // inside an indented code block
  let items = []; // content columns of the open list items, outermost first
  let prevDepth = 0;
  const saved = []; // per quote depth: that level's list items, kept while a deeper quote is open
  const top = () => (items.length ? items[items.length - 1] : 0);
  for (const line of text.split('\n')) {
    const u0 = unquote(line);
    const { body, start, marks } = u0;
    // a lazy continuation line (fewer `>` inside an open paragraph, and itself
    // paragraph text rather than a block start) stays in the quote: the
    // containers remain open until the paragraph ends
    const depth = u0.depth < prevDepth && para && !startsBlock(lead(body, start).rest) ? prevDepth : u0.depth;
    if (depth > prevDepth) {
      // a quote opened inside a list item keeps that item for after the quote;
      // one opened left of an item's content column ends the item
      saved[prevDepth] = items.filter((c) => c <= marks[prevDepth]);
      for (let k = prevDepth + 1; k < depth; k++) saved[k] = [];
      para = false; indented = false; items = [];
    } else if (depth < prevDepth && (!para || body.trim() === '')) {
      // a quote ends on a line with fewer markers, unless it lazily continues
      // the quote's paragraph; a blank line always ends it
      indented = false;
      items = saved[depth] || [];
      saved.length = depth;
    }
    prevDepth = depth;
    if (fence) {
      const u = unquote(line, fence.depth);
      const inner = lead(u.body, u.start);
      const itemEnded = fence.base > 0 && inner.rest !== '' && inner.col < fence.base;
      if (depth >= fence.depth && !itemEnded) {
        // only the fence's own quote markers — a deeper `>` is code content
        const c = inner.rest.match(/^(`+|~+)[ \t]*$/);
        if (c && inner.col - fence.base <= 3 && c[1][0] === fence.ch && c[1].length >= fence.len) fence = null;
        continue;
      }
      fence = null; // its blockquote or list item ended, so did the fence
    }
    if (comment !== null) {
      if (depth >= comment) {
        if (line.includes('-->')) comment = null;
        continue;
      }
      comment = null;
    }
    const { col, rest } = lead(body, start);
    if (rest === '') { para = false; kept.push(line); continue; }
    let fm = rest.match(/^(`{3,}|~{3,})(.*)$/);
    // a backtick fence's info string may not contain a backtick — such a line
    // is inline code, not a fence
    if (fm && fm[1][0] === '`' && fm[2].includes('`')) fm = null;
    // outside a paragraph, a line left of an item's content column ends that
    // item; inside one, so does a block that interrupts the paragraph (a fence,
    // a comment block, a heading, a break) — only paragraph text continues lazily
    const starts = fm !== null || rest.startsWith('<!--') || HEADING_RE.test(rest) || BREAK_RE.test(rest);
    if (!para || starts) while (items.length && col < top()) items.pop();
    const base = top();
    if (!para && col >= base + 4) { indented = true; continue; }
    indented = false;
    const rel = col - base;
    const f = rel <= 3 ? fm : null;
    if (f) { fence = { ch: f[1][0], len: f[1].length, depth, base }; para = false; continue; }
    if (rel <= 3 && rest.startsWith('<!--')) {
      if (!rest.slice(4).includes('-->')) comment = depth;
      para = false;
      continue;
    }
    if (rel <= 3 && (HEADING_RE.test(rest) || BREAK_RE.test(rest))) { para = false; kept.push(line); continue; }
    let m = rel <= 3 ? rest.match(MARKER_RE) : null;
    // an ordered marker other than 1, or an empty item, cannot interrupt a paragraph
    if (m && para && ((/^\d/.test(m[1]) && parseInt(m[1], 10) !== 1) || rest.slice(m[0].length).trim() === '')) m = null;
    if (m) {
      while (items.length && col < top()) items.pop(); // a sibling or outer marker closes deeper items
      // the padding after the marker in columns, tabs to 4-column stops
      const end = col + m[1].length;
      let pad = end;
      for (const ch of m[2]) pad += ch === '\t' ? 4 - (pad % 4) : 1;
      const gap = m[2] === '' || pad - end > 4 ? 1 : pad - end;
      items.push(end + gap);
      if (pad - end > 4 && rest.slice(m[0].length).trim() !== '') {
        // one column of padding, the rest indents the item's first line: code
        para = false;
        indented = true;
        continue;
      }
      para = m[2] !== '' && rest.slice(m[0].length).trim() !== '';
    } else {
      para = true;
    }
    kept.push(line);
  }
  return kept.join('\n');
}

// Inline code (CommonMark): a run of N backticks is closed by the next run of
// exactly N. A run length that finds no closer never will later either, so
// each length fails at most once — linear in practice, bounded regardless.
function stripCodeSpans(text) {
  let out = '';
  let i = 0;
  const failed = new Set();
  while (i < text.length) {
    if (text[i] !== '`') { out += text[i++]; continue; }
    let j = i;
    while (j < text.length && text[j] === '`') j++;
    const n = j - i;
    if (!failed.has(n)) {
      let k = j;
      let closed = false;
      while (k < text.length) {
        if (text[k] !== '`') { k++; continue; }
        let m = k;
        while (m < text.length && text[m] === '`') m++;
        if (m - k === n) { closed = true; break; }
        k = m;
      }
      if (closed) { i = k + n; continue; }
      failed.add(n);
    }
    out += text.slice(i, j);
    i = j;
  }
  return out;
}

// Inline HTML comments (block ones are gone by now): `<!-- … -->` is dropped,
// across lines if need be; an unterminated `<!--` is literal text, which
// GitHub renders — and links — as prose, so it is kept.
function stripInlineComments(text) {
  let out = '';
  let i = 0;
  let noCloser = false; // once a search for `-->` fails, every later one would too
  while (i < text.length) {
    const open = text.indexOf('<!--', i);
    if (open === -1) { out += text.slice(i); break; }
    out += text.slice(i, open);
    const close = noCloser ? -1 : text.indexOf('-->', open + 4);
    if (close !== -1) { i = close + 3; continue; }
    noCloser = true;
    out += '<!--';
    i = open + 4;
  }
  return out;
}

function stripNonProse(text) {
  // GitHub normalises line endings before rendering; so do we, or a CRLF body
  // hides every fence's closing line (`~~~\r` is not a fence).
  const lf = String(text || '').replace(/\r\n?/g, '\n');
  return stripInlineComments(stripCodeSpans(stripBlocks(lf)));
}
const stripHtmlComments = stripNonProse; // kept for callers of the old name

// Every issue the body closes: [{ repo: 'owner/name' | null, number }]. A
// reference qualified with this repository's own name counts as local.
function linkedIssues(body, repo) {
  const seen = new Map();
  for (const m of stripNonProse(body).matchAll(CLOSES_RE)) {
    const qualifier = m[1] || m[3] || null;
    const number = Number(m[2] || m[4]);
    const local = !qualifier || (repo && qualifier.toLowerCase() === String(repo).toLowerCase());
    const key = `${local ? '' : qualifier + '#'}${number}`;
    if (!seen.has(key)) seen.set(key, { repo: local ? null : qualifier, number });
  }
  return [...seen.values()];
}

function describe(ref) {
  return ref.repo ? `${ref.repo}#${ref.number}` : `#${ref.number}`;
}

function isExempt({ author, labels }) {
  if (author && EXEMPT_AUTHORS.includes(author)) return `opened by ${author}`;
  const hit = (labels || []).find((l) => EXEMPT_LABELS.includes(l));
  return hit ? `carries the '${hit}' label` : null;
}

// Pure. `repo` is 'owner/name' when known (run() passes context.repo), so a
// fully qualified self-reference is treated as local. `author` is the PR
// author's login and `labels` the PR's label names.
// Returns { exempt, why, problems: [string], branchIssue, linked: [number], cross: [string] }.
function lint({ headRef, body, repo, author, labels }) {
  const ref = String(headRef || '');
  const refs = linkedIssues(body, repo);
  const linked = refs.filter((r) => !r.repo).map((r) => r.number);
  const cross = refs.filter((r) => r.repo).map(describe);
  const why = isExempt({ author, labels });
  if (why) {
    return { exempt: true, why, problems: [], branchIssue: null, linked, cross };
  }
  const problems = [];
  const branch = ref.match(BRANCH_RE);
  const branchIssue = branch ? Number(branch[2]) : null;
  if (!branch) {
    problems.push(
      `branch '${ref}' is not <type>/<issue#>-<slug> (types: ${TYPES.join(', ')}; e.g. fix/42-label-sync) — ` +
        'the usual slip is an empty issue number, which reads as "<type>/-<slug>"',
    );
  }
  if (linked.length === 0) {
    problems.push(
      'body links no issue in this repository — the PR template line is `Closes #<!-- issue number -->`; replace the comment ' +
        'with the number. Any GitHub closing keyword works: Closes / Fixes / Resolves, optional colon, #N or a full issue URL ' +
        '(prose only — not inside code or an HTML comment). If this PR only advances an issue, give it a sub-issue it can close — skills/pr-authoring rule 5',
    );
  }
  if (cross.length > 0) {
    problems.push(
      `body closes ${cross.join(', ')} in another repository — one issue per PR, and it lives here (skills/pr-authoring rule 5); ` +
        'mention the other issue with "Refs" instead',
    );
  }
  if (linked.length > 1) {
    problems.push(
      `body closes #${linked.join(', #')} — one issue per PR (skills/pr-authoring rule 5): keep the one this branch is for, ` +
        'and close a genuine duplicate by hand after merge',
    );
  } else if (branchIssue !== null && linked.length === 1 && linked[0] !== branchIssue) {
    problems.push(
      `branch names issue #${branchIssue} but the body closes #${linked[0]} — one of them is wrong`,
    );
  }
  return { exempt: false, why: null, problems, branchIssue, linked, cross };
}

// The one API read: 404 → the number is invented; a pull_request field →
// the number is a PR, which GitHub would not close. Any other failure is a
// failure — a check that cannot check must not pass.
async function verifyIssue(github, owner, repo, number) {
  let issue;
  try {
    ({ data: issue } = await github.rest.issues.get({ owner, repo, issue_number: number }));
  } catch (err) {
    if (err && err.status === 404) return `issue #${number} does not exist in ${owner}/${repo} — the number is wrong, or the issue was never opened (AGENTS.md rule 1)`;
    if (err && err.status === 410) return `issue #${number} was deleted — link the issue the work is for, or open a new one`;
    // 403 here is the job's token, not the PR: on a private repository the
    // read needs `issues: read` and `pull-requests: read` (the ci job's permissions in ci.yml).
    if (err && err.status === 403) throw new Error(`could not verify issue #${number}: ${err.message} — the workflow's GITHUB_TOKEN cannot read issues; on a private repository the job needs \`issues: read\` and \`pull-requests: read\` on the ci job's permissions block`);
    throw new Error(`could not verify issue #${number}: ${err && err.message ? err.message : err}`);
  }
  if (issue && issue.pull_request) return `#${number} is a pull request, not an issue — link the issue the work is for`;
  if (issue && issue.state === 'closed') return `issue #${number} is already closed, so merging cannot close it — reopen it, or open a follow-up issue and link that`;
  return null;
}

// Entry point for actions/github-script.
async function run({ github, context, core }) {
  const pr = context.payload.pull_request;
  if (!pr) {
    core.info('not a pull_request event — nothing to lint');
    return { exempt: true, problems: [] };
  }
  // A closed PR (merged or not) has no merge left to gate; editing its body
  // still fires `edited`, and a red run there only adds noise.
  if (pr.state === 'closed') {
    core.info(`PR lint skipped: pull request #${pr.number} is closed`);
    return { exempt: true, why: 'closed', problems: [] };
  }
  const repo = context.repo ? `${context.repo.owner}/${context.repo.repo}` : undefined;
  const result = lint({
    headRef: pr.head && pr.head.ref,
    body: pr.body,
    repo,
    author: pr.user && pr.user.login,
    labels: (pr.labels || []).map((l) => l.name),
  });
  if (result.exempt) {
    core.info(`PR lint skipped: ${result.why}`);
    return result;
  }
  if (result.problems.length === 0 && github && context.repo) {
    const problem = await verifyIssue(github, context.repo.owner, context.repo.repo, result.linked[0]);
    if (problem) result.problems.push(problem);
  }
  if (result.problems.length > 0) {
    core.setFailed(`PR lint failed:\n- ${result.problems.join('\n- ')}`);
    return result;
  }
  const also = result.cross.length > 0 ? ` (and ${result.cross.join(', ')} elsewhere)` : '';
  core.info(`PR lint passed: branch issue #${result.branchIssue}, body closes #${result.linked.join(', #')}${also}`);
  return result;
}

module.exports = { run, lint, verifyIssue, isExempt, linkedIssues, describe, stripNonProse, stripBlocks, stripCodeSpans, stripInlineComments, stripHtmlComments, TYPES, BRANCH_RE, CLOSES_RE, EXEMPT_AUTHORS, EXEMPT_LABELS };
