# 17 — Reliability engineering and chaos for AI platforms

Material: [`reliability/`](../reliability/README.md).

## 1. Why AI platforms fail differently

* **Synchronous training amplifies failure.** In a 1024-GPU data-parallel
  job, *one* GPU dying stops all 1024. The job's failure rate is the sum of
  every component's failure rate.
* **Recovery is expensive.** Restarting means rescheduling, pulling 15 GB
  images, NCCL init across hundreds of nodes, loading checkpoints from
  storage, and redoing all work since the last checkpoint.
* **Serving has long-lived state.** A streaming response can last minutes,
  and KV caches take time to rebuild. "Just restart the pod" has user-visible
  cost.
* **Hardware is the dominant failure source**: GPUs, HBM, NVLink, NICs and
  optics, more than software.

## 2. Goodput math (training)

```
goodput = productive_compute_time / allocated_time

Expected loss per failure ≈ restart_time + checkpoint_interval / 2
Failures per day           = num_gpus × per_gpu_failure_rate
```

Example: 1,024 GPUs with one job-killing failure every 10 hours. Checkpoint
every 60 min (average loss 30 min) plus a 15 min restart gives about 45 min
lost per 10 h, so **goodput ≈ 92.5%**. Checkpoint every 15 min
(asynchronously, so saving is ~free) plus a 5 min restart gives about 12.5
min lost, or **≈ 98%**. At $2/GPU-hour ($49k/day for this job), that 5.4-point difference is about $2.7k/day
on this job.

The **optimal checkpoint interval** (Young/Daly approximation) is
√(2 × checkpoint_cost × MTBF). Checkpoint cost is the pause the job takes to
checkpoint, which async checkpointing makes small.

Levers, in order of usual impact: faster detection (minutes, not hours) →
faster restart (pre-pulled images, hot spares, quick NCCL init) → cheaper
and more frequent checkpoints → fewer failures (burn-in, quarantine of flaky
nodes).

## 3. Serving reliability patterns

| Pattern | Where in this repo |
|---|---|
| ≥ 2 replicas per production model, spread across nodes | production-stack `replicaCount`, topology spread constraints |
| retries *before first byte* only | `reliability/02-experiments/fix-gateway-retries.yaml` |
| fallback to another backend or model | AIGatewayRoute `priority` (gateway/03 optional-external-provider.yaml) |
| graceful drain on rollout (finish in-flight streams) | `terminationGracePeriodSeconds` ≥ max generation time; vLLM handles SIGTERM |
| admission control and load shedding | token budgets at the gateway, `--max-num-seqs`, queue-length limits |
| slow cold starts absorbed | `minReplicas ≥ 1`, weight cache, KEDA scale-up before saturation |
| multi-node groups restart atomically | LWS `RecreateGroupOnPodRestart` |
| bad hardware quarantined automatically | `reliability/03-gpu-health` |

## 4. Chaos engineering: method

1. **Define steady state** with SLIs, e.g. TTFT p95 < 1 s, error rate
   < 0.5%, training step time 1.2 s ± 5%.
2. **Hypothesis**: "If one vLLM replica dies, error rate stays < 1% and TTFT
   p95 recovers within 2 min."
3. **Inject** the smallest realistic fault (`reliability/02-experiments`).
4. **Observe** with dashboards, traces and logs. Did alerts fire? Were they
   the right ones?
5. **Learn and fix**, then **re-run** until the experiment is boring.
6. **Automate** it (Chaos Mesh `Schedule`) so it stays boring.

Start in kind (`02-experiments/kind/`), then the GPU lab, and never on
shared infrastructure without telling people.

## 5. Game day plan (2 hours, run quarterly)

| Time | Activity |
|---|---|
| T-1 week | pick scenarios, announce, confirm rollback (`kubectl delete` chaos objects) |
| 0:00 | brief: roles (incident commander, operator, scribe), steady-state SLIs on screen |
| 0:10 | start load (`evaluation/01-load-test`, or a training job) |
| 0:15 | apply `07-gameday-workflow.yaml` (latency → pod kill → CPU stress) |
| 0:15–1:00 | the operator responds *as if real*, using only alerts, dashboards, traces and logs. The scribe timestamps detection and actions |
| 1:00 | bonus round: kill the LMCache server; packet loss on a training job |
| 1:30 | debrief and blameless postmortem (template below) |

### Postmortem template

```
Title / date / duration
Impact:        which SLOs burned, how much error budget, which users/jobs
Timeline:      inject → first signal → alert → diagnosis → mitigation → recovery
Detection:     what told us? what should have, and didn't?
Root cause(s): technical + contributing factors (no blame)
What went well / what was hard
Action items:  owner, due date, type (detect / mitigate / prevent)
```

## 6. Exercises

1. **Experiment 1 (kill a vLLM pod)** with and without
   `fix-gateway-retries.yaml`. Measure the failed requests. Why do some
   streams still fail with retries enabled?
2. **Experiment 3 (packet loss)** on `trainjob-pytorch-ddp`. Plot step time
   against loss %. At what loss does NCCL time out? Set `NCCL_TIMEOUT` and
   the checkpoint interval accordingly.
3. **Experiment 4 (LWS worker)**. Measure total unavailability of the
   multi-node model. Design the gateway fallback that keeps users served,
   and test it.
4. **Goodput.** For your lab's largest training job, measure restart time
   end to end (failure → first new training step). Break it down (schedule,
   pull, init, checkpoint load) and cut the largest part.
5. **GPU health loop.** On a GPU node, inject a fake XID line:
   `echo "NVRM: Xid (PCI:0000:01:00): 79, pid=1, GPU has fallen off the bus." | sudo tee /dev/kmsg`.
   Watch NPD set `GPUHardwareProblem`, then watch the remediator (dry run)
   decide to quarantine. Then run `dcgm-diag-job.yaml` and uncordon.
6. **Write an SLO** for a training platform (e.g. "95% of TrainJobs start
   within 10 min of admission"), with an alert, and run it for a week.

## 7. Further reading

* Google SRE Workbook: "Alerting on SLOs" (burn-rate alerts) and "Implementing SLOs".
* The Llama 3 paper §3.3.4 (reliability at 16k GPUs).
* Principles of Chaos Engineering (principlesofchaos.org).
* NVIDIA XID error documentation and the DCGM diagnostics guide.
