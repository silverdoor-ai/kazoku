// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { HatsModule } from "hats-module/HatsModule.sol";
import { IBaal } from "baal/interfaces/IBaal.sol";
import { IBaalToken } from "baal/interfaces/IBaalToken.sol";
import { ECDSAUpgradeable } from "openzeppelin/utils/cryptography/ECDSAUpgradeable.sol";
import { EIP712Upgradeable } from "openzeppelin/utils/cryptography/EIP712Upgradeable.sol";

/**
 * @title Seneschal positive ownership manager
 * @notice A Baal manager shaman that allows "sponsor" hat wearers to commit to a token distribution sponsorship w/
 * deliverables and "processor" hat wearers to mark a token distribution sponsorship as completed.  After the
 * distribution is approved; the recipient can claim their tokens at any future date.
 * @author SilverDoor
 * @author RaidGuild
 * @author @st4rgard3n
 * @dev This contract inherits from the HatsModule contract, and is meant to be deployed as a clone from the
 * HatsModuleFactory.
 */
contract Seneschal is HatsModule {

    struct Commitment {
        uint256 hatId;
        uint256 shares;
        uint256 loot;
        uint256 extraRewardAmount;
        uint256 deadline;
        uint256 sponsoredTime;
        string proposal;
        address recipient;
        address extraRewardToken;
    }

    enum SponsorshipStatus {
        Pending,
        Approved,
        Claimed
    }

    /*//////////////////////////////////////////////////////////////
    ////                 CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotSponsor();
    error NotProcessor();
    error NotApproved();
    error NotSponsored();
    error Ineligible();
    error ProcessedEarly();
    error DeadlinePassed();
    error InvalidClaim();

    /*//////////////////////////////////////////////////////////////
    ////                     EVENTS
    //////////////////////////////////////////////////////////////*/

    event Sponsored(address indexed sponsor, address indexed recipient, Commitment commitment);
    event Processed(address indexed processor, address indexed recipient, Commitment commitment);
    event Claimed(address indexed recipient, Commitment commitment);

    /*//////////////////////////////////////////////////////////////
    ////                   PUBLIC CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
    * This contract is a clone with immutable args, which means that it is deployed with a set of
    * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
    * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
    * but requires a slightly different approach since they are read from calldata instead of storage.
    *
    * Below is a table of constants and their locations. The first three are inherited from HatsModule.
    *
    * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
    *
    * ----------------------------------------------------------------------+
    * CLONE IMMUTABLE "STORAGE"                                             |
    * ----------------------------------------------------------------------|
    * Offset  | Constant          | Type    | Length  | Source Contract     |
    * ----------------------------------------------------------------------|
    * 0       | IMPLEMENTATION    | address | 20      | HatsModule          |
    * 20      | HATS              | address | 20      | HatsModule          |
    * 40      | hatId (sponsor)   | uint256 | 32      | HatsModule          |
    * 72      | BAAL              | address | 20      | this                |
    * 92      | OWNER_HAT         | uint256 | 32      | this                |
    * 124     | hatId2 (processor)| uint256 | 32      | this                |
    * ----------------------------------------------------------------------+
    */

    // Returns clone code that mimics storage state
    // @notice returns the instantiated interface of the Baal DAO contract
    function BAAL() public pure returns (IBaal) {
      return IBaal(_getArgAddress(72));
    }

    // @notice returns the hatId of the owner hat
    function OWNER_HAT() public pure returns (uint256) {
      return _getArgUint256(92);
    }

    // @notice returns the hatId of the approver hat
    // note that hatId() returns the hatId of the proposer hat
    function hatId2() public pure returns (uint256) {
      return _getArgUint256(124);
    }

    /**
     * @dev These are not stored as immutable args in order to enable instances to be set as shamans in new Baal
     * deployments via `initializationActions`, which is not possible if these values determine an instance's address.
     */
    IBaalToken public SHARES_TOKEN;
    IBaalToken public LOOT_TOKEN;

    uint256 public claimDelay;

    /*//////////////////////////////////////////////////////////////
                          MUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    // hashed fingerprint of the proposal
    mapping(bytes32 commitmentHash => SponsorshipStatus status) commitments;

    // note that HatsModule constructor disables initializer automatically
    constructor(string memory _version) HatsModule(_version) { }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc HatsModule
     */
    function setUp(bytes calldata _initData) public override initializer {
    SHARES_TOKEN = IBaalToken(BAAL().sharesToken());
    LOOT_TOKEN = IBaalToken(BAAL().lootToken());

    claimDelay = abi.decode(_initData, (uint256));

    }

    /*//////////////////////////////////////////////////////////////
    ////                  SHAMAN LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allows a sponsor to commit to a token distribution sponsorship w/ deliverables
     * @param commitment contains all the details of the sponsorship
     */
    function sponsor(Commitment memory commitment) public returns (bool) {
        if (!HATS().isWearerOfHat(msg.sender, hatId())) {
        revert NotSponsor();
        }

        if (commitment.hatId != 0) {
            if (!HATS().isWearerOfHat(commitment.recipient, commitment.hatId)) {
            revert Ineligible();
            }
        }

        commitment.sponsoredTime = block.timestamp;
        bytes32 commitmentHash = keccak256(abi.encode(commitment));
        commitments[commitmentHash] = Seneschal.SponsorshipStatus.Pending;

        emit Sponsored(msg.sender, commitment.recipient, commitment);
        return true;
    }

    /**
     * @dev Allows a processor to mark a token distribution commitment as completed
     * @param commitment contains all the details of the sponsorship
     */
    function process(Commitment calldata commitment) public returns (bool) {
        if (!HATS().isWearerOfHat(msg.sender, hatId2())) {
        revert NotProcessor();
        }

        if (commitment.sponsoredTime + claimDelay > block.timestamp) {
        revert ProcessedEarly();
        }

        if (commitment.hatId != 0) {
            if (!HATS().isWearerOfHat(commitment.recipient, commitment.hatId)) {
            revert Ineligible();
            }
        }

        if (block.timestamp > commitment.deadline) {
        revert DeadlinePassed();
        }

        bytes32 commitmentHash = keccak256(abi.encode(commitment));

        if (commitments[commitmentHash] != Seneschal.SponsorshipStatus.Pending) {
        revert NotSponsored();
        }

        commitments[commitmentHash] = Seneschal.SponsorshipStatus.Approved;
        emit Processed(msg.sender, commitment.recipient, commitment);
        return true;
    }

    /**
     * @dev Allows a recipient to claim their tokens after the claim delay has passed
     * @param commitment contains all the details of the sponsorship
     */
    function claim(Commitment calldata commitment) public returns (bool) {
        if (msg.sender != commitment.recipient) {
        revert InvalidClaim();
        }

        bytes32 commitmentHash = keccak256(abi.encode(commitment));

        if (commitments[commitmentHash] != Seneschal.SponsorshipStatus.Approved) {
        revert NotApproved();
        }

        delete commitments[commitmentHash];

        address[] memory recipient = new address[](1);
        recipient[0] = commitment.recipient;

        if (commitment.shares > 0) {
            uint256[] memory shareAmount = new uint256[](1);
            shareAmount[0] = commitment.shares;
            BAAL().mintShares(recipient, shareAmount);
        }

        if (commitment.loot > 0) {
            uint256[] memory lootAmount = new uint256[](1);
            lootAmount[0] = commitment.loot;
            BAAL().mintLoot(recipient, lootAmount);
        }

        emit Claimed(msg.sender, commitment);
        return true;
    }

}