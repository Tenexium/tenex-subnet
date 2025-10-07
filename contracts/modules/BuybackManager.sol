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

        // Market-responsive sizing
        uint256 targetFraction = buybackRate;

        // Time ramp: linearly increase fraction up to 100% over 7 intervals without execution
        uint256 intervalsSince = (block.number - lastBuybackBlock) / buybackIntervalBlocks;
        if (intervalsSince > 0) {
            uint256 rampBoost = intervalsSince * ((10 * PRECISION) / 100); // +10% per interval
            if (rampBoost > (50 * PRECISION) / 100) rampBoost = (50 * PRECISION) / 100; // cap extra at +50%
            uint256 boosted = targetFraction + rampBoost;
            if (boosted > PRECISION) boosted = PRECISION;
            targetFraction = boosted;
        }

        uint256 buybackAmount = buybackPool.safeMul(targetFraction) / PRECISION;

        // Use simulation to check expected alpha amount and slippage
        uint256 expectedAlpha = ALPHA_PRECOMPILE.simSwapTaoForAlpha(TENEX_NETUID, uint64(buybackAmount.weiToRao()));
        if (expectedAlpha == 0) revert TenexiumErrors.BuybackSimInvalid();

        // Execute buyback by staking TAO to get Tenexium alpha
        uint256 actualAlphaReceived = _stakeTaoForAlpha(protocolValidatorHotkey, buybackAmount, TENEX_NETUID);

        // Calculate actual slippage for reporting
        uint256 actualSlippage =
            expectedAlpha > actualAlphaReceived ? ((expectedAlpha - actualAlphaReceived) * 10000) / expectedAlpha : 0;

        // Burn alpha tokens
        uint256 alphaToBurn = actualAlphaReceived.safeMul(buybackBurningRate) / PRECISION;
        _burnAlpha(protocolValidatorHotkey, alphaToBurn, TENEX_NETUID);

        // Update accounting
        buybackPool -= buybackAmount;
        totalTaoUsedForBuybacks += buybackAmount;
        totalAlphaBought += actualAlphaReceived;
        lastBuybackBlock = block.number;

        // Create vesting schedule for bought tokens (lock them)
        uint256 vestingAlpha = actualAlphaReceived - alphaToBurn;
        _createVestingScheduleForBuyback(vestingAlpha);

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
        uint256 planned = buybackPool.safeMul(buybackRate) / PRECISION;
        return address(this).balance >= planned;
    }

    // ==================== VESTING FUNCTIONS ====================

    /**
     * @notice Create vesting schedule for buyback tokens (locks them)
     * @param alphaAmount Amount of alpha tokens to vest
     */
    function _createVestingScheduleForBuyback(uint256 alphaAmount) internal {
        address beneficiary = treasury;

        VestingSchedule memory schedule = VestingSchedule({
            totalAmount: alphaAmount,
            claimedAmount: 0,
            startBlock: block.number,
            cliffBlock: block.number + cliffDurationBlocks,
            endBlock: block.number + vestingDurationBlocks,
            revoked: false
        });

        vestingSchedules[beneficiary].push(schedule);

        emit VestingScheduleCreated(beneficiary, alphaAmount, block.number, vestingDurationBlocks);
    }

    /**
     * @notice Claim vested tokens to specified SS58 address
     * @param beneficiarySs58Address SS58 address to receive the tokens
     * @return claimed Amount of tokens claimed
     */
    function _claimVestedTokens(bytes32 beneficiarySs58Address) internal returns (uint256 claimed) {
        VestingSchedule[] storage schedules = vestingSchedules[msg.sender];
        if (schedules.length == 0) revert TenexiumErrors.NoVestingSchedules();

        uint256 totalClaimable = 0;

        for (uint256 i = 0; i < schedules.length; i++) {
            VestingSchedule storage schedule = schedules[i];

            if (schedule.revoked || block.number < schedule.cliffBlock) {
                continue;
            }

            uint256 vested = _calculateVestedAmount(schedule);
            uint256 claimable = vested - schedule.claimedAmount;

            if (claimable > 0) {
                schedule.claimedAmount += claimable;
                totalClaimable += claimable;
            }
        }

        if (totalClaimable > 0) {
            _transferStake(beneficiarySs58Address, protocolValidatorHotkey, TENEX_NETUID, TENEX_NETUID, totalClaimable);
            claimed = totalClaimable;
            emit TokensClaimed(msg.sender, beneficiarySs58Address, totalClaimable);
        }

        return claimed;
    }

    /**
     * @notice Calculate vested amount for a schedule
     * @param schedule Vesting schedule
     * @return vested Amount of tokens vested
     */
    function _calculateVestedAmount(VestingSchedule memory schedule) internal view returns (uint256 vested) {
        if (block.number >= schedule.endBlock) {
            return schedule.totalAmount;
        }

        uint256 vestingBlocks = block.number - schedule.startBlock;
        uint256 totalBlocks = schedule.endBlock - schedule.startBlock;

        return schedule.totalAmount.safeMul(vestingBlocks) / totalBlocks;
    }
}
