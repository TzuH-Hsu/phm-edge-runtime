# Licensing

> Adopter note (this repository): the upstream template added the bootstrap
> phase described below after this repository was created, so
> `scripts/bootstrap.sh` here has no phase 9. This repository is Apache-2.0 by
> choice, and `NOTICE` has carried the template's MIT attribution since
> bootstrap (2026-09-02) — the outcome "Manual equivalent" below describes.
> The rest of this page is the upstream text, kept for the reasoning.

`scripts/bootstrap.sh` phase 9 makes you choose a licence for your repository.
This page is the reasoning behind that prompt, the manual equivalent, and both
file bodies verbatim.

**Not legal advice.** Everything here is a starting point written by the
template author, who is not a lawyer. See the last section.

## The template's licence is not your licence

A repository created from this template starts out carrying the *template's*
`LICENSE`: MIT, copyright the template author. Nothing about creating a
repository changes that, and until phase 9 existed nothing in bootstrap did
either.

That is wrong for essentially everyone:

- If you want MIT, the copyright line still has to name **you**.
- If you do not want MIT, you have shipped an irrevocable grant by accident.

## Client and commissioned work: why MIT is the wrong default

MIT grants anyone who obtains a copy the right to use, modify, publish,
distribute, sublicense and **sell** the work. It is written, irrevocable, and
takes effect on receipt.

A commission or work-for-hire agreement normally says something like
"copyright transfers to the client on final payment". An MIT file in the
delivered repository is a much broader grant than that, made to the whole
world rather than the client, and made *before* payment. It does not just
leak rights — it removes the leverage the payment clause was built on.

This is not hypothetical. The report that produced this phase came from an
adopter who shipped four private client repositories carrying the template
author's MIT licence and only noticed afterwards.

## The three answers

| Answer | `LICENSE` becomes | `NOTICE` |
| --- | --- | --- |
| 1. MIT under your name | MIT, copyright you | created |
| 2. Proprietary / all rights reserved | the notice below | created |
| 3. Decide later | untouched | not created |

There is no default. A bare Enter re-asks, and a closed stdin resolves to
answer 3 — the phase would rather write nothing than guess. Under `--yes` it
always takes answer 3 and files the decision as the first remaining manual
step. `--license mit|proprietary|defer` answers it non-interactively.

Choosing anything else — Apache-2.0, GPL, MPL, BUSL — is answer 3. Take the
text from [SPDX](https://spdx.org/licenses/) or
[choosealicense.com](https://choosealicense.com/), and still write `NOTICE`.

## Attribution: what you must keep even if you relicense

Substantial parts of this template ship verbatim in your repository — the
GitHub Actions workflows, the issue and pull request templates, the `Makefile`,
`scripts/` (over 900 lines in `bootstrap.sh` alone), `skills/`, and the `docs/`
structure. MIT says:

> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.

So relicensing your repository is fine — MIT permits sublicensing, and your own
code is yours — but **you may not drop the template's notice from the
scaffolding**. Rewriting `LICENSE`'s copyright line to your name deletes the
only copy of that notice in the repository, which is why phase 9 writes
`NOTICE` on every answer that touches `LICENSE`, including the MIT one.

`NOTICE` rather than a comment inside `LICENSE`, deliberately: a `LICENSE` file
containing both an all-rights-reserved notice and a verbatim MIT grant is
genuinely ambiguous about what a client is receiving, and a client's counsel
reads `LICENSE` and nothing else. `NOTICE` is also where licence scanners look,
which matters when a client runs an open-source audit on delivery.

## Proprietary notice (the text bootstrap writes)

`__YEAR__` and `__HOLDER__` are substituted with the current year and the
copyright holder you give the prompt.

```text
PROPRIETARY SOFTWARE -- ALL RIGHTS RESERVED

Copyright (c) __YEAR__ __HOLDER__. All rights reserved.

1. No licence granted

   This repository and its contents (the "Work") are proprietary and
   confidential. No licence, express or implied, is granted by this file. You
   may not use, copy, modify, merge, publish, distribute, sublicense, sell, or
   create derivative works of the Work, in whole or in part, except under a
   separate written agreement signed by the copyright holder named above.

2. Commissioned work

   If the Work was produced under a commission, services, or work-for-hire
   agreement, that agreement -- not this file -- determines who owns the Work
   and when ownership or a licence passes to the commissioning party (commonly
   on final payment). Until the conditions of that agreement are met, all
   rights remain with the copyright holder named above. This file does not
   transfer, assign, or waive anything, and it does not modify that agreement.

3. Third-party components

   The scaffolding in this repository derives from third-party open-source
   software, which remains under its own licence. See the NOTICE file.
   Sections 1 and 2 do not apply to those components, and nothing in NOTICE
   grants any right in the rest of the Work.

4. No warranty

   THE WORK IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW.

--------------------------------------------------------------------------
Template-generated example -- NOT LEGAL ADVICE.

This file was written into your repository by scripts/bootstrap.sh from a
generic example shipped with a project template. It has not been reviewed by a
lawyer, it is not tailored to your jurisdiction, your business, or your
contract, and a notice file cannot override, replace, or complete the terms of
a signed agreement. Have your own counsel review it. Once they have, delete
this trailer.
--------------------------------------------------------------------------
```

## NOTICE (the text bootstrap writes)

The copyright line here is the **template's**, not yours, and that is the whole
point — this file exists to carry the upstream notice. Do not substitute your own
name into it; your identity belongs in `LICENSE`.

```text
NOTICE — third-party attribution

This repository's scaffolding — the GitHub Actions workflows, issue and pull
request templates, Makefile, scripts/, skills/, and the docs/ structure —
derives from GitHub Project OS and is used under the MIT Licence.

The MIT Licence requires that its copyright notice and permission notice be
included in all copies or substantial portions of that software. They are
reproduced below for that purpose, and must be kept in this repository even if
the rest of it is relicensed.

The terms below apply ONLY to that scaffolding. They grant no rights in any
other part of this repository; see LICENSE for those.

--------------------------------------------------------------------------
GitHub Project OS — https://github.com/TzuH-Hsu/github-project-os

MIT License

Copyright (c) 2026 TzuH-Hsu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--------------------------------------------------------------------------
```

## Manual equivalent

If you are not running bootstrap, do the same thing by hand:

```bash
# 1. Replace LICENSE with your chosen licence, naming YOU as the holder.
#    (For MIT, keep the body and change only the copyright line.)

# 2. Create NOTICE with the block above, so the template's MIT notice survives.

# 3. If your project is not MIT, update README.md -- the starter README's
#    License section and any licence badge still point at MIT.
```

## Not legal advice

The mechanics above are the defensible parts: MIT requires notice retention,
keeping that notice in `NOTICE` is standard practice, and relicensing a
combined work is permitted. The following are **not** things this page can
answer, and a lawyer should:

1. Whether putting the notice in `NOTICE` rather than `LICENSE` satisfies
   "included in all copies" for your situation.
2. Whether an all-rights-reserved notice conflicts with your commission
   contract's IP clause — if that clause already assigns copyright on
   signature, naming yourself as holder may be wrong from day one.
3. Whether copyright actually transfers on payment in your jurisdiction, or
   needs a separate signed assignment.
4. Moral rights, which are inalienable in many jurisdictions and are not
   addressed by a blanket "all rights reserved".
5. **The one most likely to bite:** whether your client contract warrants "no
   open-source components" or requires a disclosed bill of materials.
   MIT-licensed scaffolding, even correctly attributed, can breach such a
   clause. `NOTICE` makes that visible rather than creating it — but you have
   to go and read your contract.

## See also

- `docs/setup/bootstrap.md` — this repository's (older) bootstrap phases
- upstream `docs/adr/ADR-0004-adopter-licence-choice.md` (<https://github.com/TzuH-Hsu/github-project-os/blob/main/docs/adr/ADR-0004-adopter-licence-choice.md>) — why this is a phase at all; this repository's `docs/adr/` numbers its own decisions
