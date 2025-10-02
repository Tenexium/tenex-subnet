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

// Converts a number or numeric string (including scientific notation) into a
// plain decimal string without exponent and clamps the fractional part to
// at most `maxDecimals` digits.
function toPlainDecimalString(value: number | string, maxDecimals: number): string {
    const raw = typeof value === "number" ? value.toString() : value.trim();
    if (raw === "" || raw === "NaN" || raw === "Infinity" || raw === "-Infinity") {
        return "0";
    }

    const isNeg = raw.startsWith("-");
    const s = isNeg ? raw.slice(1) : raw;

    const expandExp = (str: string): string => {
        if (!/[eE]/.test(str)) return str;
        const [coeff, expStr] = str.split(/[eE]/);
        const exp = parseInt(expStr, 10);
        const [intPart, fracPart = ""] = coeff.split(".");
        const digits = (intPart + fracPart).replace(/^0+(?=\d)/, "");
        if (digits === "") return "0";
        if (exp >= 0) {
            const move = exp - fracPart.length;
            if (move >= 0) {
                return digits + "0".repeat(move);
            } else {
                const idx = digits.length + move;
                return digits.slice(0, idx) + "." + digits.slice(idx);
            }
        } else {
            const absExp = Math.abs(exp);
            const zeros = absExp - intPart.replace(/^0+/, "").length;
            if (zeros >= 0) {
                return "0." + "0".repeat(zeros) + digits;
            } else {
                const idx = intPart.replace(/^0+/, "").length - absExp;
                const left = digits.slice(0, idx);
                const right = digits.slice(idx);
                return (left === "" ? "0" : left) + "." + right;
            }
        }
    };

    // Expand exponent if any
    let dec = expandExp(s);

    // Normalize: ensure we have only digits and at most one dot
    if (!/^\d*(?:\.\d*)?$/.test(dec)) {
        // Fallback: strip invalid chars
        dec = dec.replace(/[^\d.]/g, "");
        const parts = dec.split(".");
        if (parts.length > 2) {
            dec = parts.shift()! + "." + parts.join("");
        }
    }

    // Remove leading zeros (keep one if number < 1)
    if (dec.includes(".")) {
        const [i, f] = dec.split(".");
        const intNorm = i.replace(/^0+(?=\d)/, "");
        dec = (intNorm === "" ? "0" : intNorm) + "." + (f || "");
    } else {
        dec = dec.replace(/^0+(?=\d)/, "");
        if (dec === "") dec = "0";
    }

    // Clamp fractional digits to maxDecimals
    if (dec.includes(".")) {
        let [i, f] = dec.split(".");
        if (f.length > maxDecimals) {
            f = f.slice(0, maxDecimals); // truncate to avoid rounding up
        }
        // Trim trailing zeros in fraction
        f = f.replace(/0+$/, "");
        dec = f.length > 0 ? `${i}.${f}` : i;
    }

    // Re-apply sign if necessary and avoid "-0"
    if (isNeg && dec !== "0" && dec !== "0.0") {
        dec = "-" + dec;
    }
    return dec;
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
                const decimal = toPlainDecimalString(deposit.amount_deposited as unknown as (number | string), 18);
                const amount = ethers.parseUnits(decimal, 18);
                depositAddressesWithAmount.push({ hotkey: neuron.hotkey, depositAddress: deposit.deposit_address, amount: amount.toString() });
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
            console.log(`${index + 1}. ${address.depositAddress}: ${address.amount} ${lpInfo[0]}`, address.amount.toString()===lpInfo[0].toString() ? "✅" : "❌");
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
