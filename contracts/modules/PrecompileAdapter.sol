// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../core/TenexiumStorage.sol";
import "../libraries/TenexiumErrors.sol";
import "../libraries/AlphaMath.sol";

/**
 * @title PrecompileAdapter
 * @notice Adapter for interacting with Bittensor precompiles (staking, alpha, metagraph)
 */
abstract contract PrecompileAdapter is TenexiumStorage {
    using AlphaMath for uint256;

    /**
     * @notice Stake TAO for Alpha tokens using the staking precompile with price limit
     * @param validatorHotkey Validator hotkey
     * @param taoAmount TAO amount to stake (wei)
     * @param limitPrice Price limit in rao per alpha (0 for no limit)
     * @param allowPartial Whether to allow partial stake execution
     * @param alphaNetuid Alpha subnet ID
     * @return alphaReceived Alpha tokens received (in alpha base units)
     */
    function _stakeTaoForAlpha(
        bytes32 validatorHotkey,
        uint256 taoAmount,
        uint256 limitPrice,
        bool allowPartial,
        uint16 alphaNetuid
    ) internal returns (uint256 alphaReceived) {
        bytes32 _protocolSs58Address = addressConversionContract.addressToSS58Pub(address(this));
        uint256 initialStake = STAKING_PRECOMPILE.getStake(validatorHotkey, _protocolSs58Address, uint256(alphaNetuid));

        uint256 amountRao = taoAmount.weiToRao();
        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.addStakeLimit.selector,
            validatorHotkey,
            amountRao,
            limitPrice,
            allowPartial,
            uint256(alphaNetuid)
        );
        (bool success,) = address(STAKING_PRECOMPILE).call{gas: gasleft()}(data);
        if (!success) revert TenexiumErrors.StakeFailed();

        uint256 finalStake = STAKING_PRECOMPILE.getStake(validatorHotkey, _protocolSs58Address, uint256(alphaNetuid));

        alphaReceived = finalStake - initialStake;
        return alphaReceived;
    }

    /**
     * @notice Unstake Alpha tokens for TAO using the staking precompile with price limit
     * @param validatorHotkey Validator hotkey
     * @param alphaAmount Alpha amount to unstake (alpha base units)
     * @param limitPrice Price limit in rao per alpha (0 for no limit)
     * @param allowPartial Whether to allow partial unstake execution
     * @param alphaNetuid Alpha subnet ID
     * @return taoReceived TAO received from unstaking (wei)
     */
    function _unstakeAlphaForTao(
        bytes32 validatorHotkey,
        uint256 alphaAmount,
        uint256 limitPrice,
        bool allowPartial,
        uint16 alphaNetuid
    ) internal returns (uint256 taoReceived) {
        uint256 initialBalance = address(this).balance;

        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.removeStakeLimit.selector,
            validatorHotkey,
            alphaAmount,
            limitPrice,
            allowPartial,
            uint256(alphaNetuid)
        );
        (bool success,) = address(STAKING_PRECOMPILE).call{gas: gasleft()}(data);
        if (!success) revert TenexiumErrors.UnstakeFailed();

        uint256 finalBalance = address(this).balance;
        taoReceived = finalBalance - initialBalance;
        return taoReceived;
    }

    /**
     * @notice Burn Alpha tokens staked to BURN_ADDRESS using the staking precompile
     * @param burnAmount Alpha amount to burn (alpha base units)
     * @param alphaNetuid Alpha subnet ID
     */
    function _burnAlpha(bytes32 hotkey, uint256 burnAmount, uint16 alphaNetuid) internal {
        bytes memory data =
            abi.encodeWithSelector(STAKING_PRECOMPILE.burnAlpha.selector, hotkey, burnAmount, uint256(alphaNetuid));
        (bool success,) = address(STAKING_PRECOMPILE).call{gas: gasleft()}(data);
        if (!success) revert TenexiumErrors.BurnAlphaFailed();
    }
}
