// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { HatsModule } from "hats-module/HatsModule.sol";
import { IBaal } from "baal/interfaces/IBaal.sol";
import { IBaalToken } from "baal/interfaces/IBaalToken.sol";
import { HatsModuleEIP712 } from "src/HatsModuleEIP712.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { IERC20 } from "src/dep/IERC20.sol";
import { Commitment, SponsorshipStatus } from "src/CommitmentStructs.sol";

/**
 * @title Seneschal positive ownership manager
 * @notice A Baal manager shaman that allows "sponsor" hat wearers to commit to a token distribution sponsorship w/
 * deliverables and "processor" hat wearers to mark a token distribution sponsorship as completed.  After the
 * distribution is approved; the recipient can claim their tokens at any future date.  Proposals are submitted
 * to Arweave; likely via Mirror - and mapped to the SHA256 bytes32 content digest hash.  This content digest hash
 * is the ItemID for the proposal and can be used to retrieve the proposal forever.
 * @author SilverDoor
 * @author RaidGuild
 * @author @st4rgard3n
 * @dev This contract inherits from the HatsModule contract, and is meant to be deployed as a clone from the
 * HatsModuleFactory.
 */
contract Seneschal is HatsModule, HatsModuleEIP712 {

    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
    ////                 CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotAuth(uint256 hatId);
    error FailedExtraRewards(address extraRewardToken, uint256 extraRewardAmount);
    error NotApproved();
    error NotSponsored();
    error ProcessedEarly();
    error DeadlinePassed();
    error InvalidClaim();
    error InvalidSignature();
    error ExistingCommitment();

    /*//////////////////////////////////////////////////////////////
    ////                     EVENTS
    //////////////////////////////////////////////////////////////*/

    event Sponsored(address indexed sponsor, address indexed recipient, Commitment commitment);
    event Processed(address indexed processor, address indexed recipient, Commitment commitment);
    event Claimed(address indexed recipient, Commitment commitment);
    event ClaimDelaySet(uint256 delay);

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
    * 40      | sponsorHatId      | uint256 | 32      | HatsModule          |
    * 72      | BAAL              | address | 20      | this                |
    * 92      | OWNER_HAT         | uint256 | 32      | this                |
    * 124     | processorHatId    | uint256 | 32      | this                |
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

    // @notice returns the hatId of the processor hat
    // note that hatId() returns the hatId of the sponsor hat
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
    // note that HatsModuleEIP712 constructor disables initializer automatically
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

        uint256 additiveDelay = abi.decode(_initData, (uint256));
        claimDelay = additiveDelay + BAAL().votingPeriod() + BAAL().gracePeriod();
        emit ClaimDelaySet(claimDelay);
        __init_EIP712();
    }

    /*//////////////////////////////////////////////////////////////
    ////                     SHAMAN LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allows a sponsor to commit to a token distribution sponsorship w/ deliverables
     * @param commitment contains all the details of the sponsorship
     * @param signature valid signature of the commitment by the sponsor
     */
    function sponsor(Commitment memory commitment, bytes calldata signature) public returns (bool) {
        address signer = _verify(commitment, signature);
        _authenticateHat(signer, hatId());

        if (commitment.hatId != 0) {
            _authenticateHat(commitment.recipient, commitment.hatId);
        }

        commitment.sponsoredTime = block.timestamp;

        bytes32 commitmentHash = keccak256(abi.encode(commitment));
        if (commitments[commitmentHash] != SponsorshipStatus.Empty) {
            revert ExistingCommitment();
        }
        commitments[commitmentHash] = SponsorshipStatus.Pending;

        emit Sponsored(msg.sender, commitment.recipient, commitment);
        return true;
    }

    /**
     * @dev Allows a processor to mark a token distribution commitment as completed
     * @param commitment contains all the details of the sponsorship
     * @param signature valid signature of the commitment by the processor
     */
    function process(Commitment calldata commitment, bytes calldata signature) public returns (bool) {
        address signer = _verify(commitment, signature);

        _authenticateHat(signer, hatId2());

        if (commitment.sponsoredTime + claimDelay > block.timestamp) {
        revert ProcessedEarly();
        }

        if (block.timestamp > commitment.completionDeadline) {
        revert DeadlinePassed();
        }

        if (commitment.hatId != 0) {
            _authenticateHat(commitment.recipient, commitment.hatId);
        }

        bytes32 commitmentHash = keccak256(abi.encode(commitment));

        if (commitments[commitmentHash] != SponsorshipStatus.Pending) {
        revert NotSponsored();
        }

        commitments[commitmentHash] = SponsorshipStatus.Approved;
        emit Processed(msg.sender, commitment.recipient, commitment);
        return true;
    }

    /**
     * @dev Allows a recipient to claim their tokens after the claim delay has passed
     * Note that the recipient's eligibility is no longer checked here; because the commitment was processed already
     * as completed.
     * @param commitment contains all the details of the sponsorship
     * @param signature valid signature of the commitment by the recipient
     */
    function claim(Commitment calldata commitment, bytes calldata signature) public returns (bool) {
        address signer = _verify(commitment, signature);
        if (signer != commitment.recipient) {
        revert InvalidClaim();
        }

        bytes32 commitmentHash = keccak256(abi.encode(commitment));

        if (commitments[commitmentHash] != SponsorshipStatus.Approved) {
        revert NotApproved();
        }

        commitments[commitmentHash] = SponsorshipStatus.Claimed;

        _claim(commitment);

        emit Claimed(msg.sender, commitment);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
    ////                   ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    // @dev Allows the owner to change the claim delay
    // Especially useful if the DAO plans to increase it's voting and/or grace periods.  Change this contracts delay
    // pre-emptively to prevent rogue proposals from being processed early.
    // @param additiveDelay the amount of time to add to the voting and grace periods
    function setClaimDelay(uint256 additiveDelay) public {
        _authenticateHat(msg.sender, OWNER_HAT());
        claimDelay = additiveDelay + BAAL().votingPeriod() + BAAL().gracePeriod();
        emit ClaimDelaySet(claimDelay);
    }

    /*//////////////////////////////////////////////////////////////
    ////                   INTERNAL / PRIVATE
    //////////////////////////////////////////////////////////////*/

    // @dev Reverts if the specified signer is not wearing the specified hat
    // @param signer the address of the signer
    // @param hatId the id of the hat
    function _authenticateHat(address signer, uint256 hatId) internal view returns (bool) {
        if (!HATS().isWearerOfHat(signer, hatId)) {
            revert NotAuth(hatId);
        }
        return true;
    }

    // @dev Verifies the signature against the commitment by building a typed data hash digest and recovering the
    // signer from the digest.
    // @param commitment contains all the details of the sponsorship
    // @param signature valid signature of the commitment by the signer
    function _verify(Commitment memory commitment, bytes memory signature) internal view returns (address) {
        bytes32 digest = _hashTypedData(keccak256(abi.encode(
            keccak256("Commitment(uint256 hatId,uint256 shares,uint256 loot,uint256 extraRewardAmount,uint256 completionDeadline,uint256 sponsoredTime,bytes32 arweaveContentDigest,address recipient,address extraRewardToken)"),
            commitment.hatId,
            commitment.shares,
            commitment.loot,
            commitment.extraRewardAmount,
            commitment.completionDeadline,
            commitment.sponsoredTime,
            commitment.arweaveContentDigest,
            commitment.recipient,
            commitment.extraRewardToken
        )));

        address signer = digest.recover(signature);
        if (signer == address(0)) {
            revert InvalidSignature();
        }

        return signer;
    }

    // @dev Mints the shares, loot, and extra rewards to the recipient
    // @param commitment contains all the details of the sponsorship
    function _claim(Commitment memory commitment) internal {
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

        if (commitment.extraRewardAmount > 0 && commitment.extraRewardToken != address(0)) {
            bool success = IERC20(commitment.extraRewardToken).transfer(commitment.recipient, commitment.extraRewardAmount);
            if (!success) {
                revert FailedExtraRewards(commitment.extraRewardToken, commitment.extraRewardAmount);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
    ////                        OVERRIDES
    //////////////////////////////////////////////////////////////*/

    // @dev Returns the contract version and name for constructing a domain separator.
    // note: update the version value prior to deploying any modified implementation
    function _domainNameAndVersion()
        internal
        pure
        override(HatsModuleEIP712)
        returns (string memory name, string memory version) {
        return ("Seneschal", "1.0");
    }
}