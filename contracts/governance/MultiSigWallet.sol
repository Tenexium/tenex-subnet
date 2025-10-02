// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MultiSigWallet
 * @notice Minimal on-chain multisig wallet for controlling timelock/governance
 * @dev Owners manage transactions by submitting, confirming, and executing after threshold
 */
contract MultiSigWallet is ReentrancyGuard {
    event Deposit(address indexed sender, uint256 value);
    event Submission(uint256 indexed transactionId);
    event Confirmation(address indexed owner, uint256 indexed transactionId);
    event Revocation(address indexed owner, uint256 indexed transactionId);
    event Execution(uint256 indexed transactionId);
    event ExecutionFailure(uint256 indexed transactionId);
    event OwnerAddition(address indexed owner);
    event OwnerRemoval(address indexed owner);

    struct Transaction {
        address destination;
        uint256 value;
        bytes data;
        bool executed;
    }

    mapping(address => bool) public isOwner;
    address[] public owners;

    mapping(uint256 => Transaction) public transactions;
    uint256 public transactionCount;
    mapping(uint256 => mapping(address => bool)) public confirmations;
    // Confirmation versions so that owner set changes invalidate old confirmations
    mapping(uint256 => mapping(address => uint256)) public confirmationVersion;
    uint256 private ownerSetVersion;

    modifier onlyOwner() {
        require(isOwner[msg.sender], "MSW: not owner");
        _;
    }

    modifier txExists(uint256 transactionId) {
        require(transactionId < transactionCount, "MSW: tx !exists");
        _;
    }

    modifier notConfirmed(uint256 transactionId, address owner) {
        require(!confirmations[transactionId][owner], "MSW: confirmed");
        _;
    }

    modifier notExecuted(uint256 transactionId) {
        require(!transactions[transactionId].executed, "MSW: executed");
        _;
    }

    constructor(address[] memory _owners) {
        require(_owners.length > 0, "MSW: owners=0");
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "MSW: owner=0");
            require(!isOwner[owner], "MSW: owner dup");
            isOwner[owner] = true;
            owners.push(owner);
            emit OwnerAddition(owner);
        }
        ownerSetVersion = 1;
    }

    receive() external payable {
        if (msg.value > 0) emit Deposit(msg.sender, msg.value);
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "MSW: only self");
        _;
    }

    function addOwner(address owner) external onlySelf {
        require(owner != address(0), "MSW: owner=0");
        require(!isOwner[owner], "MSW: exists");
        owners.push(owner);
        isOwner[owner] = true;
        emit OwnerAddition(owner);
        ownerSetVersion += 1;
    }

    function removeOwner(address owner) external onlySelf {
        require(isOwner[owner], "MSW: !owner");
        require(owners.length > 1, "MSW: last owner");
        isOwner[owner] = false;
        // remove from array
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        emit OwnerRemoval(owner);
        ownerSetVersion += 1;
    }

    function submitTransaction(address destination, uint256 value, bytes calldata data)
        external
        onlyOwner
        returns (uint256 transactionId)
    {
        require(destination != address(0), "MSW: dest=0");
        transactionId = _addTransaction(destination, value, data);
        emit Submission(transactionId);
        confirmTransaction(transactionId);
    }

    function confirmTransaction(uint256 transactionId)
        public
        onlyOwner
        txExists(transactionId)
        notConfirmed(transactionId, msg.sender)
    {
        confirmations[transactionId][msg.sender] = true;
        confirmationVersion[transactionId][msg.sender] = ownerSetVersion;
        emit Confirmation(msg.sender, transactionId);
    }

    function revokeConfirmation(uint256 transactionId)
        external
        onlyOwner
        txExists(transactionId)
        notExecuted(transactionId)
    {
        require(confirmations[transactionId][msg.sender], "MSW: !conf");
        confirmations[transactionId][msg.sender] = false;
        confirmationVersion[transactionId][msg.sender] = 0;
        emit Revocation(msg.sender, transactionId);
    }

    function executeTransaction(uint256 transactionId)
        external
        nonReentrant
        onlyOwner
        txExists(transactionId)
        notExecuted(transactionId)
    {
        Transaction storage txn = transactions[transactionId];
        require(_getConfirmationCount(transactionId) >= _getThreshold(), "MSW: low conf");
        txn.executed = true;
        (bool success,) = txn.destination.call{value: txn.value}(txn.data);
        if (success) {
            emit Execution(transactionId);
        } else {
            txn.executed = false;
            emit ExecutionFailure(transactionId);
        }
    }

    function _addTransaction(address destination, uint256 value, bytes calldata data)
        internal
        returns (uint256 transactionId)
    {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({destination: destination, value: value, data: data, executed: false});
        transactionCount += 1;
    }

    // Views
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getTransaction(uint256 transactionId) external view returns (Transaction memory) {
        return transactions[transactionId];
    }

    function isConfirmed(uint256 transactionId, address owner) external view returns (bool) {
        return confirmations[transactionId][owner];
    }

    // Dynamic threshold and confirmation counts
    function getThreshold() external view returns (uint256) {
        return _getThreshold();
    }

    function getConfirmationCount(uint256 transactionId) external view returns (uint256) {
        return _getConfirmationCount(transactionId);
    }

    function _getThreshold() internal view returns (uint256) {
        uint256 ownerCount = owners.length;
        // more than half => floor(n/2) + 1
        return ownerCount / 2 + 1;
    }

    function _getConfirmationCount(uint256 transactionId) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < owners.length; i++) {
            if (
                confirmations[transactionId][owners[i]]
                    && confirmationVersion[transactionId][owners[i]] == ownerSetVersion
            ) {
                count += 1;
            }
        }
        return count;
    }

    function getOwnerSetVersion() external view returns (uint256) {
        return ownerSetVersion;
    }
}
