// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Script, console2, VmSafe } from "forge-std/Script.sol";
import { Seneschal } from "../src/Seneschal.sol";
import { HatsModuleFactory, deployModuleFactory, deployModuleInstance } from "hats-module/utils/DeployFunctions.sol";

contract DeployImplementation is Script {
  Seneschal public implementation;

  string public saltyString = vm.envString("SALT");
  bytes32 public SALT = keccak256(bytes(saltyString));

  // default values
  string public version = "0.1.0"; // increment with each deploy
  bool private verbose = true;

  /// @notice Override default values, if desired
  function prepare(string memory _version, bool _verbose) public {
    version = _version;
    verbose = _verbose;
  }

  function run() public {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    implementation = new Seneschal{ salt: SALT}(version);

    vm.stopBroadcast();

    if (verbose) {
      console2.log("Seneschal: ", address(implementation));
    }
  }

  // forge script script/Seneschal.s.sol:DeployImplementation -f gnosis --broadcast --verify
}

contract DeployInstance is Script {
  HatsModuleFactory public factory = HatsModuleFactory(vm.envAddress("HATS_MODULE_FACTORY"));

  address public instance;
  address public implementation = vm.envAddress("IMPLEMENTATION");

  uint256 public sponsorHatId = vm.envUint("SPONSOR_HAT_ID");
  address public baal = vm.envAddress("BAAL");
  uint256 public ownerHat = vm.envUint("OWNER_HAT");
  uint256 public witnessHatId = vm.envUint("WITNESS_HAT_ID");
  bytes public otherImmutableArgs;

  uint256 additiveDelay = vm.envUint("ADDITIVE_DELAY");
  bytes public initData;

  bool internal verbose = true;
  bool internal defaults = true;

  /// @dev override this to abi.encode (packed) other relevant immutable args (initialized and set within the function
  /// body). Alternatively, you can pass encoded data in
  function encodeImmutableArgs() internal virtual returns (bytes memory) {
    otherImmutableArgs = abi.encodePacked(baal, sponsorHatId, witnessHatId);
    return otherImmutableArgs;
  }

  /// @dev override this to abi.encode (unpacked) the init data (initialized and set within the function body)
  function encodeInitData() internal virtual returns (bytes memory) {
    initData = abi.encode(additiveDelay);
    return initData;
  }

  /// @dev override this to set the default values within the function body
  function setDefaultValues() internal virtual {
    // factory = HatsModuleFactory(0x);
    // implementation = 0x;
    // hatId = ;
  }

  /// @dev Call from tests or other scripts to override default values
  function prepare(
    HatsModuleFactory _factory,
    address _implementation,
    uint256 _sponsorHatId,
    address _baal,
    uint256 _ownerHat,
    uint256 _witnessHatId,
    bytes memory _otherImmutableArgs,
    bytes memory _initData,
    bool _verbose
  ) public {
    factory = _factory;
    implementation = _implementation;
    sponsorHatId = _sponsorHatId;
    baal = _baal;
    ownerHat = _ownerHat;
    witnessHatId = _witnessHatId;
    otherImmutableArgs = _otherImmutableArgs;
    initData = _initData;
    verbose = _verbose;

    defaults = false;
  }

  /// @dev Designed for override to not be necessary (all changes / config can be made in above functions), but can be
  /// if desired
  function run() public virtual {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    // encode the other immutable args
    otherImmutableArgs = encodeImmutableArgs();
    // encode the init data
    initData = encodeInitData();

    // deploy the instance
    instance = deployModuleInstance(factory, implementation, sponsorHatId, otherImmutableArgs, initData);

    vm.stopBroadcast();

    if (verbose) {
      console2.log("Instance: ", instance);
    }
  }

  // forge script script/Seneschal.s.sol:DeployInstance -f gnosis --broadcast --verify
}
