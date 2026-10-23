# Provenance

aura-distill was created by Ivan Gonzalez ([@tomacco](https://github.com/tomacco)). This file records how authorship of the project can be verified.

## Public record

- **Git history.** Every change since the first commit is public, dated, and attributed.
- **License headers.** Every core file starts with an `SPDX-License-Identifier: Apache-2.0` line and a copyright line naming the author. `tests/check-headers.sh` enforces this in CI. Apache-2.0 §4 requires redistributions to keep these notices and the [NOTICE](NOTICE) file.
- **Citation.** [CITATION.cff](CITATION.cff) gives the canonical citation.

## Fingerprint register (commit-reveal)

The author keeps a private register of verbatim passages from the core prompts that would be very unlikely to appear independently in someone else's work. The register also holds a random nonce, so nobody can confirm a guess at which passages it lists.

Only the register's SHA-256 is published here. If a copy of this work turns up without attribution, the author can publish the register byte for byte. Anyone can then hash it and check it against the value below, which proves the passages were chosen as fingerprints before the copy appeared, not picked afterwards.

| Registered | SHA-256 of the register |
|---|---|
| 2026-10-23 | `7a91eee154a74e814d7e41fa4caf4827a5dd29757616c95095ee1e786cdf066c` |
