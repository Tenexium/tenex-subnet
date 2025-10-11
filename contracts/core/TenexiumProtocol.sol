// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./TenexiumStorage.sol";
import "./TenexiumEvents.sol";
import "../modules/LiquidityManager.sol";
import "../modules/PositionManager.sol";
import "../modules/LiquidationManager.sol";
import "../modules/FeeManager.sol";
import "../modules/BuybackManager.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/TenexiumErrors.sol";

/**
 * @title TenexiumProtocol
 * @notice Main protocol contract that orchestrates all modules for leveraged alpha trading
 * @dev This contract serves as the entry point and coordinator for all protocol operations
 */
contract TenexiumProtocol is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    TenexiumStorage,
    TenexiumEvents,
    LiquidityManager,
    PositionManager,
    LiquidationManager,
    BuybackManager
{
    using AlphaMath for uint256;

    // Protocol version
    string public constant VERSION = "1.0.0";

    /**
     * @notice Minimal constructor for UUPS proxy pattern
     */
    constructor() {
        _disableInitializers();
    }

    // ==================== INITIALIZATION ====================

    /**
     * @notice Initialize protocol parameters
     * @param _maxLeverage Global maximum leverage (scaled by PRECISION, e.g., 10 * PRECISION for 10x)
     * @param _liquidationThreshold Global liquidation threshold (e.g., 110% = 110 * PRECISION / 100)
     * @param _minLiquidityThreshold Minimum TAO liquidity in pool
     * @param _maxUtilizationRate Max utilization rate
     * @param _liquidityBufferRatio Buffer ratio for new positions
     * @param _userCooldownBlocks User action cooldown in blocks
     * @param _lpCooldownBlocks LP action cooldown in blocks
     * @param _buybackRate Fraction of pool to spend per buyback (scaled by PRECISION)
     * @param _buybackIntervalBlocks Minimum interval between buybacks, in blocks
     * @param _buybackExecutionThreshold Minimum balance required to execute a buyback
     * @param _protocolFeeGoveranceShare Protocol fee goverance share
     * @param _protocolFeeInsuranceShare Protocol fee insurance share
     * @param _lpFeeInsuranceShare LP fee insurance share
     * @param _perfFeeInsuranceShare Performance fee insurance share
     * @param _baseTradingFeeRate Base trading fee rate (scaled by PRECISION, e.g., 0.3% = 3 * PRECISION / 1000)
     * @param _baseBorrowingFeeRate Base borrowing fee rate per 360 blocks (scaled by PRECISION)
     * @param _baseLiquidationFeeRate Base liquidation fee rate (scaled by PRECISION, e.g., 2% = 2 * PRECISION / 100)
     * @param _protocolValidatorHotkey Protocol validator hotkey for staking operations
     * @param _functionPermissions [Open position, Close position, Add collateral]
     * @param _maxLiquidityProvidersPerHotkey Maximum number of liquidity providers per hotkey
     */
    function initialize(
        uint256 _maxLeverage,
        uint256 _liquidationThreshold,
        uint256 _minLiquidityThreshold,
        uint256 _maxUtilizationRate,
        uint256 _liquidityBufferRatio,
        uint256 _userCooldownBlocks,
        uint256 _lpCooldownBlocks,
        uint256 _buybackRate,
        uint256 _buybackIntervalBlocks,
        uint256 _buybackExecutionThreshold,
        uint256 _protocolFeeGoveranceShare,
        uint256 _protocolFeeInsuranceShare,
        uint256 _lpFeeInsuranceShare,
        uint256 _perfFeeInsuranceShare,
        uint256 _baseTradingFeeRate,
        uint256 _baseBorrowingFeeRate,
        uint256 _baseLiquidationFeeRate,
        bytes32 _protocolValidatorHotkey,
        bool[3] memory _functionPermissions,
        uint256 _maxLiquidityProvidersPerHotkey
    ) public initializer {
        __Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        // 1) Core leverage and liquidation threshold
        maxLeverage = _maxLeverage;
        liquidationThreshold = _liquidationThreshold;

        // 2) Liquidity guardrails
        minLiquidityThreshold = _minLiquidityThreshold;
        maxUtilizationRate = _maxUtilizationRate;
        liquidityBufferRatio = _liquidityBufferRatio;
        liquidityCircuitBreaker = false;

        // 3) Action cooldowns
        userActionCooldownBlocks = _userCooldownBlocks;
        lpActionCooldownBlocks = _lpCooldownBlocks;

        // 4) Buyback parameters
        buybackRate = _buybackRate;
        buybackIntervalBlocks = _buybackIntervalBlocks;
        buybackExecutionThreshold = _buybackExecutionThreshold;

        // 5) Protocol fee goverance share
        protocolFeeGoveranceShare = _protocolFeeGoveranceShare;

        // 6) Insurance Rates
        protocolFeeInsuranceShare = _protocolFeeInsuranceShare;
        lpFeeInsuranceShare = _lpFeeInsuranceShare;
        perfFeeInsuranceShare = _perfFeeInsuranceShare;

        // 7) Fee parameters
        tradingFeeRate = _baseTradingFeeRate;
        borrowingFeeRate = _baseBorrowingFeeRate;
        liquidationFeeRate = _baseLiquidationFeeRate;

        // 8) Protocol validator hotkey
        protocolValidatorHotkey = _protocolValidatorHotkey;

        // 9) Treasury default to owner at initialization
        treasury = owner();

        // 10) Function permissions
        functionPermissions = _functionPermissions;

        // 11) Max liquidity providers per hotkey
        maxLiquidityProvidersPerHotkey = _maxLiquidityProvidersPerHotkey;
    }

    // ==================== PROTOCOL UPDATE FUNCTIONS ====================

    /**
     * @notice Update risk parameters (owner only): liquidation threshold and max leverage
     * @param _maxLeverage New maximum leverage
     * @param _liquidationThreshold New liquidation threshold
     */
    function updateRiskParameters(uint256 _maxLeverage, uint256 _liquidationThreshold) external onlyOwner {
        if (_maxLeverage > 20 * PRECISION) revert TenexiumErrors.LeverageTooHigh();
        if (_liquidationThreshold < (105 * PRECISION) / 100) {
            revert TenexiumErrors.ThresholdTooLow();
        }

        maxLeverage = _maxLeverage;
        liquidationThreshold = _liquidationThreshold;
    }

    /**
     * @notice Update liquidity circuit breaker parameters (owner only)
     * @param _minLiquidityThreshold Minimum liquidity threshold
     * @param _maxUtilizationRate Maximum utilization rate
     * @param _liquidityBufferRatio Buffer ratio for new positions
     */
    function updateLiquidityGuardrails(
        uint256 _minLiquidityThreshold,
        uint256 _maxUtilizationRate,
        uint256 _liquidityBufferRatio
    ) external onlyOwner {
        if (_minLiquidityThreshold < 100e18) revert TenexiumErrors.ThresholdTooLow();
        if (_maxUtilizationRate > (95 * PRECISION) / 100) {
            revert TenexiumErrors.UtilizationExceeded();
        }
        if (_liquidityBufferRatio > (50 * PRECISION) / 100) revert TenexiumErrors.FeeTooHigh();

        minLiquidityThreshold = _minLiquidityThreshold;
        maxUtilizationRate = _maxUtilizationRate;
        liquidityBufferRatio = _liquidityBufferRatio;

        _updateLiquidityCircuitBreaker();
    }

    /**
     * @notice Update action cooldown blocks (owner only)
     * @param _userCooldownBlocks New user cooldown in blocks
     * @param _lpCooldownBlocks New LP cooldown in blocks
     */
    function updateActionCooldowns(uint256 _userCooldownBlocks, uint256 _lpCooldownBlocks) external onlyOwner {
        userActionCooldownBlocks = _userCooldownBlocks;
        lpActionCooldownBlocks = _lpCooldownBlocks;
    }

    /**
     * @notice Update buyback parameters
     * @param _buybackRate Fraction of pool to spend per buyback (PRECISION-scaled)
     * @param _buybackIntervalBlocks Minimum interval between buybacks, in blocks
     * @param _buybackExecutionThreshold Minimum balance required to execute a buyback
     */
    function updateBuybackParameters(
        uint256 _buybackRate,
        uint256 _buybackIntervalBlocks,
        uint256 _buybackExecutionThreshold
    ) external onlyOwner {
        if (_buybackRate > PRECISION) revert TenexiumErrors.PercentageTooHigh();
        buybackRate = _buybackRate;
        buybackIntervalBlocks = _buybackIntervalBlocks;
        buybackExecutionThreshold = _buybackExecutionThreshold;
    }

    /**
     * @notice Update Insurance Rates parameters
     * @param _protocolFeeGoveranceShare Protocol fee goverance share
     * @param _protocolFeeInsuranceShare Protocol fee insurance share
     * @param _lpFeeInsuranceShare LP fee insurance share
     * @param _perfFeeInsuranceShare Performance fee insurance share
     */
    function updateInsuranceRates(
        uint256 _protocolFeeGoveranceShare,
        uint256 _protocolFeeInsuranceShare,
        uint256 _lpFeeInsuranceShare,
        uint256 _perfFeeInsuranceShare
    ) external onlyOwner {
        if (
            _protocolFeeGoveranceShare > PRECISION || _protocolFeeInsuranceShare > PRECISION
                || _lpFeeInsuranceShare > PRECISION || _perfFeeInsuranceShare > PRECISION
        ) revert TenexiumErrors.PercentageTooHigh();

        protocolFeeGoveranceShare = _protocolFeeGoveranceShare;
        protocolFeeInsuranceShare = _protocolFeeInsuranceShare;
        lpFeeInsuranceShare = _lpFeeInsuranceShare;
        perfFeeInsuranceShare = _perfFeeInsuranceShare;
    }

    /**
     * @notice Update fee parameters (owner only): trading, borrowing baseline per 360 blocks, liquidation fee
     * @param _tradingFeeRate New trading fee rate
     * @param _borrowingFeeRate New borrowing fee rate per 360 blocks
     * @param _liquidationFeeRate New liquidation fee rate
     */
    function updateFeeParameters(uint256 _tradingFeeRate, uint256 _borrowingFeeRate, uint256 _liquidationFeeRate)
        external
        onlyOwner
    {
        if (_tradingFeeRate > PRECISION / 100) revert TenexiumErrors.FeeTooHigh();
        if (_borrowingFeeRate > (1 * PRECISION) / 1000) revert TenexiumErrors.FeeTooHigh();
        if (_liquidationFeeRate > (10 * PRECISION) / 100) revert TenexiumErrors.FeeTooHigh();

        tradingFeeRate = _tradingFeeRate;
        borrowingFeeRate = _borrowingFeeRate;
        liquidationFeeRate = _liquidationFeeRate;
    }

    /**
     * @notice Update fee distributions (owner only). Each triple must sum to PRECISION.
     * @param _trading [LP, Liquidator, Protocol]
     * @param _borrowing [LP, Liquidator, Protocol]
     * @param _liquidation [LP, Liquidator, Protocol]
     */
    function updateFeeDistributions(
        uint256[3] calldata _trading,
        uint256[3] calldata _borrowing,
        uint256[3] calldata _liquidation
    ) external onlyOwner {
        if (_trading[0] + _trading[1] + _trading[2] != PRECISION) revert TenexiumErrors.DistributionInvalid();
        if (_borrowing[0] + _borrowing[1] + _borrowing[2] != PRECISION) revert TenexiumErrors.DistributionInvalid();
        if (_liquidation[0] + _liquidation[1] + _liquidation[2] != PRECISION) {
            revert TenexiumErrors.DistributionInvalid();
        }
        tradingFeeLpShare = _trading[0];
        tradingFeeLiquidatorShare = _trading[1];
        tradingFeeProtocolShare = _trading[2];
        borrowingFeeLpShare = _borrowing[0];
        borrowingFeeLiquidatorShare = _borrowing[1];
        borrowingFeeProtocolShare = _borrowing[2];
        liquidationFeeLpShare = _liquidation[0];
        liquidationFeeLiquidatorShare = _liquidation[1];
        liquidationFeeProtocolShare = _liquidation[2];
    }

    /**
     * @notice Update tier thresholds, fee discounts, and max leverages (owner only)
     * @param _tierThresholds [t1..t5] token thresholds for each tier
     * @param _tierFeeDiscounts [tier0..tier5] fee discounts for each tier
     * @param _tierMaxLeverages [tier0..tier5] leverage caps for each tier
     */
    function updateTierParameters(
        uint256[5] calldata _tierThresholds,
        uint256[6] calldata _tierFeeDiscounts,
        uint256[6] calldata _tierMaxLeverages
    ) external onlyOwner {
        for (uint256 i = 0; i < 6; i++) {
            if (_tierFeeDiscounts[i] > PRECISION) revert TenexiumErrors.FeeTooHigh();
        }
        for (uint256 i = 0; i < 6; i++) {
            if (_tierMaxLeverages[i] > maxLeverage) revert TenexiumErrors.LeverageTooHigh();
        }

        tier1Threshold = _tierThresholds[0];
        tier2Threshold = _tierThresholds[1];
        tier3Threshold = _tierThresholds[2];
        tier4Threshold = _tierThresholds[3];
        tier5Threshold = _tierThresholds[4];
        tier0FeeDiscount = _tierFeeDiscounts[0];
        tier1FeeDiscount = _tierFeeDiscounts[1];
        tier2FeeDiscount = _tierFeeDiscounts[2];
        tier3FeeDiscount = _tierFeeDiscounts[3];
        tier4FeeDiscount = _tierFeeDiscounts[4];
        tier5FeeDiscount = _tierFeeDiscounts[5];
        tier0MaxLeverage = _tierMaxLeverages[0];
        tier1MaxLeverage = _tierMaxLeverages[1];
        tier2MaxLeverage = _tierMaxLeverages[2];
        tier3MaxLeverage = _tierMaxLeverages[3];
        tier4MaxLeverage = _tierMaxLeverages[4];
        tier5MaxLeverage = _tierMaxLeverages[5];
    }

    /**
     * @notice Update protocol validator hotkey
     * @param newHotkey New validator hotkey
     */
    function updateProtocolValidatorHotkey(bytes32 newHotkey) external onlyOwner {
        if (newHotkey == bytes32(0)) revert TenexiumErrors.InvalidValue();
        protocolValidatorHotkey = newHotkey;
    }

    /**
     * @notice Update protocol treasury address
     * @param newTreasury New treasury address
     */
    function updateTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert TenexiumErrors.InvalidValue();
        treasury = newTreasury;
    }

    /**
     * @notice Update function permissions
     * @param _functionPermissions [Open position, Close position, Add collateral]
     */
    function updateFunctionPermissions(bool[3] calldata _functionPermissions) external onlyManager {
        functionPermissions = _functionPermissions;
    }

    /**
     * @notice Update address conversion contract
     * @param newAddressConversionContract New address conversion contract
     */
    function updateAddressConversionContract(address newAddressConversionContract) external onlyOwner {
        if (newAddressConversionContract == address(0)) revert TenexiumErrors.InvalidValue();
        ADDRESS_CONVERSION_CONTRACT = IAddressConversion(newAddressConversionContract);
    }

    /**
     * @notice Update manager
     * @param newManager New manager
     */
    function updateManager(address newManager) external onlyOwner {
        if (newManager == address(0)) revert TenexiumErrors.InvalidValue();
        manager = newManager;
    }

    /**
     * @notice Update insurance manager
     * @param newInsuranceManager New insurance manager
     */
    function updateInsuranceManager(address newInsuranceManager) external onlyOwner {
        if (newInsuranceManager == address(0)) revert TenexiumErrors.InvalidValue();
        insuranceManager = newInsuranceManager;
    }

    /**
     * @notice Update max liquidation count
     * @param newMaxLiquidationCount New max liquidation count
     */
    function updateMaxLiquidationCount(uint256 newMaxLiquidationCount) external onlyManager {
        if (newMaxLiquidationCount < 1) revert TenexiumErrors.InvalidValue();
        maxLiquidationCount = newMaxLiquidationCount;
    }

    /**
     * @notice Update global accrued borrowing fees (called every 360 blocks)
     * @dev This function should be called periodically to update the global fee accumulator
     * @dev Has a 360-block cooldown to prevent excessive updates
     */
    function updateAccruedBorrowingFees() external {
        // Check 360-block cooldown
        if (block.number < lastAccruedBorrowingFeesUpdate + 360) revert TenexiumErrors.BorrowingFeesCooldownActive();

        if (totalBorrowed == 0) return;

        // Calculate current borrowing rate based on global utilization
        uint256 utilization = totalBorrowed.safeMul(PRECISION) / totalLpStakes;
        uint256 ratePer360 = _dynamicBorrowRatePer360(utilization);

        // Update global accumulator
        accruedBorrowingFees += ratePer360;

        // Update last update block
        lastAccruedBorrowingFeesUpdate = block.number;
    }

    /**
     * @notice Add a new alpha pair for trading
     * @param alphaNetuid Alpha subnet ID
     * @param maxLeverageForPair Maximum leverage for this pair
     * @dev Uses global liquidation threshold for all pairs
     */
    function addAlphaPair(
        uint16 alphaNetuid,
        uint256 maxLeverageForPair,
        uint256 liquidationThresholdForPair,
        bytes32 validatorHotkey
    ) external onlyManager {
        if (alphaPairs[alphaNetuid].isActive) revert TenexiumErrors.PairExists();
        if (maxLeverageForPair > maxLeverage) revert TenexiumErrors.LeverageTooHigh();
        if (validatorHotkey == bytes32(0)) revert TenexiumErrors.InvalidValue();
        if (liquidationThresholdForPair < (105 * PRECISION) / 100) {
            revert TenexiumErrors.ThresholdTooLow();
        }

        AlphaPair storage pair = alphaPairs[alphaNetuid];
        pair.netuid = alphaNetuid;
        pair.maxLeverage = maxLeverageForPair;
        pair.liquidationThreshold = liquidationThresholdForPair;
        pair.validatorHotkey = validatorHotkey;
        pair.isActive = true;
    }

    /**
     * @notice Remove an existing alpha pair
     * @param alphaNetuid Alpha subnet ID
     * @dev Requires no collateral or borrows outstanding in the pair
     */
    function removeAlphaPair(uint16 alphaNetuid) external onlyManager {
        AlphaPair storage pair = alphaPairs[alphaNetuid];
        if (!pair.isActive) revert TenexiumErrors.PairMissing();
        if (pair.totalCollateral != 0 || pair.totalBorrowed != 0 || pair.totalAlphaStaked != 0) {
            revert TenexiumErrors.InvalidValue();
        }

        // Deactivate and clear parameters
        pair.isActive = false;
        pair.maxLeverage = 0;
        pair.liquidationThreshold = 0;
        pair.validatorHotkey = bytes32(0);
    }

    /**
     * @notice Update alpha pair parameters
     * @param alphaNetuid Alpha subnet ID
     * @param newMaxLeverage New maximum leverage for this pair
     * @param newValidatorHotkey New validator hotkey for this pair
     */
    function updateAlphaPairParameters(
        uint16 alphaNetuid,
        uint256 newMaxLeverage,
        uint256 newLiquidationThreshold,
        bytes32 newValidatorHotkey
    ) external onlyManager {
        AlphaPair storage pair = alphaPairs[alphaNetuid];
        if (!pair.isActive) revert TenexiumErrors.PairMissing();
        if (newMaxLeverage > maxLeverage) revert TenexiumErrors.LeverageTooHigh();
        if (newLiquidationThreshold < (105 * PRECISION) / 100) {
            revert TenexiumErrors.ThresholdTooLow();
        }
        if (newValidatorHotkey == bytes32(0)) revert TenexiumErrors.InvalidValue();

        pair.maxLeverage = newMaxLeverage;
        pair.liquidationThreshold = newLiquidationThreshold;
        pair.validatorHotkey = newValidatorHotkey;
    }

    // ==================== EMERGENCY FUNCTIONS ====================

    /**
     * @notice Emergency pause toggle
     */
    function _toggleEmergencyPause() internal {
        bool isCurrentlyPaused = paused();
        bool shouldBePaused = liquidityCircuitBreaker;

        if (shouldBePaused != isCurrentlyPaused) {
            if (shouldBePaused) {
                _pause();
            } else {
                _unpause();
            }
        }
    }

    /**
     * @notice Manually reset liquidity circuit breaker (owner only)
     * @dev Should only be used after addressing underlying liquidity/utilization issues
     */
    function resetLiquidityCircuitBreaker(bool _liquidityCircuitBreaker) external onlyManager {
        liquidityCircuitBreaker = _liquidityCircuitBreaker;
        _toggleEmergencyPause();
    }

    // ==================== CIRCUIT BREAKER FUNCTIONS ====================

    /**
     * @notice Update liquidity-based circuit breaker status
     */
    function _updateLiquidityCircuitBreaker() internal {
        // Check minimum liquidity threshold
        if (totalLpStakes < minLiquidityThreshold) {
            liquidityCircuitBreaker = true;
            _toggleEmergencyPause();
            return;
        }

        // Check utilization rate
        if (totalBorrowed > 0 && totalLpStakes > 0) {
            uint256 utilizationRate = totalBorrowed.safeMul(PRECISION) / totalLpStakes;
            if (utilizationRate > maxUtilizationRate) {
                liquidityCircuitBreaker = true;
                _toggleEmergencyPause();
                return;
            }
        }

        // Circuit breaker can be disabled if conditions are met
        liquidityCircuitBreaker = false;
        _toggleEmergencyPause();
    }

    // ==================== LIQUIDITY PROVIDER FUNCTIONS ====================

    /**
     * @notice Add liquidity to the protocol
     */
    function addLiquidity() external payable nonReentrant {
        _addLiquidity();
        _updateLiquidityCircuitBreaker();
    }

    /**
     * @notice Remove liquidity from the protocol
     * @param amount Amount of liquidity to remove (0 for all)
     */
    function removeLiquidity(uint256 amount) external nonReentrant lpRateLimit {
        _removeLiquidity(amount);
        _updateLiquidityCircuitBreaker();
    }

    // ==================== TRADING FUNCTIONS ====================

    /**
     * @notice Open a leveraged position (LONG only - no shorting allowed)
     * @param alphaNetuid Alpha subnet ID
     * @param leverage Desired leverage
     * @param maxSlippage Maximum acceptable slippage (in basis points)
     */
    function openPosition(uint16 alphaNetuid, uint256 leverage, uint256 maxSlippage)
        external
        payable
        whenNotPaused
        nonReentrant
        userRateLimit
        validAlphaPair(alphaNetuid)
        hasPermission(0)
    {
        _openPosition(alphaNetuid, leverage, maxSlippage);
        _updateLiquidityCircuitBreaker();
    }

    /**
     * @notice Close a position and return collateral (TAO-only withdrawals)
     * @param positionId User's position identifier
     * @param amountToClose Amount of alpha to close (0 for full close)
     * @param maxSlippage Maximum acceptable slippage
     */
    function closePosition(uint256 positionId, uint256 amountToClose, uint256 maxSlippage)
        external
        nonReentrant
        userRateLimit
        validPosition(msg.sender, positionId)
        hasPermission(1)
    {
        _closePosition(positionId, amountToClose, maxSlippage);
        _updateLiquidityCircuitBreaker();
    }

    /**
     * @notice Add collateral to an existing position (TAO only)
     * @param positionId User's position identifier
     */
    function addCollateral(uint256 positionId)
        external
        payable
        nonReentrant
        userRateLimit
        validPosition(msg.sender, positionId)
        hasPermission(2)
    {
        _addCollateral(positionId);
        _updateLiquidityCircuitBreaker();
    }

    /**
     * @notice Liquidate an undercollateralized position
     * @param user Address of the position owner
     * @param positionId User's position identifier
     */
    function liquidatePosition(address user, uint256 positionId)
        external
        validPosition(user, positionId)
        nonReentrant
    {
        // Prevent multiple calls in the same block
        if (lastLiquidationBlock[msg.sender][user][positionId] == block.number) {
            return;
        }

        // Update the last liquidation block
        lastLiquidationBlock[msg.sender][user][positionId] = block.number;

        if (!_isPositionLiquidatable(user, positionId)) {
            // Reset counters when position is not liquidatable
            firstLiquidatableBlock[msg.sender][user][positionId] = 0;
            consecutiveLiquidatableBlocks[msg.sender][user][positionId] = 0;
            return;
        }

        // If this is the first time this liquidator sees position as liquidatable, record the block
        if (
            firstLiquidatableBlock[msg.sender][user][positionId] == 0
                || block.number - firstLiquidatableBlock[msg.sender][user][positionId] > maxLiquidationCount
        ) {
            firstLiquidatableBlock[msg.sender][user][positionId] = block.number;
            consecutiveLiquidatableBlocks[msg.sender][user][positionId] = 1;
        } else {
            // Increment consecutive liquidatable blocks counter
            consecutiveLiquidatableBlocks[msg.sender][user][positionId]++;
        }

        // Check if position has been liquidatable for maxLiquidationCount consecutive blocks for this liquidator
        if (consecutiveLiquidatableBlocks[msg.sender][user][positionId] >= maxLiquidationCount) {
            _liquidatePosition(user, positionId);
            _updateLiquidityCircuitBreaker();
            // Reset counters after liquidation
            firstLiquidatableBlock[msg.sender][user][positionId] = 0;
            consecutiveLiquidatableBlocks[msg.sender][user][positionId] = 0;
            return;
        }
    }

    // ==================== REWARD CLAIM FUNCTIONS ====================

    /**
     * @notice Claim accrued LP fee rewards
     * @return rewards Amount of TAO claimed
     */
    function claimLpFeeRewards() external whenNotPaused nonReentrant lpRateLimit returns (uint256 rewards) {
        rewards = _claimLpFeeRewards(msg.sender);
    }

    // ==================== BUYBACK FUNCTIONS ====================

    /**
     * @notice Execute automated buyback using accumulated protocol fees
     */
    function executeBuyback() external whenNotPaused nonReentrant {
        _executeBuyback();
    }

    /**
     * @notice Execute burn of bought back Alpha tokens
     */
    function executeBurn() external whenNotPaused nonReentrant {
        _burnBuybackedAlpha();
    }

    /**
     * @notice Withdraw protocol fees
     */
    function withdrawProtocolFees() external onlyManager nonReentrant {
        uint256 totalRewards = protocolFees;
        if (totalRewards == 0) revert TenexiumErrors.NoFees();

        // governance fee for signers
        uint256 totalGovernanceFee = totalRewards.safeMul(protocolFeeGoveranceShare) / PRECISION;
        // Transfer governance fee to owner(MultiSigWallet)
        (bool success,) = payable(owner()).call{value: totalGovernanceFee}("");
        if (!success) revert TenexiumErrors.TransferFailed();

        // Reserve buyback fee for buyback pool
        uint256 buybackAmount = totalRewards.safeMul(buybackRate) / PRECISION;
        // Fund buyback pool
        buybackPool += buybackAmount;

        // Reserve insurance fee for LP Recover
        uint256 insuranceAmount = totalRewards.safeMul(protocolFeeInsuranceShare) / PRECISION;
        (success,) = payable(insuranceManager).call{value: insuranceAmount}("");
        if (!success) revert TenexiumErrors.TransferFailed();

        // Reset protocol fees
        protocolFees = 0;

        uint256 withdrawAmount =
            totalRewards.safeSub(totalGovernanceFee).safeSub(buybackAmount).safeSub(insuranceAmount);

        // Transfer remaining fees to treasury
        (success,) = payable(treasury).call{value: withdrawAmount}("");
        if (!success) revert TenexiumErrors.TransferFailed();
    }

    // ==================== REWARD DISTRIBUTION FUNCTIONS ====================

    /**
     * @notice Distribute rewards to selected users based on their weekly trading volume
     * @param selectedUsers Array of user addresses to receive rewards
     * @param netUids Array of net UIDs to unstake alpha tokens from
     * @param totalWeeklyVolume Total weekly trading volume
     * @dev This function unstakes all alpha tokens from the provided net UIDs and distributes
     *      the resulting TAO to selected users based on their weekly trading volume
     */
    function distributeRewardsToUsers(
        address[] calldata selectedUsers,
        uint16[] calldata netUids,
        uint256 totalWeeklyVolume
    ) external onlyManager nonReentrant {
        if (selectedUsers.length == 0 || netUids.length == 0 || totalWeeklyVolume == 0) {
            revert TenexiumErrors.InvalidValue();
        }

        uint256 totalRewardPool = 0;

        // Unstake alpha tokens from all provided net UIDs and accumulate TAO
        for (uint256 i = 0; i < netUids.length; i++) {
            uint16 netuid = netUids[i];
            AlphaPair storage pair = alphaPairs[netuid];

            if (!pair.isActive) revert TenexiumErrors.PairMissing();

            // Get the total alpha staked for this netuid
            bytes32 protocolSs58Address = ADDRESS_CONVERSION_CONTRACT.addressToSS58Pub(address(this));
            uint256 totalAlphaStaked =
                STAKING_PRECOMPILE.getStake(pair.validatorHotkey, protocolSs58Address, uint256(netuid));

            uint256 availableAlphaStaked = totalAlphaStaked.safeSub(pair.totalAlphaStaked);

            if (availableAlphaStaked > 0) {
                // Unstake all alpha tokens for this netuid
                uint256 taoReceived = _unstakeAlphaForTao(
                    pair.validatorHotkey,
                    availableAlphaStaked,
                    0, // No price limit
                    false, // Don't allow partial
                    netuid
                );

                totalRewardPool = totalRewardPool.safeAdd(taoReceived);
            }
        }

        if (totalRewardPool == 0) revert TenexiumErrors.InvalidValue();

        // Distribute rewards based on weekly trading volume
        for (uint256 i = 0; i < selectedUsers.length; i++) {
            address user = selectedUsers[i];
            uint256 userVolume = userWeeklyTradingVolume[user][currentWeek];

            if (userVolume > 0) {
                // Calculate user's share of the reward pool
                uint256 userReward = totalRewardPool.safeMul(userVolume) / totalWeeklyVolume;
                if (userReward > 0) {
                    // Transfer reward to user
                    (bool success,) = payable(user).call{value: userReward}("");
                    if (!success) revert TenexiumErrors.TransferFailed();
                }
            }
        }
        currentWeek = currentWeek + 1;
        emit RewardsDistributed(totalRewardPool, selectedUsers.length, currentWeek);
    }

    // ==================== LIQUIDITY PROVIDER TRACKING FUNCTIONS ====================

    /**
     * @notice Associate an address with a hotkey
     * @param hotkey The hotkey to associate the address with
     * @return true if the address was associated with the hotkey
     */
    function setAssociate(bytes32 hotkey) public nonReentrant returns (bool) {
        if (liquidityProviderSet[hotkey][msg.sender] || uniqueLiquidityProviders[msg.sender]) {
            revert TenexiumErrors.AddressAlreadyAssociated();
        }
        if (groupLiquidityProviders[hotkey].length >= maxLiquidityProvidersPerHotkey) {
            revert TenexiumErrors.MaxLiquidityProvidersPerHotkeyReached();
        }
        uniqueLiquidityProviders[msg.sender] = true;
        groupLiquidityProviders[hotkey].push(msg.sender);
        liquidityProviderSet[hotkey][msg.sender] = true;
        return true;
    }

    /**
     * @notice Set the maximum number of liquidity providers per hotkey
     * @param _maxLiquidityProvidersPerHotkey The maximum number of liquidity providers per hotkey
     */
    function setMaxLiquidityProvidersPerHotkey(uint256 _maxLiquidityProvidersPerHotkey) public onlyManager {
        if (_maxLiquidityProvidersPerHotkey == 0 || _maxLiquidityProvidersPerHotkey > 10) {
            revert TenexiumErrors.InvalidValue();
        }
        maxLiquidityProvidersPerHotkey = _maxLiquidityProvidersPerHotkey;
    }

    /**
     * @notice Get the length of the liquidity provider set for a hotkey
     * @param hotkey The hotkey to get the length of the liquidity provider set for
     * @return The length of the liquidity provider set for the hotkey
     */
    function liquidityProviderSetLength(bytes32 hotkey) public view returns (uint256) {
        return groupLiquidityProviders[hotkey].length;
    }

    // ==================== INSURANCE FUND FUNCTIONS ====================

    /**
     * @notice Receive insurance fund from InsuranceManager contract
     * @dev This function allows the InsuranceManager to send TAO to this contract
     * @dev Only callable by the InsuranceManager contract
     */
    function receiveInsuranceFund() external payable {
        if (msg.sender != insuranceManager) revert TenexiumErrors.InvalidValue();
        if (msg.value == 0) revert TenexiumErrors.InvalidValue();

        // The TAO is automatically added to the contract's balance
        // No additional processing needed as this is just a funding mechanism
    }

    // ==================== UPGRADES (UUPS) ====================

    /**
     * @notice Authorize upgrade (owner only)
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ==================== FALLBACK ====================

    /**
     * @notice Prohibit direct TAO transfers
     * @dev This prevents accidental TAO loss and ensures proper protocol interaction
     */
    receive() external payable {
        revert TenexiumErrors.DirectTaoTransferProhibited();
    }

    /**
     * @notice Prohibit fallback calls
     * @dev Prevents accidental function calls with invalid data
     */
    fallback() external payable {
        revert TenexiumErrors.FunctionNotFound();
    }
}
