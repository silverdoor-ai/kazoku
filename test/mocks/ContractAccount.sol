pragma solidity ^0.8.18;

contract ContractAccount {

    bytes4 constant magicValue = 0x1626ba7e;
    mapping(bytes32 digest => bool authorized) public authorizedDigests;

    constructor() {}

    function isValidSignature(bytes32 hash, bytes memory) external view returns (bytes4) {
        if (authorizedDigests[hash]) {
            return magicValue;
        } else {
            return 0xffffffff;
        }
    }

    function authorizeDigest(bytes32 digest) external {
        authorizedDigests[digest] = true;
    }

}