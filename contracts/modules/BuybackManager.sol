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

        // Use simulation to check expected alpha amount and slippage
        uint256 expectedAlpha = ALPHA_PRECOMPILE.simSwapTaoForAlpha(TENEX_NETUID, uint64(buybackAmount.weiToRao()));
        if (expectedAlpha == 0) revert TenexiumErrors.BuybackSimInvalid();

        // Execute buyback by staking TAO to get Tenexium alpha
        uint256 slippage = 100;
        uint256 actualAlphaReceived = 0;
        while (slippage <= 1000) {
            uint256 minAcceptableAlpha = expectedAlpha.safeMul(10000 - slippage) / 10000;
            uint256 limitPrice = buybackAmount / minAcceptableAlpha;
            actualAlphaReceived =
                _stakeTaoForAlpha(protocolValidatorHotkey, buybackAmount, limitPrice, false, TENEX_NETUID);
            if (actualAlphaReceived > 0) break;
            slippage += 100;
        }

        if (actualAlphaReceived == 0) revert TenexiumErrors.StakeFailed();

        // Calculate actual slippage for reporting
        uint256 actualSlippage =
            expectedAlpha > actualAlphaReceived ? ((expectedAlpha - actualAlphaReceived) * 10000) / expectedAlpha : 0;

        // Burn 100% of received alpha tokens for avoiding selling pressure
        _burnAlpha(protocolValidatorHotkey, actualAlphaReceived, TENEX_NETUID);

        // Update accounting
        buybackPool -= buybackAmount;
        totalTaoUsedForBuybacks += buybackAmount;
        totalAlphaBought += actualAlphaReceived;
        lastBuybackBlock = block.number;

        emit BuybackExecuted(buybackAmount, actualAlphaReceived, block.number, actualSlippage);
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
