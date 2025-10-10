import { ethers } from "hardhat";
import utils from "./utils";

// Interface for IStaking precompile
const ISTAKING_ABI = [
    "function getStake(bytes32 hotkey, bytes32 coldkey, uint256 netuid) external view returns (uint256)",
    "function getTotalAlphaStaked(bytes32 hotkey, uint256 netuid) external view returns (uint256)",
    "function getTotalColdkeyStake(bytes32 coldkey) external view returns (uint256)"
];

// Constants
const STAKING_PRECOMPILE_ADDRESS = "0x0000000000000000000000000000000000000805";
const BURN_ADDRESS = "0xc2cdcf01af7163d2d99b2ec87954e4c1b735e9e9ea80f8775bf29dd9457eaca1";

interface BuybackStats {
    buybackPool: bigint;
    lastBuybackBlock: bigint;
    totalTaoUsedForBuybacks: bigint;
    totalAlphaBought: bigint;
    buybackIntervalBlocks: bigint;
    buybackExecutionThreshold: bigint;
    BURN_ADDRESS: string;
    contractBalance: bigint;
    totalBorrowed: bigint;
    totalLpStakes: bigint;
    totalPendingLpFees: bigint;
    protocolFees: bigint;
    burnAddressStake: bigint;
    burnAddressTotalStake: bigint;
    blockNumber: number;
}

async function getBuybackStats(contract: any, stakingContract: any, netuid: number, provider: any): Promise<BuybackStats> {
    const [
        buybackPool,
        lastBuybackBlock,
        totalTaoUsedForBuybacks,
        totalAlphaBought,
        buybackIntervalBlocks,
        buybackExecutionThreshold,
        BURN_ADDRESS,
        contractBalance,
        totalBorrowed,
        totalLpStakes,
        totalPendingLpFees,
        protocolFees,
        blockNumber
    ] = await Promise.all([
        contract.buybackPool(),
        contract.lastBuybackBlock(),
        contract.totalTaoUsedForBuybacks(),
        contract.totalAlphaBought(),
        contract.buybackIntervalBlocks(),
        contract.buybackExecutionThreshold(),
        contract.BURN_ADDRESS(),
        provider.getBalance(contract.target),
        contract.totalBorrowed(),
        contract.totalLpStakes(),
        contract.totalPendingLpFees(),
        contract.protocolFees(),
        provider.getBlockNumber()
    ]);

    // Get burn address stake information
    const [burnAddressStake, burnAddressTotalStake] = await Promise.all([
        stakingContract.getStake(BURN_ADDRESS, BURN_ADDRESS, netuid),
        stakingContract.getTotalColdkeyStake(BURN_ADDRESS)
    ]);

    return {
        buybackPool,
        lastBuybackBlock,
        totalTaoUsedForBuybacks,
        totalAlphaBought,
        buybackIntervalBlocks,
        buybackExecutionThreshold,
        BURN_ADDRESS,
        contractBalance,
        totalBorrowed,
        totalLpStakes,
        totalPendingLpFees,
        protocolFees,
        burnAddressStake,
        burnAddressTotalStake,
        blockNumber
    };
}

function formatWeiToTao(wei: bigint): string {
    return ethers.formatEther(wei);
}

function formatRaoToTao(rao: bigint): string {
    return ethers.formatEther(rao);
}

function printBuybackStats(stats: BuybackStats, label: string) {
    console.log(`\n=== ${label} ===`);
    console.log(`Block Number: ${stats.blockNumber}`);
    console.log(`Buyback Pool: ${formatWeiToTao(stats.buybackPool)} TAO`);
    console.log(`Last Buyback Block: ${stats.lastBuybackBlock}`);
    console.log(`Total TAO Used for Buybacks: ${formatWeiToTao(stats.totalTaoUsedForBuybacks)} TAO`);
    console.log(`Total Alpha Bought: ${formatRaoToTao(stats.totalAlphaBought)} TAO`);
    console.log(`Buyback Interval Blocks: ${stats.buybackIntervalBlocks}`);
    console.log(`Buyback Execution Threshold: ${formatWeiToTao(stats.buybackExecutionThreshold)} TAO`);
    console.log(`BURN_ADDRESS: ${stats.BURN_ADDRESS}`);
    console.log(`Contract Balance: ${formatWeiToTao(stats.contractBalance)} TAO`);
    console.log(`Total Borrowed: ${formatWeiToTao(stats.totalBorrowed)} TAO`);
    console.log(`Total LP Stakes: ${formatWeiToTao(stats.totalLpStakes)} TAO`);
    console.log(`Total Pending LP Fees: ${formatWeiToTao(stats.totalPendingLpFees)} TAO`);
    console.log(`Protocol Fees: ${formatWeiToTao(stats.protocolFees)} TAO`);
    console.log(`Burn Address Stake (Tenex): ${formatRaoToTao(stats.burnAddressStake)} TAO`);
    console.log(`Burn Address Total Stake: ${formatRaoToTao(stats.burnAddressTotalStake)} TAO`);
}

function calculateAvailableBalance(stats: BuybackStats): bigint {
    return stats.contractBalance + stats.totalBorrowed - stats.totalLpStakes - stats.totalPendingLpFees - stats.protocolFees;
}

function canExecuteBuyback(stats: BuybackStats): boolean {
    const blocksSinceLastBuyback = BigInt(stats.blockNumber) - stats.lastBuybackBlock;
    const hasEnoughBlocks = blocksSinceLastBuyback >= stats.buybackIntervalBlocks;
    const hasEnoughPool = stats.buybackPool >= stats.buybackExecutionThreshold;
    const hasEnoughBalance = calculateAvailableBalance(stats) >= stats.buybackPool;
    
    console.log(`\n=== Buyback Conditions Check ===`);
    console.log(`Blocks since last buyback: ${blocksSinceLastBuyback} (required: ${stats.buybackIntervalBlocks})`);
    console.log(`Has enough blocks: ${hasEnoughBlocks}`);
    console.log(`Pool amount: ${formatWeiToTao(stats.buybackPool)} TAO (required: ${formatWeiToTao(stats.buybackExecutionThreshold)} TAO)`);
    console.log(`Has enough pool: ${hasEnoughPool}`);
    console.log(`Available balance: ${formatWeiToTao(calculateAvailableBalance(stats))} TAO (required: ${formatWeiToTao(stats.buybackPool)} TAO)`);
    console.log(`Has enough balance: ${hasEnoughBalance}`);
    console.log(`Can execute buyback: ${hasEnoughBlocks && hasEnoughPool && hasEnoughBalance}`);
    
    return hasEnoughBlocks && hasEnoughPool && hasEnoughBalance;
}

async function main() {
    try {
        console.log("=== TENEXIUM BUYBACK TEST ===");
        
        // Setup contracts
        const { contract } = await utils.getTenexiumProtocolContract("testnet", process.env.ETH_PRIVATE_KEY!);
        const provider = new ethers.JsonRpcProvider(utils.getRpcUrl("testnet"));
        const stakingContract = new ethers.Contract(STAKING_PRECOMPILE_ADDRESS, ISTAKING_ABI, provider);
        
        // Get network info
        const netuid = await contract.TENEX_NETUID();
        console.log(`Testing on Tenex NetUID: ${netuid}`);
        
        // Get initial stats
        console.log("\n📊 Getting initial buyback statistics...");
        const initialStats = await getBuybackStats(contract, stakingContract, Number(netuid), provider);
        printBuybackStats(initialStats, "INITIAL BUYBACK STATS");
        
        // Check if we need to fill buyback pool first
        const protocolFees = await contract.protocolFees();
        console.log(`\n💰 Current protocol fees: ${formatWeiToTao(protocolFees)} TAO`);
        
        if (protocolFees > 0) {
            console.log("\n🔄 Filling buyback pool by withdrawing protocol fees...");
            try {
                const withdrawTx = await contract.withdrawProtocolFees();
                console.log(`Withdraw protocol fees transaction hash: ${withdrawTx.hash}`);
                console.log("Waiting for confirmation...");
                const withdrawReceipt = await withdrawTx.wait();
                console.log(`Withdraw protocol fees confirmed in block: ${withdrawReceipt?.blockNumber}`);
                
                // Get updated stats after filling buyback pool
                console.log("\n📊 Getting updated buyback statistics after filling pool...");
                const updatedStats = await getBuybackStats(contract, stakingContract, Number(netuid), provider);
                printBuybackStats(updatedStats, "UPDATED BUYBACK STATS (AFTER FILLING POOL)");
            } catch (error) {
                console.error("❌ Error filling buyback pool:", error);
            }
        } else {
            console.log("ℹ️ No protocol fees available to fill buyback pool");
        }
        
        // Check if buyback can be executed with existing pool
        const canExecute = canExecuteBuyback(initialStats);
        
        if (!canExecute) {
            console.log("\n❌ Buyback cannot be executed at this time. Conditions not met.");
            console.log("This might be due to:");
            console.log("- Not enough blocks since last buyback");
            console.log("- Buyback pool below execution threshold");
            console.log("- Insufficient available balance");
            console.log("\n💡 Try running some trading activity to generate protocol fees first!");
            return;
        }
        
        console.log("\n✅ Buyback conditions are met. Proceeding with execution...");
        
        // Execute buyback
        console.log("\n🔥 Executing buyback...");
        const tx = await contract.executeBuyback();
        console.log(`Transaction hash: ${tx.hash}`);
        console.log("Waiting for confirmation...");
        const receipt = await tx.wait();
        console.log(`Transaction confirmed in block: ${receipt?.blockNumber}`);
        
        const burnTx = await contract.executeBurn();
        console.log(`Transaction hash: ${burnTx.hash}`);
        console.log("Waiting for confirmation...");
        const burnReceipt = await burnTx.wait();
        console.log(`Transaction confirmed in block: ${burnReceipt?.blockNumber}`);
        
        // Get final stats
        console.log("\n📊 Getting final buyback statistics...");
        const finalStats = await getBuybackStats(contract, stakingContract, Number(netuid), provider);
        printBuybackStats(finalStats, "FINAL BUYBACK STATS");
        
        // Calculate differences
        console.log("\n=== BUYBACK EXECUTION ANALYSIS ===");
        const buybackAmount = initialStats.buybackPool;
        const alphaReceived = finalStats.totalAlphaBought - initialStats.totalAlphaBought;
        const burnAddressStakeIncrease = finalStats.burnAddressStake - initialStats.burnAddressStake;
        const burnAddressTotalStakeIncrease = finalStats.burnAddressTotalStake - initialStats.burnAddressTotalStake;
        
        console.log(`Buyback Amount: ${formatWeiToTao(buybackAmount)} TAO`);
        console.log(`Alpha Received: ${formatRaoToTao(alphaReceived)} TAO`);
        console.log(`Burn Address Stake Increase (Tenex): ${formatRaoToTao(burnAddressStakeIncrease)} TAO`);
        console.log(`Burn Address Total Stake Increase: ${formatRaoToTao(burnAddressTotalStakeIncrease)} TAO`);
        
        // Verify burn address balance increased
        console.log("\n=== BURN ADDRESS VERIFICATION ===");
        if (burnAddressStakeIncrease > 0) {
            console.log(`✅ SUCCESS: Burn address stake increased by ${formatRaoToTao(burnAddressStakeIncrease)} TAO`);
            console.log(`✅ This confirms that ${formatRaoToTao(alphaReceived)} TAO worth of alpha tokens were burned`);
        } else {
            console.log(`❌ WARNING: Burn address stake did not increase as expected`);
            console.log(`Expected increase: ${formatRaoToTao(alphaReceived)} TAO`);
            console.log(`Actual increase: ${formatRaoToTao(burnAddressStakeIncrease)} TAO`);
        }
        
        // Verify buyback pool was reduced
        const poolReduction = initialStats.buybackPool - finalStats.buybackPool;
        console.log("\n=== BUYBACK POOL VERIFICATION ===");
        if (poolReduction === buybackAmount) {
            console.log(`✅ SUCCESS: Buyback pool reduced by exactly ${formatWeiToTao(poolReduction)} TAO`);
        } else {
            console.log("❌ WARNING: Buyback pool reduction mismatch");
            console.log(`Expected reduction: ${formatWeiToTao(buybackAmount)} TAO`);
            console.log(`Actual reduction: ${formatWeiToTao(poolReduction)} TAO`);
        }
        
        // Verify total TAO used for buybacks increased
        const taoUsedIncrease = finalStats.totalTaoUsedForBuybacks - initialStats.totalTaoUsedForBuybacks;
        console.log("\n=== TOTAL TAO USED VERIFICATION ===");
        if (taoUsedIncrease === buybackAmount) {
            console.log(`✅ SUCCESS: Total TAO used for buybacks increased by ${formatWeiToTao(taoUsedIncrease)} TAO`);
        } else {
            console.log("❌ WARNING: Total TAO used increase mismatch");
            console.log(`Expected increase: ${formatWeiToTao(buybackAmount)} TAO`);
            console.log(`Actual increase: ${formatWeiToTao(taoUsedIncrease)} TAO`);
        }
        
        // Calculate slippage if we have expected vs actual alpha
        if (alphaReceived > 0) {
            // Note: We can't get the exact expected alpha from the simulation here,
            // but we can show the alpha that was actually received and burned
            console.log("\n=== ALPHA BURNING VERIFICATION ===");
            console.log(`✅ SUCCESS: ${ethers.formatUnits(alphaReceived, 9)} Alpha tokens were received and burned`);
            console.log("✅ This creates buy pressure and removes tokens from circulation");
        }
        
        console.log("\n🎉 Buyback test completed successfully!");
        
    } catch (error) {
        console.error("❌ Error during buyback test:", error);
        throw error;
    }
}

// Execute the main function
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
