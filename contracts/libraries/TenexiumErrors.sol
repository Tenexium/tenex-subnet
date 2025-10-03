// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library TenexiumErrors {
    // Generic / governance
    error InvalidValue();
    error FunctionNotFound(bytes4 selector);
    error DirectTaoTransferProhibited(address sender, uint256 taoWeiAmount);

    // Pairs / params
    error PairExists(uint16 netuid);
    error PairMissing(uint16 netuid);
    error LeverageTooHigh(uint256 leverageScaled);
    error FeeTooHigh(uint256 rateScaled);
    error DistributionInvalid();
    error ThresholdTooLow(uint256 thresholdScaled);
    error UserCooldownTooLarge(uint256 blocks);
    error LpCooldownTooLarge(uint256 blocks);

    // Liquidity / LP
    error NotLiquidityProvider();
    error NoFees();
    error LpMinDeposit();
    error InvalidWithdrawalAmount();
    error UtilizationExceeded(uint256 utilizationScaled);
    error InsufficientContractBalance(uint256 haveWei, uint256 needWei);
    error UserCooldownActive(uint256 remainingBlocks);
    error LpCooldownActive(uint256 remainingBlocks);

    // Positions
    error SlippageTooHigh();
    error MinDeposit();
    error PositionExists();
    error InsufficientLiquidity();
    error SwapSimInvalid();
    error UnstakeSimInvalid();
    error UnstakeSlippage();
    error InsufficientProceeds();

    // Transfer / TransferStake / MoveStake / Stake / Unstake
    error TransferFailed();
    error TransferStakeFailed();
    error MoveStakeFailed();
    error StakeFailed();
    error UnstakeFailed();

    // Liquidation
    error PositionInactive();
    error NoAlpha();
    error NotLiquidatable();
    error InvalidAlphaPrice();
    error LiquiFeeTransferFailed();
    error CollateralReturnFailed();
    error ArrayLengthMismatch();
    error PositionNotFound(address user, uint256 positionId);

    // Rewards
    error NoRewards();

    // Buyback / vesting
    error BuybackSimInvalid(uint256 taoWeiAmount);
    error AmountZero();
    error DurationTooShort(uint256 blocks);
    error CliffTooLong(uint256 blocks);
    error NoVestingSchedules();
    error PercentageTooHigh(uint256 rateScaled);
    error IntervalTooShort(uint256 blocks);
    error BuybackConditionsNotMet();

    // Permission controls
    error FunctionNotPermitted(uint256 permissionIndex);

    // Liquidity provider tracking
    error AddressAlreadyAssociated();
    error MaxLiquidityProvidersPerHotkeyReached();

    // Manager
    error NotManager();
}
