// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Script, console2 } from "forge-std/Script.sol";
import { Seneschal } from "../src/Seneschal.sol";
import { Commitment, SponsorshipStatus } from "../src/CommitmentStructs.sol";

contract SeneschalSponsor is Script {
  address public instance = vm.envAddress("INSTANCE");

  uint256 public additiveDelay = vm.envUint("ADDITIVE_DELAY");

  Seneschal public shaman = Seneschal(instance);

  string public contextURL = "https://mirror.xyz/ethdaily.eth/Jo47vaxEpV7jBTw7g6doxSB7i7Ogctppuc9N7nWRPPA";
  string public metadataString = "ipfs://blahblah";

  address public deployerAddress = 0x87002DEbA8A7a0194870CfE2309F6C018Ad01AE8;

  uint256 public amount = 95 ether;

  uint8 public v;
  bytes32 public r;
  bytes32 public s;

  uint256 public _claimDelay = shaman.claimDelay();
  uint256 public _timeFactor = block.timestamp + 1 days + _claimDelay;

  Commitment public commitment = Commitment({
    eligibleHat: uint256(0),
    shares: amount,
    loot: amount,
    extraRewardAmount: uint256(0),
    timeFactor: _timeFactor,
    sponsoredTime: uint256(0),
    expirationTime: uint256(3650 days + block.timestamp),
    contextURL: contextURL,
    metadata: metadataString,
    recipient: deployerAddress,
    extraRewardToken: address(0)
  });

  bytes32 public digest = shaman.getDigest(commitment);

  function run() public virtual {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    (v, r, s) = vmSafe.sign(privKey, digest);
    bytes memory signature = abi.encodePacked(r, s, v);

    shaman.sponsor(commitment, signature);

    console2.log("Digest: ");
    console2.logBytes32(digest);
    console2.logBytes(signature);

    vm.stopBroadcast();

    // forge script script/SeneschalActions.s.sol:SeneschalSponsor -f gnosis --broadcast
  }
}

contract SeneschalProcess is SeneschalSponsor {
  Commitment public nextCommitment = Commitment({
    eligibleHat: uint256(0),
    shares: amount,
    loot: amount,
    extraRewardAmount: uint256(0),
    timeFactor: _timeFactor,
    sponsoredTime: uint256(1_693_702_920),
    expirationTime: uint256(3650 days + block.timestamp),
    contextURL: contextURL,
    metadata: metadataString,
    recipient: deployerAddress,
    extraRewardToken: address(0)
  });

  bytes32 public nextDigest = shaman.getDigest(nextCommitment);

  function run() public override {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    (v, r, s) = vmSafe.sign(privKey, nextDigest);
    bytes memory signature = abi.encodePacked(r, s, v);

    shaman.witness(nextCommitment, signature);

    vm.stopBroadcast();

    // forge script script/SeneschalActions.s.sol:SeneschalProcess -f gnosis --broadcast
  }
}

contract SeneschalClaim is SeneschalSponsor {
  Commitment public nextCommitment = Commitment({
    eligibleHat: uint256(0),
    shares: amount,
    loot: amount,
    extraRewardAmount: uint256(0),
    timeFactor: _timeFactor,
    sponsoredTime: uint256(1_693_702_920),
    expirationTime: uint256(3650 days + block.timestamp),
    contextURL: contextURL,
    metadata: metadataString,
    recipient: deployerAddress,
    extraRewardToken: address(0)
  });

  bytes32 public nextDigest = shaman.getDigest(nextCommitment);

  function run() public override {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    (v, r, s) = vmSafe.sign(privKey, nextDigest);
    bytes memory signature = abi.encodePacked(r, s, v);

    shaman.claim(nextCommitment, signature);

    vm.stopBroadcast();

    // forge script script/SeneschalActions.s.sol:SeneschalClaim -f gnosis --broadcast
  }
}
