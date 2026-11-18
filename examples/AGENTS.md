# Adobe automation instructions (copy into your workspace AGENTS.md)

- Launch Adobe only via scripts/launch-adobe-fullenv.ps1 or Start-AdobeApp, then attach.
- Never start a second instance or kill an app the person may be using.
- Never click or synthesize keys. Ask the person to handle one specific dialog/button.
- Before blaming installation/version or recommending reinstall, compare the required
  environment variables in manually launched and agent-launched processes. Use an
  authorized isolated A/B reproduction; keep the version constant.
- Stop on env-missing or env-unreadable. Do not bypass environment preflight.
- Configuration changes take effect in a new agent session; existing apps keep their old environment.
- Judge job success by its VERDICT line. OK started proves launch only, not job success.
- Never publish tokens, full environment dumps or private paths.
