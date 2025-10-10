// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../core/TenexiumStorage.sol";
import "../core/TenexiumEvents.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/TenexiumErrors.sol";
import "./PrecompileAdapter.sol";

/**
 * @title BuybackManager
 * @notice Functions for automated buybacks of Tenexium subnet token with vesting
 * @dev Uses protocol fees to create buy pressure and locks purchased tokens
 */
abstract contract BuybackManager is TenexiumStorage, TenexiumEvents, PrecompileAdapter {
    using AlphaMath for uint256;

    // ==================== BUYBACK FUNCTIONS ====================

    /**
     * @notice Execute automated buyback using accumulated protocol fees
     * @dev Can be called by anyone to trigger buyback (decentralized execution)
     */
    function _executeBuyback() internal {
        if (!_canExecuteBuyback()) revert TenexiumErrors.BuybackConditionsNotMet();

        uint256 buybackAmount = buybackPool;

        // Burn 100% of received alpha tokens for avoiding selling pressure
        uint256 actualAlphaBurned = _burnAlpha(buybackAmount, TENEX_NETUID);

        // Update accounting
        buybackPool -= buybackAmount;
        totalTaoUsedForBuybacks += buybackAmount;
        totalAlphaBought += actualAlphaBurned;
        lastBuybackBlock = block.number;

        emit BuybackExecuted(buybackAmount, actualAlphaBurned, block.number);
    }

    /**
     * @notice Check if buyback can be executed
     * @return canExecute Whether buyback conditions are met
     */
    function _canExecuteBuyback() internal view returns (bool canExecute) {
        if (block.number < lastBuybackBlock + buybackIntervalBlocks) return false;
        // Enforce minimum pool threshold before executing to avoid dust buybacks
        if (buybackPool < buybackExecutionThreshold) return false;
        uint256 availableBalance = address(this).balance.safeAdd(totalBorrowed).safeSub(totalLpStakes).safeSub(
            totalPendingLpFees
        ).safeSub(protocolFees);
        return availableBalance >= buybackPool;
    }
}
