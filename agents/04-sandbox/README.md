# Sandbox — gVisor for code execution

`exec_code` is the first tool that can change something outside the
cluster's API. Folder 02 allows it only when the caller passes
`sandbox=gvisor` and `approval=granted`. This folder is that runtime.

[gVisor](https://gvisor.dev) (`runsc`) intercepts the container's syscalls
in a user-space kernel. A shell in this pod does not share the node's
kernel the way a normal container does. Kata or Firecracker are the
stronger isolation step when you need a guest kernel or a microVM. The
RuntimeClass name in the blueprint stays `gvisor` until you change both
the policy and this file.

`install.sh` registers the RuntimeClass. It does not install `runsc`.
Doing that from a pod would mean writing to the node's containerd config,
which is a host change, not a lab manifest.

## On each node

```bash
curl -fsSL https://gvisor.dev/archive.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" \
  | sudo tee /etc/apt/sources.list.d/gvisor.list
sudo apt-get update && sudo apt-get install -y runsc
sudo runsc install
sudo systemctl restart containerd
```

`runsc install` registers the handler name `runsc`, which matches
`runtimeclass.yaml`. Restarting containerd drops pods on that node.

kind nodes are containers themselves. gVisor inside kind needs a nested
setup and is a poor place to learn this. Use a real node, or read the
manifest and the policy together and skip the pod.

## Example

```bash
./install.sh
kubectl apply -f code-exec-pod.yaml
kubectl -n agents logs pod/code-exec-sandbox
# sandbox runtime ok
kubectl -n agents delete pod code-exec-sandbox
```

A code-exec MCP tool belongs in a pod with this `runtimeClassName`, the
same way `apps/04` pins its read-only ServiceAccount. The gateway checks
the string. The RuntimeClass checks the node. Both have to be true.
