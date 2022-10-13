---
eip: <to be assigned>
title: Smart Derivative Contract
description: A protocol for deterministic post-trade processing of OTC financial contracts
author: Christian Fries (@cfries), Peter Kohl-Landgraf (@pekola), ...
discussions-to: https://ethereum-magicians.org/
status: Draft
type: Standard Track
category (*only required for Standards Track): ERC
created: 2022-09-11
requires (*optional): <EIP number(s)>
---

## Abstract
Abstract is a multi-sentence (short paragraph) technical summary. This should be a very terse and human-readable version of the specification section. Someone should be able to read only the abstract to get the gist of what this specification does.

## Motivation
The motivation section should describe the "why" of this EIP. What problem does it solve? Why should someone want to implement this standard? What benefit does it provide to the Ethereum ecosystem? What use cases does this EIP address? 

### Rethinking Financial Derivatives
https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3249430

### Concept of a Smart Derivative Contract
The concept of a Smart Derivative Contract was introduced in the following paper: https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3163074
A Smart Derivative Contract is a deterministic settlement protocol which has economically the same behaviour as a collateralized OTC
Derivative. In contrast to a collateralized derivative contract based and collateral flows are netted such that the smart derivative
introduces a high frequent - e.g. daily - settlement flow schedule. With each settlement flow  net present value of the underlying contract is
exchanged and the value of the contract is reset to zero.
To automatically process the settlement counterparties need to provide sufficient prefunded margin amounts and termination fees at the
beginning of each settlement cycle. Through a settlement cycle the margin amounts are locked.
A SDC contract automatically terminates the derivatives contract if there is insufficient prefunding or if the settlement amount exceeds a
prefunded margin balance. Beyond mutual termination is also intended by the function specification.


## Specification
The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119.

The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for any of the current Ethereum platforms (go-ethereum, parity, cpp-ethereum, ethereumj, ethereumjs, and [others](https://github.com/ethereum/wiki/wiki/Clients)).

## Rationale
The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages.

## Backwards Compatibility
All EIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The EIP must explain how the author proposes to deal with these incompatibilities. EIP submissions without a sufficient backwards compatibility treatise may be rejected outright.

## Test Cases
Test cases for an implementation are mandatory for EIPs that are affecting consensus changes.  If the test suite is too large to reasonably be included inline, then consider adding it as one or more files in `../assets/eip-####/`.

## Reference Implementation
An optional section that contains a reference/example implementation that people can use to assist in understanding or implementing this specification.  If the implementation is too large to reasonably be included inline, then consider adding it as one or more files in `../assets/eip-####/`.

## Security Considerations
All EIPs must contain a section that discusses the security implications/considerations relevant to the proposed change. Include information that might be important for security discussions, surfaces risks and can be used throughout the life cycle of the proposal. E.g. include security-relevant design decisions, concerns, important discussions, implementation-specific guidance and pitfalls, an outline of threats and risks and how they are being addressed. EIP submissions missing the "Security Considerations" section will be rejected. An EIP cannot proceed to status "Final" without a Security Considerations discussion deemed sufficient by the reviewers.

## Copyright
Copyright and related rights waived via [CC0](../LICENSE.md).