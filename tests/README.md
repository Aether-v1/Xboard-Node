# Nezha installer smoke tests

The shell harness uses test-only credentials and mocks the panel, Agent download,
`systemctl`, and the Agent binary. It never connects to a production dashboard.

Fetch the pinned official script as a local test fixture:

```sh
git clone https://github.com/nezhahq/scripts.git /tmp/nezha-scripts-ref
git -C /tmp/nezha-scripts-ref checkout 26b81c4ad221ee2356a71f7d7563e68550b2e7a3
```

From the Xboard-Node repository, run in a Linux environment with Docker:

```sh
for case in normal disabled repeat orphaned_binary malformed fetch_failed agent_failed \
  node_survives_agent_failure node_survives_config_failure upgrade_uninstall; do
  docker run --rm -v "$PWD:/src:ro" \
    -v /tmp/nezha-scripts-ref:/official:ro python:3.12-slim \
    bash /src/tests/test_nezha_installer.sh "$case"
done
```

These tests exercise installer control flow. They do not prove that a real VPS can
connect to a live Nezha dashboard or that the upstream Agent release is healthy.
