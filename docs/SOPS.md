# Sealed secrets

A workspace that sets `sops.enabled: true` gets a Cloud KMS key in its own
project (`<client>-<workspace>-sops` / `sops`), unless `sops.kms_key` already
names one. `terraform output sops_kms_key` is the id that goes in `.sops.yaml`.
Start from `.sops.yaml.example`. People who encrypt and decrypt are
`sops.decrypters` (`user:name@example.com`). The key ring is this project's.
Do not point it at a key from another platform.

Put the payload at `secrets/<workspace>/<service>.enc.yaml`. Each top-level key
that matches a Cloud Run `secret_env` name (`DATABASE_PASSWORD`) becomes that
secret's version. A secret with no entry keeps the placeholder, and Terraform
leaves a later console version alone.

```bash
sops --encrypt --gcp-kms "$(terraform output -raw sops_kms_key)" \
  secrets/pro/api.yaml > secrets/pro/api.enc.yaml
```

The file is safe to commit. The plaintext yaml is not.
