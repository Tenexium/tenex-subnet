// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.24;

import "../interfaces/INeuron.sol";
import "../interfaces/IMetagraph.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

interface ITenexium {
    struct LiquidityProvider {
        uint256 stake; // LP stake amount
        uint256 rewards; // Accumulated rewards
        uint256 lastRewardBlock; // Last reward calculation block
        uint256 shares; // LP shares
        uint256 rewardDebt; // Accumulator-based reward debt for LP fee claims
        bool isActive; // LP status
    }

    function liquidityProviders(address) external view returns (LiquidityProvider memory);
    function liquidityProviderSetLength(bytes32) external view returns (uint256);
    function groupLiquidityProviders(bytes32, uint256) external view returns (address);
    function maxLiquidityProvidersPerHotkey() external view returns (uint256);
}

contract SubnetManager is OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    // The subnet ID for Tenex
    uint16 public constant TENEX_NETUID = 67;
    // The version key for the weights
    uint64 public versionKey;

    // Bittensor EVM precompiles
    IMetagraph public constant METAGRAPH_PRECOMPILE = IMetagraph(0x0000000000000000000000000000000000000802);
    INeuron public constant NEURON_PRECOMPILE = INeuron(0x0000000000000000000000000000000000000804);

    // Tenexium contract
    ITenexium public TenexiumContract;

    // Errors
    error SetWeightsFailed();
    error VersionKeyZero();
    error TenexiumAddrZero();
    error AmountZero();
    error InsufficientBalance();
    error WithdrawFailed();

    function initialize(address _TenexiumContractAddress, uint64 _versionKey) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        TenexiumContract = ITenexium(_TenexiumContractAddress);
        versionKey = _versionKey;
    }

    function setWeights() external onlyOwner {
        (uint16[] memory dests, uint16[] memory weights) = getWeights();
        bytes memory data =
            abi.encodeWithSelector(INeuron.setWeights.selector, TENEX_NETUID, dests, weights, versionKey);
        (bool success,) = address(NEURON_PRECOMPILE).call{gas: gasleft()}(data);
        if (!success) {
            revert SetWeightsFailed();
        }
    }

    function getWeights() internal view returns (uint16[] memory dests, uint16[] memory weights) {
        uint256[] memory unnormalizedWeights;
        (dests, unnormalizedWeights) = _getUnnormalizedWeights();
        weights = new uint16[](unnormalizedWeights.length);

        uint256 totalWeight;
        for (uint16 i = 1; i < weights.length; i++) {
            totalWeight += unnormalizedWeights[i];
        }

        if (totalWeight == 0) {
            weights[0] = uint16(type(uint16).max);
        } else {
            for (uint16 i = 1; i < weights.length; i++) {
                uint256 normalizedWeight = (unnormalizedWeights[i] * type(uint16).max) / totalWeight;
                weights[i] = uint16(normalizedWeight);
            }
        }

        return (dests, weights);
    }

    function _getUnnormalizedWeights()
        internal
        view
        returns (uint16[] memory dests, uint256[] memory unnormalizedWeights)
    {
        uint16 uidCount = METAGRAPH_PRECOMPILE.getUidCount(TENEX_NETUID);
        dests = new uint16[](uidCount);
        unnormalizedWeights = new uint256[](uidCount);
        uint256 maxLiquidityProvidersPerHotkey = TenexiumContract.maxLiquidityProvidersPerHotkey();

        for (uint16 uid = 1; uid < uidCount; uid++) {
            dests[uid] = uid;
            bytes32 hotkey = METAGRAPH_PRECOMPILE.getHotkey(TENEX_NETUID, uid);
            uint256 liquidityProviderCount = TenexiumContract.liquidityProviderSetLength(hotkey);
            uint256 maxLiquidityProviders = liquidityProviderCount > maxLiquidityProvidersPerHotkey
                ? maxLiquidityProvidersPerHotkey
                : liquidityProviderCount;

            for (uint256 i = 0; i < maxLiquidityProviders; i++) {
                address liquidityProvider = TenexiumContract.groupLiquidityProviders(hotkey, i);
                uint256 liquidityProviderBalance = TenexiumContract.liquidityProviders(liquidityProvider).stake;
                unnormalizedWeights[uid] += liquidityProviderBalance;
            }
        }
    }

    function setVersionKey(uint64 _versionKey) public onlyOwner {
        if (_versionKey == 0) revert VersionKeyZero();
        versionKey = _versionKey;
    }

    function setTenexiumContract(address _TenexiumContractAddress) public onlyOwner {
        if (_TenexiumContractAddress == address(0)) revert TenexiumAddrZero();
        TenexiumContract = ITenexium(_TenexiumContractAddress);
    }

    function withdrawFunds(uint256 amount) external onlyOwner {
        if (amount == 0) revert AmountZero();
        if (address(this).balance < amount) revert InsufficientBalance();
        (bool success,) = payable(owner()).call{value: amount}("");
        if (!success) revert WithdrawFailed();
    }

    receive() external payable {}

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
