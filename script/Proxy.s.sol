// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "../src/FilNft.sol";
import "../src/Proxy.sol";

contract ProxyScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        address sys_mgr = address(0xF2EB95407637Fad37b8f4Fe9Fcf6e39bC50c5214);
        address data_mgr = address(0x8DD84d83d2575Ca036cC4FFFcDDa6EAA83aa3dB8);
        FilNft filNft = new FilNft();
        UpgradeableBeacon upgrade = new UpgradeableBeacon(address(filNft));
        new FilNftProxy(
            address(upgrade), 
            abi.encodeWithSignature("initialize(string,string,address,address)", "fnft", "fn", sys_mgr, data_mgr)
        );
        vm.stopBroadcast();
    }
}