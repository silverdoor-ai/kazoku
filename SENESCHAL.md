# Seneschal Shaman Contract
## Introduction:
The Seneschal smart contract is designed as a positive ownership manager to enable and manage token distribution sponsorships in the context of a DAO, likely built on top of the Baal framework. The contract enables entities defined as "sponsors" to commit to a token distribution with deliverables, and "processors" to verify and approve the token distribution once conditions are met.

### Key Points:
The contract utilizes the "hats" concept from the "HatsModule" for role-based access control, e.g., sponsors and processors.

A sponsorship is a commitment to distribute tokens to an address (the recipient). The details of this commitment are stored in the Sponsorship struct.

The contract utilizes EIP-1167 minimal proxy pattern (clones) with immutable arguments for cheaper deployment.

### Structs and Enums:
1. Sponsorship:
Represents a sponsorship offer.

hatId: ID representing the hat required for the recipient to claim the distribution. If it's 0, there's no specific hat requirement.

shares: The amount of shares to distribute.

loot: The amount of loot to distribute.

deadline: The deadline by which the sponsorship can be processed.

sponsoredTime: The timestamp when the sponsorship was created.

proposal: A string containing the proposal details.

recipient: The address intended to receive the shares/loot distribution.

2. SponsorshipStatus:
Represents the status of a sponsorship.

Pending: The sponsorship is committed but not yet processed.

Approved: The sponsorship has been processed and approved.

### Key Functions:
1. sponsor:
Allows a "sponsor" to commit to a token distribution sponsorship.

The function checks if the sender is a wearer of the defined sponsor hat.

If there's a specific hat requirement (hatId), the recipient must be a wearer of the hat.

Emits the Sponsored event.

2. process:
Allows a "processor" to mark a token distribution sponsorship as completed.

Checks the eligibility of the sender, ensures deadlines are not breached, and verifies the sponsorship hasn't been processed.

After validation, the sponsorship status is updated to Approved.

Emits the Processed event.

3. claim:
Allows the recipient of the sponsorship to claim their tokens.

Validates the eligibility of the caller, checks the status of the sponsorship, and transfers the appropriate amount of shares or loot to the recipient.

Emits the Claimed event.