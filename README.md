# Hats Baal Shamans

[Hats Protocol](https://hatsprotocol.xyz)-powered Shaman contracts for [Moloch V3 (Baal)](https://github.com/hausdao/baal).

This repo contains the contracts for the following Shamans:

- Seneschal

---
## Seneschal

Manages sponsorships for token distributions, with specific deliverables. It allows hat wearers to sponsor projects,
processors to mark the sponsorship as complete, and recipients to claim their tokens at any future date.

---
## Development

This repo uses Foundry for development and testing. To get started:

1. Fork the project
2. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
3. To compile the contracts, run `forge build`
4. To test, run `forge test`
5. For coverage reports `forge coverage` or

- Alternate coverage using html document:
`forge coverage --report lcov` then `genhtml -o report --branch-coverage lcov.info` navigate to the "report" folder and preview index.html

---
## Gotchas

[The immutable args are set by the HatsModuleFactory.](https://github.com/Hats-Protocol/hats-module/blob/main/src/HatsModuleFactory.sol)

## Seneschal

**Seneschal** - A Baal manager shaman that facilitates token distribution sponsorships.

## Contract Overview
The `Seneschal` contract allows sponsors to commit to token distribution sponsorships with specific deliverables. Witnesses can mark these sponsorships as completed, and once approved, the recipient can claim their tokens.

The contract handles:
1. Sponsorship commitments by sponsors.
2. Validation of sponsorship by witnesses.
3. Claims by recipients after approvals.
4. Reporting of completion.
5. Clearing commitments.

## Commitment Struct

### Overview
The `Commitment` struct is a foundational data structure in the `Seneschal` contract which embodies the details of each sponsorship agreement. This documentation explains each field and its significance in the system.

### Fields

1. **eligibleHat**:
    - **Type**: `uint256`
    - **Description**: Represents the ID of the hat that the recipient must be wearing for eligibility.
    - **Notes**: If set to 0, it signifies that no particular hat is required.

2. **shares**:
    - **Type**: `uint256`
    - **Description**: Dictates the quantity of shares to be minted for the recipient as part of their reward upon successful completion.

3. **loot**:
    - **Type**: `uint256`
    - **Description**: Specifies the amount of loot tokens to be minted for the recipient as another component of their reward.
    
4. **extraRewardAmount**:
    - **Type**: `uint256`
    - **Description**: Represents any additional token rewards that the recipient can claim besides shares and loot.
    - **Notes**: A value of 0 indicates no additional rewards are present.

5. **timeFactor**:
    - **Type**: `uint256`
    - **Description**: A UNIX Timestamp detailing the commitment's time factor, which might vary among different Kazoku shamans.  This is the witness deadline for the Seneschal.

6. **sponsoredTime**:
    - **Type**: `uint256`
    - **Description**: The UNIX timestamp marking the instant the sponsorship was established. It is auto-set upon invoking the sponsor function.

7. **expirationTime**:
    - **Type**: `uint256`
    - **Description**: A UNIX timestamp defining the deadline post which the commitment can't be claimed. 
    - **Notes**: While manually set, it should comply with social and legal norms.

8. **contextURL**:
    - **Type**: `string`
    - **Description**: Provides a link connecting the on-chain commitment to its off-chain counterpart. This serves as an access point to fetch the proposal's details.

9. **metadata**:
    - **Type**: `string`
    - **Description**: Carries any supplementary data or details about the commitment.

10. **recipient**:
    - **Type**: `address`
    - **Description**: The Ethereum address of the beneficiary of the sponsorship who is entitled to the shares, loot, and potential extra rewards.

11. **extraRewardToken**:
    - **Type**: `address`
    - **Description**: Specifies the ERC20 token address if there are extra rewards in a different token.
    - **Notes**: If set to the null address (`address(0)`), it indicates the absence of additional token rewards.

## SponsorshipStatus Enum

### Overview
The `SponsorshipStatus` enum is a mechanism to represent the evolving states of a sponsorship throughout its life cycle within the `Seneschal` contract. This documentation provides insights into each state.

### States

1. **Empty**:
    - **Description**: The default, uninitialized state of a sponsorship prior to its creation.

2. **Pending**:
    - **Description**: This state signifies the inception of the sponsorship. At this juncture, the sponsorship is yet to undergo review or obtain approval.

3. **Approved**:
    - **Description**: Denotes that the sponsorship has gained approval. While the sponsorship is deemed legitimate in this state, the recipient hasn't claimed their tokens yet.

4. **Claimed**:
    - **Description**: This state highlights that the beneficiary has claimed the rewards linked to the sponsorship, marking its completion.

5. **Failed**:
    - **Description**: This unfortunate state signifies that the commitment couldn't be realized. It serves to prevent signature replay attacks.

## Public Functions

### `BAAL()`
Returns the interface of the Baal DAO contract. 

### `OWNER_HAT()`
Returns the hatId of the owner hat.

### `getSponsorHat()`
Returns the hatId of the sponsor hat.

### `getWitnessHat()`
Returns the hatId of the witness hat.

### `sponsor(Commitment, bytes)`
Allows a sponsor to commit to a token distribution sponsorship with deliverables.
- Input: `Commitment` (structured data representing the sponsorship details) & a valid signature of the commitment by the sponsor.
- Event: `Sponsored` - Logs sponsor details and commitment details.

### `witness(Commitment, bytes)`
Allows a witness to mark a token distribution commitment as completed.
- Input: `Commitment` (structured data representing the sponsorship details) & a valid signature of the commitment by the witness.
- Event: `Witnessed` - Logs witness details and the commitment hash.

### `claim(Commitment, bytes)`
Allows the recipient to claim their tokens after the claim delay has passed.
- Input: `Commitment` (structured data representing the sponsorship details) & a valid signature of the commitment by the recipient.
- Event: `Claimed` - Logs the commitment hash.

### `poke(Commitment, string)`
Allows the recipient to notify/report the contract of the completion of the sponsorship.
- Input: `Commitment` (structured data representing the sponsorship details) & a completion report (content digest identifier).
- Event: `Poke` - Logs recipient details, commitment hash, and the completion report.

### `clear(Commitment)`
Allows anyone to clear a commitment that has failed or hasn't been claimed within a stipulated time.
- Input: `Commitment` (structured data representing the sponsorship details).
- Event: `Cleared` - Logs who cleared the commitment and the commitment hash.

### `clearExpired(Commitment)`
Allows anyone to clear commitments that have expired.
- Input: `Commitment` (structured data representing the sponsorship details).
- Event: `Cleared` - Logs who cleared the commitment and the commitment hash.

## Modifiers and Internal Functions

The contract uses multiple internal functions and modifiers for:
1. Verifying if an address has the right hat.
2. Splitting and verifying ECDSA signatures.
3. Handling token claims.

## Events
- `Sponsored`: Triggered when a new sponsorship commitment is made.
- `Witnessed`: Triggered when a witness validates a sponsorship.
- `Claimed`: Triggered when a recipient claims their tokens.
- `Poke`: Triggered when the completion of a sponsorship is reported.
- `Cleared`: Triggered when a commitment is cleared.

## Errors
The contract uses custom error messages for better clarity. These include errors like `NotAuth`, `InvalidExtraRewards`, `NoBalance`, and more to handle various scenarios like invalid operations, early actions, expired commitments, etc.

## Note
The contract is designed to be a clone with specific immutable storage variables (like the `BAAL`, `OWNER_HAT`, etc.), leveraging the benefits of the EIP-1167 standard.

## Conclusion
The `Seneschal` contract serves as a bridge between sponsors, witnesses, and recipients. It enables sponsors to commit to token distributions, witnesses to validate these distributions, and recipients to claim their tokens once approved. The system relies heavily on ECDSA signatures to verify actions, ensuring security and credibility.
