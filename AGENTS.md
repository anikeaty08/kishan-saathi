# Kishan Saathi Project Rules

These rules apply to every human or AI contributor working in this repository.

## Engineering standard

- Correctness, safety, and maintainability take priority over finishing quickly.
- Do not take shortcuts merely to make a task appear complete. Do not hide
  failures, fabricate results, bypass validation, weaken authorization, or call
  a placeholder implementation production-ready.
- Inspect the existing code, requirements, and interfaces before changing them.
  Preserve established behavior unless the requested change explicitly replaces
  it.
- When an answer or implementation detail is unknown, investigate it. Search the
  codebase first, then consult current primary documentation or other reliable
  sources. Do not guess when the fact can be verified.
- Work confidently and persistently, but communicate real uncertainty honestly.
  If a task cannot be completed safely, explain the exact blocker and the next
  useful action instead of forcing an unreliable solution.
- Do not mark work complete until the relevant checks pass. Verification should
  be proportional to risk and should cover success, validation failure,
  authorization boundaries, and external-provider failure where applicable.
- Keep implementation modular and typed. Prefer explicit contracts, Pydantic
  validation, dependency injection, provider plugins, and structured logging to
  provider-specific condition chains or hidden global state.
- Never commit secrets, credentials, private farmer data, local environments,
  uploaded images, model checkpoints, or generated runtime files.

## Leaf-diagnosis input contract

- A diagnosis request accepts one or more leaf images from the camera or gallery.
- The plant or crop name is optional. A farmer must be able to submit images
  without knowing the plant name.
- When a plant name is supplied, treat it as typed context that can narrow or
  rerank compatible disease candidates. Do not treat it as unquestionable truth
  and do not let it replace evidence from the images.
- Multi-image requests belong to one diagnosis case. Validate every image,
  preserve per-image quality information, and combine the evidence into one
  case-level result.
- Low-quality or low-confidence input should produce possible diagnoses and a
  clear request for better images; it must not produce false certainty.
- Keep the diagnosis result linked to its images, optional plant context, farmer,
  chat, and farm or plot when one was selected.

## Git contribution workflow

- Do not push project changes directly to `main`.
- Create a focused branch using the `codex/` prefix, commit only files belonging
  to the task, push that branch, and open a pull request into `main`.
- Keep unrelated local or untracked files out of the commit.
- Do not force-push, rewrite shared history, or merge the pull request unless the
  user explicitly requests it.
- The pull-request description must state what changed, how it was verified, and
  any known limitation or deferred work.
