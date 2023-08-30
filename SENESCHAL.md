# Seneschal Smart Contract Documentation

## Overview

The `Seneschal` smart contract is designed to manage sponsorships for token distributions, with specific deliverables. It allows sponsors to commit to a sponsorship and processors to mark the sponsorship as complete. Once the distribution is approved, the recipient can claim their tokens at any future date.

## Table of Contents

- [Public Constants](#public-constants)
- [Mutable State](#mutable-state)
- [Events](#events)
- [Public Functions](#public-functions)
  
## Public Constants

### `BAAL()`

Returns the instantiated interface of the Baal DAO contract.

### `OWNER_HAT()`

Returns the hatId of the owner hat.

### `hatId2()`

Returns the hatId of the processor hat.

## Mutable State

- `commitments`: A mapping from a commitment hash to its sponsorship status (`SponsorshipStatus` enum).

## Events

### `Sponsored`

Emitted when a sponsorship is committed by a sponsor.

### `Processed`

Emitted when a commitment is marked as processed by a processor.

### `Claimed`

Emitted when the recipient claims their tokens.

## Public Functions

### `sponsor(Commitment memory commitment, bytes calldata signature)`

#### Parameters

- `commitment`: The details of the sponsorship.
- `signature`: The valid signature of the commitment by the sponsor.

#### Returns

- `bool`: True if the operation is successful.

#### Description

Allows a sponsor to commit to a token distribution sponsorship with deliverables.

---

### `process(Commitment calldata commitment, bytes calldata signature)`

#### Parameters

- `commitment`: The details of the sponsorship.
- `signature`: The valid signature of the commitment by the processor.

#### Returns

- `bool`: True if the operation is successful.

#### Description

Allows a processor to mark a token distribution commitment as completed.

---

### `claim(Commitment calldata commitment, bytes calldata signature)`

#### Parameters

- `commitment`: The details of the sponsorship.
- `signature`: The valid signature of the commitment by the recipient.

#### Returns

- `bool`: True if the operation is successful.

#### Description

Allows a recipient to claim their tokens after the claim delay has passed.

---

### `setClaimDelay(uint256 additiveDelay)`

#### Parameters

- `additiveDelay`: The amount of time to add to the voting and grace periods.

#### Description

Allows the owner to change the claim delay. Useful if the DAO plans to increase its voting and/or grace periods.

## Notes

The contract includes additional utility methods and internal logic to manage the state and enforce constraints but those are not detailed here. The contract also includes various custom errors for exceptional cases.