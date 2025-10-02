// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IAlpha.sol";
import "../interfaces/IStaking.sol";
import "../interfaces/IMetagraph.sol";
import "../interfaces/INeuron.sol";
import "../interfaces/IAddressConversion.sol";
import "../libraries/TenexiumErrors.sol";

/**
 * @title TenexiumStorage
 * @notice Central storage contract for all Tenexium Protocol state variables
 */
contract TenexiumStorage {
    // ==================== CONSTANTS ====================

    // Precision for fixed-point math (9 decimals)
    uint256 public constant PRECISION = 1e9;

    // Subnet identifier for Tenex
    uint16 public constant TENEX_NETUID = 67;

    // Bittensor EVM precompiles
    IMetagraph public constant METAGRAPH_PRECOMPILE = IMetagraph(0x0000000000000000000000000000000000000802);
    INeuron public constant NEURON_PRECOMPILE = INeuron(0x0000000000000000000000000000000000000804);
    IStaking public constant STAKING_PRECOMPILE = IStaking(0x0000000000000000000000000000000000000805);
    IAlpha public constant ALPHA_PRECOMPILE = IAlpha(0x0000000000000000000000000000000000000808);

    // ==================== PROTOCOL PARAMETERS ====================

    // Core leverage and liquidation threshold
    uint256 public maxLeverage; // Global maximum leverage
    uint256 public liquidationThreshold; // Liquidation threshold ratio

    // Liquidity guardrails
    uint256 public minLiquidityThreshold; // Min TAO liquidity to keep protocol open
    uint256 public maxUtilizationRate; // Max allowed utilization
    uint256 public liquidityBufferRatio; // Extra liquidity buffer required for borrows

    // Action cooldowns
    uint256 public userActionCooldownBlocks; // User action cooldown in blocks
    uint256 public lpActionCooldownBlocks; // LP action cooldown in blocks

    // Buyback parameters
    uint256 public buybackRate; // Fraction of pool per buyback
    uint256 public buybackIntervalBlocks; // Buyback interval in blocks
    uint256 public buybackExecutionThreshold; // Min balance to execute buyback

    // Vesting parameters
    uint256 public vestingDurationBlocks; // Vesting duration in blocks
    uint256 public cliffDurationBlocks; // Cliff duration in blocks

    // Fee parameters
    uint256 public tradingFeeRate; // Trading fee
    uint256 public borrowingFeeRate; // Borrowing fee baseline per 360 blocks
    uint256 public liquidationFeeRate; // Liquidation fee

    // Fee distributions
    uint256 public tradingFeeLpShare; // Trading fee LP share
    uint256 public tradingFeeLiquidatorShare; // Trading fee liquidator share
    uint256 public tradingFeeProtocolShare; // Trading fee protocol share
    uint256 public borrowingFeeLpShare; // Borrowing fee LP share
    uint256 public borrowingFeeLiquidatorShare; // Borrowing fee liquidator share
    uint256 public borrowingFeeProtocolShare; // Borrowing fee protocol share
    uint256 public liquidationFeeLpShare; // Liquidation fee LP share
    uint256 public liquidationFeeLiquidatorShare; // Liquidation fee liquidator share
    uint256 public liquidationFeeProtocolShare; // Liquidation fee protocol share

    // Tier thresholds
    uint256 public tier1Threshold; // Tier 1 threshold
    uint256 public tier2Threshold; // Tier 2 threshold
    uint256 public tier3Threshold; // Tier 3 threshold
    uint256 public tier4Threshold; // Tier 4 threshold
    uint256 public tier5Threshold; // Tier 5 threshold

    // Tier fee discounts
    uint256 public tier0FeeDiscount; // Tier 0 fee discount
    uint256 public tier1FeeDiscount; // Tier 1 fee discount
    uint256 public tier2FeeDiscount; // Tier 2 fee discount
    uint256 public tier3FeeDiscount; // Tier 3 fee discount
    uint256 public tier4FeeDiscount; // Tier 4 fee discount
    uint256 public tier5FeeDiscount; // Tier 5 fee discount

    // Tier max leverages
    uint256 public tier0MaxLeverage; // Tier 0 max leverage
    uint256 public tier1MaxLeverage; // Tier 1 max leverage
    uint256 public tier2MaxLeverage; // Tier 2 max leverage
    uint256 public tier3MaxLeverage; // Tier 3 max leverage
    uint256 public tier4MaxLeverage; // Tier 4 max leverage
    uint256 public tier5MaxLeverage; // Tier 5 max leverage

    // Protocol validator and treasury
    bytes32 public protocolValidatorHotkey; // Protocol validator hotkey
    bytes32 public protocolSs58Address; // Protocol SS58 address
    address public treasury; // Protocol treasury

    // ==================== STATE VARIABLES ====================

    // Emergency controls
    bool public liquidityCircuitBreaker; // Liquidity circuit breaker flag

    // Permission controls for sensitive functions
    // 0: Open position (User)
    // 1: Close position (User)
    // 2: Add collateral (User)
    bool[3] public functionPermissions; // Function permissions

    // Global protocol state
    uint256 public totalCollateral; // Total collateral in protocol
    uint256 public totalBorrowed; // Total borrowed amount in protocol
    uint256 public totalVolume; // Total volume in protocol
    uint256 public totalTrades; // Total trades in protocol
    uint256 public protocolFees; // Total fees collected in protocol

    // Buyback system state
    uint256 public buybackPool; // Buyback pool balance
    uint256 public lastBuybackBlock; // Last buyback block
    uint256 public totalTaoUsedForBuybacks; // Total TAO used for buybacks
    uint256 public totalAlphaBought; // Total Alpha tokens bought
    uint256 public accumulatedFees; // Accumulated fees

    // Fee distribution tracking
    uint256 public totalFeesCollected; // Total fees collected
    uint256 public totalFeesDistributed; // Total fees distributed
    uint256 public lastFeeDistributionBlock; // Last fee distribution block
    uint256 public currentEpoch; // Current epoch

    // LP fee tracking
    uint256 public totalLpFees; // Total LP fees collected
    uint256 public totalLpStakes; // Total LP stakes

    // Liquidator fee tracking
    uint256 public totalLiquidatorFees; // Total liquidator fees collected
    uint256 public totalLiquidatorScore; // Total liquidator score

    // Accumulator-based fee accounting
    uint256 public accLpFeesPerShare; // Accumulated LP fees per share
    uint256 public accLiquidatorFeesPerScore; // Accumulated liquidator fees per score

    // ==================== MAPPINGS ====================

    // Rate limitings
    mapping(address => uint256) public lastUserActionBlock;
    mapping(address => uint256) public lastLpActionBlock;

    // Positions
    mapping(address => mapping(uint16 => Position)) public positions;

    // User aggregates
    mapping(address => uint256) public userCollateral;
    mapping(address => uint256) public userTotalBorrowed;
    mapping(address => uint256) public userTotalVolume;

    // Liquidity providers
    mapping(address => LiquidityProvider) public liquidityProviders;

    // LP fee rewards
    mapping(address => uint256) public lpFeeRewards;

    // Liquidator fee rewards
    mapping(address => uint256) public liquidatorFeeRewards;

    // Liquidator scores
    mapping(address => uint256) public liquidatorScores;

    // Liquidator reward debt
    mapping(address => uint256) public liquidatorRewardDebt;

    // Vesting schedules
    mapping(address => VestingSchedule[]) public vestingSchedules;

    // Alpha pairs
    mapping(uint16 => AlphaPair) public alphaPairs;

    // ==================== Liquidity Provider Tracking ====================

    // Liquidity provider tracking
    mapping(address => bool) public uniqueLiquidityProviders;
    // Liquidity provider set tracking
    mapping(bytes32 => mapping(address => bool)) public liquidityProviderSet;
    // Liquidity provider list tracking
    mapping(bytes32 => address[]) public groupLiquidityProviders;
    // The maximum number of liquidity providers per hotkey
    uint256 public maxLiquidityProvidersPerHotkey;

    // ==================== LP SHARE TRACKING ====================
    // Total LP shares
    uint256 public totalLpShares;

    // ==================== LIQUIDATION STATISTICS ====================

    uint256 public totalLiquidations; // Total number of liquidations executed
    uint256 public totalLiquidationValue; // Total TAO value liquidated
    mapping(address => uint256) public liquidatorLiquidations; // Number of liquidations by liquidator
    mapping(address => uint256) public liquidatorLiquidationValue; // Total TAO value liquidated by liquidator

    // ==================== ADDRESS CONVERSION ====================
    IAddressConversion public ADDRESS_CONVERSION_CONTRACT;

    // ==================== STRUCTS ====================

    struct Position {
        uint256 collateral; // TAO collateral amount
        uint256 borrowed; // TAO borrowed amount
        uint256 alphaAmount; // Alpha tokens held
        uint256 leverage; // Position leverage
        uint256 entryPrice; // Alpha price at entry
        uint256 lastUpdateBlock; // Last position update block
        uint256 accruedFees; // Accrued borrowing fees
        bool isActive; // Position status
        bytes32 validatorHotkey; // Hotkey used to stake alpha for this position
    }

    struct AlphaPair {
        uint16 netuid; // Subnet ID
        uint256 totalCollateral; // Total collateral in pair
        uint256 totalBorrowed; // Total borrowed amount
        uint256 utilizationRate; // Current utilization
        uint256 borrowingRate; // Current borrowing rate
        uint256 maxLeverage; // Maximum leverage allowed
        bool isActive; // Pair status
    }

    struct LiquidityProvider {
        uint256 stake; // LP stake amount
        uint256 rewards; // Accumulated rewards
        uint256 lastRewardBlock; // Last reward calculation block
        uint256 shares; // LP shares
        uint256 rewardDebt; // Accumulator-based reward debt for LP fee claims
        bool isActive; // LP status
    }

    struct VestingSchedule {
        uint256 totalAmount; // Total alpha tokens vesting
        uint256 claimedAmount; // Amount already claimed
        uint256 startBlock; // Vesting start block
        uint256 cliffBlock; // Cliff end block
        uint256 endBlock; // Vesting end block
        bool revoked; // Whether vesting is revoked
    }

    // ==================== MODIFIERS ====================

    modifier validPosition(address user, uint16 alphaNetuid) {
        if (!positions[user][alphaNetuid].isActive) revert TenexiumErrors.PositionNotFound(user, alphaNetuid);
        _;
    }

    modifier validAlphaPair(uint16 alphaNetuid) {
        if (!alphaPairs[alphaNetuid].isActive) revert TenexiumErrors.PairMissing(alphaNetuid);
        _;
    }

    modifier userRateLimit() {
        if (block.number < lastUserActionBlock[msg.sender] + userActionCooldownBlocks) {
            revert TenexiumErrors.UserCooldownActive(
                (lastUserActionBlock[msg.sender] + userActionCooldownBlocks) - block.number
            );
        }
        lastUserActionBlock[msg.sender] = block.number;
        _;
    }

    modifier lpRateLimit() {
        if (block.number < lastLpActionBlock[msg.sender] + lpActionCooldownBlocks) {
            revert TenexiumErrors.LpCooldownActive(
                (lastLpActionBlock[msg.sender] + lpActionCooldownBlocks) - block.number
            );
        }
        lastLpActionBlock[msg.sender] = block.number;
        _;
    }

    modifier hasPermission(uint8 permissionIndex) {
        if (permissionIndex >= functionPermissions.length) revert TenexiumErrors.InvalidValue();
        if (!functionPermissions[permissionIndex]) revert TenexiumErrors.FunctionNotPermitted(permissionIndex);
        _;
    }
}
