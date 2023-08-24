// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { Seneschal } from "../src/Seneschal.sol";
import { DeployImplementation } from "../script/HatsOnboardingShaman.s.sol";
import {
  IHats,
  HatsModuleFactory,
  deployModuleFactory,
  deployModuleInstance
} from "lib/hats-module/src/utils/DeployFunctions.sol";
import { IBaal } from "baal/interfaces/IBaal.sol";
import { IBaalToken } from "baal/interfaces/IBaalToken.sol";
import { IBaalSummoner } from "baal/interfaces/IBaalSummoner.sol";
import { Commitment, SponsorshipStatus } from "src/CommitmentStructs.sol";

contract SeneschalTest is DeployImplementation, Test {

  // variables inherited from DeployImplementation script
  // HatsOnboardingShaman public implementation;
  // bytes32 public SALT;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 16_947_805; // the block number where v1.hatsprotocol.eth was deployed;

  IHats public constant HATS = IHats(0x9D2dfd6066d5935267291718E8AA16C8Ab729E9d); // v1.hatsprotocol.eth
  string public FACTORY_VERSION = "factory test version";
  string public SHAMAN_VERSION = "shaman test version";

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


  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy via the script
    DeployImplementation.prepare(SHAMAN_VERSION, false); // set last arg to true to log deployment addresses
    DeployImplementation.run();
  }
}

contract WithInstanceTest is SeneschalTest {

  HatsModuleFactory public factory;
  Seneschal public shaman;
  uint256 public hatId;
  uint256 public hatId2;
  bytes public otherImmutableArgs;
  bytes public initData;

  address public zodiacFactory = 0x00000000000DC7F163742Eb4aBEf650037b1f588;
  IBaalSummoner public summoner = IBaalSummoner(0x7e988A9db2F8597735fc68D21060Daed948a3e8C);
  IBaal public baal;
  IBaalToken public sharesToken;
  IBaalToken public lootToken;

  uint256 public baalSaltNonce;

  uint256 public tophat;
  uint256 public memberHat;
  address public eligibility = makeAddr("eligibility");
  address public toggle = makeAddr("toggle");
  address public dao = makeAddr("dao");
  address public wearer1 = makeAddr("wearer1");
  address public wearer2 = makeAddr("wearer2");
  address public eligibleRecipient = makeAddr("eligibleRecipient");
  address public nonWearer = makeAddr("nonWearer");

  address public predictedBaalAddress;
  address public predictedShamanAddress;

  // @dev handles data formatting for the HatsFactory and deploys the new instance w/ immutable args
  // note that the HATS contract address is hardcoded in the HatsFactory
  function deployInstance(
    address _baal,
    uint256 _sponsorHatId,
    uint256 _ownerHat,
    uint256 _processorHatId,
    uint256 _additiveDelay)
    public
    returns (Seneschal)
  {
    // encode the other immutable args as packed bytes
    otherImmutableArgs = abi.encodePacked(_baal, _ownerHat, _processorHatId);
    // encoded the initData as unpacked bytes -- for Seneschal, we just need any non-empty bytes
    initData = abi.encode(_additiveDelay);
    // deploy the instance
    return Seneschal(
      deployModuleInstance(factory, address(implementation), _sponsorHatId, otherImmutableArgs, initData)
    );
  }

}