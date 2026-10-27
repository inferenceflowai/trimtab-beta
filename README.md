# Trimtab beta

**Small adjustments. Big runs.** Trimtab tests your training project on your Mac with a few smart trials, then hands you one
command for the full GPU run.

> **Beta.** Free to use during the beta, rough in places. This repository holds the installer and release binaries only —
> there is no source code here.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/rayzhao27/trimtab-beta/main/install.sh | bash
trimtab
```

Requirements: an **Apple Silicon Mac** (M1 or newer) and an **API key** for one model provider (Anthropic, OpenAI, Gemini, …)
or a local model (Ollama / LM Studio). Nothing else: the installer brings its own Python and does not touch yours.

- Update: `trimtab update` · Uninstall: `trimtab uninstall`
- Pin a version: `TRIMTAB_VERSION=0.1.0b1 curl -fsSL …/install.sh | bash`

## What happens to your data
Your data, datasets and full code stay on your Mac. Only a short excerpt of your training script, its `--help` text and the start
of its README, per-trial summaries and the settings tried go to the model provider you choose, using your own key. The app shows
the exact list on first start ("What's sent to the AI").

## Feedback
Use **Feedback** inside the app (left rail). You see the exact text before it is sent.

## Terms
By using the beta you agree to the [beta terms](BETA_TERMS.md) (DRAFT). See also [LICENSE.md](LICENSE.md).

© 2026 Inference Flow AI Studio
