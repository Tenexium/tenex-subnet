# Tenexium

> **Decentralized Long-Only Spot Margin Protocol for the Bittensor Network**

**Tenexium** operates as a spot margin protocol within the Bittensor ecosystem, serving as the core infrastructure for the Tenex subnet. The protocol enables users to establish leveraged long positions on subnet tokens using TAO as collateral, while providing TAO liquidity providers with sustainable yields through both Bittensor miner emissions and protocol-generated fees from trading, borrowing, and liquidations.

## Table of Contents

- [Overview](#overview)
- [Architecture](#%EF%B8%8Farchitecture)
- [Core Mechanics](#%EF%B8%8Fcore-mechanics)
- [Tokenomics](#tokenomics)
- [Security](#security)
- [API Reference](#api-reference)
- [License](#license)
- [Disclaimer](#%EF%B8%8Fdisclaimer)

---

## 📋Overview

### Key Features

- **TAO-Only Liquidity Pool**: Liquidity providers supply TAO exclusively, earning both miner emissions and protocol fee shares without direct alpha volatility exposure
- **Long-Only Design**: Deliberately prohibits short positions to prevent artificial sell pressure in dTAO markets
- **Tiered Leverage System**: Maximum leverage (up to 10×) determined by Tenex alpha token holdings with on-chain enforcement
- **Dynamic Fee Structure**: Trading and borrowing fees adjust based on utilization rates with tier-based discounts
- **Automated Buyback Program**: A defined share of protocol fees fund programmatic buybacks to support Tenex alpha token demand
- **Circuit Breaker Protection**: Multiple safety mechanisms including rate limiting, utilization caps, and emergency controls

### How It Works

1. **Liquidity Providers** deposit TAO into the protocol and earn:
   - Bittensor miner emissions
   - Share of trading, borrowing, and liquidation fees

2. **Traders** can:
   - Deposit TAO as collateral
   - Borrow additional TAO against their position
   - Execute leveraged long positions on alpha tokens
   - Benefit from tier-based fee discounts and higher leverage limits

3. **Protocol** automatically:
   - Maintains TAO liquidity for sustainable borrowing
   - Manages liquidations and risk parameters
   - Routes fees to buyback pool for Tenex alpha support

---

## 🏗️Architecture

### Contract Structure

```
contracts/
├── core/
│   ├── TenexiumProtocol.sol     # Main protocol contract
│   ├── TenexiumStorage.sol      # Persistent state storage
│   └── TenexiumEvents.sol       # Event definitions
├── modules/
│   ├── PositionManager.sol      # Position lifecycle management
│   ├── LiquidityManager.sol     # LP operations & rewards
│   ├── FeeManager.sol           # Fee collection & distribution
│   ├── BuybackManager.sol       # Automated buybacks → burn
│   ├── LiquidationManager.sol   # Liquidation manager
│   ├── InsuranceManager.sol     # LP loss insurance manager
│   ├── SubnetManager.sol        # EVM validator manager
│   └── PrecompileAdapter.sol    # Bittensor precompile adapter
├── interfaces/
│   ├── IAlpha.sol               # Alpha token interface
│   ├── IStaking.sol             # Staking interface
│   ├── INeuron.sol              # Neuron interface
│   ├── IMetagraph.sol           # Metagraph interface
│   ├── ICrowdloan.sol           # Crowdloan interface
│   ├── IInsuranceManager        # Insurance interface
│   └── IAddressConversion       # Address conversion interface
├── libraries/
│   ├── AlphaMath.sol            # Mathematical operations for alpha calculations
│   ├── AddressConversion.sol    # H160 → SS58 address conversion
│   └── TenexiumErrors.sol       # Custom error definitions
└── governance/
    └── MultiSigWallet.sol       # Multisig governance
```

### Key Components

- **UUPS Upgradeable**: Proxy pattern for seamless contract upgrades
- **Modular Architecture**: Separated concerns for maintainability and security
- **Bittensor Integration**: Native integration with Bittensor precompiles for staking and other operations
- **Multi-Role Access**: Owner, LPs, traders, and liquidators with appropriate permissions

---

## 🛠️Core Mechanics

### Position Management

#### Opening Positions
1. User deposits TAO collateral
2. Protocol validates tier and leverage limits
3. User borrows additional TAO (up to leverage limit)
4. Protocol executes alpha token purchase on behalf of user
5. Position is recorded with health ratio monitoring

#### Health Ratio
```
Health Ratio = (Collateral Value + Alpha Position Value) / Borrowed TAO Value
```

- **Maintenance Margin**: 110% (positions liquidated below this threshold)
- **Liquidation Penalty**: Additional 2% fee on liquidated collateral

#### Circuit Breakers
- **Utilization Cap**: Borrowing disabled when utilization > 90%
- **Rate Limiting**: LP operations limited to prevent flash attacks
- **Emergency Pause**: Owner can pause all operations in extreme scenarios

### Liquidation System

#### Liquidation Triggers
- Health ratio < 110%
- Position becomes underwater due to price movements
- Automatic execution by liquidator bots

#### Liquidation Process
1. Liquidator identifies underwater position
2. Protocol validates liquidation conditions
3. Liquidator receives 40% of liquidation fee
4. Remaining collateral returned to user (minus fees)
5. Borrowed TAO returned to liquidity pool

#### Liquidator Incentives
- **Fee Share**: 40% of liquidation penalty
- **Reward Pool**: Separate reward mechanism for active liquidators

### Fee Structure

#### Trading Fees
- **Base Rate**: 0.3% per trade (tier-discounted)
- **Payment**: Deducted from acquired alpha tokens
- **Timing**: Applied immediately on position open/close

#### Borrowing Fees
- **Base Rate**: 0.005% per 360 blocks (dynamic based on utilization)
- **Utilization-Kinked Model**:
  - **Kink Point**: 80% utilization
  - **Below Kink (0-80%)**: Gradual increase from base rate to 0.02% per 360 blocks
  - **Above Kink (80%+)**: Steeper increase from 0.02% to maximum rates
- **Payment**: Settled when position is closed or liquidated
- **Timing**: Accrued continuously in real-time, calculated on position updates or closure

#### Liquidation Fees
- **Rate**: 2% fixed (paid by liquidated position)
- **Payment**: Distributed to liquidators and protocol
- **Timing**: Applied immediately upon liquidation execution

### Fee Distribution

| Fee Type    | Liquidity Providers | Liquidators | Protocol |
|-------------|-------------------:|------------:|---------:|
| Trading     | 30%                | 0%          | 70%      |
| Borrowing   | 35%                | 0%          | 65%      |
| Liquidation | 0%                 | 40%         | 60%      |

### Leverage Tiers

Eligible Tenex alpha holders receive tier-based fee discounts and higher maximum leverage limits.

| Tier | Token Threshold | Max Leverage | Fee Discount |
|-----:|----------------:|-------------:|-------------:|
| 0    | 0               | 2×           | 0%           |
| 1    | 100             | 3×           | 10%          |
| 2    | 1,000           | 4×           | 20%          |
| 3    | 2,000           | 5×           | 30%          |
| 4    | 5,000           | 7×           | 40%          |
| 5    | 10,000          | 10×          | 50%          |

> **Note**: Maximum leverage is enforced at position open and cannot exceed the user's tier cap.

### Crowdloan Participant Benefits

Crowdloans will be offered only occasionally, and early participants receive permanent benefits.

| Contributed TAO | Max Leverage | Fee Discount |
|----------------:|-------------:|-------------:|
|        1        | 2×           | 2%           |
|        2        | 2×           | 4%           |
|        3        | 3×           | 6%           |
|        4        | 4×           | 8%           |
|        5        | 5×           | 10%          |
|        6        | 5×           | 12%          |
|        7        | 7×           | 14%          |
|        8        | 7×           | 16%          |
|        9        | 7×           | 18%          |
|        10       | 10×          | 20%          |

> **Note:** Fee discounts are cumulative; they stack instead of replacing each other.

### Buyback Program

#### Revenue Sources
- **60% of total protocol revenue** (comes from protocol fees)

#### Buyback Mechanics
- **Execution Threshold**: Buybacks trigger when buyback pool > `buybackExecutionThreshold`
- **Execution Interval**: Automated execution every `buybackIntervalBlocks`
- **Burning**: Purchased tokens are immediately 100% burned

---

## 💰Tokenomics

### TAO Liquidity Pool
- **Backing Asset**: 100% TAO collateral
- **Yield Sources**:
  - Miner emissions
  - Protocol fee share (30-35% of all fees)
  - Impermanent loss protection (long-only design)

### Tenex Alpha Token
- **Utility**: Tier determination and fee discounts
- **Demand Drivers**:
  - Automated buyback program
  - Governance participation
  - Future utility expansion

### Reward Distribution
- **LP Rewards**: Allocated pro rata to TAO liquidity provided
- **Liquidator Rewards**: Performance-based with minimum activity thresholds
- **Buyback Allocation**: 60% of protocol fees directed to token purchases and burn

---

## 🔒Security

### Audit Status
The Hashlock audit is complete.

Audit link: https://hashlock.com/audits/tenexium

### Architecture Security

#### Contract Design
- **UUPS Upgradeable**: Proxy pattern with secure upgrade mechanisms
- **Access Control**: Multi-role permissions with Ownable and custom modifiers
- **Reentrancy Protection**: OpenZeppelin ReentrancyGuard on all external functions
- **Input Validation**: Comprehensive parameter validation and bounds checking

#### Risk Management
- **Circuit Breakers**: Multiple emergency stop mechanisms
- **Rate Limiting**: Anti-flash attack protection on LP operations
- **Slippage Controls**: Maximum slippage limits on interactions
- **Conservative Parameters**: Initial deployment with conservative risk settings

### Multisig Governance

Protocol upgrades and parameter changes are controlled by a multisig, not by a single key.

#### How it works
- The core contracts are owned by a multisig wallet.
- The multisig requires N-of-M approvals (e.g. 3 of 5 signers) before any action can execute.
- No single signer can upgrade logic or change parameters alone.
- Multisig actions have a 48-hour timelock.

#### What the multisig can do
- Approve contract upgrades / deployments.
- Update protocol config (fees, LTV thresholds, liquidation settings, etc.).
- Execute governance actions after the timelock expires.

### Known Risk Factors

#### Bittensor Ecosystem Risks
- **Bittensor Network Stability**: Protocol operations depend on Bittensor network uptime and consensus
- **Precompile Reliability**: Price feeds and staking operations rely on Bittensor precompile functionality

#### Protocol Risks
- **Liquidity Risk**: Insufficient TAO liquidity could impact borrowing
- **Volatility Risk**: Extreme alpha price movements could trigger liquidations

---

## 🚀Getting Started    

### Install
```bash
git clone https://github.com/Tenexium/tenex-subnet
cd tenex-subnet/scripts
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### For Miners (Liquidity Providers)
Use the CLI to associate your hotkey and manage liquidity; no separate miner daemon is required.

Step 1.
Configure environment variables.
```bash
cp .env.example .env
```
Edit `.env` and set:
```bash
# Private key for the EVM wallet you'll use for TAO deposits
MINER_ETH_PRIVATE_KEY=your_evm_private_key_here
# Public key (hex) of your registered miner hotkey
MINER_HOTKEY=your_miner_hotkey_public_key_here
# network name for subtensor EVM (default=mainnet)
NETWORK=mainnet
```
>Note: To create an EVM wallet and export its private key, see the [EVM mainnet with Metamask wallet guide](https://docs.learnbittensor.org/evm-tutorials/evm-mainnet-with-metamask-wallet).

>Note: To get your miner hotkey public key, enter your hotkey (SS58) address in the [Snow Address Converter App](https://snow-address-converter.netlify.app/) and copy the public key.

Step 2.
Associate your EVM address with your hotkey.
```bash
python3 tenex.py associate
```

Step 3.
Add or remove liquidity.
```bash
python3 tenex.py addliq --amount <amount>
```
```bash
python3 tenex.py removeliq --amount <amount>
```
View protocol and miner stats:
```bash
python3 tenex.py showstats
```

### For EVM Validators

1. Deploy your validator contract (identical to `SubnetManager.sol`) and register to the subnet with its H160 address.

2. Copy `.env.example` to `.env` and edit the following variables:
   - `VALIDATOR_ETH_PRIVATE_KEY`: private key of your validator contract
   - `WEIGHT_UPDATE_INTERVAL_BLOCKS`: number of blocks between weight updates (default=`100`)
   - `NETWORK`: network name for Subtensor EVM (default=`mainnet`)

3. Start the validator process:
```bash
python3 evm_validator.py
```

### For Normal Validators

1. Copy `.env.example` to `.env` and edit the following variables:
   - `WEIGHT_UPDATE_INTERVAL_BLOCKS`: number of blocks between weight updates (default=`100`)
   - `NETWORK`: network name for Subtensor EVM (default=`mainnet`)
   - `NET_UID`: subnet uid (default=`67`)
   - `ENDPOINT`: subtensor endpoint to which you will connect (default=`wss://entrypoint-finney.opentensor.ai:443`)
   - `WALLET_PATH`: path where your wallets are stored (default=`~/.bittensor/wallets/`)
   - `WALLET_NAME`: name of your coldkey (default=`tenex`)
   - `WALLET_HOTKEY`: name of your hotkey (default=`validators`)

2. Start the validator process:
```bash
python3 validator.py
```

### For Users
Users can open/close long positions and add collateral via the position management functions: `openPosition()`, `closePosition()` and `addCollateral()`.
Alternatively, use the CLI (coming soon):
```bash
tenex open --address <wallet_address> --amount <tao_amount> --netuid <netuid> --leverage <leverage> --slippage <slippage>
```

```bash
tenex close --address <wallet_address> --amount <tao_amount> --netuid <netuid> --slippage <slippage>
```

```bash
tenex add --address <wallet_address> --amount <tao_amount> --netuid <netuid>
```

---

## 📚API Reference

### Core Functions

#### Position Management
```solidity
// Open a leveraged position
function openPosition(
    uint16 alphaNetuid,
    uint256 leverage,
    uint256 maxSlippage
) external payable

// Close a position
function closePosition(
    uint256 positionId,
    uint256 amountToClose,
    uint256 maxSlippage
) external

// Add collateral to position
function addCollateral(uint256 positionId) external payable
```

#### Liquidity Management
```solidity
// Add liquidity
function addLiquidity() external payable

// Remove liquidity
function removeLiquidity(uint256 amount) external

// Claim LP rewards
function claimLpFeeRewards() external returns (uint256 rewards)
```

---

## 📄License

Tenexium is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## ⚠️Disclaimer

Leveraged trading is risky and can exceed your initial investment. Tenexium is provided “as is” with no warranties. Do your own research, understand the risks, and comply with applicable laws in your jurisdiction.

---

*Built with ❤️ by the Tenexium Team*
