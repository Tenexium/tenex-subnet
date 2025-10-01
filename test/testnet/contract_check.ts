import { ethers } from "hardhat";
import utils from "./utils";
import { decodeAddress } from "@polkadot/util-crypto";

// Interface for the neuron data structure
interface NeuronData {
    id: number;
    hotkey: string;
    coldkey: string;
    daily_reward: number;
    deposits: Array<{
        id: number;
        deposit_address: string;
        amount_deposited: number;
        lp_shares: number;
    }>;
}

interface DepositAddressWithAmount {
    hotkey: string;
    depositAddress: string;
    amount: string;
}

async function fetchNeuronsData(apiUrl: string): Promise<NeuronData[]> {
    try {
        console.log(`🔍 Fetching neurons data from: ${apiUrl}`);
        
        const response = await fetch(apiUrl);
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const neurons: NeuronData[] = await response.json();
        console.log(`✅ Successfully fetched ${neurons.length} neurons`);
        
        return neurons;
    } catch (error) {
        console.error("❌ Error fetching neurons data:", error);
        throw error;
    }
}

function getDepositAddresses(neurons: NeuronData[]): DepositAddressWithAmount[] {
    const depositAddressesWithAmount: DepositAddressWithAmount[] = [];
    
    neurons.forEach(neuron => {
        neuron.deposits.forEach(deposit => {
            if (!depositAddressesWithAmount.some(address => address.depositAddress === deposit.deposit_address)) {
                depositAddressesWithAmount.push({ hotkey: neuron.hotkey, depositAddress: deposit.deposit_address, amount: deposit.amount_deposited.toString() });
            }
        });
    });
    
    return depositAddressesWithAmount;
}

// async test_lps_check(contract: TenexiumProtocol){

// }

async function main() {
    const networkName = process.env.NETWORK_NAME || "mainnet";
    const prKey = process.env.ETH_PRIVATE_KEY || "";
    const { provider, signer, contract } = await utils.getTenexiumProtocolContract(networkName, prKey);
    const TenexiumProtocolContractAddress = contract.target;

    console.log("🔍 Testing TenexiumProtocol Contract Check on " + networkName);
    console.log("=" .repeat(60));
    console.log("TenexiumProtocolContractAddress:", TenexiumProtocolContractAddress);
    console.log("RPC URL:", utils.getRpcUrl(networkName));
    console.log("Signer:", signer.address);
    console.log("Contract Balance:", ethers.formatEther(await provider.getBalance(TenexiumProtocolContractAddress)), "TAO");

    const apiUrl = process.env.BACKEND_API_URL + "/api/v1/neurons/";
    
    try {
        // Fetch neurons data from API
        const neurons = await fetchNeuronsData(apiUrl);
        
        // Get deposit addresses
        const depositAddressesWithAmount = getDepositAddresses(neurons);
        
        console.log("\n📋 Deposit Addresses with Amount:");
        console.log("=" .repeat(50));
        depositAddressesWithAmount.forEach( async (address, index) => {
            const lpInfo = await contract.liquidityProviders(address.depositAddress);
            console.log(`${index + 1}. ${address.depositAddress}: ${address.amount} ${ethers.formatEther(lpInfo[0])}`, ethers.parseEther(address.amount)===lpInfo[0] ? "✅" : "❌");
            const lp_adress_from_hotkey = await contract.groupLiquidityProviders(decodeAddress(address.hotkey), 0);
            console.log(`${index + 1}. LP Address from Hotkey(${address.hotkey}): ${lp_adress_from_hotkey}`, address.depositAddress===lp_adress_from_hotkey ? "✅" : "❌");
            const is_unique_liquidity_provider = await contract.uniqueLiquidityProviders(address.depositAddress);
            console.log(`${index + 1}. Is Unique Liquidity Provider: ${is_unique_liquidity_provider}`, is_unique_liquidity_provider===true ? "✅" : "❌");
        });
        console.log(`\n💰 Found ${depositAddressesWithAmount.length} unique deposit addresses`);
        
    } catch (error) {
        console.error("❌ Error:", error);
        process.exitCode = 1;
    }
}

main().catch((error) => {
    console.error("❌ Error:", error);
    process.exitCode = 1;
});
