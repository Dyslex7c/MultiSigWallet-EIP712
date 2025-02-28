// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/MultiSigWallet.sol";

contract DeployMultiSigWallet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        address[] memory initialOwners = new address[](3);
        initialOwners[0] = vm.addr(deployerPrivateKey);
        initialOwners[1] = 0x2d6De8aC7660102bf9FFD339Fef1Caa545B15Fd5;
        initialOwners[2] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        
        uint256 requiredConfirmations = 2;
        
        MultiSigWallet multiSig = new MultiSigWallet(
            initialOwners,
            requiredConfirmations
        );
        
        vm.stopBroadcast();
        
        console.log("MultiSigWallet deployed to:", address(multiSig));
    }
}