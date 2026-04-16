# Kernel Patch: vc4 drm-scheduler Fix

## The Bug

**Symptom:** After ~9 minutes of normal operation, the Pi display freezes permanently. `dmesg` shows `[drm] Resetting GPU.` The cage/hudcw process enters D-state (uninterruptible sleep) and cannot be killed even with SIGKILL. Only a hard reboot recovers.

**Root cause:** The vc4 driver uses a custom job queue with a hangcheck timer. When the timer fires during an active bin job, `vc4_cancel_bin_job()` cancels the job without signaling the associated DMA fence. The waiter — cage's `drmModeAtomicCommit()` in the DRM page-flip path — is blocked on that fence in `drm_atomic_helper_wait_for_fences()` with `TASK_UNINTERRUPTIBLE`. Since the fence is never signaled, the wait never returns. The process becomes immune to all signals.

This is a kernel bug in the vc4 driver's interaction with `drm_atomic_helper_wait_for_fences`. It is not triggered by `QSG_RENDER_LOOP=basic` (single-threaded, slower) but reliably triggers with `QSG_RENDER_LOOP=threaded`.

## The Fix

Branch `vc4/downstream/drm-scheduler` by Maíra Canal (Igalia):  
`https://github.com/mairacanal/linux-rpi.git`

This branch replaces vc4's custom job queue with the standard `drm_sched` (DRM GPU scheduler) framework. Key properties:

- All pending fences are signaled with an error (`-ENODEV` or `-ECANCELED`) on timeout/reset — no fence can be left permanently unsignaled.
- The D-state deadlock is structurally impossible: any waiter on a vc4 fence will eventually be unblocked.

**Kernel version built:** `6.18.6-drm-sched-v8+`  
**Local version suffix:** `-drm-sched-v8` (set in `build.sh`)

## Building

```bash
cd kernel/
bash build.sh
```

`build.sh` will:
1. Shallow-clone `vc4/downstream/drm-scheduler` from Maíra's repo (~500 MB)
2. Fetch the running kernel config from the Pi via SSH (`/proc/config.gz`)
3. Build kernel, modules, and DTBs inside a Podman arm64 container
4. Output to `kernel/output/`

Then deploy:
```bash
bash deploy.sh
# Reboots the Pi automatically. Use --no-reboot to skip.
```

## Rollback

If the new kernel causes issues:

```bash
sshpass -p raspberry ssh pi@10.10.5.2 \
  'sudo cp /boot/firmware/kernel8.img.bak /boot/firmware/kernel8.img && sudo reboot'
```

## Verification

After boot, confirm the kernel version:
```bash
sshpass -p raspberry ssh pi@10.10.5.2 'uname -r'
# Expected: 6.18.6-drm-sched-v8+
```

Run hudcw for >15 minutes and confirm no `[drm] Resetting GPU.` in dmesg:
```bash
sshpass -p raspberry ssh pi@10.10.5.2 'dmesg | grep -i "resetting\|fence\|drm_sched" | tail -20'
```

## Why Not Upstream?

As of April 2026, the `drm-scheduler` migration for vc4 is in progress upstream but not yet in the Raspberry Pi kernel releases. The branch by Maíra Canal is the most complete implementation and has been stable in testing (>690 s continuous operation without GPU reset).

## References

- Maíra Canal's linux-rpi fork: https://github.com/mairacanal/linux-rpi
- Branch: `vc4/downstream/drm-scheduler`
- Related: `drm_atomic_helper_wait_for_fences` in `drivers/gpu/drm/drm_atomic_helper.c`
- vc4 job queue: `drivers/gpu/drm/vc4/vc4_gem.c`
