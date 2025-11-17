# StakingWrapper Contract - Quick Guide

## Overview

The `StakingWrapper` contract is an upgradeable wrapper that simplifies staking/unstaking TAO for Alpha tokens with automatic slippage protection. It uses **delegatecall** to preserve `msg.sender` context, meaning stakes are associated with the user's address, not the wrapper contract.

## Key Features

✅ **Delegatecall Execution**: Preserves `msg.sender` so stakes belong to users  
✅ **Slippage Protection**: Simple basis points parameter instead of complex limitPrice  
✅ **UUPS Upgradeable**: Can be upgraded by owner  
✅ **Simulation Support**: Test stakes/unstakes before execution  
✅ **No PrecompileAdapter**: Direct implementation for clarity

## Deployment

### Environment Setup

```bash
# Set your private key
export ETH_PRIVATE_KEY="your_private_key_here"

# Get the address conversion contract address from your deployment
# Check deployments/testnet-addressConversion.json
export ADDRESS_CONVERSION_CONTRACT="0x..."
```

### Deploy Commands

```bash
# 1. Deploy new proxy with default 10% max slippage
npx hardhat deploy:staking-wrapper:new_proxy \
  --address-conversion $ADDRESS_CONVERSION_CONTRACT \
  --max-slippage 1000 \
  --save \
  --network testnet

# 2. Get deployment info
npx hardhat info:staking-wrapper --network testnet

# 3. Deploy new implementation (for upgrades)
npx hardhat deploy:staking-wrapper:implementation \
  --save \
  --network testnet

# 4. Upgrade proxy to new implementation
npx hardhat upgrade:staking-wrapper:proxy \
  --save \
  --network testnet

# 5. Get help
npx hardhat help:staking-wrapper
```

## Usage Examples

### Staking TAO for Alpha

```solidity
// User calls stakeTaoForAlpha with explicit amount and 5% max slippage
uint256 alphaReceived = stakingWrapper.stakeTaoForAlpha{value: 10 ether}(
    validatorHotkey,
    10 ether,  // explicit stake amount
    500,       // 5% slippage in basis points
    67         // alpha netuid
);

// The stake is recorded under msg.sender (the user), not the wrapper contract
```

### Unstaking Alpha for TAO

```solidity
// User calls unstakeAlphaForTao with 3% max slippage
uint256 taoReceived = stakingWrapper.unstakeAlphaForTao(
    validatorHotkey,
    1000e9,  // 1000 Alpha tokens
    300,     // 3% slippage in basis points
    67       // alpha netuid
);

// TAO is returned directly to msg.sender (the user)
```

### Simulating Operations

```solidity
// Simulate staking before execution
uint256 expectedAlpha = stakingWrapper.simulateStake(10 ether, 67);
console.log("Expected Alpha:", expectedAlpha);

// Simulate unstaking before execution
uint256 expectedTao = stakingWrapper.simulateUnstake(1000e9, 67);
console.log("Expected TAO:", expectedTao);
```

### Checking Stake Balance

```solidity
// Check user's stake with a validator
uint256 userStake = stakingWrapper.getStake(
    validatorHotkey,
    userAddress,
    67  // alpha netuid
);
```

### Burning Alpha Tokens

```solidity
// Burn alpha tokens
stakingWrapper.burnAlpha(
    hotkey,
    500e9,  // 500 Alpha tokens
    67      // alpha netuid
);
```

## Slippage Reference

| Slippage % | Basis Points |
|------------|--------------|
| 0.5%       | 50           |
| 1%         | 100          |
| 2%         | 200          |
| 3%         | 300          |
| 5%         | 500          |
| 10%        | 1000         |

## Why Delegatecall?

The contract uses `delegatecall` instead of regular `call` for precompile interactions:

```solidity
// This preserves msg.sender as the user
(bool success,) = address(STAKING_PRECOMPILE).delegatecall{gas: gasleft()}(data);
```

**Benefits:**
- ✅ Stakes are associated with the user's address
- ✅ User retains full control of their stakes
- ✅ No need to trust the wrapper contract with custody
- ✅ Compatible with Bittensor's staking model

**vs Regular Call:**
```solidity
// This would make msg.sender = wrapper contract address
(bool success,) = address(STAKING_PRECOMPILE).call{gas: gasleft()}(data);
```

## Admin Functions

Only the contract owner can:

```solidity
// Update max slippage
stakingWrapper.updateMaxSlippage(2000); // 20%

// Update address conversion contract
stakingWrapper.updateAddressConversionContract(newAddress);

// Emergency withdraw (if TAO gets stuck)
stakingWrapper.emergencyWithdraw();

// Upgrade contract
stakingWrapper.upgradeToAndCall(newImplementation, "0x");
```

## Contract Architecture

```
User
  │
  ├─► stakeTaoForAlpha()
  │   │
  │   ├─► Simulate swap
  │   ├─► Calculate limit price from slippage
  │   ├─► delegatecall STAKING_PRECOMPILE.addStakeLimit()
  │   └─► Verify slippage met
  │
  └─► unstakeAlphaForTao()
      │
      ├─► Simulate swap
      ├─► Calculate limit price from slippage
      ├─► delegatecall STAKING_PRECOMPILE.removeStakeLimit()
      ├─► Verify slippage met
      └─► Return TAO to user
```

## Testing Deployment

```bash
# 1. Deploy to testnet
npx hardhat deploy:staking-wrapper:new_proxy \
  --address-conversion $ADDRESS_CONVERSION_CONTRACT \
  --save \
  --network testnet

# 2. Verify deployment
npx hardhat info:staking-wrapper --network testnet

# 3. Test stake simulation
npx hardhat console --network testnet
```

In Hardhat console:
```javascript
const wrapper = await ethers.getContractAt("StakingWrapper", "PROXY_ADDRESS");
const expectedAlpha = await wrapper.simulateStake(ethers.parseEther("1"), 67);
console.log("Expected alpha:", expectedAlpha.toString());
```

## Security Notes

1. **Reentrancy Protection**: All external functions use `nonReentrant` modifier
2. **Slippage Limits**: Maximum slippage is configurable (default 10%)
3. **No Partial Execution**: `allowPartial` is always `false` for predictable results
4. **Owner Controls**: Only owner can upgrade or modify parameters
5. **Direct User Control**: Delegatecall ensures users maintain control of their stakes

## Troubleshooting

### "SlippageTooHigh" Error
- Your specified slippage is higher than the contract's `maxSlippage`
- Solution: Reduce slippage or ask owner to increase `maxSlippage`

### "SwapSimInvalid" Error
- The simulation returned 0, indicating the swap is not possible
- Solution: Check alpha subnet status and liquidity

### "StakeFailed" / "UnstakeFailed" Error
- The precompile call failed
- Solution: Check you have sufficient balance and the validator hotkey is valid

## File Locations

- **Contract**: `contracts/StakingWrapper.sol`
- **Deployment Task**: `tasks/staking-wrapper.ts`
- **Hardhat Config**: `hardhat.config.ts`
- **Deployments**: `deployments/{network}-staking-wrapper.json`

## Next Steps

1. ✅ Contract deployed and verified
2. Test staking with small amounts
3. Verify stakes appear under user addresses
4. Test unstaking
5. Monitor gas usage and slippage behavior
6. Consider adding additional convenience functions if needed

---

For more details, see the contract source code at `contracts/StakingWrapper.sol`.

