# Hats Baal Shamans

[Hats Protocol](https://hatsprotocol.xyz)-powered Shaman contracts for [Moloch V3 (Baal)](https://github.com/hausdao/baal).

This repo contains the contracts for the following Shamans:

- Hats Onboarding Shaman
- Seneschal

---
## Hats Onboarding Shaman

Allows teams to rapidly onboard and offboard members based on Hats Protocol hats. Members must wear the member hat to 
onboard or reboard, can be offboarded if they no longer wear the member hat, and kicked completely if they are in bad 
standing for the member hat. Onboarded members receive an initial share grant, and their shares are down-converted to 
loot when they are offboarded.

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