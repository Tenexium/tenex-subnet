// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title AlphaMath
 * @notice Advanced mathematical operations library for the Tenexium Protocol
 * @dev Provides safe arithmetic, financial calculations, and utility functions
 */
library AlphaMath {
    using Math for uint256;

    // RAO denominations
    uint256 private constant WEI_PER_RAO = 1e9;

    // Errors
    error DivisionByZero();
    error Overflow();
    error NegativeResult();

    /**
     * @notice Safe addition with overflow protection
     */
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        if (c < a) revert Overflow();
        return c;
    }

    /**
     * @notice Safe subtraction with underflow protection
     */
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b > a) revert NegativeResult();
        return a - b;
    }

    /**
     * @notice Safe multiplication with overflow protection
     */
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        uint256 c = a * b;
        if (c / a != b) revert Overflow();
        return c;
    }

    /**
     * @notice Safe division with zero check
     */
    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return a / b;
    }

    /**
     * @notice Calculate absolute difference between two values
     * @param a First value
     * @param b Second value
     * @return Absolute difference
     */
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a - b : b - a;
    }

    /**
     * @notice Calculate minimum of two values
     * @param a First value
     * @param b Second value
     * @return Minimum value
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Calculate maximum of two values
     * @param a First value
     * @param b Second value
     * @return Maximum value
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @notice Convert wei (1e-18 TAO) to rao (1e-9 TAO)
     */
    function weiToRao(uint256 weiAmount) internal pure returns (uint256) {
        return weiAmount / WEI_PER_RAO;
    }

    /**
     * @notice Convert rao (1e-9 TAO) to wei (1e-18 TAO)
     */
    function raoToWei(uint256 raoAmount) internal pure returns (uint256) {
        return safeMul(raoAmount, WEI_PER_RAO);
    }
}
