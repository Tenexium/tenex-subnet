// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

        uint256 buybackAmountRao = buybackPool.weiToRao();
        uint256 buybackAmount = buybackAmountRao.raoToWei();

        // Buyback Alpha tokens
        uint256 expectedAlpha = ALPHA_PRECOMPILE.simSwapTaoForAlpha(TENEX_NETUID, uint64(buybackAmountRao));
        if (expectedAlpha == 0) revert TenexiumErrors.SwapSimInvalid();

        expectedAlpha = expectedAlpha.safeMul(9500) / 10000; // 5% slippage buffer
        uint256 limitPrice = buybackAmount / expectedAlpha;
        uint256 actualAlphaBought =
            _stakeTaoForAlpha(protocolValidatorHotkey, buybackAmount, limitPrice, true, TENEX_NETUID);
        if (actualAlphaBought == 0) revert TenexiumErrors.AmountZero();

        // Update accounting
        buybackPool -= buybackAmount;
        totalTaoUsedForBuybacks += buybackAmount;
        totalAlphaBought += actualAlphaBought;
        lastBuybackBlock = block.number;

        emit BuybackExecuted(buybackAmount, actualAlphaBought, block.number);
    }

    function _burnBuybackedAlpha() internal {
        // Burn Alpha tokens that were bought back
        uint256 availableBurnedAlpha = STAKING_PRECOMPILE.getStake(
            protocolValidatorHotkey, addressConversionContract.addressToSS58Pub(address(this)), TENEX_NETUID
        );
        if (availableBurnedAlpha == 0) revert TenexiumErrors.AmountZero();
        _burnAlpha(protocolValidatorHotkey, availableBurnedAlpha, TENEX_NETUID);
    }

    /**
     * @notice Check if buyback can be executed
     * @return canExecute Whether buyback conditions are met
     */
    function _canExecuteBuyback() internal view returns (bool canExecute) {
        if (block.number < lastBuybackBlock + buybackIntervalBlocks) return false;
        // Enforce minimum pool threshold before executing to avoid dust buybacks
        if (buybackPool < buybackExecutionThreshold) return false;
        uint256 availableBalance = address(this).balance.safeAdd(totalBorrowed).safeSub(totalLpStakes)
            .safeSub(totalPendingLpFees).safeSub(protocolFees);
        return availableBalance >= buybackPool;
    }
}
