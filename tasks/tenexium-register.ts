import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as fs from "fs";
import * as path from "path";

// Types for deployment
interface TenexiumRegisterDeployment {
    network: string;
    deployer: string;
    timestamp: string;
    tenexiumRegister: {
        proxy?: string;
        implementation?: string;
        address: string;
        addressConversionContract: string;
        tenexiumProtocol: string;
    };
}

// Utility functions
const utils = {
    saveDeployment(networkName: string, deploymentInfo: TenexiumRegisterDeployment): void {
        const deploymentsDir = path.join(__dirname, "..", "deployments");
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }
        const filePath = path.join(deploymentsDir, `${networkName}-tenexium-register.json`);
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
    },
    getProxyAddress(networkName: string): string {
        const deploymentsDir = path.join(__dirname, "..", "deployments");
        const filePath = path.join(deploymentsDir, `${networkName}-tenexium-register.json`);
        const existingData = fs.existsSync(filePath) 
            ? JSON.parse(fs.readFileSync(filePath, "utf8"))
            : {};
        return existingData.tenexiumRegister?.proxy || "";
    },
    getNewImplementationAddress(networkName: string): string {
        const deploymentsDir = path.join(__dirname, "..", "deployments");
        const filePath = path.join(deploymentsDir, `${networkName}-tenexium-register.json`);
        const existingData = fs.existsSync(filePath) 
            ? JSON.parse(fs.readFileSync(filePath, "utf8"))
            : {};
        return existingData.newImplementation?.address || "";
    }
};

// Task: Deploy new TenexiumRegister proxy
task("deploy:tenexium-register:new_proxy", "Deploy TenexiumRegister with upgradeable proxy")
    .addParam("addressConversion", "Address conversion contract address", undefined, types.string)
    .addParam("tenexiumProtocol", "TenexiumProtocol contract address", undefined, types.string)
    .addFlag("save", "Save deployment info to file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("🚀 Deploying TenexiumRegister (Upgradeable)...");
        console.log("===============================================");
        
        const networkName = hre.network.name;
        const shouldSave = taskArgs.save;
        const addressConversionContract = taskArgs.addressConversion;
        const tenexiumProtocolAddress = taskArgs.tenexiumProtocol;
        
        console.log(`📊 Deployment Information:`);
        console.log(`  Network: ${networkName}`);
        console.log(`  Address Conversion Contract: ${addressConversionContract}`);
        console.log(`  TenexiumProtocol Contract: ${tenexiumProtocolAddress}`);
        
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();
            
            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} TAO`);
            
            // Validate inputs
            if (!addressConversionContract || addressConversionContract === "") {
                throw new Error("Address conversion contract address is required");
            }
            
            if (!tenexiumProtocolAddress || tenexiumProtocolAddress === "") {
                throw new Error("TenexiumProtocol contract address is required");
            }
            
            // Deploy contract
            console.log("\n📦 Deploying TenexiumRegister...");
            const TenexiumRegister = await hre.ethers.getContractFactory("TenexiumRegister");
            
            const tenexiumRegister = await hre.upgrades.deployProxy(
                TenexiumRegister,
                [
                    addressConversionContract,
                    tenexiumProtocolAddress
                ],
                {
                    initializer: "initialize",
                    kind: "uups",
                    unsafeAllow: ["constructor", "delegatecall"]
                }
            );

            await tenexiumRegister.waitForDeployment();
            const address = await tenexiumRegister.getAddress();
            console.log(`  ✅ TenexiumRegister deployed to: ${address}`);
            
            // Get implementation address
            const implementationAddress = await hre.upgrades.erc1967.getImplementationAddress(address);
            console.log(`  📋 Implementation address: ${implementationAddress}`);
            
            // Verify deployment
            console.log("\n🔍 Verifying deployment...");
            const deployedTenexiumProtocol = await tenexiumRegister.tenexiumProtocol();
            if (deployedTenexiumProtocol.toLowerCase() !== tenexiumProtocolAddress.toLowerCase()) {
                throw new Error("❌ Deployment verification failed: TenexiumProtocol address mismatch");
            }
            console.log("  ✅ Deployment verification successful");
            
            // Save deployment info if requested
            if (shouldSave) {
                const deploymentInfo: TenexiumRegisterDeployment = {
                    network: networkName,
                    deployer: deployer.address,
                    timestamp: new Date().toISOString(),
                    tenexiumRegister: {
                        proxy: address,
                        implementation: implementationAddress,
                        address: address,
                        addressConversionContract: addressConversionContract,
                        tenexiumProtocol: tenexiumProtocolAddress
                    }
                };
                utils.saveDeployment(networkName, deploymentInfo);
            }
            
            console.log("\n🎉 Deployment completed successfully!");
            console.log("📋 Contract Addresses:");
            console.log("  TenexiumRegister (Proxy):", address);
            console.log("  Implementation:", implementationAddress);
            
            // Verification instructions
            if (networkName !== "localhost" && networkName !== "hardhat") {
                console.log("\n🔍 To verify on block explorer, run:");
                console.log(`  npx hardhat verify --network ${networkName} ${implementationAddress}`);
            }
            
        } catch (error: any) {
            console.error("\n❌ Deployment failed:");
            console.error(error.message);
            process.exit(1);
        }
    });

// Task: Deploy new implementation only
task("deploy:tenexium-register:implementation", "Deploy new TenexiumRegister implementation for upgrades")
    .addFlag("save", "Save implementation address to deployment file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("🚀 Deploying TenexiumRegister Implementation...");
        console.log("=============================================");
        
        const networkName = hre.network.name;
        const shouldSave = taskArgs.save;
        
        console.log(`📊 Deployment Information:`);
        console.log(`  Network: ${networkName}`);
        
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();
            
            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} TAO`);
            
            // Deploy new implementation
            console.log("\n📦 Deploying TenexiumRegister Implementation...");
            const TenexiumRegister = await hre.ethers.getContractFactory("TenexiumRegister");
            
            const newImplementation = await TenexiumRegister.deploy({gasLimit: 10_000_000n});
            await newImplementation.waitForDeployment();
            
            const implementationAddress = await newImplementation.getAddress();
            console.log(`  ✅ New implementation deployed at: ${implementationAddress}`);
            
            // Save implementation address if requested
            if (shouldSave) {
                const deploymentsDir = path.join(__dirname, "..", "deployments");
                if (!fs.existsSync(deploymentsDir)) {
                    fs.mkdirSync(deploymentsDir, { recursive: true });
                }
                const filePath = path.join(deploymentsDir, `${networkName}-tenexium-register.json`);
                const existingData = fs.existsSync(filePath) 
                    ? JSON.parse(fs.readFileSync(filePath, "utf8"))
                    : {};
                
                const updatedData = {
                    ...existingData,
                    lastUpdated: new Date().toISOString(),
                    newImplementation: {
                        address: implementationAddress,
                        deployedAt: new Date().toISOString(),
                        deployer: deployer.address
                    }
                };
                fs.writeFileSync(filePath, JSON.stringify(updatedData, null, 2));
                console.log(`  📁 Implementation address saved to ${filePath}`);
            }
            
            console.log("\n🎉 Implementation deployment completed successfully!");
            console.log("📋 Implementation Address:", implementationAddress);
            console.log("\n💡 Next steps:");
            console.log("  1. Verify the implementation contract");
            console.log("  2. Use 'npx hardhat upgrade:tenexium-register:proxy' to upgrade your proxy");
            
        } catch (error: any) {
            console.error("\n❌ Implementation deployment failed:");
            console.error(error.message);
            process.exit(1);
        }
    });

// Task: Upgrade TenexiumRegister proxy
task("upgrade:tenexium-register:proxy", "Upgrade TenexiumRegister proxy to new implementation")
    .addOptionalParam("proxy", "Proxy contract address to upgrade")
    .addOptionalParam("implementation", "New implementation contract address")
    .addFlag("save", "Save upgrade info to deployment file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("🔄 Upgrading TenexiumRegister...");
        console.log("=======================");
        
        const networkName = hre.network.name;
        const proxyAddress = taskArgs.proxy || utils.getProxyAddress(networkName);
        const newImplementationAddress = taskArgs.implementation || utils.getNewImplementationAddress(networkName);
        const shouldSave = taskArgs.save;
        
        console.log(`📊 Upgrade Information:`);
        console.log(`  Network: ${networkName}`);
        console.log(`  Proxy Address: ${proxyAddress}`);
        console.log(`  New Implementation: ${newImplementationAddress}`);
        
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();
            
            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} TAO`);
            
            // Get current implementation
            const currentImplementation = await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);
            console.log(`  Current Implementation: ${currentImplementation}`);
            
            // Verify the new implementation is different
            if (currentImplementation.toLowerCase() === newImplementationAddress.toLowerCase()) {
                console.log("⚠️  Warning: New implementation address is the same as current implementation");
            }
            
            // Perform upgrade
            console.log("\n🔄 Performing upgrade...");
            
            // Get the proxy contract
            const proxyContract = await hre.ethers.getContractAt("TenexiumRegister", proxyAddress);
            
            // Perform upgrade via upgradeToAndCall
            const upgradeTx = await proxyContract.upgradeToAndCall(newImplementationAddress, "0x", {
                gasLimit: 10_000_000n
            });
            console.log(`  Transaction Hash: ${upgradeTx.hash}`);
            
            await upgradeTx.wait();
            console.log("  ✅ Upgrade transaction confirmed!");
            
            // Verify upgrade
            const updatedImplementation = await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);
            console.log(`  ✅ Verified new implementation: ${updatedImplementation}`);
            
            // Save upgrade info if requested
            if (shouldSave) {
                const deploymentsDir = path.join(__dirname, "..", "deployments");
                if (!fs.existsSync(deploymentsDir)) {
                    fs.mkdirSync(deploymentsDir, { recursive: true });
                }
                const filePath = path.join(deploymentsDir, `${networkName}-tenexium-register.json`);
                const existingData = fs.existsSync(filePath) 
                    ? JSON.parse(fs.readFileSync(filePath, "utf8"))
                    : {};
                
                const upgradeInfo = {
                    previousImplementation: currentImplementation,
                    newImplementation: newImplementationAddress,
                    upgradeTxHash: upgradeTx.hash,
                    upgradedAt: new Date().toISOString(),
                    upgradedBy: deployer.address
                };
                
                const updatedData = {
                    ...existingData,
                    lastUpdated: new Date().toISOString(),
                    upgrades: {
                        ...existingData.upgrades,
                        [upgradeTx.hash]: upgradeInfo
                    }
                };
                fs.writeFileSync(filePath, JSON.stringify(updatedData, null, 2));
                console.log(`  📁 Upgrade info saved to ${filePath}`);
            }
            
            console.log("\n🎉 Contract upgrade completed successfully!");
            console.log("📋 Upgrade Summary:");
            console.log(`  Proxy: ${proxyAddress}`);
            console.log(`  Previous Implementation: ${currentImplementation}`);
            console.log(`  New Implementation: ${updatedImplementation}`);
            console.log(`  Transaction Hash: ${upgradeTx.hash}`);
            
        } catch (error: any) {
            console.error("\n❌ Contract upgrade failed:");
            console.error(error.message);
            process.exit(1);
        }
    });

// Task: Get deployment info
task("info:tenexium-register", "Get TenexiumRegister deployment information")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        const deploymentsDir = path.join(__dirname, "..", "deployments");
        const filePath = path.join(deploymentsDir, `${hre.network.name}-tenexium-register.json`);
        
        if (!fs.existsSync(filePath)) {
            console.log(`❌ No deployment found for network: ${hre.network.name}`);
            return;
        }
        
        const deploymentData = JSON.parse(fs.readFileSync(filePath, "utf8"));
        
        console.log("📋 TenexiumRegister Deployment Info:");
        console.log(`   Network: ${deploymentData.network}`);
        console.log(`   Proxy Address: ${deploymentData.tenexiumRegister.proxy}`);
        console.log(`   Implementation: ${deploymentData.tenexiumRegister.implementation}`);
        console.log(`   Address Conversion: ${deploymentData.tenexiumRegister.addressConversionContract}`);
        console.log(`   TenexiumProtocol: ${deploymentData.tenexiumRegister.tenexiumProtocol}`);
        console.log(`   Deployer: ${deploymentData.deployer}`);
        console.log(`   Deployed: ${deploymentData.timestamp}`);
        console.log(`   Last Updated: ${deploymentData.lastUpdated}`);
        
        if (deploymentData.upgrades) {
            console.log("\n📜 Upgrade History:");
            Object.entries(deploymentData.upgrades).forEach(([txHash, info]: [string, any]) => {
                console.log(`   ${info.upgradedAt}:`);
                console.log(`     Tx: ${txHash}`);
                console.log(`     From: ${info.previousImplementation}`);
                console.log(`     To: ${info.newImplementation}`);
            });
        }
    });

// Task: Help
task("help:tenexium-register", "Show TenexiumRegister deployment task help")
    .setAction(async () => {
        console.log("🚀 TenexiumRegister Deployment Tasks");
        console.log("====================================");
        console.log("");
        console.log("Available tasks:");
        console.log("");
        console.log("  npx hardhat deploy:tenexium-register:new_proxy --address-conversion <address> --tenexium-protocol <address> [options]");
        console.log("    Deploy new upgradeable TenexiumRegister with proxy");
        console.log("");
        console.log("  npx hardhat deploy:tenexium-register:implementation [options]");
        console.log("    Deploy new implementation contract for upgrades");
        console.log("");
        console.log("  npx hardhat upgrade:tenexium-register:proxy [options]");
        console.log("    Upgrade proxy contract to new implementation");
        console.log("");
        console.log("  npx hardhat info:tenexium-register");
        console.log("    Get deployment information");
        console.log("");
        console.log("Options:");
        console.log("  --address-conversion <address>  Address conversion contract (required for new proxy)");
        console.log("  --tenexium-protocol <address>   TenexiumProtocol contract (required for new proxy)");
        console.log("  --proxy <address>               Proxy contract address (for upgrade)");
        console.log("  --implementation <address>      New implementation address (for upgrade)");
        console.log("  --save                          Save deployment info to file");
        console.log("  --network <name>                Network to deploy to");
        console.log("");
        console.log("Examples:");
        console.log("  # Deploy new proxy");
        console.log("  npx hardhat deploy:tenexium-register:new_proxy \\");
        console.log("    --address-conversion 0x123... \\");
        console.log("    --tenexium-protocol 0x456... \\");
        console.log("    --save \\");
        console.log("    --network testnet");
        console.log("");
        console.log("  # Deploy new implementation");
        console.log("  npx hardhat deploy:tenexium-register:implementation --save --network testnet");
        console.log("");
        console.log("  # Upgrade proxy");
        console.log("  npx hardhat upgrade:tenexium-register:proxy --save --network testnet");
    });

