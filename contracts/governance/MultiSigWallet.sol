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
    event RequirementChange(uint256 required);

    struct Transaction {
        address destination;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
    }

    mapping(address => bool) public isOwner;
    address[] public owners;
    uint256 public required;

    mapping(uint256 => Transaction) public transactions;
    uint256 public transactionCount;
    mapping(uint256 => mapping(address => bool)) public confirmations;

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

    constructor(address[] memory _owners, uint256 _required) {
        require(_owners.length > 0, "MSW: owners=0");
        require(_required > 0 && _required <= _owners.length, "MSW: bad required");
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "MSW: owner=0");
            require(!isOwner[owner], "MSW: owner dup");
            isOwner[owner] = true;
            owners.push(owner);
            emit OwnerAddition(owner);
        }
        required = _required;
        emit RequirementChange(_required);
    }

    receive() external payable {
        if (msg.value > 0) emit Deposit(msg.sender, msg.value);
    }

    function addOwner(address owner) external onlyOwner {
        require(owner != address(0), "MSW: owner=0");
        require(!isOwner[owner], "MSW: exists");
        owners.push(owner);
        isOwner[owner] = true;
        emit OwnerAddition(owner);
        require(required <= owners.length, "MSW: req>owners");
    }

    function removeOwner(address owner) external onlyOwner {
        require(isOwner[owner], "MSW: !owner");
        isOwner[owner] = false;
        // remove from array
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        if (required > owners.length) {
            changeRequirement(owners.length);
        }
        emit OwnerRemoval(owner);
    }

    function changeRequirement(uint256 _required) public onlyOwner {
        require(_required > 0 && _required <= owners.length, "MSW: bad required");
        required = _required;
        emit RequirementChange(_required);
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
        transactions[transactionId].confirmations += 1;
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
        transactions[transactionId].confirmations -= 1;
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
        require(txn.confirmations >= required, "MSW: low conf");
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
        transactions[transactionId] =
            Transaction({destination: destination, value: value, data: data, executed: false, confirmations: 0});
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
}
