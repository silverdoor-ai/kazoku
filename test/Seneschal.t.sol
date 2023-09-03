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
} from "hats-module/utils/DeployFunctions.sol";
import { IBaal } from "baal/interfaces/IBaal.sol";
import { IBaalToken } from "baal/interfaces/IBaalToken.sol";
import { IBaalSummoner } from "baal/interfaces/IBaalSummoner.sol";
import { Commitment, SponsorshipStatus } from "src/CommitmentStructs.sol";
import { Token } from "test/mocks/Token.sol";
import { ContractAccount } from "test/mocks/ContractAccount.sol";

contract SeneschalTest is DeployImplementation, Test {

  // variables inherited from DeployImplementation script
  // HatsOnboardingShaman public implementation;
  // bytes32 public SALT;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 16_947_805; // the block number where v1.hatsprotocol.eth was deployed;

  IHats public constant HATS = IHats(0x9D2dfd6066d5935267291718E8AA16C8Ab729E9d); // v1.hatsprotocol.eth
  string public FACTORY_VERSION = "factory test version";
  string public SHAMAN_VERSION = "shaman test version";
  Token public token;

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

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy via the script
    DeployImplementation.prepare(SHAMAN_VERSION, false); // set last arg to true to log deployment addresses
    DeployImplementation.run();
    token = new Token();
  }
}

contract WithInstanceTest is SeneschalTest {

  HatsModuleFactory public factory;
  Seneschal public shaman;
  ContractAccount contractAccount;
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
  uint256 public sponsorHatWearerPrivateKey = uint256(1);
  address public sponsorHatWearer = vm.addr(sponsorHatWearerPrivateKey);
  uint256 public processorHatWearerPrivateKey = uint256(2);
  address public processorHatWearer = vm.addr(processorHatWearerPrivateKey);
  uint256 public eligibleHatWearerPrivateKey = uint256(3);
  address public eligibleHatWearer = vm.addr(eligibleHatWearerPrivateKey);
  uint256 public nonWearerPrivateKey = uint256(4);
  address public nonWearer = vm.addr(nonWearerPrivateKey);

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

  function signFromUser(uint256 signer, bytes32 digest) public pure returns (bytes memory signature) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
    signature = abi.encodePacked(r, s, v);
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
    HATS.mintHat(eligibleHat, eligibleHatWearer);
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

    contractAccount = new ContractAccount();

    token.mint(address(shaman), 1000 ether);

    vm.label(address(factory), "Hats Module Factory");
    vm.label(address(shaman), "Seneschal");
    vm.label(address(baal), "Baal DAO");
    vm.label(address(HATS), "Hats Protocol");

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

  function test_badStartingShares_reverts() public {
    vm.expectEmit(true, false, false, false);
    uint256 claimDelay = 1 days;
    uint256 expectedClaimDelay = claimDelay + IBaal(baal).votingPeriod() + IBaal(baal).gracePeriod() + 3 days;
    emit ClaimDelaySet(expectedClaimDelay);

    shaman = deployInstance(
      predictedBaalAddress,
      sponsorHat + 1,
      tophat,
      processorHat + 1,
      additiveDelay);
  }

  function test_version() public {
    assertEq(shaman.version(), SHAMAN_VERSION);
  }

  function test_sponsorHat() public {
    assertEq(shaman.getSponsorHat(), sponsorHat);
  }

  function test_hatId() public {
    assertEq(shaman.hatId(), sponsorHat);
  }

  function test_processorHat() public {
    assertEq(shaman.getProcessorHat(), processorHat);
  }

  function test_ownerHat() public {
    assertEq(shaman.OWNER_HAT(), tophat);
  }

  function test_eip712Domain() public {
    (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = shaman.eip712Domain();

    assertEq(name, "Seneschal");
    assertEq(version, "1.0");
  }

  function test_additiveDelay() public {
    uint256 _claimDelay = additiveDelay + IBaal(baal).votingPeriod() + IBaal(baal).gracePeriod();
    assertEq(shaman.claimDelay(), _claimDelay);
  }
  
  function test_sponsor() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));
  }

  function test_sponsorBadSignerFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(nonWearerPrivateKey, digest);

    vm.expectRevert(
    abi.encodeWithSelector(NotAuth.selector, sponsorHat
    ));

    shaman.sponsor(commitment, signature);
  }

  function test_sponsorWithEligibility() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: eligibleHat,
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: eligibleHatWearer,
                  extraRewardToken: address(0),
                      expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));
  }

  function test_sponsorWithEligibilityFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: eligibleHat,
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                        expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);

    vm.expectRevert(
    abi.encodeWithSelector(NotAuth.selector, eligibleHat
    ));

    shaman.sponsor(commitment, signature);
  }

  function test_sponsorExistingCommitmentFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    vm.expectRevert(ExistingCommitment.selector);
    shaman.sponsor(commitment, signature);
  }

  function test_sponsorEvent() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: block.timestamp,
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                      expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);

    vm.expectEmit(true, true, true, true);
    emit Sponsored(sponsorHatWearer, shaman.getCommitmentHash(commitment), commitment);

    shaman.sponsor(commitment, signature);

  }

  function test_process() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));
  }

    function test_processLostEligibilityFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: eligibleHat,
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: eligibleHatWearer,
                  extraRewardToken: address(0),
                      expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.startPrank(eligibleHatWearer);
    HATS.renounceHat(eligibleHat);
    vm.stopPrank();

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    vm.expectRevert(
    abi.encodeWithSelector(NotAuth.selector, eligibleHat
    ));

    shaman.process(commitment, signature);
  }

  function test_processTooEarlyFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.expectRevert(ProcessedEarly.selector);
    shaman.process(commitment, signature);
  }

  function test_processAfterDeadlineFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 2 days + _claimDelay);

    vm.expectRevert(DeadlinePassed.selector);
    shaman.process(commitment, signature);
  }

  function test_processNonSponsoredFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    vm.expectRevert(NotSponsored.selector);
    shaman.process(commitment, signature);
  }

  function test_processEvent() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    vm.expectEmit(true, true, false, false);
    emit Processed(processorHatWearer, shaman.getCommitmentHash(commitment));
    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));
  }

  function test_claim() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    signature = signFromUser(nonWearerPrivateKey, digest);
    shaman.claim(commitment, signature);

    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Claimed;
    assertEq(uint256(actual), uint256(expected));

    uint256 expectedShareBalance = commitment.shares;
    uint256 expectedLootBalance = commitment.loot;

    assertEq(sharesToken.balanceOf(nonWearer), expectedShareBalance);
    assertEq(lootToken.balanceOf(nonWearer), expectedLootBalance);
  }

  function test_claimInvalidClaimFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    signature = signFromUser(sponsorHatWearerPrivateKey, digest);

    vm.expectRevert(InvalidClaim.selector);
    shaman.claim(commitment, signature);
  }

  function test_claimNotApprovedFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    signature = signFromUser(nonWearerPrivateKey, digest);

    vm.expectRevert(NotApproved.selector);
    shaman.claim(commitment, signature);
  }

  function test_claimEvent() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);

    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    signature = signFromUser(nonWearerPrivateKey, digest);

    vm.expectEmit(true, true, false, false);
    emit Claimed(shaman.getCommitmentHash(commitment));
    shaman.claim(commitment, signature);
  }

  function test_claimExtraReward() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(0),
        loot: uint256(0),
          extraRewardAmount: 1000 ether,
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(token),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    assertEq(shaman.extraRewardDebt(address(token)), 0);

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    assertEq(shaman.extraRewardDebt(address(token)), commitment.extraRewardAmount);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);

    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    signature = signFromUser(nonWearerPrivateKey, digest);

    vm.expectEmit(true, true, false, false);
    emit Claimed(shaman.getCommitmentHash(commitment));
    shaman.claim(commitment, signature);

    assertEq(shaman.extraRewardDebt(address(token)), 0);

    uint256 expectedExtraReward = 1000 ether;
    uint256 actualExtraReward = token.balanceOf(nonWearer);

    assertEq(actualExtraReward, expectedExtraReward);
  }

  function test_claimExtraRewardERC20Fail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(0),
        loot: uint256(0),
          extraRewardAmount: 1000 ether,
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(token),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    assertEq(shaman.extraRewardDebt(address(token)), 0);

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    assertEq(shaman.extraRewardDebt(address(token)), commitment.extraRewardAmount);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);

    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    signature = signFromUser(nonWearerPrivateKey, digest);

    token.pause();
    vm.expectRevert(
      abi.encodeWithSelector(InvalidExtraRewards.selector, commitment.extraRewardToken, commitment.extraRewardAmount)
    );
    shaman.claim(commitment, signature);
  }

  function test_sponsorExtraRewardFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(0),
        loot: uint256(0),
          extraRewardAmount: 1000 ether,
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(token),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    assertEq(shaman.extraRewardDebt(address(token)), 0);

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    assertEq(shaman.extraRewardDebt(address(token)), commitment.extraRewardAmount);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);

    commitment.extraRewardAmount = 2000 ether;
    digest = shaman.getDigest(commitment);
    signature = signFromUser(sponsorHatWearerPrivateKey, digest);

    vm.expectRevert(
      abi.encodeWithSelector(InvalidExtraRewards.selector, commitment.extraRewardToken, commitment.extraRewardAmount)
    );
    shaman.sponsor(commitment, signature);
  }

  function test_clear() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(0),
        loot: uint256(0),
          extraRewardAmount: 1000 ether,
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(token),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    assertEq(shaman.extraRewardDebt(address(token)), 0);

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);
    commitment.sponsoredTime = block.timestamp;

    assertEq(shaman.extraRewardDebt(address(token)), commitment.extraRewardAmount);

    vm.warp(commitment.timeFactor + 1);
    shaman.clear(commitment);

    assertEq(shaman.extraRewardDebt(address(token)), 0);

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus expected = SponsorshipStatus.Failed;
    assertEq(uint256(shaman.commitments(commitmentHash)), uint256(expected));
  }
  
  function test_clearInvalidClearFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(0),
        loot: uint256(0),
          extraRewardAmount: 1000 ether,
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(token),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    assertEq(shaman.extraRewardDebt(address(token)), 0);

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    assertEq(shaman.extraRewardDebt(address(token)), commitment.extraRewardAmount);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);

    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    signature = signFromUser(nonWearerPrivateKey, digest);

    vm.warp(commitment.timeFactor + 1);
    vm.expectRevert(
      abi.encodeWithSelector(InvalidClear.selector, uint256(2), commitment.timeFactor)
    );
    shaman.clear(commitment);
  }

  function test_setClaimDelay() public {
    vm.startPrank(dao);
    uint256 newClaimDelay = 3 days;
    shaman.setClaimDelay(newClaimDelay);
    vm.stopPrank();

    uint256 actual = shaman.claimDelay();
    uint256 expected = IBaal(baal).votingPeriod() + IBaal(baal).gracePeriod() + 6 days;
    assertEq(actual, expected);
  }

  function test_setClaimDelayEvent() public {
    vm.startPrank(dao);
    uint256 newClaimDelay = 3 days;
    uint256 expected = IBaal(baal).votingPeriod() + IBaal(baal).gracePeriod() + 6 days;

    vm.expectEmit(true, false, false, false);
    emit ClaimDelaySet(expected);
    shaman.setClaimDelay(newClaimDelay);
    vm.stopPrank();
  }

  function test_pokeEvent() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    vm.warp(block.timestamp + _claimDelay + 1);

    vm.expectEmit(true, true, true, false);
    emit Poke(nonWearer, shaman.getCommitmentHash(commitment), bytes32("The Report"));
    vm.prank(nonWearer);
    shaman.poke(commitment, bytes32("The Report"));

  }

  function test_pokePokedEarlyFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    vm.expectRevert(PokedEarly.selector);
    vm.prank(nonWearer);
    shaman.poke(commitment, bytes32("The Report"));
  }

  function test_pokeInvalidPokeFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });


    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    vm.expectRevert(InvalidPoke.selector);
    shaman.poke(commitment, bytes32("The Report"));

  }

  function test_pokeNotSponsoredFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    vm.expectRevert(NotSponsored.selector);
    shaman.poke(commitment, bytes32("The Report"));

  }

  function test_sponsorContractSigner() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    bytes32 r = bytes32(uint256(uint160(address(contractAccount))));
    bytes32 s = shaman.getDigest(commitment);
    uint8 v = 0;

    bytes memory signature = abi.encode(r, s, v);
    vm.prank(dao);
    HATS.mintHat(sponsorHat, address(contractAccount));

    contractAccount.authorizeDigest(s);

    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;
    bytes32 digest = shaman.getDigest(commitment);

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));
  }

  function test_processContractSigner() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 r = bytes32(uint256(uint160(address(contractAccount))));
    bytes32 s = shaman.getDigest(commitment);
    uint8 v = 0;

    signature = abi.encode(r, s, v);
    vm.prank(dao);
    HATS.mintHat(processorHat, address(contractAccount));

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    contractAccount.authorizeDigest(digest);

    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));
  }

  function test_contractSignerInvalidContractSignerFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    bytes32 r = bytes32(uint256(uint160(address(contractAccount))));
    bytes32 s = shaman.getDigest(commitment);
    uint8 v = 0;

    bytes memory signature = abi.encode(r, s, v);
    vm.prank(dao);
    HATS.mintHat(sponsorHat, address(contractAccount));

    vm.expectRevert(InvalidContractSigner.selector);
    shaman.sponsor(commitment, signature);
  }

  function test_claimContractSigner() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: address(contractAccount),
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    bytes32 r = bytes32(uint256(uint160(address(contractAccount))));
    bytes32 s = shaman.getDigest(commitment);
    uint8 v = 0;

    signature = abi.encode(r, s, v);

    contractAccount.authorizeDigest(digest);

    shaman.claim(commitment, signature);

    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Claimed;
    assertEq(uint256(actual), uint256(expected));

    uint256 expectedShareBalance = commitment.shares;
    uint256 expectedLootBalance = commitment.loot;

    assertEq(sharesToken.balanceOf(address(contractAccount)), expectedShareBalance);
    assertEq(lootToken.balanceOf(address(contractAccount)), expectedLootBalance);
  }

  function test_claimContractSignerInvalidClaimFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });
    
    

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    bytes32 r = bytes32(uint256(uint160(address(contractAccount))));
    bytes32 s = shaman.getDigest(commitment);
    uint8 v = 0;

    signature = abi.encode(r, s, v);

    contractAccount.authorizeDigest(digest);

    vm.expectRevert(InvalidClaim.selector);
    shaman.claim(commitment, signature);
  }

  function test_claimAfterExpirationFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    signature = signFromUser(nonWearerPrivateKey, digest);
    vm.warp(commitment.expirationTime + 1);

    vm.expectRevert(Expired.selector);
    shaman.claim(commitment, signature);
  }

  function test_clearExpired() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0),
                   expirationTime : uint256(3650 days + block.timestamp)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    signature = signFromUser(nonWearerPrivateKey, digest);
    vm.warp(commitment.expirationTime + 1);

    shaman.clearExpired(commitment);
    SponsorshipStatus status = shaman.commitments(commitmentHash);
    assertEq(uint256(status), uint256(SponsorshipStatus.Failed));
  }

  function test_clearExpiredInvalidClearFailOne() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
               expirationTime : uint256(3650 days + block.timestamp),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    signature = signFromUser(nonWearerPrivateKey, digest);
    vm.warp(commitment.expirationTime - 1);
    SponsorshipStatus status = shaman.commitments(commitmentHash);

    vm.expectRevert(abi.encodeWithSelector(InvalidClear.selector, status, commitment.expirationTime));
    shaman.clearExpired(commitment);
  }

  function test_clearExpiredInvalidClearFailTwo() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
              expirationTime : uint256(3650 days + block.timestamp),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus status = shaman.commitments(commitmentHash);

    vm.expectRevert(abi.encodeWithSelector(InvalidClear.selector, status, commitment.expirationTime));
    shaman.clearExpired(commitment);
  }

  function test_clearExpiredEmptyFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
              expirationTime : uint256(3650 days + block.timestamp),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0)
    });

    vm.expectRevert(abi.encodeWithSelector(InvalidClear.selector, uint256(0), commitment.expirationTime));
    shaman.clearExpired(commitment);
  }

  function test_claimedClearFail() public {
    uint256 _claimDelay = shaman.claimDelay();
    uint256 _timeFactor = block.timestamp + 1 days + _claimDelay;

    Commitment memory commitment = Commitment({
      eligibleHat: uint256(0),
      shares: uint256(1000 ether),
        loot: uint256(1000 ether),
          extraRewardAmount: uint256(0),
            timeFactor: _timeFactor,
             sponsoredTime: uint256(0),
                expirationTime : uint256(3650 days + block.timestamp),
                contextURL: "theSlug",
                 recipient: nonWearer,
                  extraRewardToken: address(0)
    });

    bytes32 digest = shaman.getDigest(commitment);

    bytes memory signature = signFromUser(sponsorHatWearerPrivateKey, digest);
    shaman.sponsor(commitment, signature);

    // This line below is very important; because the original commitment is modified during contract execution
    // The contract stores the current block timestamp in the commitment's sponsored time attribute
    // Since the commitment is enforced by hash; and requires signing it's really important to update the commitment
    commitment.sponsoredTime = block.timestamp;

    bytes32 commitmentHash = shaman.getCommitmentHash(commitment);
    SponsorshipStatus actual = shaman.commitments(commitmentHash);
    SponsorshipStatus expected = SponsorshipStatus.Pending;
    assertEq(uint256(actual), uint256(expected));

    digest = shaman.getDigest(commitment);
    signature = signFromUser(processorHatWearerPrivateKey, digest);

    vm.warp(block.timestamp + 1 hours + _claimDelay);

    shaman.process(commitment, signature);
    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Approved;
    assertEq(uint256(actual), uint256(expected));

    signature = signFromUser(nonWearerPrivateKey, digest);
    shaman.claim(commitment, signature);

    actual = shaman.commitments(commitmentHash);
    expected = SponsorshipStatus.Claimed;
    assertEq(uint256(actual), uint256(expected));

    uint256 expectedShareBalance = commitment.shares;
    uint256 expectedLootBalance = commitment.loot;

    assertEq(sharesToken.balanceOf(nonWearer), expectedShareBalance);
    assertEq(lootToken.balanceOf(nonWearer), expectedLootBalance);

    SponsorshipStatus status = shaman.commitments(commitmentHash);

    vm.expectRevert(abi.encodeWithSelector(InvalidClear.selector, status, commitment.expirationTime));
    shaman.clearExpired(commitment);
  }
}