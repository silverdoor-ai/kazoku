// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { HatsModule } from "hats-module/HatsModule.sol";
import { IBaal } from "baal/interfaces/IBaal.sol";
import { IBaalToken } from "baal/interfaces/IBaalToken.sol";
import { HatsModuleEIP712 } from "src/HatsModuleEIP712.sol";
import { ECDSA } from "solady/utils/ECDSA.sol";
import { IERC20 } from "src/dep/IERC20.sol";
import { IERC1271 } from "src/dep/IERC1271.sol";
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
    error InvalidExtraRewards(address extraRewardToken, uint256 extraRewardAmount);
    error InvalidClear(SponsorshipStatus status, uint256 timeFactor);
    error NotApproved();
    error NotSponsored();
    error ProcessedEarly();
    error DeadlinePassed();
    error InvalidClaim();
    error InvalidSignature();
    error ExistingCommitment();
    error InvalidPoke();
    error PokedEarly();
    error InvalidContractSigner();
    error InvalidMagicValue();
    error Expired();

    /*//////////////////////////////////////////////////////////////
    ////                     EVENTS
    //////////////////////////////////////////////////////////////*/

    event Sponsored(
        address indexed sponsor,
        bytes32 indexed commitmentHash,
        Commitment commitment);

    event Processed(address indexed processor, bytes32 indexed commitmentHash);
    
    event Cleared(address indexed clearedBy, bytes32 indexed commitmentHash);
    event Claimed(bytes32 indexed commitmentHash);
    event ClaimDelaySet(uint256 delay);
    event Poke(address indexed recipient, bytes32 indexed commitmentHash, bytes32 completionReport);

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

    // @notice returns the hatId of the sponsor hat
    function getSponsorHat() public pure returns (uint256) {
      return _getArgUint256(40);
    }

    // @notice returns the hatId of the processor hat
    function getProcessorHat() public pure returns (uint256) {
      return _getArgUint256(124);
    }

    /**
     * @dev These are not stored as immutable args in order to enable instances to be set as shamans in new Baal
     * deployments via `initializationActions`, which is not possible if these values determine an instance's address.
     */
    IBaalToken public SHARES_TOKEN;
    IBaalToken public LOOT_TOKEN;

    mapping (address tokenContract => uint256 totalExtraRewards) private _extraRewardDebt;

    uint256 public claimDelay;

    /*//////////////////////////////////////////////////////////////
                          MUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    // hashed fingerprint of the proposal
    mapping(bytes32 commitmentHash => SponsorshipStatus status) private _commitments;

    // note that HatsModule constructor disables initializer automatically
    // note that HatsModuleEIP712 constructor disables initializer automatically
    constructor(string memory _version) HatsModule(_version) { }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc HatsModule
     */
    function _setUp(bytes calldata _initData) internal override {
        SHARES_TOKEN = IBaalToken(BAAL().sharesToken());
        LOOT_TOKEN = IBaalToken(BAAL().lootToken());

        uint256 additiveDelay = abi.decode(_initData, (uint256));
        claimDelay = additiveDelay;
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
    function sponsor(Commitment memory commitment, bytes memory signature) public returns (bool) {
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = _splitSignature(signature);
        address signer;

        if (v == 0) {
            signer = address(uint160(uint256(r)));
            _authenticateHat(signer, getSponsorHat());
            _verifyContractSignature(getDigest(commitment), s, signer);
        }

        else {
            signer = _verifySigner(commitment, signature);
            _authenticateHat(signer, getSponsorHat());
        }

        if (commitment.eligibleHat != 0) {
            _authenticateHat(commitment.recipient, commitment.eligibleHat);
        }

        if (commitment.extraRewardAmount > 0) {
            address extraRewardToken = commitment.extraRewardToken;
            uint256 rewardTokenDebt = extraRewardDebt(commitment.extraRewardToken);
            rewardTokenDebt += commitment.extraRewardAmount;
            if (rewardTokenDebt > IERC20(extraRewardToken).balanceOf(address(this))) {
                revert InvalidExtraRewards(extraRewardToken, commitment.extraRewardAmount);
            }
            _extraRewardDebt[extraRewardToken] = rewardTokenDebt;
        }

        commitment.sponsoredTime = block.timestamp;

        bytes32 commitmentHash = keccak256(abi.encode(commitment));

        if (_commitments[commitmentHash] != SponsorshipStatus.Empty) {
            revert ExistingCommitment();
        }
        _commitments[commitmentHash] = SponsorshipStatus.Pending;

        emit Sponsored(signer, commitmentHash, commitment);
        return true;
    }

    /**
     * @dev Allows a processor to mark a token distribution commitment as completed
     * @param commitment contains all the details of the sponsorship
     * @param signature valid signature of the commitment by the processor
     */
    function process(Commitment calldata commitment, bytes calldata signature) public returns (bool) {
        bytes32 commitmentHash = keccak256(abi.encode(commitment));
        if (_commitments[commitmentHash] != SponsorshipStatus.Pending) {
        revert NotSponsored();
        }

        if (commitment.sponsoredTime + getClaimDelay() > block.timestamp) {
        revert ProcessedEarly();
        }

        if (block.timestamp > commitment.timeFactor) {
        revert DeadlinePassed();
        }

        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = _splitSignature(signature);
        address signer;

        if (v == 0) {
            signer = address(uint160(uint256(r)));
            _authenticateHat(signer, getProcessorHat());
            _verifyContractSignature(getDigest(commitment), s, signer);
        }

        else {
            signer = _verifySigner(commitment, signature);
            _authenticateHat(signer, getProcessorHat());
        }

        if (commitment.eligibleHat != 0) {
            _authenticateHat(commitment.recipient, commitment.eligibleHat);
        }

        _commitments[commitmentHash] = SponsorshipStatus.Approved;

        emit Processed(signer, commitmentHash);
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
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = _splitSignature(signature);
        address signer;

        bytes32 commitmentHash = keccak256(abi.encode(commitment));

        if (_commitments[commitmentHash] != SponsorshipStatus.Approved) {
        revert NotApproved();
        }

        _commitments[commitmentHash] = SponsorshipStatus.Claimed;

        if (v == 0) {
            signer = address(uint160(uint256(r)));
            if (signer != commitment.recipient) {
                revert InvalidClaim();
            }
            _verifyContractSignature(getDigest(commitment), s, signer);
        }

        else {
            signer = _verifySigner(commitment, signature);
            if (signer != commitment.recipient) {
                revert InvalidClaim();
            }
        }

        if (commitment.expirationTime < block.timestamp) {
            revert Expired();
        }
        _claim(commitment);

        emit Claimed(commitmentHash);
        return true;
    }

    // @dev Allows a recipient to poke the contract to report completion of the sponsorship
    // @param commitment contains all the details of the sponsorship
    // @param completionReport the content digest identifier of the completion report
    function poke(Commitment calldata commitment, bytes32 completionReport) public returns (bool) {
        bytes32 commitmentHash = keccak256(abi.encode(commitment));
        if (_commitments[commitmentHash] != SponsorshipStatus.Pending) {
            revert NotSponsored();
        }
        if (commitment.recipient != msg.sender) {
            revert InvalidPoke();
        }

        if (block.timestamp < commitment.sponsoredTime + claimDelay) {
            revert PokedEarly();
        }

        emit Poke(msg.sender, commitmentHash, completionReport);
        return true;
    }

    // @dev Allows anyone to clear a commitment that has failed
    // @param commitment contains all the details of the sponsorship
    function clear(Commitment calldata commitment) public returns (bool) {
        bytes32 commitmentHash = keccak256(abi.encode(commitment));

        // time factor is the deadline for the commitment
        SponsorshipStatus status = _commitments[commitmentHash];
        if (status != SponsorshipStatus.Pending && commitment.timeFactor < block.timestamp) {
            revert InvalidClear(status, commitment.timeFactor);
        }

        _commitments[commitmentHash] = SponsorshipStatus.Failed;
        _extraRewardDebt[commitment.extraRewardToken] -= commitment.extraRewardAmount;
        emit Cleared(msg.sender, commitmentHash);
        return true;
    }

    function clearExpired(Commitment calldata commitment) public returns (bool) {
        bytes32 commitmentHash = keccak256(abi.encode(commitment));

        // expiration time is the expiration of a completed commitment
        SponsorshipStatus status = _commitments[commitmentHash];
        if (commitment.expirationTime > block.timestamp ||
            status == SponsorshipStatus.Empty ||
            status == SponsorshipStatus.Failed ||
            status == SponsorshipStatus.Claimed)
        {
            revert InvalidClear(status, commitment.expirationTime);
        }

        _commitments[commitmentHash] = SponsorshipStatus.Failed;
        _extraRewardDebt[commitment.extraRewardToken] -= commitment.extraRewardAmount;
        emit Cleared(msg.sender, commitmentHash);
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
        claimDelay = additiveDelay;
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
    function _verifySigner(Commitment memory commitment, bytes memory signature) internal view returns (address) {
        bytes32 digest = getDigest(commitment);

        address signer = digest.recover(signature);
        if (signer == address(0)) {
            revert InvalidSignature();
        }

        return signer;
    }

    /**
     * @dev Checks whether the signature provided is valid for the provided hash, complies with EIP-1271. A signature is valid if:
     *  - It's a valid EIP-1271 signature by a contract wearing the specified hat
     * @param digest Hash of the data (could be either a message hash or transaction hash)
     * @param s ECDSA signature parameter s

     */
    function _verifyContractSignature(bytes32 digest, bytes32 s, address signer) internal view {

        // The signature data to pass for validation to the contract is appended to the signature and the offset is stored in s
        bytes memory contractSignature = abi.encode(s);

        bytes4 magicValue = IERC1271(signer).isValidSignature(
                digest,
                contractSignature
            );
        if (magicValue != EIP1271_MAGICVALUE) {
            revert InvalidContractSigner();
        }

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
            address extraRewardToken = commitment.extraRewardToken;
            bool success = IERC20(extraRewardToken).transfer(commitment.recipient, commitment.extraRewardAmount);
            if (!success) {
                revert InvalidExtraRewards(extraRewardToken, commitment.extraRewardAmount);
            }
            _extraRewardDebt[extraRewardToken] -= commitment.extraRewardAmount;
        }
    }

    /*//////////////////////////////////////////////////////////////
    ////                      VIEW & PURE
    //////////////////////////////////////////////////////////////*/

    // @dev Returns the correct EIP712 hash digest of the commitment
    // @param commitment contains all the details of the sponsorship
    function getDigest(Commitment memory commitment) public view returns (bytes32) {
        return _hashTypedData(keccak256(abi.encode(
            keccak256("Commitment(uint256 eligibleHat,uint256 shares,uint256 loot,uint256 extraRewardAmount,uint256 timeFactor,uint256 sponsoredTime,uint256 expirationTime,string contextURL,address recipient,address extraRewardToken)"),
            commitment.eligibleHat,
            commitment.shares,
            commitment.loot,
            commitment.extraRewardAmount,
            commitment.timeFactor,
            commitment.sponsoredTime,
            commitment.expirationTime,
            keccak256(bytes(commitment.contextURL)),
            commitment.recipient,
            commitment.extraRewardToken
        )));
    }

    // @dev Returns the commitment hash
    // @param commitment contains all the details of the sponsorship
    function getCommitmentHash(Commitment memory commitment) public pure returns (bytes32) {
        return keccak256(abi.encode(commitment));
    }

    // @dev Returns the status of a commitment
    // @param commitmentHash the hash of the commitment
    function commitments(bytes32 commitmentHash) public view returns (SponsorshipStatus) {
        return _commitments[commitmentHash];
    }

    // @dev Returns the total amount of extra rewards owed to recipients
    // @param tokenContract the address of the extra reward token
    function extraRewardDebt(address tokenContract) public view returns (uint256) {
        return _extraRewardDebt[tokenContract];
    }

    // @dev Returns the claim delay including the voting and grace periods
    function getClaimDelay() public view returns (uint256) {
        return claimDelay + BAAL().votingPeriod() + BAAL().gracePeriod();
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