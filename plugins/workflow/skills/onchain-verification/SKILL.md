---
name: onchain-verification
description: Design or review layered verification for deployable Solidity, EVM bytecode, financial or authorization invariants, stateful fuzzing, mutation testing, Lean models, Kontrol, or KEVM.
---

<!-- Auto-synced from ~/.claude/includes/onchain-verification.md — do not edit manually -->

# Onchain Verification

Use this guidance when work creates or changes deployable Solidity, reasons about EVM bytecode, protects money or authorization, or evaluates a smart-contract test/proof suite. The objective is a traceable chain from a domain claim to the exact artifact and independent evidence that checks it.

## Core Rule

Do not call a contract "verified" because one test suite, one source-level proof, or one compiler run is green. Record four separate facts:

1. **Claim:** the invariant stated in domain language.
2. **Model:** any abstraction used to make the claim provable.
3. **Implementation target:** source, compiler settings, creation/runtime bytecode, deployed address, or proxy implementation actually checked.
4. **Independent evidence:** tests, differential oracle, fuzzer, mutation campaign, proof checker, and negative control that evaluated the target.

A proof of an abstract model does not establish that Solidity implements the model. A source-level result does not establish that deployed bytecode matches the source. Close both gaps explicitly.

## Route by Artifact and Risk

| Surface | Required evidence |
|---|---|
| BEAM/Rust wire formats, math, signing, protocol parsers | Example tests, property tests, an independent differential oracle, mutation adequacy, and boundary/error cases |
| EVM executor or simulator | Pinned Ethereum execution vectors, an independent EVM semantics/oracle, post-state/return/revert/log comparisons, fork-sensitive cases, and deliberate bad-bytecode controls |
| Immutable data/UI wrapper | Reproducible compiler artifacts, Foundry unit/fuzz/invariant tests, stateful Echidna and Medusa campaigns, mutation adequacy, exact reconstruction/lineage claims, and bytecode-level checking for those claims |
| Contract that holds value or grants authority | Every layer above plus an abstract model of solvency/authorization, implementation refinement evidence, upgrade/privilege invariants, and independent audit before production authorization |

Do not add Lean merely to decorate a simple data wrapper. Do not omit formal modeling when correctness depends on financial conservation, bounded loss, authorization, or adversarial multi-step state transitions.

## Invariant Inventory

Write invariants before writing verification code. Cover the applicable classes:

- conservation and solvency across every reachable resolution/state;
- maximum loss, balance floors, rounding direction, and bounded fees;
- authorization, allowed targets/selectors/assets, recipients, deadlines, and replay/idempotency;
- lifecycle and temporal rules: maturity, expiry, cancellation, upgrades, pauses, oracle freshness, and reorg-sensitive state;
- deployment and lineage: CREATE2 address, write-once links, implementation identity, and bounded traversal;
- storage and call effects: permitted slots, permitted external targets, reentrancy boundaries, and no unexpected delegatecall/selfdestruct;
- serialization/reconstruction: exact byte output, offsets, lengths, selectors, signatures, and canonical encodings;
- liveness claims only where assumptions about callers, keepers, or external protocols are stated explicitly.

Every invariant needs a stable identifier used by tests, proofs, mutation reports, and the verification ledger.

## Evidence Layers

### Foundry

Use example tests for known cases, fuzz tests for input domains, and handler-based invariant tests for multi-actor state transitions. Inspect call/revert metrics: a campaign that mostly discards or reverts inputs has not exercised the intended state space. Pin runs, depth, seed policy, fork/EVM version, and compiler settings.

### Independent Stateful Fuzzers

For critical Solidity, run both Echidna and Medusa against the same invariant inventory. Preserve minimized failing sequences and coverage-increasing corpora. A green campaign records coverage and reachable handler activity, not only an exit code.

### Differential Oracles

Compare against an authority independent of the implementation under test: official protocol vectors, verified deployed behavior, or a separately implemented semantics. Two wrappers over the same library are not independent. Compare domain outcomes and state effects, not merely success status or response shape.

### Mutation Adequacy

Use Gambit for Solidity or a maintained language-appropriate mutator for BEAM/Rust code. Mutate one fault at a time and run the real verification stack against each mutant.

Classify every survivor as:

- equivalent to the original for the reachable domain;
- unreachable, with the reachability assumption named;
- redundant/subsumed by another mutant;
- a genuine test/specification gap that must be closed.

Hand-written domain mutants complement generated operators for privilege checks, storage targets, rounding, time bounds, replay, and forbidden external calls.

### Lean Models

Use Lean for the abstract economic or authorization model. Reject `sorry`, `admit`, placeholders, and undeclared axioms. Emit the axiom inventory for every release proof. State finite-domain, arithmetic, oracle, timing, and adversary assumptions in the theorem boundary.

Keep refinement explicit: map Solidity storage and transitions to model state, then verify that the compiled implementation preserves the modeled transition relation. Without this bridge, the Lean result applies only to the model.

### Kontrol / KEVM

Use Kontrol/KEVM for claims about EVM execution and compiled artifacts. Bind the proof to the exact compiler version, optimizer/via-IR/EVM settings, linked libraries, creation bytecode, and runtime bytecode. For proxies, also bind the implementation address/slot, upgrade authority, and initialization state.

## Verification Ledger and Negative Controls

Produce one machine-readable or reviewable ledger tied to one exact commit. It records:

- invariant identifiers and their domain wording;
- source hashes, compiler settings, artifact hashes, deployment/proxy identity;
- tool and semantics versions, seeds/configs, proof axiom inventory;
- test/fuzz coverage, corpora, mutation totals, killed mutants, and reviewed survivors;
- failures, waivers, and the evidence supporting each waiver;
- the independent reviewer/auditor and durable run reference.

Every release-grade stack contains a deliberate negative control: inject a forbidden storage write, removed authorization check, wrong rounding direction, broken lineage edge, or equivalent defect. The verification run is invalid unless the expected checker catches it. This guards against proving or testing the wrong target.

Generated mutants and canaries run in isolated worktrees or disposable copies. Never overwrite tracked source or release artifacts in the main checkout.

## Task-Writing Contract

A Solidity/EVM rmap task states WHAT must be established, not a pile of tool-install steps. Its acceptance criteria name:

- the invariant set and authority for each claim;
- the exact artifact/state the evidence binds to;
- the independent oracle or checker;
- the required negative control;
- mutation survivor review and verification-ledger output;
- focused tests plus the repository's canonical gate.

If a product concept has no repository yet, keep these requirements in its existing concept document. Create the repo-local rmap task when that repository is founded; do not create an orphan roadmap in an unrelated coordination checkout.

## Primary References

- [Foundry invariant testing](https://getfoundry.sh/forge/invariant-testing)
- [Echidna](https://github.com/crytic/echidna)
- [Medusa](https://github.com/crytic/medusa)
- [Gambit](https://docs.certora.com/en/latest/docs/gambit/index.html)
- [Kontrol, built on KEVM](https://docs.runtimeverification.com/kontrol)
- [Ethereum.org: formal verification](https://ethereum.org/developers/docs/smart-contracts/formal-verification/)
