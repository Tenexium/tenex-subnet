import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as fs from "fs";
import * as path from "path";

// Types for deployment
interface InsuranceManagerDeployment {
    network: string;
    deployer: string;
    timestamp: string;
    insuranceManager: {
        address: string;
        tenexiumProtocol: string;
    };
}

// Utility functions
const utils = {
    saveDeployment(networkName: string, deploymentInfo: InsuranceManagerDeployment): void {
        const deploymentsDir = path.join(__dirname, "..", "deployments");
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }
        const filePath = path.join(deploymentsDir, `${networkName}-insurance-manager.json`);
        const existingData = fs.existsSync(filePath) 
            ? JSON.parse(fs.readFileSync(filePath, "utf8"))
            : {};
        const updatedData = {
            ...existingData,
            ...deploymentInfo,
            lastUpdated: new Date().toISOString(),
        };
        fs.writeFileSync(filePath, JSON.stringify(updatedData, null, 2));
        console.log(`  📁 Deployment info saved to ${filePath}`);
    }
};

// Main deployment task
task("deploy:insurance-manager", "Deploy InsuranceManager contract")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        const tenexiumProtocol = "0x2cc611c0c47C30F6E291487ee55996b2AE726522";
        
        console.log("🚀 Starting InsuranceManager deployment...");
        console.log(`📍 Network: ${hre.network.name}`);
        console.log(`🔗 Tenexium Protocol: ${tenexiumProtocol}`);
        
        // Get deployer
        const [deployer] = await hre.ethers.getSigners();
        console.log(`👤 Deployer: ${deployer.address}`);
        
        // Check deployer balance
        const balance = await hre.ethers.provider.getBalance(deployer.address);
        console.log(`💰 Deployer balance: ${hre.ethers.formatEther(balance)} ETH`);
        
        if (balance < hre.ethers.parseEther("0.01")) {
            console.log("⚠️  Warning: Low deployer balance");
        }
        
        // Deploy InsuranceManager
        console.log("\n📦 Deploying InsuranceManager...");
        const InsuranceManager = await hre.ethers.getContractFactory("InsuranceManager");
        
        const insuranceManager = await InsuranceManager.deploy(tenexiumProtocol);
        await insuranceManager.waitForDeployment();
        
        const insuranceManagerAddress = await insuranceManager.getAddress();
        console.log(`✅ InsuranceManager deployed to: ${insuranceManagerAddress}`);
        
        // Verify deployment
        console.log("\n🔍 Verifying deployment...");
        const deployedTenexiumProtocol = await insuranceManager.tenexiumProtocol();
        if (deployedTenexiumProtocol.toLowerCase() !== tenexiumProtocol.toLowerCase()) {
            throw new Error("❌ Deployment verification failed: Tenexium protocol address mismatch");
        }
        
        console.log("✅ Deployment verification successful");
        
        // Save deployment info
        const deploymentInfo: InsuranceManagerDeployment = {
            network: hre.network.name,
            deployer: deployer.address,
            timestamp: new Date().toISOString(),
            insuranceManager: {
                address: insuranceManagerAddress,
                tenexiumProtocol: tenexiumProtocol
            }
        };
        
        utils.saveDeployment(hre.network.name, deploymentInfo);
        
        // Final summary
        console.log("\n🎉 Deployment Summary:");
        console.log(`   Contract: InsuranceManager`);
        console.log(`   Address: ${insuranceManagerAddress}`);
        console.log(`   Tenexium Protocol: ${tenexiumProtocol}`);
        console.log(`   Network: ${hre.network.name}`);
        console.log(`   Deployer: ${deployer.address}`);
        
        // Optional: Verify on block explorer (if not localhost)
        if (hre.network.name !== "localhost" && hre.network.name !== "hardhat") {
            console.log("\n🔍 To verify on block explorer, run:");
            console.log(`   npx hardhat verify --network ${hre.network.name} ${insuranceManagerAddress} "${tenexiumProtocol}"`);
        }
        
        return {
            address: insuranceManagerAddress,
            tenexiumProtocol: tenexiumProtocol
        };
    });

// Task to get deployment info
task("info:insurance-manager", "Get InsuranceManager deployment information")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        const deploymentsDir = path.join(__dirname, "..", "deployments");
        const filePath = path.join(deploymentsDir, `${hre.network.name}-insurance-manager.json`);
        
        if (!fs.existsSync(filePath)) {
            console.log(`❌ No deployment found for network: ${hre.network.name}`);
            return;
        }
        
        const deploymentData = JSON.parse(fs.readFileSync(filePath, "utf8"));
        
        console.log("📋 InsuranceManager Deployment Info:");
        console.log(`   Network: ${deploymentData.network}`);
        console.log(`   Address: ${deploymentData.insuranceManager.address}`);
        console.log(`   Tenexium Protocol: ${deploymentData.insuranceManager.tenexiumProtocol}`);
        console.log(`   Deployer: ${deploymentData.deployer}`);
        console.log(`   Deployed: ${deploymentData.timestamp}`);
        console.log(`   Last Updated: ${deploymentData.lastUpdated}`);
    });
