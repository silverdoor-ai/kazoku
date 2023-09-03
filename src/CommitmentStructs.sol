pragma solidity ^0.8.18;

// the Arweave content digest can be used to retrieve the proposal forever
// Mirror Arweave retrieval ( https://dev.mirror.xyz/GjssNdA6XK7VYynkvwDem3KYwPACSU9nDWpR5rei3hw )

/// @title Commitment
/// @notice This struct serves as the primary data storage for each sponsorship commitment.
/// Each field within this struct represents a specific parameter of the commitment.
struct Commitment {

    /// @notice The ID of the hat that the recipient must be wearing.
    /// @dev If set to 0, there is no requirement for a hat.
    uint256 eligibleHat;

    /// @notice The number of shares to be minted for the recipient.
    /// @dev This is part of the reward that the recipient would get upon successful completion.
    uint256 shares;

    /// @notice The number of loot tokens to be minted for the recipient.
    /// @dev This is also part of the reward that the recipient would get upon successful completion.
    uint256 loot;

    /// @notice Additional token rewards other than shares and loot.
    /// @dev If set to 0, there are no additional rewards.
    uint256 extraRewardAmount;

    /// @notice A UNIX Timestamp element that represents the time factor of the commitment.
    /// @dev The effect of the time factory can change from different Kazoku shamans.
    uint256 timeFactor;

    /// @notice The UNIX timestamp when the sponsorship was created.
    /// @dev This is set automatically when the sponsor function is called.
    uint256 sponsoredTime;

    /// @notice The UNIX timestamp when the commitment can no longer be claimed.
    /// @dev This is manual but must adhere to social and legal requirements
    uint256 expirationTime;

    /// @notice URL linking the commitment on chain to the commitment off chain.
    /// @dev This is used as an identifier to retrieve the proposal details.
    string contextURL;

    /// @notice The address of the recipient of the sponsorship.
    /// @dev The person/entity that will receive the shares, loot, and possibly extra rewards.
    address recipient;

    /// @notice The ERC20 token address for additional rewards.
    /// @dev If set to address(0), there are no additional token rewards.
    address extraRewardToken;

}


/// @title SponsorshipStatus
/// @notice This enum represents the various states that a sponsorship can be in within the contract.
/// @dev The SponsorshipStatus enum helps track the lifecycle of a sponsorship and is integral for business logic within the contract.
enum SponsorshipStatus {

    /// @notice The default state before it is sponsored.
    Empty,

    /// @notice The initial state of the sponsorship when it is created.
    /// @dev In this state, the sponsorship has not yet been reviewed or approved.
    Pending,

    /// @notice The state indicating that the sponsorship has been approved.
    /// @dev In this state, the sponsorship is considered valid but has not yet been claimed by the recipient.
    Approved,

    /// @notice The state indicating that the rewards for the sponsorship have been claimed by the recipient.
    /// @dev In this state, the sponsorship lifecycle is considered complete.
    Claimed,

    /// @notice The state indicating that the commitment has failed.
    /// @dev This state blocks signature replay attacks.
    Failed
}
