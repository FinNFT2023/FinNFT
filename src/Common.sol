// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

struct MintNodeNftParams {
    string nodeId;
    string uri;
    uint256 size;
    uint256 nonce;
    bytes32 hash;
    bytes signature;
}

struct MintUserNft {
    string uri;
    uint256 deadline;
    string[] nodeids;
    uint256[] sizes;
    uint256 proportion;
    address useraddr;
    uint256 nonce;
    bytes32 hash;
    bytes signature;
}

struct BurnParams {
    string nodeId;
    uint256 nonce;
    bytes32 hash;
    bytes signature;
}

struct WithdrawParams {
    uint256 tokenId;
    uint256 amount;
    uint256 nonce;
    bytes32 hash;
    bytes signature;
}

