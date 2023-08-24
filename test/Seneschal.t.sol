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

contract HatsOnboardingShamanTest is DeployImplementation, Test {

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

    event Sponsored(address indexed sponsor, address indexed recipient, Commitment commitment);
    event Processed(address indexed processor, address indexed recipient, Commitment commitment);
    event Claimed(address indexed recipient, Commitment commitment);
    event ClaimDelaySet(uint256 delay);

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy via the script
    DeployImplementation.prepare(SHAMAN_VERSION, false); // set last arg to true to log deployment addresses
    DeployImplementation.run();
  }

}