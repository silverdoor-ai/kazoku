pragma solidity ^0.8.18;

// the Arweave content digest can be used to retrieve the proposal forever
// Mirror Arweave retrieval ( https://dev.mirror.xyz/GjssNdA6XK7VYynkvwDem3KYwPACSU9nDWpR5rei3hw )
struct Commitment {
    uint256 hatId;
    uint256 shares;
    uint256 loot;
    uint256 extraRewardAmount;
    uint256 completionDeadline;
    uint256 sponsoredTime;
    bytes32 arweaveContentDigest;
    address recipient;
    address extraRewardToken;
}

enum SponsorshipStatus {
    Pending,
    Approved,
    Claimed
}