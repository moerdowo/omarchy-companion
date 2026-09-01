# Security policy

## Supported version

Security fixes are made on the latest release line. Reproduce a report on the
current version before filing it when practical.

## Reporting a vulnerability

Open a GitHub issue containing only a request for private contact. Do not put
the vulnerability, exploit, tokens, conversation contents, personal paths, or
other user data in that issue. A maintainer will establish a private channel;
include the Omarchy Companion and Omarchy versions, the smallest reproduction you can
provide, and the security boundary crossed there.

Useful reports include command or argument injection, path traversal, unsafe
plugin/config migration, unintended writes outside Omarchy Companion's documented
config and state, duplicate agent execution, or a stale process callback that
can affect a later turn.

## Trust boundary

Omarchy plugins execute unsandboxed inside the long-lived `omarchy-shell`
process. Omarchy Companion does not make that boundary narrower.

An explicit bubble submission or `omarchy-shell companion order …` call runs
the selected agent headlessly and unattended. Depending on the agent and the
installed Omarchy version, that mode may approve actions automatically or
bypass approval and sandbox checks entirely. Sending an order to the Quake
console or opening a saved conversation there makes the process visible and
steerable, but does not create a sandbox or promise per-tool confirmation.
Opening an empty console starts no order until the user enters one; forwarding
an order to it starts that order immediately.

The selected agent has the same filesystem and network reach its CLI has in a
terminal. Apart from the agent it launches, Omarchy Companion's own runtime makes no
network request and sends no telemetry. The plugin code itself may write only
its documented state plus this plugin's own entry in Omarchy's `shell.json`,
including the documented one-time migration of pre-4.0 entries. It must not
install agent hooks, edit another application's settings, or execute an order
without a user action or explicit IPC call. Reports that show it crossing one
of those boundaries are security issues.
