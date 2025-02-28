// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/MultiSigWallet.sol";

contract MultiSigWalletTest is Test {
    MultiSigWallet public wallet;
    address[] public owners;
    uint256 public required = 2;
    
    address public owner1;
    address public owner2;
    address public owner3;
    address public nonOwner = address(0x4);
    
    uint256 private constant OWNER1_PRIVATE_KEY = 0x1;
    uint256 private constant OWNER2_PRIVATE_KEY = 0x2;
    uint256 private constant OWNER3_PRIVATE_KEY = 0x3;
    uint256 private constant NON_OWNER_PRIVATE_KEY = 0x999;
    
    event TransactionSubmitted(
        uint256 indexed txIndex,
        address indexed owner,
        address to,
        uint256 value,
        bytes data,
        string description,
        uint256 nonce
    );
    event TransactionApproved(uint256 indexed txIndex, address indexed owner);
    event TransactionExecuted(uint256 indexed txIndex, address indexed owner);
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event RequirementChanged(uint256 required);
    
    function setUp() public {
        owner1 = vm.addr(OWNER1_PRIVATE_KEY);
        owner2 = vm.addr(OWNER2_PRIVATE_KEY);
        owner3 = vm.addr(OWNER3_PRIVATE_KEY);
        
        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);
        
        wallet = new MultiSigWallet(owners, required);
        
        vm.deal(address(wallet), 10 ether);
    }
    
    function testInitialState() public view {
        assertEq(wallet.getOwners().length, 3);
        assertEq(wallet.getOwners()[0], owner1);
        assertEq(wallet.getOwners()[1], owner2);
        assertEq(wallet.getOwners()[2], owner3);
        assertEq(wallet.required(), 2);
        assertEq(wallet.getTransactionCount(), 0);
        assertEq(address(wallet).balance, 10 ether);
    }
    
    function _signTransaction(
        address to,
        uint256 value,
        bytes memory data,
        string memory description,
        uint256 nonce,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Transaction(address to,uint256 value,bytes data,string description,uint256 nonce)"),
                to,
                value,
                keccak256(data),
                keccak256(bytes(description)),
                nonce
            )
        );
        
        bytes32 digest = wallet.getMessageHash(structHash);
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        
        return abi.encodePacked(r, s, v);
    }
    
    function testSubmitTransaction() public {
        address to = address(0x5);
        uint256 value = 1 ether;
        bytes memory data = "";
        string memory description = "Test transaction";
        uint256 nonce = 0;
        
        bytes memory signature = _signTransaction(to, value, data, description, nonce, OWNER1_PRIVATE_KEY);
        
        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(0, owner1, to, value, data, description, nonce);
        
        uint256 txIndex = wallet.submitTransaction(to, value, data, description, nonce, signature);
        
        assertEq(txIndex, 0);
        assertEq(wallet.getTransactionCount(), 1);
        
        (
            address txTo,
            uint256 txValue,
            bytes memory txData,
            string memory txDescription,
            bool executed,
            uint256 approvalCount
        ) = wallet.getTransaction(0);
        
        assertEq(txTo, to);
        assertEq(txValue, value);
        assertEq(keccak256(txData), keccak256(data));
        assertEq(keccak256(bytes(txDescription)), keccak256(bytes(description)));
        assertEq(executed, false);
        assertEq(approvalCount, 1);
        
        assertTrue(wallet.isApproved(0, owner1));
    }
    
    function testApproveAndExecuteTransaction() public {
        address to = address(0x5);
        uint256 value = 1 ether;
        bytes memory data = "";
        string memory description = "Test transaction";
        uint256 nonce = 0;
        
        bytes memory signature = _signTransaction(to, value, data, description, nonce, OWNER1_PRIVATE_KEY);
        
        uint256 txIndex = wallet.submitTransaction(to, value, data, description, nonce, signature);
        
        vm.prank(owner2);
        vm.expectEmit(true, true, false, true);
        emit TransactionApproved(txIndex, owner2);
        wallet.approveTransaction(txIndex);
        
        assertTrue(wallet.isApproved(txIndex, owner2));
        
        uint256 initialBalance = address(to).balance;
        
        vm.prank(owner3);
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txIndex, owner3);
        wallet.executeTransaction(txIndex);
        
        (,,,, bool executed,) = wallet.getTransaction(txIndex);
        assertTrue(executed);
        
        assertEq(address(to).balance, initialBalance + value);
    }
    
    function test_RevertWhen_ExecutingWithoutEnoughApprovals() public {
        address to = address(0x5);
        uint256 value = 1 ether;
        bytes memory data = "";
        string memory description = "Test transaction";
        uint256 nonce = 0;
        
        bytes memory signature = _signTransaction(to, value, data, description, nonce, OWNER1_PRIVATE_KEY);
        
        uint256 txIndex = wallet.submitTransaction(to, value, data, description, nonce, signature);
        
        vm.prank(owner2);
        vm.expectRevert("Not enough approvals");
        wallet.executeTransaction(txIndex);
    }
    
    function testAddOwner() public {
        address newOwner = address(0x6);
        
        vm.expectEmit(true, false, false, true);
        emit OwnerAdded(newOwner);
        wallet.addOwner(newOwner);
        
        assertTrue(wallet.isOwner(newOwner));
        assertEq(wallet.getOwners().length, 4);
    }
    
    function testRemoveOwner() public {
        vm.expectEmit(true, false, false, true);
        emit OwnerRemoved(owner3);
        wallet.removeOwner(owner3);
        
        assertFalse(wallet.isOwner(owner3));
        assertEq(wallet.getOwners().length, 2);
    }
    
    function testChangeRequirement() public {
        vm.expectEmit(true, false, false, true);
        emit RequirementChanged(3);
        wallet.changeRequirement(3);
        
        assertEq(wallet.required(), 3);
    }
    
    function test_RevertWhen_ChangingRequirementTooHigh() public {
        vm.expectRevert("Invalid required number");
        wallet.changeRequirement(4);
    }
    
    function test_RevertWhen_ChangingRequirementToZero() public {
        vm.expectRevert("Invalid required number");
        wallet.changeRequirement(0);
    }
    
    function testReuseSignature() public {
        address to = address(0x5);
        uint256 value = 1 ether;
        bytes memory data = "";
        string memory description = "Test transaction";
        uint256 nonce = 0;
        
        bytes memory signature = _signTransaction(to, value, data, description, nonce, OWNER1_PRIVATE_KEY);
        
        wallet.submitTransaction(to, value, data, description, nonce, signature);
        
        vm.expectRevert("Signature already used");
        wallet.submitTransaction(to, value, data, "Another transaction", nonce, signature);
    }
    
    function test_RevertWhen_NonOwnerApprovesTransaction() public {
        address to = address(0x5);
        uint256 value = 1 ether;
        bytes memory data = "";
        string memory description = "Test transaction";
        uint256 nonce = 0;
        
        bytes memory signature = _signTransaction(to, value, data, description, nonce, OWNER1_PRIVATE_KEY);
        
        uint256 txIndex = wallet.submitTransaction(to, value, data, description, nonce, signature);
        
        vm.prank(nonOwner);
        vm.expectRevert("Not an owner");
        wallet.approveTransaction(txIndex);
    }
    
    function testMultipleSignaturesForDifferentTransactions() public {
        address to1 = address(0x5);
        uint256 value1 = 1 ether;
        bytes memory data1 = "";
        string memory description1 = "First transaction";
        uint256 nonce1 = 0;
        
        address to2 = address(0x6);
        uint256 value2 = 2 ether;
        bytes memory data2 = "";
        string memory description2 = "Second transaction";
        uint256 nonce2 = 1;
        
        bytes memory signature1 = _signTransaction(to1, value1, data1, description1, nonce1, OWNER1_PRIVATE_KEY);
        bytes memory signature2 = _signTransaction(to2, value2, data2, description2, nonce2, OWNER1_PRIVATE_KEY);
        
        wallet.submitTransaction(to1, value1, data1, description1, nonce1, signature1);
        wallet.submitTransaction(to2, value2, data2, description2, nonce2, signature2);
        
        assertEq(wallet.getTransactionCount(), 2);
    }
    
    function testReceiveEther() public {
        vm.deal(address(this), 5 ether);
        (bool success,) = address(wallet).call{value: 5 ether}("");
        
        assertTrue(success);
        assertEq(address(wallet).balance, 15 ether); // 10 ETH initial + 5 ETH sent
    }
    
    function test_RevertWhen_ApprovingAlreadyExecutedTransaction() public {
        address to = address(0x5);
        uint256 value = 1 ether;
        bytes memory data = "";
        string memory description = "Test transaction";
        uint256 nonce = 0;
        
        bytes memory signature = _signTransaction(to, value, data, description, nonce, OWNER1_PRIVATE_KEY);
        
        uint256 txIndex = wallet.submitTransaction(to, value, data, description, nonce, signature);
        
        vm.prank(owner2);
        wallet.approveTransaction(txIndex);
        
        vm.prank(owner3);
        wallet.executeTransaction(txIndex);
        
        vm.prank(owner3);
        vm.expectRevert("Transaction already executed");
        wallet.approveTransaction(txIndex);
    }
    
    function test_RevertWhen_SubmittingWithInvalidSigner() public {
        address to = address(0x5);
        uint256 value = 1 ether;
        bytes memory data = "";
        string memory description = "Test transaction";
        uint256 nonce = 0;
        
        bytes memory signature = _signTransaction(to, value, data, description, nonce, NON_OWNER_PRIVATE_KEY);
        
        vm.expectRevert("Signer is not an owner");
        wallet.submitTransaction(to, value, data, description, nonce, signature);
    }
}