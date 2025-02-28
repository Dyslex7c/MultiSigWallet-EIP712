// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MultiSigWallet
 * @dev A multi-signature wallet with EIP-712 typed signature support
 */
contract MultiSigWallet is EIP712, Ownable {
    using ECDSA for bytes32;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        string description;
        uint256 nonce;
        bool executed;
        uint256 approvalCount;
        mapping(address => bool) approvals;
    }

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

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public required;

    Transaction[] public transactions;
    mapping(bytes32 => bool) public usedSignatures;

    bytes32 private constant TRANSACTION_TYPEHASH = keccak256(
        "Transaction(address to,uint256 value,bytes data,string description,uint256 nonce)"
    );

    string private constant SIGNING_DOMAIN = "MultiSig-Wallet";
    string private constant SIGNATURE_VERSION = "1";

    /**
     * @dev Constructor
     * @param _owners Array of owner addresses
     * @param _required Number of required approvals
     */
    constructor(address[] memory _owners, uint256 _required) 
        EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) 
        Ownable(msg.sender)
    {
        require(_owners.length > 0, "Owners required");
        require(_required > 0 && _required <= _owners.length, "Invalid required number of owners");

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner already added");

            isOwner[owner] = true;
            owners.push(owner);
        }

        required = _required;
    }

    /**
     * @dev Fallback function allows to deposit ether.
     */
    receive() external payable {}

    /**
     * @dev Get the count of transactions
     * @return Count of transactions
     */
    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }

    /**
     * @dev Get transaction details
     * @param _txIndex Transaction index
     * @return to Recipient address
     * @return value Transaction value
     * @return data Transaction data
     * @return description Transaction description
     * @return executed Execution status
     * @return approvalCount Number of approvals
     */
    function getTransaction(uint256 _txIndex)
        public
        view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            string memory description,
            bool executed,
            uint256 approvalCount
        )
    {
        require(_txIndex < transactions.length, "Transaction does not exist");
        Transaction storage transaction = transactions[_txIndex];

        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.description,
            transaction.executed,
            transaction.approvalCount
        );
    }

    /**
     * @dev Check if an owner has approved a transaction
     * @param _txIndex Transaction index
     * @param _owner Owner address
     * @return Approval status
     */
    function isApproved(uint256 _txIndex, address _owner) public view returns (bool) {
        require(_txIndex < transactions.length, "Transaction does not exist");
        return transactions[_txIndex].approvals[_owner];
    }

    /**
     * @dev Get the list of owners
     * @return Array of owner addresses
     */
    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    /**
     * @dev Hash a transaction according to EIP-712
     * @param _tx Transaction to hash
     * @return Hash of the transaction
     */
    function hashTransaction(Transaction storage _tx) private view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    TRANSACTION_TYPEHASH,
                    _tx.to,
                    _tx.value,
                    keccak256(_tx.data),
                    keccak256(bytes(_tx.description)),
                    _tx.nonce
                )
            )
        );
    }

    /**
     * @dev Get message hash for a struct hash (for testing)
     * @param _structHash The hash of the struct to sign
     * @return The final message hash
     */
    function getMessageHash(bytes32 _structHash) public view returns (bytes32) {
        return _hashTypedDataV4(_structHash);
    }

    /**
     * @dev Recover signer from signature
     * @param _txHash Transaction hash
     * @param _signature Signature
     * @return Signer address
     */
    function recoverSigner(bytes32 _txHash, bytes memory _signature) public pure returns (address) {
        return ECDSA.recover(_txHash, _signature);
    }

    /**
     * @dev Submit a transaction with EIP-712 signature
     * @param _to Recipient address
     * @param _value Transaction value
     * @param _data Transaction data
     * @param _description Transaction description
     * @param _nonce Transaction nonce
     * @param _signature EIP-712 signature
     * @return Transaction index
     */
    function submitTransaction(
        address _to,
        uint256 _value,
        bytes memory _data,
        string memory _description,
        uint256 _nonce,
        bytes memory _signature
    ) public returns (uint256) {
        require(_to != address(0), "Invalid recipient");
        
        uint256 txIndex = transactions.length;
        transactions.push();
        Transaction storage transaction = transactions[txIndex];
        transaction.to = _to;
        transaction.value = _value;
        transaction.data = _data;
        transaction.description = _description;
        transaction.nonce = _nonce;
        transaction.executed = false;
        transaction.approvalCount = 0;

        bytes32 txHash = hashTransaction(transaction);
        
        require(!usedSignatures[keccak256(_signature)], "Signature already used");
        usedSignatures[keccak256(_signature)] = true;
        
        address signer = recoverSigner(txHash, _signature);
        require(isOwner[signer], "Signer is not an owner");
        
        _approveTransaction(txIndex, signer);
        
        emit TransactionSubmitted(
            txIndex,
            signer,
            _to,
            _value,
            _data,
            _description,
            _nonce
        );
        
        return txIndex;
    }

    /**
     * @dev Approve a transaction
     * @param _txIndex Transaction index
     */
    function approveTransaction(uint256 _txIndex) public {
        require(isOwner[msg.sender], "Not an owner");
        require(_txIndex < transactions.length, "Transaction does not exist");
        require(!transactions[_txIndex].executed, "Transaction already executed");
        require(!transactions[_txIndex].approvals[msg.sender], "Transaction already approved");

        _approveTransaction(_txIndex, msg.sender);
    }

    /**
     * @dev Internal function to approve a transaction
     * @param _txIndex Transaction index
     * @param _owner Owner address
     */
    function _approveTransaction(uint256 _txIndex, address _owner) private {
        Transaction storage transaction = transactions[_txIndex];
        transaction.approvals[_owner] = true;
        transaction.approvalCount++;

        emit TransactionApproved(_txIndex, _owner);
    }

    /**
     * @dev Execute a transaction
     * @param _txIndex Transaction index
     */
    function executeTransaction(uint256 _txIndex) public {
        require(isOwner[msg.sender], "Not an owner");
        require(_txIndex < transactions.length, "Transaction does not exist");
        
        Transaction storage transaction = transactions[_txIndex];
        
        require(!transaction.executed, "Transaction already executed");
        require(transaction.approvalCount >= required, "Not enough approvals");

        transaction.executed = true;

        (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "Transaction execution failed");

        emit TransactionExecuted(_txIndex, msg.sender);
    }

    /**
     * @dev Add a new owner
     * @param _owner New owner address
     */
    function addOwner(address _owner) public onlyOwner {
        require(_owner != address(0), "Invalid owner");
        require(!isOwner[_owner], "Owner already exists");

        isOwner[_owner] = true;
        owners.push(_owner);

        emit OwnerAdded(_owner);
    }

    /**
     * @dev Remove an owner
     * @param _owner Owner address to remove
     */
    function removeOwner(address _owner) public onlyOwner {
        require(isOwner[_owner], "Not an owner");
        require(owners.length - 1 >= required, "Cannot remove owner, minimum required would not be met");

        isOwner[_owner] = false;
        
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }

        emit OwnerRemoved(_owner);
    }

    /**
     * @dev Change required number of approvals
     * @param _required New required number
     */
    function changeRequirement(uint256 _required) public onlyOwner {
        require(_required > 0 && _required <= owners.length, "Invalid required number");
        required = _required;
        
        emit RequirementChanged(_required);
    }
}