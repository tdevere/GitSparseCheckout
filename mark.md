Update on the sparse checkout behavior — root cause identified

**Problem statement:** On Azure DevOps Server 2025 (`20.256.36719.1`), the
`sparseCheckoutDirectories` and `sparseCheckoutPatterns` properties of the
`checkout` step are silently ignored. The pipeline task performs a full clone
every time, regardless of which sparse property is set or how it is configured.
No error is raised and the build does not fail — the property has no observable
effect on the working tree or the git commands issued by the agent.

We have now identified the specific root cause in the agent source code.

**Root cause:** In `src/Agent.Sdk/Knob/AgentKnobs.cs`, the feature knob
`UseSparseCheckoutInCheckoutTask` is defined with a built-in default of `false`
and only a `RuntimeKnobSource` — no `PipelineFeatureSource`, no
`EnvironmentKnobSource`. In `src/Agent.Plugins/GitSourceProvider.cs`, the entire
`git sparse-checkout` code block is wrapped inside a conditional on this knob:

```
if (AgentKnobs.UseSparseCheckoutInCheckoutTask.GetValue(ctx).AsBoolean())
{
    // git sparse-checkout init
    // git sparse-checkout set
}
```

On cloud ADO, Microsoft enables this knob server-side for all organizations. On
ADO Server 2025 on-premises there is no equivalent mechanism — the knob defaults
to `false`, the conditional is never entered, and no `git sparse-checkout`
commands are ever issued. The YAML properties are parsed correctly by the
pipeline engine (they appear in the schema validation log), but the agent
silently skips acting on them.

**Immediate workaround for any pipeline:** Add one pipeline variable:

```yaml
variables:
  - name: AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK
    value: "true"
```

This sets the `RuntimeKnobSource` value to `true` and unblocks the sparse
checkout code path. We have a test pipeline running now (build queued against
`.azuredevops/server2025-knob-test.yml`) that runs the same YAML with and
without the variable side-by-side to produce a binary confirmation.

**What this means for the fix:** The correct on-premises fix is for ADO Server
2025 to either (a) ship a patch that sets this knob to true by default on-prem,
or (b) document the variable requirement — neither is the case today. The
release notes describe sparse checkout as fully supported with agent v4.248.0+.
Our agent is v4.260.0, the code is present, but the activation switch is never
turned on.

Key versions:

| Property              | Value                                             |
|-----------------------|---------------------------------------------------|
| ADO Server            | 20.256.36719.1 (AzureDevOps25H2)                 |
| Agent                 | v4.260.0                                         |
| Git                   | 2.49.0.windows.1                                 |
| Agent OS              | Windows NT                                       |
| Knob (agent source)   | `UseSparseCheckoutInCheckoutTask`                |
| Knob default          | `false`                                          |
| Knob fix variable     | `AGENT_USE_SPARSE_CHECKOUT_IN_CHECKOUT_TASK=true` |

We have full build logs, workspace inspection output, two validated workarounds
in CI, and are now running a knob-isolation test. Happy to share the repo, raw
logs, or the specific source file references if that helps the fix.
