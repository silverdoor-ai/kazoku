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

    address public deployerAddress = 0x87002DEbA8A7a0194870CfE2309F6C018Ad01AE8;

    uint8 public v;
    bytes32 public r;
    bytes32 public s;

    uint256 public _claimDelay = shaman.claimDelay();
    uint256 public _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment public commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                expirationTime : uint256(3650 days + block.timestamp),
                contextURL: contextURL,
                 recipient: deployerAddress,
                  extraRewardToken: address(0)
    });

    bytes32 public digest = shaman.getDigest(commitment);

    function run() public {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    (v, r, s) = vmSafe.sign(privKey, digest);
    bytes memory signature = abi.encodePacked(r, s, v);

    shaman.sponsor(commitment, signature);

    vm.stopBroadcast();
    // forge script script/SeneschalActions.s.sol:SeneschalSponsor -f gnosis --broadcast
  }

}

contract SeneschalProcess is SeneschalSponsor {



}