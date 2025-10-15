import { ethers } from "hardhat";
import utils from "./utils";

interface FeeStats {
    tradingFees: bigint;
    borrowingFees: bigint;
    protocolFees: bigint;
    totalPendingLpFees: bigint;
    totalTradingFees: bigint;
    totalBorrowingFees: bigint;
    totalLiquidations: bigint;
    totalLiquidationValue: bigint;
}

interface PositionStats {
    collateral: bigint;
    borrowed: bigint;
    alphaAmount: bigint;
    leverage: bigint;
    entryPrice: bigint;
    isActive: boolean;
    alphaNetuid: number;
    borrowingFeeDebt: bigint;
}

interface UserStats {
    totalCollateral: bigint;
    totalBorrowed: bigint;
    nextPositionId: bigint;
}

async function getFeeStats(contract: any): Promise<FeeStats> {
    return {
        tradingFees: await contract.tradingFeeRate(),
        borrowingFees: await contract.borrowingFeeRate(),
        protocolFees: await contract.protocolFees(),
        totalPendingLpFees: await contract.totalPendingLpFees(),
        totalTradingFees: await contract.totalTradingFees(),
        totalBorrowingFees: await contract.totalBorrowingFees(),
        totalLiquidations: await contract.totalLiquidations(),
        totalLiquidationValue: await contract.totalLiquidationValue()
    };
}

async function getPositionStats(contract: any, userAddress: string, positionId: bigint): Promise<PositionStats> {
    const position = await contract.positions(userAddress, positionId);
    return {
        collateral: position.initialCollateral + position.addedCollateral,
        borrowed: position.borrowed,
        alphaAmount: position.alphaAmount,
        leverage: position.leverage,
        entryPrice: position.entryPrice,
        isActive: position.isActive,
        alphaNetuid: position.alphaNetuid,
        borrowingFeeDebt: position.borrowingFeeDebt
    };
}

async function getUserStats(contract: any, userAddress: string): Promise<UserStats> {
    return {
        totalCollateral: await contract.userCollateral(userAddress),
        totalBorrowed: await contract.userTotalBorrowed(userAddress),
        nextPositionId: await contract.nextPositionId(userAddress)
    };
}

function formatFeeStats(stats: FeeStats): void {
    console.log("📊 Fee Statistics:");
    console.log(`   Trading Fee Rate: ${ethers.formatUnits(stats.tradingFees, 9)}%`);
    console.log(`   Borrowing Fee Rate: ${ethers.formatUnits(stats.borrowingFees, 9)}%`);
    console.log(`   Protocol Fees: ${ethers.formatEther(stats.protocolFees)} TAO`);
    console.log(`   Total Pending LP Fees: ${ethers.formatEther(stats.totalPendingLpFees)} TAO`);
    console.log(`   Total Trading Fees: ${ethers.formatEther(stats.totalTradingFees)} TAO`);
    console.log(`   Total Borrowing Fees: ${ethers.formatEther(stats.totalBorrowingFees)} TAO`);
    console.log(`   Total Liquidations: ${stats.totalLiquidations.toString()}`);
    console.log(`   Total Liquidation Value: ${ethers.formatEther(stats.totalLiquidationValue)} TAO`);
}

function formatPositionStats(stats: PositionStats, positionId: bigint): void {
    console.log(`📈 Position ${positionId.toString()} Statistics:`);
    console.log(`   Collateral: ${ethers.formatEther(stats.collateral)} TAO`);
    console.log(`   Borrowed: ${ethers.formatEther(stats.borrowed)} TAO`);
    console.log(`   Alpha Amount: ${ethers.formatUnits(stats.alphaAmount, 9)} Alpha`);
    console.log(`   Leverage: ${ethers.formatUnits(stats.leverage, 9)}x`);
    console.log(`   Entry Price: ${ethers.formatEther(stats.entryPrice)} TAO/Alpha`);
    console.log(`   Is Active: ${stats.isActive}`);
    console.log(`   Alpha Netuid: ${stats.alphaNetuid}`);
    console.log(`   Borrowing Fee Debt: ${ethers.formatEther(stats.borrowingFeeDebt)} TAO`);
}

function formatUserStats(stats: UserStats): void {
    console.log("👤 User Statistics:");
    console.log(`   Total Collateral: ${ethers.formatEther(stats.totalCollateral)} TAO`);
    console.log(`   Total Borrowed: ${ethers.formatEther(stats.totalBorrowed)} TAO`);
    console.log(`   Next Position ID: ${stats.nextPositionId.toString()}`);
}

function calculateFeeChanges(before: FeeStats, after: FeeStats): void {
    console.log("💰 Fee Changes:");
    console.log(`   Protocol Fees Change: ${ethers.formatEther(after.protocolFees - before.protocolFees)} TAO`);
    console.log(`   Total Pending LP Fees Change: ${ethers.formatEther(after.totalPendingLpFees - before.totalPendingLpFees)} TAO`);
    console.log(`   Total Trading Fees Change: ${ethers.formatEther(after.totalTradingFees - before.totalTradingFees)} TAO`);
    console.log(`   Total Borrowing Fees Change: ${ethers.formatEther(after.totalBorrowingFees - before.totalBorrowingFees)} TAO`);
}

async function main() {
    const networkName = process.env.NETWORK_NAME || "mainnet";
    const prKey = process.env.ETH_PRIVATE_KEY || "";
    const { provider, signer, contract: TenexiumProtocol } = await utils.getTenexiumProtocolContract(networkName, prKey);
    const TenexiumProtocolContractAddress = TenexiumProtocol.target;

    console.log("🔍 Testing TenexiumProtocol Position Management on " + networkName);
    console.log("=" .repeat(80));
    console.log("TenexiumProtocolContractAddress:", TenexiumProtocolContractAddress);
    console.log("RPC URL:", utils.getRpcUrl(networkName));
    console.log("User:", signer.address);
    console.log("User balance:", ethers.formatEther(await provider.getBalance(signer.address)), "TAO");
    console.log("Contract Balance:", ethers.formatEther(await provider.getBalance(TenexiumProtocolContractAddress)), "TAO");
    
    const userAddress = await signer.getAddress();
    console.log(`👤 User Address: ${userAddress}`);
    
    // Test parameters
    const alphaNetuid = 67; // Using netuid 67 for testing
    const leverage = ethers.parseUnits("2", 9); // 2x leverage
    const maxSlippage = 100; // 1% max slippage
    const collateralAmount = ethers.parseEther("0.5"); // 0.5 TAO collateral
    
    console.log(`\n🧪 Test Parameters:`);
    console.log(`   Alpha Netuid: ${alphaNetuid}`);
    console.log(`   Leverage: ${ethers.formatUnits(leverage, 9)}x`);
    console.log(`   Max Slippage: ${maxSlippage / 100}%`);
    console.log(`   Collateral Amount: ${ethers.formatEther(collateralAmount)} TAO`);
    
    try {
        // Get initial state
        console.log("\n📊 Initial Protocol State:");
        const initialFeeStats = await getFeeStats(TenexiumProtocol);
        formatFeeStats(initialFeeStats);
        
        const initialUserStats = await getUserStats(TenexiumProtocol, userAddress);
        formatUserStats(initialUserStats);
        
        // Check if user has any existing positions
        const nextPositionId = initialUserStats.nextPositionId;
        console.log(`\n🔍 Checking for existing positions...`);
        console.log(`   Next Position ID: ${nextPositionId.toString()}`);
        
        const initialBalance = await provider.getBalance(userAddress);

        // Step 1: Open Position
        console.log("\n🚀 Step 1: Opening Position...");
        console.log(`   Sending ${ethers.formatEther(collateralAmount)} TAO as collateral`);
        
        const openTx = await TenexiumProtocol.openPosition(alphaNetuid, leverage, maxSlippage, {
            value: collateralAmount
        });
        console.log(`   Transaction Hash: ${openTx.hash}`);
        await openTx.wait();
        console.log("   ✅ Position opened successfully!");
        
        // Get state after opening position
        const afterOpenFeeStats = await getFeeStats(TenexiumProtocol);
        const afterOpenUserStats = await getUserStats(TenexiumProtocol, userAddress);
        const positionStats = await getPositionStats(TenexiumProtocol, userAddress, nextPositionId);
        
        console.log("\n📊 State After Opening Position:");
        formatFeeStats(afterOpenFeeStats);
        formatUserStats(afterOpenUserStats);
        formatPositionStats(positionStats, nextPositionId);
        
        console.log("\n💰 Fee Changes from Opening Position:");
        calculateFeeChanges(initialFeeStats, afterOpenFeeStats);
        
        // Calculate position metrics
        const totalPositionValue = positionStats.collateral + positionStats.borrowed;
        const currentAlphaPrice = positionStats.entryPrice;
        const positionValueInTao = positionStats.alphaAmount * currentAlphaPrice / ethers.parseEther("1");
        
        console.log("\n📈 Position Metrics:");
        console.log(`   Total Position Value: ${ethers.formatEther(totalPositionValue)} TAO`);
        console.log(`   Position Value in TAO: ${ethers.formatUnits(positionValueInTao, 9)} TAO`);
        console.log(`   Current Alpha Price: ${ethers.formatEther(currentAlphaPrice)} TAO/Alpha`);
        
        // Step 2: Update borrowing fees
        try {
            console.log("\n🔄 Step 2: Updating Borrowing Fees...");
            const updateBorrowingFeesTx = await TenexiumProtocol.updateAccruedBorrowingFees();
            console.log(`   Transaction Hash: ${updateBorrowingFeesTx.hash}`);
            await updateBorrowingFeesTx.wait();
            console.log("   ✅ Borrowing fees updated successfully!");
            // Get state after updating borrowing fees
            const afterUpdateBorrowingFeesFeeStats = await getFeeStats(TenexiumProtocol);
            const afterUpdateBorrowingFeesUserStats = await getUserStats(TenexiumProtocol, userAddress);
            const afterUpdateBorrowingFeesPositionStats = await getPositionStats(TenexiumProtocol, userAddress, nextPositionId);
            
            console.log("\n📊 State After Updating Borrowing Fees:");
            formatFeeStats(afterUpdateBorrowingFeesFeeStats);
            formatUserStats(afterUpdateBorrowingFeesUserStats);
            formatPositionStats(afterUpdateBorrowingFeesPositionStats, nextPositionId);

            console.log("\n💰 Fee Changes from Updating Borrowing Fees:");
            calculateFeeChanges(afterOpenFeeStats, afterUpdateBorrowingFeesFeeStats);
        } catch (error) {
            console.error("❌ Cool down period not passed yet");
        }
        
        // Wait a bit to simulate time passing (for borrowing fees to accrue)
        console.log("\n⏳ Waiting 30 seconds to simulate time passing...");
        await new Promise(resolve => setTimeout(resolve, 30000));
        
        // Step 3: Close Position (partial close)
        console.log("\n🔒 Step 3: Closing Position (Full Close)...");
        const closeTx = await TenexiumProtocol.closePosition(nextPositionId, 0, maxSlippage);
        console.log(`   Transaction Hash: ${closeTx.hash}`);
        await closeTx.wait();
        console.log("   ✅ Position closed successfully!");
        
        // Get final state
        const finalFeeStats = await getFeeStats(TenexiumProtocol);
        const finalUserStats = await getUserStats(TenexiumProtocol, userAddress);
        const finalPositionStats = await getPositionStats(TenexiumProtocol, userAddress, nextPositionId);
        
        console.log("\n📊 Final Protocol State:");
        formatFeeStats(finalFeeStats);
        formatUserStats(finalUserStats);
        formatPositionStats(finalPositionStats, nextPositionId);
        
        console.log("\n💰 Total Fee Changes from Position Lifecycle:");
        calculateFeeChanges(initialFeeStats, finalFeeStats);
        
        // Calculate total fees paid
        const totalTradingFeesPaid = finalFeeStats.totalTradingFees - initialFeeStats.totalTradingFees;
        const totalBorrowingFeesPaid = finalFeeStats.totalBorrowingFees - initialFeeStats.totalBorrowingFees;
        const totalProtocolFeesCollected = finalFeeStats.protocolFees - initialFeeStats.protocolFees;
        const totalLpFeesCollected = finalFeeStats.totalPendingLpFees - initialFeeStats.totalPendingLpFees;
        
        console.log("\n💸 Total Fees Summary:");
        console.log(`   Trading Fees Paid: ${ethers.formatEther(totalTradingFeesPaid)} TAO`);
        console.log(`   Borrowing Fees Paid: ${ethers.formatEther(totalBorrowingFeesPaid)} TAO`);
        console.log(`   Total Fees Paid: ${ethers.formatEther(totalTradingFeesPaid + totalBorrowingFeesPaid)} TAO`);
        console.log(`   Protocol Fees Collected: ${ethers.formatEther(totalProtocolFeesCollected)} TAO`);
        console.log(`   LP Fees Collected: ${ethers.formatEther(totalLpFeesCollected)} TAO`);
        
        // Calculate PnL
        const finalBalance = await provider.getBalance(userAddress);
        const balanceChange = finalBalance - initialBalance;
        
        console.log("\n📊 PnL Analysis:");
        console.log(`   Initial Balance: ${ethers.formatEther(initialBalance)} TAO`);
        console.log(`   Final Balance: ${ethers.formatEther(finalBalance)} TAO`);
        console.log(`   Balance Change: ${ethers.formatEther(balanceChange)} TAO`);
        console.log(`   Net PnL (including fees): ${ethers.formatEther(balanceChange)} TAO`);
        
        // Verify position is closed
        if (!finalPositionStats.isActive) {
            console.log("   ✅ Position successfully closed and deactivated");
        } else {
            console.log("   ⚠️  Position still active after close attempt");
        }
        
        console.log("\n🎉 Position test completed successfully!");
        console.log("=" .repeat(80));
        
    } catch (error) {
        console.error("❌ Error during position test:", error);
        
        // Try to get current state even if there was an error
        try {
            const errorFeeStats = await getFeeStats(TenexiumProtocol);
            const errorUserStats = await getUserStats(TenexiumProtocol, userAddress);
            console.log("\n📊 State after error:");
            formatFeeStats(errorFeeStats);
            formatUserStats(errorUserStats);
        } catch (stateError) {
            console.error("❌ Could not retrieve state after error:", stateError);
        }
        
        throw error;
    }
}

main().catch((error) => {
    console.error("❌ Error:", error);
    process.exitCode = 1;
});
