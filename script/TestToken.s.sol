// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Script, console2 } from "forge-std/Script.sol";
import { Token } from "../test/mocks/Token.sol";

contract DeployToken is Script {
  /// @dev Designed for override to not be necessary (all changes / config can be made in above functions), but can be
  /// if desired
  function run() public virtual {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    Token token = new Token();

    vm.stopBroadcast();

    console2.log("Instance: ", address(token));
  }
}
