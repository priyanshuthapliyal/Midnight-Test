# Security & Key Management Design (Midnight Preprod Validator)

---

## 1. Key Storage in a Production Cloud Environment

### Recommended Approach (Layered Defense)
Midnight validators use distinct key types with different risk profiles: **hot session keys** (AURA `sr25519`, GRANDPA `ed25519`, Cross-Chain `ecdsa` in the Substrate keystore), the **P2P network key** (`secret_ed25519`), **WireGuard tunnel key**, and **offline mnemonic backups**. No single tool fits all of them equally, so the recommended production pattern combines:

1. **Secrets Manager + KMS Envelope Encryption for Runtime Keys:**
   - Store session seeds, `secret_ed25519`, WireGuard `privatekey`, and DB credentials in a **Cloud Secrets Manager** (e.g., AWS Secrets Manager or HashiCorp Vault) encrypted with a dedicated **Cloud KMS Customer Managed Key (CMK)**.
   - At boot, the `systemd` unit fetches secrets via a least-privilege **IAM instance profile** (scoped to that single node's secret ARN) into a **`tmpfs` (RAM-backed) mount** or `0600` files owned strictly by the non-login `midnight` user.
   - **Never** bake keys into AMIs, Docker images, Terraform state, or Git repositories.
2. **Offline / Hardware-Protected Cold Backups:**
   - Keep raw mnemonic phrases (`aura.json`, `grandpa.json`, `cross_chain.json`) off the cloud host entirely (encrypted cold storage or hardware-backed vault with quorum/MFA).
3. **Host & Network Hardening:**
   - Enforce IMDSv2, disable password/root SSH, restrict RPC (`9933`) and metrics (`9615`) to localhost/VPN, enable encrypted EBS volumes, and stream all secret-access and IAM events to immutable audit logs (CloudTrail).

### Tradeoffs: HSM vs. KMS vs. Secrets Manager

| Option | Strengths | Limitations / Tradeoffs | Best Fit for Midnight |
| :--- | :--- | :--- | :--- |
| **HSM** (e.g., AWS CloudHSM) | FIPS 140-3 Level 3; private keys never leave hardware; strong protection against host/OS compromise. | High cost & operational overhead; **most cloud HSMs do not natively support Substrate's `sr25519` (Schnorrkel) curve**, so `midnight-node` cannot offload AURA signing directly to it. | Root/governance keys, CA keys, or high-assurance `ecdsa` custody. |
| **Cloud KMS** | Managed, low cost, fine-grained IAM policies, automatic audit trail (CloudTrail). | Designed for envelope encryption and standard curves (RSA/ECDSA); cannot act as a drop-in Substrate `sr25519` keystore. | **Encrypting** secrets in Secrets Manager and offline key backups. |
| **Secrets Manager** (AWS SM / Vault) | Built-in versioning, IAM gating, easy runtime injection into `tmpfs` / `systemd`, audit logging. | Secrets are decrypted into host memory/keystore at runtime, so a full host/root compromise can still read active hot keys. | **Runtime delivery** of keystore seeds, `secret_ed25519`, and `wg0.conf` to hardened validator hosts. |

---

## 2. Key Rotation (Minimal Disruption)

Substrate/Midnight activates newly registered validator session keys on the **`n+2` epoch boundary**. Key rotation must respect this window so the node never misses blocks or finality votes.

### Rotation Process
1. **Generate & Stage New Keys (Keep Old Keys Active):**
   - Generate new session keys (`aura`, `grandpa`, `cross_chain`) and insert them into the node's keystore **alongside** the currently active keys—do **not** delete the old keys yet.
2. **Register New Public Keys:**
   - Export the updated `partner-chains-public-keys.json` and submit it through the Midnight Foundation / governance registration process.
3. **Wait Through the `n+2` Epoch Transition:**
   - During epochs `n` and `n+1`, the node continues signing with the old keys. At epoch `n+2`, the runtime automatically switches to the newly registered keys.
4. **Verify & Decommission:**
   - Confirm in logs/metrics that the node is authoring and finalizing blocks under the new keys, then remove the old keys from the keystore and revoke/archive the old version in Secrets Manager.
   - *(If also rotating `secret_ed25519` / `PeerID` or WireGuard keys, coordinate the new `PeerID` / WireGuard public key with the Foundation's reserved-peer list **before** cutting over.)*

### Key Risks & Mitigations
- **Premature deletion of old keys** → Node fails to sign during `n` / `n+1` and misses blocks.
  - *Mitigation:* Always keep both old and new keys in the keystore until `n+2` is confirmed active.
- **Equivocation (double-signing)** → Running two validator instances with the same active session keys causes slashing/penalties.
  - *Mitigation:* Rotate keys in-place on the single active validator, or strictly stop the old validator before starting a replacement host.
- **P2P isolation during network key rotation** → Changing `PeerID` breaks `--reserved-nodes` peering.
  - *Mitigation:* Rotate session keys separately from `secret_ed25519`/WireGuard keys, and pre-register peer changes with the Foundation.

---

## 3. Incident Response: Suspected Signing Key Exposure

If an operator reports that a validator signing key may have been exposed, take these **first three actions** immediately:

1. **Stop the Validator Process & Isolate the Host (Preserve Forensics)**
   - **Action:** Stop `midnight-node` (`sudo systemctl stop midnight-node`), revoke the host's IAM role / WireGuard peer access, and snapshot disk/logs (`journalctl`, CloudTrail) before terminating anything.
   - **Why:** Prevents an attacker (or a duplicate instance) from using the exposed key to **equivocate (double-sign)** or inject malicious finality votes, while preserving evidence needed to determine the root cause.

2. **Notify the Midnight Foundation & Provision Clean Replacement Keys**
   - **Action:** Immediately alert the Midnight Foundation / governance contacts to flag and deregister the compromised public key, and generate a **brand-new keypair on a freshly provisioned host** (never on the suspected host).
   - **Why:** Governance needs to remove the untrusted key from the active validator set as fast as possible to protect network integrity, and only a clean host guarantees the attacker does not retain persistence.

3. **Audit Blast Radius & Rotate All Co-Located Secrets**
   - **Action:** Inspect CloudTrail, Secret Manager access logs, SSH/auth logs, and chain telemetry to trace how the exposure occurred, and rotate **all** secrets on that host (other session keys, `secret_ed25519`, WireGuard `privatekey`, PostgreSQL `.pgpass`).
   - **Why:** A host or secret-store compromise rarely affects just one key—assuming all co-located credentials are exposed prevents a secondary breach during recovery.
