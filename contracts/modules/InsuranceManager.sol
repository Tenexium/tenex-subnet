// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title InsuranceManager
 * @notice Immutable insurance contract that can receive TAO directly and fund the Tenexium protocol
 * @dev This contract serves as an insurance fund for the Tenexium protocol
 */
contract InsuranceManager is ReentrancyGuard {
    // ==================== STATE VARIABLES ====================

    /// @notice Address of the Tenexium protocol contract
    address public immutable tenexiumProtocol;

    /// @notice Total TAO received by this contract
    uint256 public totalReceived;

    /// @notice Total TAO sent to Tenexium protocol
    uint256 public totalFunded;

    // ==================== EVENTS ====================

    /// @notice Emitted when TAO is received by the contract
    event TaoReceived(address indexed sender, uint256 amount, uint256 newBalance);

    /// @notice Emitted when TAO is funded to Tenexium protocol
    event TaoFunded(address indexed caller, uint256 amount, uint256 newBalance);

    // ==================== ERRORS ====================

    error OnlyTenexiumProtocol();
    error InsufficientBalance();
    error TransferFailed();
    error InvalidAmount();
    error InvalidTenexiumProtocol();

    // ==================== CONSTRUCTOR ====================

    /**
     * @notice Initialize the InsuranceManager contract
     * @param _tenexiumProtocol Address of the Tenexium protocol contract
     */
    constructor(address _tenexiumProtocol) {
        if (_tenexiumProtocol == address(0)) revert InvalidTenexiumProtocol();
        tenexiumProtocol = _tenexiumProtocol;
    }

    // ==================== RECEIVE FUNCTION ====================

    /**
     * @notice Receive TAO directly from any address
     * @dev This function allows the contract to receive TAO transfers
     */
    receive() external payable {
        if (msg.value == 0) revert InvalidAmount();

        totalReceived += msg.value;

        emit TaoReceived(msg.sender, msg.value, address(this).balance);
    }

    // ==================== FUNDING FUNCTION ====================

    /**
     * @notice Fund the Tenexium protocol with specified amount
     * @dev Only the Tenexium protocol contract can call this function
     * @param amount Amount of TAO to send to Tenexium protocol
     */
    function fund(uint256 amount) external nonReentrant {
        if (msg.sender != tenexiumProtocol) revert OnlyTenexiumProtocol();
        if (amount == 0) revert InvalidAmount();
        if (address(this).balance < amount) revert InsufficientBalance();

        totalFunded += amount;

        // Call the receiveInsuranceFund function on Tenexium protocol
        (bool success,) = tenexiumProtocol.call{value: amount}(abi.encodeWithSignature("receiveInsuranceFund()"));

        if (!success) revert TransferFailed();

        emit TaoFunded(msg.sender, amount, address(this).balance);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get the current balance of the contract
     * @return Current TAO balance
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Get the net balance (total received - total funded)
     * @return Net balance available for funding
     */
    function getNetBalance() external view returns (uint256) {
        return totalReceived - totalFunded;
    }
}
