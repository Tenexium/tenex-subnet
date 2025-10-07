import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as fs from "fs";
import * as path from "path";
import deployConfig from "./deploy-config-testnet";
import { convertH160ToSS58, publicKeyToHex, ss58ToPublicKey } from "./address-utils";

// Types for deployment
interface DeploymentResult {
    network: string;
    deployer: string;
    timestamp: string;
    tenexiumProtocol: {
        proxy?: string;
        implementation?: string;
        address: string;
    };
}

// Utility functions
const utils = {
    saveDeployment(networkName: string, contractName:string, deploymentInfo: DeploymentResult): void {
        const deploymentsDir = path.join(__dirname, "..", "deployments");
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }
        const filePath = path.join(deploymentsDir, `${networkName}-${contractName}.json`);
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
    getProxyAddress(networkName: string, contractName:string): string {
        const deploymentsDir = path.join(__dirname, "..", "deployments");
        const filePath = path.join(deploymentsDir, `${networkName}-${contractName}.json`);
        const existingData = fs.existsSync(filePath) 
            ? JSON.parse(fs.readFileSync(filePath, "utf8"))
            : {};
        return existingData.tenexiumProtocol.proxy || "";
    },
    getNewImplementationAddress(networkName: string, contractName:string): string {
        const deploymentsDir = path.join(__dirname, "..", "deployments");
        const filePath = path.join(deploymentsDir, `${networkName}-${contractName}.json`);
        const existingData = fs.existsSync(filePath) 
            ? JSON.parse(fs.readFileSync(filePath, "utf8"))
            : {};
        return existingData.newImplementation.address || "";
    }
};

// Task: Deploy upgradeable contract
task("deploy:new_proxy", "Deploy Tenexium Protocol with upgradeable parameters")
    .addFlag("save", "Save deployment info to file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("�� Deploying Tenexium Protocol (Upgradeable)...");
        console.log("===============================================");
        
        const networkName = hre.network.name;
        const shouldSave = taskArgs.save;
        
        console.log(`📊 Deployment Information:`);
        console.log(`  Network: ${networkName}`);
        
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();
            
            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);
            
            // Deploy contract
            console.log("\n�� Deploying TenexiumProtocol...");
            const TenexiumProtocol = await hre.ethers.getContractFactory("TenexiumProtocol");
            
            const tenexiumProtocol = await hre.upgrades.deployProxy(
                TenexiumProtocol,
                [
                    deployConfig.maxLeverage,
                    deployConfig.liquidationThreshold,
                    deployConfig.minLiquidityThreshold,
                    deployConfig.maxUtilizationRate,
                    deployConfig.liquidityBufferRatio,
                    deployConfig.userCooldownBlocks,
                    deployConfig.lpCooldownBlocks,
                    deployConfig.buybackRate,
                    deployConfig.buybackIntervalBlocks,
                    deployConfig.buybackExecutionThreshold,
                    deployConfig.buybackBurningRate,
                    deployConfig.vestingDurationBlocks,
                    deployConfig.cliffDurationBlocks,
                    deployConfig.baseTradingFee,
                    deployConfig.borrowingFeeRate,
                    deployConfig.baseLiquidationFee,
                    [
                        deployConfig.tradingFeeDistribution.lpShare,
                        deployConfig.tradingFeeDistribution.liquidatorShare,
                        deployConfig.tradingFeeDistribution.protocolShare
                    ],
                    [
                        deployConfig.borrowingFeeDistribution.lpShare,
                        deployConfig.borrowingFeeDistribution.liquidatorShare,
                        deployConfig.borrowingFeeDistribution.protocolShare
                    ],
                    [
                        deployConfig.liquidationFeeDistribution.lpShare,
                        deployConfig.liquidationFeeDistribution.liquidatorShare,
                        deployConfig.liquidationFeeDistribution.protocolShare
                    ],
                    deployConfig.tierThresholds,
                    deployConfig.tierFeeDiscounts,
                    deployConfig.tierMaxLeverages,
                    deployConfig.protocolValidatorHotkey,
                    deployConfig.functionPermissions,
                    deployConfig.maxLiquidityProvidersPerHotkey
                ],
                {
                    initializer: "initialize",
                    kind: "uups",
                    unsafeAllow: ["constructor"]
                }
            );

            await tenexiumProtocol.waitForDeployment();
            const address = await tenexiumProtocol.getAddress();
            console.log(`  ✅ TenexiumProtocol deployed to: ${address}`);
            
            // Get implementation address
            const implementationAddress = await hre.upgrades.erc1967.getImplementationAddress(address);
            console.log(`  📋 Implementation address: ${implementationAddress}`);
            
            // Post-deploy configuration
            console.log("\n⚙️  Post-deploy configuration");
            const protocolSs58Address = convertH160ToSS58(address);
            const protocolSs58PublicKey = ss58ToPublicKey(protocolSs58Address);
            console.log("  → Setting protocol SS58 address (bytes32)");
            const tx = await tenexiumProtocol.updateProtocolSs58Address(protocolSs58PublicKey);
            await tx.wait();
            console.log("    ✅ Protocol SS58 address set to " + protocolSs58Address + " with public key " + publicKeyToHex(protocolSs58PublicKey));
            
            
            // Save deployment info if requested
            if (shouldSave) {
                const deploymentInfo: DeploymentResult = {
                    network: networkName,
                    deployer: deployer.address,
                    timestamp: new Date().toISOString(),
                    tenexiumProtocol: {
                        proxy: address,
                        implementation: implementationAddress,
                        address: address
                    }
                };
                utils.saveDeployment(networkName, "tenexiumProtocol", deploymentInfo);
            }
            
            console.log("\n🎉 Deployment completed successfully!");
            console.log("�� Contract Addresses:");
            console.log("TenexiumProtocol (Proxy):", address);
            console.log("Implementation:", implementationAddress);
            
        } catch (error: any) {
            console.error("\n❌ Deployment failed:");
            console.error(error.message);
            process.exit(1);
        }
    });

// Task: Deploy new implementation (equivalent to DeployImplementation.s.sol)
task("deploy:implementation", "Deploy new implementation contract for upgrades")
    .addFlag("save", "Save implementation address to deployment file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("🚀 Deploying New Implementation Contract...");
        console.log("=============================================");
        
        const networkName = hre.network.name;
        const shouldSave = taskArgs.save;
        
        console.log(`📊 Deployment Information:`);
        console.log(`  Network: ${networkName}`);
        
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();
            
            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);
            
            // Deploy new implementation
            console.log("\n�� Deploying TenexiumProtocol Implementation...");
            const TenexiumProtocol = await hre.ethers.getContractFactory("TenexiumProtocol");
            
            const newImplementation = await TenexiumProtocol.deploy();
            await newImplementation.waitForDeployment();
            
            const implementationAddress = await newImplementation.getAddress();
            console.log(`  ✅ New implementation deployed at: ${implementationAddress}`);
            
            // Save implementation address if requested
            if (shouldSave) {
                const deploymentsDir = path.join(__dirname, "..", "deployments");
                if (!fs.existsSync(deploymentsDir)) {
                    fs.mkdirSync(deploymentsDir, { recursive: true });
                }
                const filePath = path.join(deploymentsDir, `${networkName}-${"tenexiumProtocol"}.json`);
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
            console.log("  2. Use 'npx hardhat upgrade:proxy' to upgrade your proxy");
            
        } catch (error: any) {
            console.error("\n❌ Implementation deployment failed:");
            console.error(error.message);
            process.exit(1);
        }
    });

// Task: Upgrade contract (equivalent to Upgrade.s.sol)
task("upgrade:proxy", "Upgrade proxy contract to new implementation")
    .addOptionalParam("proxy", "Proxy contract address to upgrade")
    .addOptionalParam("implementation", "New implementation contract address")
    .addOptionalParam("data", "Initialization data for upgrade (hex string)", "", types.string)
    .addFlag("save", "Save upgrade info to deployment file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("�� Upgrading Contract...");
        console.log("=======================");
        
        const networkName = hre.network.name;
        const proxyAddress = taskArgs.proxy || utils.getProxyAddress(networkName, "tenexiumProtocol");
        const newImplementationAddress = taskArgs.implementation || utils.getNewImplementationAddress(networkName, "tenexiumProtocol");
        const initializationData = taskArgs.data;
        const shouldSave = taskArgs.save;
        
        console.log(`📊 Upgrade Information:`);
        console.log(`  Network: ${networkName}`);
        console.log(`  Proxy Address: ${proxyAddress}`);
        console.log(`  New Implementation: ${newImplementationAddress}`);
        if (initializationData) {
            console.log(`  Initialization Data: ${initializationData}`);
        }
        
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();
            
            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);
            
            // Get current implementation
            const currentImplementation = await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);
            console.log(`  Current Implementation: ${currentImplementation}`);
            
            // Verify the new implementation is different
            if (currentImplementation.toLowerCase() === newImplementationAddress.toLowerCase()) {
                console.log("⚠️  Warning: New implementation address is the same as current implementation");
            }
            
            // Perform upgrade
            console.log("\n�� Performing upgrade...");
            
            // Get the proxy contract
            const proxyContract = await hre.ethers.getContractAt("TenexiumProtocol", proxyAddress);
            
            // Prepare upgrade data
            const upgradeData = initializationData ? initializationData : "0x";
            
            // Perform upgrade via upgradeToAndCall
            const upgradeTx = await proxyContract.upgradeToAndCall(newImplementationAddress, upgradeData);
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
                const filePath = path.join(deploymentsDir, `${networkName}-${"tenexiumProtocol"}.json`);
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
                        [upgradeTx.hash]: upgradeInfo
                    }
                };
                fs.writeFileSync(filePath, JSON.stringify(updatedData, null, 2));
                console.log(`  �� Upgrade info saved to ${filePath}`);
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


// Task: Deploy subnet manager
task("deploy:subnet-manager:new_proxy", "Deploy subnet manager contract")
    .addFlag("save", "Save deployment info to file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("🚀 Deploying Subnet Manager Contract...");
        console.log("=============================================");
        
        const networkName = hre.network.name;
        const shouldSave = taskArgs.save;

        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();
            
            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);

            // Deploy subnet manager
            console.log("\n�� Deploying Subnet Manager...");
            const SubnetManager = await hre.ethers.getContractFactory("SubnetManager");
            const TenexiumContractAddress = utils.getProxyAddress(networkName, "tenexiumProtocol");
            const subnetManager = await hre.upgrades.deployProxy(
                SubnetManager,
                [
                    TenexiumContractAddress,
                    deployConfig.versionKey
                ],
                {
                    initializer: "initialize",
                    kind: "uups",
                    unsafeAllow: ["constructor"]
                }
            );

            await subnetManager.waitForDeployment();
            const address = await subnetManager.getAddress();
            console.log(`  ✅ Subnet Manager deployed to: ${address}`);

            // Get implementation address
            const implementationAddress = await hre.upgrades.erc1967.getImplementationAddress(address);
            console.log(`  📋 Implementation address: ${implementationAddress}`);

            // Save deployment info if requested
            if (shouldSave) {
                const deploymentInfo: DeploymentResult = {
                    network: networkName,
                    deployer: deployer.address,
                    timestamp: new Date().toISOString(),
                    tenexiumProtocol: {
                        proxy: address,
                        implementation: implementationAddress,
                        address: address
                    }
                };
                utils.saveDeployment(networkName, "subnetManager", deploymentInfo);
            }
        } catch (error: any) {
            console.error("\n❌ Subnet manager deployment failed:");
            console.error(error.message);
            process.exit(1);
        }
    });

// Task: Deploy subnet manager new implementation
task("deploy:subnet-manager:implementation", "Deploy subnet manager new implementation")
    .addFlag("save", "Save deployment info to file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("🚀 Deploying Subnet Manager New Implementation Contract...");
        console.log("=============================================");

        const networkName = hre.network.name;
        const shouldSave = taskArgs.save;
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();

            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);

            // Deploy subnet manager new implementation
            console.log("\n�� Deploying Subnet Manager New Implementation...");
            const SubnetManager = await hre.ethers.getContractFactory("SubnetManager");
            const subnetManager = await SubnetManager.deploy();
            await subnetManager.waitForDeployment();
            const implementationAddress = await subnetManager.getAddress();

            // Save implementation address if requested
            if (shouldSave) {
                const deploymentsDir = path.join(__dirname, "..", "deployments");
                if (!fs.existsSync(deploymentsDir)) {
                    fs.mkdirSync(deploymentsDir, { recursive: true });
                }
                const filePath = path.join(deploymentsDir, `${networkName}-${"subnetManager"}.json`);
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
            console.log(`  📋 Implementation address: ${implementationAddress}`);
            console.log("\n💡 Next steps:");
            console.log("  1. Verify the implementation contract");
            console.log("  2. Use 'npx hardhat upgrade:proxy' to upgrade your proxy");
        } catch (error: any) {
            console.error("\n❌ Subnet manager new implementation deployment failed:");
            console.error(error.message);
            process.exit(1);
        }
    });

// Task: Upgrade subnet manager
task("upgrade:subnet-manager:proxy", "Upgrade subnet manager proxy to new implementation")
    .addFlag("save", "Save upgrade info to deployment file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("🚀 Upgrading Subnet Manager Contract...");
        console.log("=============================================");

        const networkName = hre.network.name;
        const proxyAddress = utils.getProxyAddress(networkName, "subnetManager");
        const newImplementationAddress = utils.getNewImplementationAddress(networkName, "subnetManager");
        const shouldSave = taskArgs.save;
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();
            
            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);

            // Get current implementation
            const currentImplementation = await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);
            console.log(`  Current Implementation: ${currentImplementation}`);
            
            // Verify the new implementation is different
            if (currentImplementation.toLowerCase() === newImplementationAddress.toLowerCase()) {
                console.log("⚠️  Warning: New implementation address is the same as current implementation");
            }
            
            // Perform upgrade
            console.log("\n�� Performing upgrade...");
            
            // Get the proxy contract
            const proxyContract = await hre.ethers.getContractAt("TenexiumProtocol", proxyAddress);
            
            // Prepare upgrade data
            const upgradeData = "0x";
            
            // Perform upgrade via upgradeToAndCall
            const upgradeTx = await proxyContract.upgradeToAndCall(newImplementationAddress, upgradeData);
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
                const filePath = path.join(deploymentsDir, `${networkName}-${"subnetManager"}.json`);
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
                        [upgradeTx.hash]: upgradeInfo
                    }
                };
                fs.writeFileSync(filePath, JSON.stringify(updatedData, null, 2));
                console.log(`  �� Upgrade info saved to ${filePath}`);
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

// Task: Deploy address conversion contract
task("deploy:address-conversion", "Deploy address conversion contract")
    .addFlag("save", "Save deployment info to file")
    .addOptionalParam("gas", "Gas limit to use for deployment (bypass estimate)", undefined, types.int)
    .addOptionalParam("gasPrice", "Legacy gasPrice in wei (overrides auto)", undefined, types.string)
    .addFlag("legacyTx", "Use legacy transactions with gasPrice instead of EIP-1559 fees")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("🚀 Deploying Address Conversion Contract...");
        console.log("=============================================");

        const networkName = hre.network.name;
        const shouldSave = taskArgs.save;
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();

            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);

            // Deploy address conversion contract (bypass gas estimation on Frontier-style RPCs)
            console.log("\n�� Deploying Address Conversion Contract...");
            const AddressConversion = await hre.ethers.getContractFactory("AddressConversion");

            // Prepare fee overrides to avoid eth_estimateGas traps on Substrate EVM
            const defaultGasLimit = 10_000_000n; // safe high limit for deployment
            const gasLimit: bigint = taskArgs.gas ? BigInt(taskArgs.gas) : defaultGasLimit;

            const feeData = await deployer.provider.getFeeData();
            const useLegacy: boolean = Boolean(taskArgs.legacyTx) || (feeData.maxFeePerGas == null);

            let overrides: any = { gasLimit };
            if (useLegacy) {
                const gasPrice = taskArgs.gasPrice ? BigInt(taskArgs.gasPrice) : (feeData.gasPrice ?? 1_000_000_000n); // 1 gwei fallback
                overrides.gasPrice = gasPrice;
                console.log(`  Using legacy tx with gasPrice=${gasPrice.toString()} and gasLimit=${gasLimit}`);
            } else {
                // Fallback to EIP-1559 if supported by the RPC
                overrides.maxFeePerGas = feeData.maxFeePerGas;
                overrides.maxPriorityFeePerGas = feeData.maxPriorityFeePerGas ?? feeData.maxFeePerGas;
                console.log(`  Using EIP-1559 with maxFeePerGas=${overrides.maxFeePerGas}, maxPriorityFeePerGas=${overrides.maxPriorityFeePerGas}, gasLimit=${gasLimit}`);
            }

            const addressConversion = await AddressConversion.deploy(overrides);
            await addressConversion.waitForDeployment();
            const implementationAddress = await addressConversion.getAddress();

            // Save implementation address if requested
            if (shouldSave) {
                const deploymentsDir = path.join(__dirname, "..", "deployments");
                if (!fs.existsSync(deploymentsDir)) {
                    fs.mkdirSync(deploymentsDir, { recursive: true });
                }
                const filePath = path.join(deploymentsDir, `${networkName}-${"addressConversion"}.json`); 
                const updatedData = {
                    lastUpdated: new Date().toISOString(),
                    addressConversion: {
                        address: implementationAddress,
                        deployedAt: new Date().toISOString(),
                        deployer: deployer.address
                    }
                };
                fs.writeFileSync(filePath, JSON.stringify(updatedData, null, 2));
                console.log(`  📁 Address conversion address saved to ${filePath}`);
            }

            console.log("\n🎉 Address conversion deployment completed successfully!");
            console.log(`  📋 Address conversion address: ${implementationAddress}`);
            console.log("\n💡 Next steps:");
            console.log("  1. Verify the address conversion contract");
        } catch (error: any) {
            console.error("\n❌ Address conversion deployment failed:");
            console.error(error.message);
            process.exit(1);
        }
    });

// Task: Show deployment help
task("deploy:help", "Show deployment task help")
    .setAction(async () => {
        console.log("🚀 Tenexium Protocol Deployment Tasks");
        console.log("=====================================");
        console.log("");
        console.log("Available tasks:");
        console.log("");
        console.log("  npx hardhat deploy:new_proxy [options]");
        console.log("    Deploy new upgradeable version of the contract");
        console.log("");
        console.log("  npx hardhat deploy:implementation [options]");
        console.log("    Deploy new implementation contract for upgrades");
        console.log("");
        console.log("  npx hardhat upgrade:proxy [options]");
        console.log("    Upgrade proxy contract to new implementation");
        console.log("");
        console.log("Common options:");
        console.log("  --save               Save deployment info to file");
        console.log("");
        console.log("Upgrade options:");
        console.log("  --proxy <address>    Proxy contract address to upgrade");
        console.log("  --implementation <address>  New implementation address");
        console.log("  --data <hex>         Initialization data (optional)");
        console.log("");
        console.log("Examples:");
        console.log("  npx hardhat deploy:new_proxy --save");
        console.log("  npx hardhat deploy:implementation --save");
        console.log("  npx hardhat upgrade:proxy --proxy 0x123... --implementation 0x456... --save");
    }); 
