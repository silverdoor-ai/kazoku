// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { Seneschal } from "../src/Seneschal.sol";
import { DeployImplementation } from "../script/Seneschal.s.sol";
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

  event Sponsored(
        address indexed sponsor,
        address indexed recipient,
        bytes32 indexed commitmentHash,
        Commitment commitment);

    event Processed(
        address indexed processor,
        address indexed recipient,
        bytes32 indexed commitmentHash);

    event Claimed(address indexed recipient, bytes32 indexed commitmentHash);
    event ClaimDelaySet(uint256 delay);


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
  uint256 public sponsorHat;
  uint256 public processorHat;
  uint256 public eligibleHat;
  uint256 public additiveDelay = 1 days;
  address public eligibility = makeAddr("eligibility");
  address public toggle = makeAddr("toggle");
  address public dao = makeAddr("dao");
  address public sponsorHatWearer = makeAddr("sponsorHatWearer");
  address public processorHatWearer = makeAddr("processorHatWearer");
  address public eligibleRecipient = makeAddr("eligibleRecipient");
  address public nonWearer = makeAddr("nonWearer");

  // EIP712 Signing
  bytes32 public DOMAIN_SEPARATOR;
  bytes32 public constant _DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

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

  function deployBaalWithShaman(string memory _name, string memory _symbol, bytes32 _saltNonce, address _shaman)
    public
    returns (IBaal)
  {
    // encode initParams
    bytes memory initializationParams = abi.encode(_name, _symbol, address(0), address(0), address(0), address(0));
    // encode initial action to set the shaman
    address[] memory shamans = new address[](1);
    uint256[] memory permissions = new uint256[](1);
    shamans[0] = _shaman;
    permissions[0] = 2; // manager only
    bytes[] memory initializationActions = new bytes[](1);
    initializationActions[0] = abi.encodeCall(IBaal.setShamans, (shamans, permissions));
    // deploy the baal
    return IBaal(
      summoner.summonBaalFromReferrer(initializationParams, initializationActions, uint256(_saltNonce), "referrer")
    );
  }

  /// @dev props to @santteegt
  function predictBaalAddress(bytes32 _saltNonce) public view returns (address baalAddress) {
    address template = summoner.template();
    bytes memory initializer = abi.encodeWithSignature("avatar()");

    bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), uint256(_saltNonce)));

    // This is how ModuleProxyFactory works
    bytes memory deployment =
    //solhint-disable-next-line max-line-length
     abi.encodePacked(hex"602d8060093d393df3363d3d373d3d3d363d73", template, hex"5af43d82803e903d91602b57fd5bf3");

    bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), zodiacFactory, salt, keccak256(deployment)));

    // NOTE: cast last 20 bytes of hash to address
    baalAddress = address(uint160(uint256(hash)));
  }

  function grantShares(address _member, uint256 _amount) public {
    vm.prank(address(baal));
    sharesToken.mint(_member, _amount);
  }

  function grantLoot(address _member, uint256 _amount) public {
    vm.prank(address(baal));
    lootToken.mint(_member, _amount);
  }

  function buildSeparatorFromShaman() public {
    ( ,
      string memory name,
      string memory version,
      uint256 chainId,
        address verifyingContract,
    , ) = shaman.eip712Domain();

    bytes32 nameHash = keccak256(bytes(name));
    bytes32 versionHash = keccak256(bytes(version));

    bytes32 separator;
    /// @solidity memory-safe-assembly
    assembly {
        let m := mload(0x40) // Load the free memory pointer.
        mstore(m, _DOMAIN_TYPEHASH)
        mstore(add(m, 0x20), nameHash)
        mstore(add(m, 0x40), versionHash)
        mstore(add(m, 0x60), chainid())
        mstore(add(m, 0x80), verifyingContract)
        separator := keccak256(m, 0xa0)
    }
    DOMAIN_SEPARATOR = separator;
  }

  function _hashTypedData(bytes32 structHash) public returns (bytes32 digest) {
        bytes32 separator = DOMAIN_SEPARATOR;
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the digest.
            mstore(0x00, 0x1901000000000000) // Store "\x19\x01".
            mstore(0x1a, separator) // Store the domain separator.
            mstore(0x3a, structHash) // Store the struct hash.
            digest := keccak256(0x18, 0x42)
            // Restore the part of the free memory slot that was overwritten.
            mstore(0x3a, 0)
        }
    }

  function setUp() public virtual override {
    super.setUp();

    // deploy the hats module factory
    factory = deployModuleFactory(HATS, SALT, FACTORY_VERSION);

    // set up hats
    tophat = HATS.mintTopHat(dao, "tophat", "dao.eth/tophat");
    vm.startPrank(dao);
    sponsorHat = HATS.createHat(tophat, "sponsorHat", 50, eligibility, toggle, true, "dao.eth/sponsorHat");
    processorHat = HATS.createHat(tophat, "processorHat", 50, eligibility, toggle, true, "dao.eth/processorHat");
    eligibleHat = HATS.createHat(tophat, "eligibleHat", 50, eligibility, toggle, true, "dao.eth/eligibleHat");
    HATS.mintHat(sponsorHat, sponsorHatWearer);
    HATS.mintHat(processorHat, processorHatWearer);
    HATS.mintHat(eligibleHat, eligibleRecipient);
    vm.stopPrank();

    // predict the baal's address
    predictedBaalAddress = predictBaalAddress(SALT);

    // predict the shaman's address via the hats module factory
    predictedShamanAddress =
      factory.getHatsModuleAddress(
        address(implementation),
        sponsorHat,
        abi.encodePacked(predictedBaalAddress, tophat, processorHat));

    // deploy a test baal with the predicted shaman address
    baal = deployBaalWithShaman("TEST_BAAL", "TEST_BAAL", SALT, predictedShamanAddress);
    // find and set baal token addresses
    sharesToken = IBaalToken(baal.sharesToken());
    lootToken = IBaalToken(baal.lootToken());

    // deploy the shaman instance
    shaman = deployInstance(
      predictedBaalAddress,
      sponsorHat,
      tophat,
      processorHat,
      additiveDelay);

    // ensure that the actual and predicted addresses are the same
    require(address(baal) == predictedBaalAddress, "actual and predicted baal addresses do not match");
  }
}

contract Deployment is WithInstanceTest {

  function testDeployment() public {
    // check that the shaman was deployed at the predicted address
    assertEq(address(shaman), predictedShamanAddress);
  }

  function test_setAsManagerShaman() public {
    assertEq(baal.shamans(address(shaman)), 2);
  }

  function test_baal() public {
    assertEq(address(shaman.BAAL()), address(baal));
    assertEq(address(shaman.BAAL()), predictBaalAddress(SALT));
  }

  function test_sharesToken() public {
    assertEq(address(shaman.SHARES_TOKEN()), address(sharesToken));
  }

  function test_lootToken() public {
    assertEq(address(shaman.LOOT_TOKEN()), address(lootToken));
  }

  function test_version() public {
    assertEq(shaman.version(), SHAMAN_VERSION);
  }

  function test_sponsorHat() public {
    assertEq(shaman.hatId(), sponsorHat);
  }

  function test_ownerHat() public {
    assertEq(shaman.OWNER_HAT(), tophat);
  }

  function test_additiveDelay() public {
    uint256 _claimDelay = additiveDelay + IBaal(baal).votingPeriod() + IBaal(baal).gracePeriod() + 3 days;
    assertEq(shaman.claimDelay(), _claimDelay);
  }
  
  function test_commit() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _completionDeadline = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      hatId: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            completionDeadline: _completionDeadline,
             sponsoredTime: uint256(0),
                arweaveContentDigest: bytes32("theSlug"),
                 recipient: nonWearer,
                  extraRewardToken: address(0)
    });



  }
}