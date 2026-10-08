# MetalLB — LoadBalancer IPs on bare metal

**Why:** In a lab there is no cloud load balancer. MetalLB hands out real LAN
IPs to `Service type=LoadBalancer`, so the Envoy AI Gateway gets a stable IP
you can `curl` from your laptop.

**Skip if (the default in this repo):** you use Cilium LB-IPAM + L2 announcements
(platform/00-cilium/lb-ipam.yaml). Also skip if you already have another LB (
kube-vip, a cloud LB).

```bash
./install.sh                               # installs controller + speaker
vi ip-pool.yaml                            # set a FREE range on your LAN
kubectl apply -f ip-pool.yaml
```

Pick a range your DHCP server does not hand out (e.g. `192.168.1.240-192.168.1.250`).
